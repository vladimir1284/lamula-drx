// `vector_source` — reproductor de vectores desde BRAM, cargable en tiempo de
// ejecución (D-01, SSA).
//
// `jesd204b_source` (ZU9) y `vector_source` (esta placa y la ZU9) son las dos
// implementaciones intercambiables del interfaz SSA
// (`docs/plataforma/fuente-de-muestras.md`); nada aguas abajo distingue cuál
// está activa.
//
// Puertos ya en arrays por canal, sin pasar por el TDATA entrelazado de
// `drx_ssa_pkg.sv` (`SSA_N_CH` = Rx + Tx burst): igual que documenta la
// cabecera de `drx_ddc_quad_top.sv`, el demux del stream SSA es
// responsabilidad de la fuente concreta, y para el bring-up de ZedBoard con
// N_CH<SSA_N_CH (Config A/B de P-12, 3 canales) no hay ningún entrelazado que
// deshacer: cada canal tiene su propio banco de BRAM independiente desde el
// principio.
//
// Memoria: un array SystemVerilog por canal (NO un único array 2D indexado
// por señal variable), con un proceso de lectura y un proceso de escritura
// separados y sin ninguna sentencia compartida entre ellos — el mismo patrón,
// por la misma razón, que ya fijó `drx_range_gate.sv`: es el único que Vivado
// infiere como BRAM sin ambigüedad. Con el if/else compartido, y hasta con
// `(* ram_style = "block" *)`, Vivado real contestó «Infeasible... trying to
// implement using LUTRAM». Ninguno de los dos procesos lleva reset asíncrono
// en su sensibilidad: ninguna BRAM real de Xilinx tiene borrado asíncrono de
// contenido, y el síntoma es «RAM is sensitive to asynchronous reset signal».
//
// --- Las dos longitudes ----------------------------------------------------
//
// `DEPTH` es la capacidad FÍSICA de cada banco; `vec_len` es la longitud que
// se REPRODUCE en bucle, y llega por registro en tiempo de ejecución. El
// puntero de lectura envuelve en `vec_len-1`, no en `DEPTH-1`. Con
// `VECTOR_BRAM_DEPTH = 8192` y `VECTOR_LOOP_LEN = 4000` (config/params.toml),
// la BRAM son 4 RAMB36 por canal y el bucle precargado ocupa la mitad.
//
// La distinción existe porque la longitud tiene que ser múltiplo de
// `IF_NORM_DEN` para que el tono cierre un número entero de periodos y no haya
// salto de fase al envolver, y una potencia de dos no lo es.
//
// --- Precarga y carga en caliente ------------------------------------------
//
// `$readmemh` precarga el bucle de síntesis desde un fichero por canal
// (`tools/gen_vector_source_init.py`, reutiliza `model/drx_model/vectors.tone`
// — no se reinventa la matemática del tono). Ese fichero trae `DEPTH` líneas:
// las primeras `VECTOR_LOOP_LEN` son el tono y el resto ceros, para que no
// quede ni una palabra indefinida en el array.
//
// Encima de eso, el PS puede sobreescribir el contenido en tiempo de ejecución
// por la ventana `VEC_ADDR`/`VEC_DATA` del mapa de registros v11, que es lo
// que convierte un barrido del catálogo de ocho vectores en ocho mensajes en
// vez de ocho corridas de Vivado. Antes de v11 eso lo hacía el modo
// Throttled(DDR) (DDR -> AXI DMA MM2S -> AXI4-Stream), que se retiró porque
// entregaba una muestra cada N_CH ciclos y el DDS Compiler, que no tiene
// `aclken`, seguía avanzando un paso de fase por ciclo: el DDC mezclaba a
// ~N_CH veces el IF (P-16).
//
// La carga va protegida por `vec_load`: con él en alto el lector se congela y
// las escrituras llegan a la memoria; con él en bajo el lector corre y las
// escrituras se ignoran. Así nunca se mezcla medio vector viejo con medio
// nuevo, y al soltarlo la reproducción empieza siempre en la muestra 0.
//
// `last` pulsa cada `vec_len` muestras — es un marcador ARTIFICIAL de "fin de
// ventana" para poder ejercitar el framing de `drx_range_gate`, NO el PRF
// real. No leer este pulso como una cadencia de rayo real.
//

`ifndef VECTOR_SOURCE_SV
`define VECTOR_SOURCE_SV

module vector_source
  import drx_params_pkg::*;
#(
    parameter int N_CH = 3,
    parameter int DEPTH = 4000,
    // Un fichero para los N_CH canales (mismo bucle en los tres — contenido
    // distinto por canal ya no necesita cambiar nada de estructura: se carga
    // banco a banco por `vec_bank`). Sin default: cuál fichero toca es una
    // decisión del top-level por plataforma (D-02, ver `drx_top.sv`), no de
    // este módulo — una `vector_source` que adivinara "zedboard" por defecto
    // sería la misma trampa de plataforma hardcodeada que el gate de
    // `tools/check_hardcoded_clock.py` ya prohíbe para el reloj. Instanciar
    // sin fijar `INIT_FILE` falla `$readmemh` de forma ruidosa en vez de leer
    // en silencio el fichero de la placa equivocada.
    parameter string INIT_FILE = "",

    // En la lista de parámetros, no en el cuerpo: los puertos de la ventana de
    // carga son de este ancho y un `localparam` del cuerpo no se puede usar en
    // la declaración de puertos.
    localparam int AddrBits = $clog2(DEPTH)
) (
    input logic clk,
    input logic rst_n,

    // --- Ventana de carga (mapa de registros v11) ---------------------------
    //
    // `vec_load` alto congela el lector y habilita la escritura; al bajar,
    // deja el puntero de lectura en la muestra 0.
    input logic vec_load,

    // `vec_we` es un pulso de un ciclo por muestra, con `vec_addr`,
    // `vec_bank` y `vec_data` válidos en ESE mismo ciclo. Quien lo genera
    // (`drx_axil_regs`) registra los cuatro juntos: un strobe combinacional
    // sobre el commit de AXI entrega el dato de la escritura ANTERIOR, que es
    // el bug de `nco_pinc_we` medido en placa el 2-oct-2026.
    input logic                          vec_we,
    input logic [          AddrBits-1:0] vec_addr,
    // Banco de destino: 0..N_CH-1 uno solo, `BankAll` (7) difusión a todos.
    // Un valor entre N_CH y 6 no escribe en ninguno.
    input logic [                   2:0] vec_bank,
    input logic signed [SAMPLE_BITS-1:0] vec_data,

    // Longitud del bucle en muestras. 0 se trata como 1; parar no es esto,
    // es `vec_load`.
    input logic [AddrBits-1:0] vec_len,

    input  logic                          ready[N_CH],
    output logic                          valid[N_CH],
    output logic signed [SAMPLE_BITS-1:0] data [N_CH],
    output logic                          last [N_CH]
);

  localparam logic [2:0] BankAll = 3'd7;

  // Último índice del bucle. Se calcula una vez y lo comparten los N_CH
  // lectores: es el mismo número para todos, y replicarlo por canal solo
  // añadiría N_CH restadores idénticos al camino crítico.
  //
  // `vec_len == 0` se mapea a 1 en vez de dejar `0-1` envolver a todo unos:
  // una longitud de cero no significa nada útil y el envolvente a `DEPTH-1`
  // leería la mitad no precargada del banco.
  logic [AddrBits-1:0] last_idx;
  assign last_idx = (vec_len == '0) ? '0 : AddrBits'(vec_len - AddrBits'(1));

  genvar gc;
  generate
    for (gc = 0; gc < N_CH; gc = gc + 1) begin : g_ch

      logic [SAMPLE_BITS-1:0] mem[0:DEPTH-1];

      initial $readmemh(INIT_FILE, mem);

      logic [AddrBits-1:0] rd_ptr;
      logic                out_valid_r;
      logic [SAMPLE_BITS-1:0] out_data_r;
      logic                out_last_r;

      // Este banco acepta la escritura si va dirigida a él o a todos.
      logic bank_hit;
      assign bank_hit = (vec_bank == BankAll) || (vec_bank == 3'(gc));

      logic can_advance;
      assign can_advance = !vec_load && (!out_valid_r || ready[gc]);

      // Proceso de control. Lleva reset asíncrono; `mem` NO vive aquí.
      //
      // Con `vec_load` en alto el lector se congela Y se rearma: así una
      // carga nueva empieza siempre en la muestra 0 y con la salida
      // invalidada, sin arrastrar el dato del vector anterior ni dejar el
      // puntero en un sitio arbitrario.
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          rd_ptr      <= '0;
          out_valid_r <= 1'b0;
          out_last_r  <= 1'b0;
        end else if (vec_load) begin
          rd_ptr      <= '0;
          out_valid_r <= 1'b0;
          out_last_r  <= 1'b0;
        end else if (can_advance) begin
          // `>=` y no `==`: si `vec_len` se acorta con el puntero ya mas
          // alla del nuevo final, una igualdad estricta obligaria a dar la
          // vuelta entera al banco antes de resincronizar -- y esa vuelta
          // recorre la parte no cargada de la memoria. Con `>=` el bucle
          // nuevo entra en el ciclo siguiente, al precio de una muestra
          // fuera de rango. El flujo normal no lo ve nunca (VEC_LEN se
          // escribe con `vec_load` en alto, que ya deja el puntero en 0);
          // esto es para el que lo escriba en caliente.
          out_last_r  <= (rd_ptr >= last_idx);
          out_valid_r <= 1'b1;
          rd_ptr      <= (rd_ptr >= last_idx) ? '0 : rd_ptr + 1'b1;
        end
      end

      // Puerto de lectura registrado a propósito (ver cabecera): `out_data_r`
      // se carga desde `mem[rd_ptr]` solo cuando el dato anterior ya se
      // consumió o todavía no hay ninguno, nunca pisa uno no leído.
      //
      // Proceso aparte del de control, sin reset en la sensibilidad: `mem` no
      // puede vivir en un proceso con reset asíncrono (confirmado contra
      // Vivado real, 19-sep-2026, sobre `drx_range_gate.sv` — «RAM is
      // sensitive to asynchronous reset signal», con o sin que el reset toque
      // la memoria). `out_data_r` viaja con la lectura; su valor tras reset no
      // se observa nunca, porque `out_valid_r` (que sí se resetea) se lo
      // impide a cualquier consumidor.
      always_ff @(posedge clk) begin
        if (can_advance) begin
          out_data_r <= mem[rd_ptr];
        end
      end

      // Puerto de escritura. Proceso propio, sin nada compartido con la
      // lectura: es la condición que hace que Vivado lo reconozca como un
      // simple-dual-port de libro en vez de tirarlo a LUTRAM.
      //
      // `vec_load` también cualifica aquí, y no solo en quien genera
      // `vec_we`: con el lector corriendo, una escritura dejaría medio vector
      // viejo y medio nuevo sonando a la vez, sin ningún síntoma salvo un
      // espectro raro. Con `vec_load` en alto no hay lecturas, así que los dos
      // puertos nunca coinciden.
      always_ff @(posedge clk) begin
        if (vec_we && vec_load && bank_hit) begin
          mem[vec_addr] <= vec_data;
        end
      end

      assign valid[gc] = out_valid_r;
      assign data[gc]  = signed'(out_data_r);
      assign last[gc]  = out_valid_r && out_last_r;

    end
  endgenerate

endmodule : vector_source

`endif  // VECTOR_SOURCE_SV
