// `vector_source` — reproductor de vectores en modo BRAM-loop (D-01, SSA).
//
// Primer entregable de Z1 sin escribir hasta hoy (ver la investigación que lo
// encontró): `jesd204b_source` (ZU9) y `vector_source` (esta placa y la ZU9)
// son las dos implementaciones intercambiables del interfaz SSA
// (`docs/plataforma/fuente-de-muestras.md`); nada aguas abajo distingue cuál
// está activa. De los tres modos documentados (RT, BRAM-loop, Throttled) este
// módulo implementa SOLO BRAM-loop: una forma de onda corta y repetitiva
// precargada en BRAM, sin DDR ni DMA de por medio — el camino más simple para
// tener ALGO real que alimente la cadena DDC en un P&R real.
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
// por señal variable) con puerto de lectura REGISTRADO — el mismo patrón, por
// la misma razón, que ya fijó `drx_range_gate.sv`: es el que Vivado infiere
// como BRAM sin ambigüedad, y con lectura combinacional xsim se cuelga contra
// IP real (hallazgo ya documentado en esa cabecera). Aquí no hay ping-pong
// porque no hace falta — es de solo lectura, precargado una vez en `initial`.
//
// Precarga con `$readmemh` desde un fichero por canal
// (`tools/gen_vector_source_init.py`, reutiliza `model/drx_model/vectors.tone`
// — no se reinventa la matemática del tono). Es el mismo mecanismo de
// `sim/tb_sv/drx_l1_file_source.sv` para simulación, pero aquí es síntesis de
// verdad: el contenido queda fijo en el bitstream, no hay AXI-Lite todavía
// para seleccionarlo en tiempo de ejecución (fase siguiente de Z1).
//
// `last` pulsa cada `DEPTH` muestras — es un marcador ARTIFICIAL de "fin de
// ventana" para poder ejercitar el framing de `drx_range_gate`, NO el PRF
// real: el motor de timing (Z2) no existe todavía. No leer este pulso como
// una cadencia de rayo real.
//
// --- Modo Throttled(DDR), Z4.3 (1-oct-2026) --------------------------------
//
// Segundo de los tres modos de `docs/plataforma/fuente-de-muestras.md`:
// «DDR con backpressure AXIS, 4 canales, por debajo de tiempo real, para
// corrección funcional bit a bit». Las muestras ya no salen de la BRAM
// precargada en síntesis sino de un AXI4-Stream que alimenta un AXI DMA MM2S
// desde la DDR del PS, así que el vector se elige en TIEMPO DE EJECUCIÓN
// (mensaje `test_stimulus_select` del contrato, v0.5) en vez de quedar fijo en
// el bitstream. Eso es lo que convierte un barrido del catálogo de 8 vectores
// de `tools/gen_l1_vectors.py` en algo que cuesta un DMA en vez de ocho
// corridas de Vivado.
//
// El modo NO reemplaza a BRAM-loop, convive con él y se elige por registro
// (`CTRL` bit 1, mapa v8). Quitarlo habría perdido el único modo que sostiene
// la tasa real, que es para lo que existe según esa misma tabla.
//
// Formato del stream: 16 bits por beat, UNA muestra por beat, canales en orden
// ascendente y repitiendo — canal 0, 1, ..., N_CH-1, canal 0, ... Es el
// formato más simple que existe y no hay motivo para otro: este modo es
// explícitamente más lento que tiempo real, así que estrechar el bus a una
// muestra por beat no cuesta nada que importe, y a cambio el buffer de DDR que
// prepara el firmware es exactamente un array de int16 entrelazado por canal,
// sin reglas de alineación ni relleno.
//
// Los N_CH canales avanzan en BLOQUE: se juntan N_CH beats en un conjunto y los
// N_CH salidas se presentan válidas a la vez, y el conjunto no se retira hasta
// que TODOS los consumidores lo han tomado. Es más estricto de lo que pide
// AXI4-Stream —un canal lento frena a los demás— y es a propósito: este modo
// existe para corrección bit a bit, donde que los canales vayan en el mismo
// instante de muestra es parte de lo que se compara. Dejar que un canal se
// adelantara convertiría un desfase en un resultado distinto sin ningún error
// visible. Aguas abajo no cambia nada: `drx_ddc_quad_top` es un `generate` de
// cadenas idénticas que ya van en bloque.
//
// `s_axis_last` marca el fin del vector. Se propaga a `last` de los N_CH
// canales del conjunto que lo contiene, no solo al canal del beat donde llegó:
// `last` es un marcador de ventana por canal, y marcarlo en uno solo dejaría a
// `drx_range_gate` cerrando un rayo en un canal y no en los otros dos.
//
// CONDICIÓN QUE EL FIRMWARE TIENE QUE CUMPLIR: la transferencia MM2S lleva un
// número de muestras múltiplo de N_CH. Un conjunto a medio llenar nunca se
// presenta, así que un resto distinto de 0 deja la cadena parada en silencio
// —sin error, sin bandera— hasta la transferencia siguiente. Este módulo no lo
// valida: no puede distinguir "faltan beats" de "todavía no han llegado", que
// es la misma situación un ciclo antes.

`ifndef VECTOR_SOURCE_SV
`define VECTOR_SOURCE_SV

module vector_source
  import drx_params_pkg::*;
#(
    parameter int N_CH = 3,
    parameter int DEPTH = 4000,
    // Un fichero para los N_CH canales (mismo bucle en los tres — contenido
    // distinto por canal es un cambio de un array de parámetros, no de
    // estructura, el día que haga falta distinguir canales cruzados, mismo
    // patrón que ya usa `tb_l1_ddc_tri.sv` en simulación). Sin default: cuál
    // fichero toca es una decisión del top-level por plataforma (D-02, ver
    // `drx_top.sv`), no de este módulo — una `vector_source` que adivinara
    // "zedboard" por defecto sería la misma trampa de plataforma hardcodeada
    // que el gate de `tools/check_hardcoded_clock.py` ya prohíbe para el
    // reloj. Instanciar sin fijar `INIT_FILE` falla `$readmemh` de forma
    // ruidosa en vez de leer en silencio el fichero de la placa equivocada.
    parameter string INIT_FILE = ""
) (
    input logic clk,
    input logic rst_n,

    // 1 = modo Throttled(DDR), las muestras vienen de `s_axis_*`.
    // 0 = BRAM-loop, el modo de siempre. Solo es seguro cambiarlo con la
    // cadena parada: este módulo no vacía el conjunto a medio llenar ni el
    // registro de salida de BRAM al conmutar, igual que `drx_prf_batch_seq`
    // no revalida su configuración a mitad de radial.
    input logic ddr_mode,

    // AXI4-Stream esclavo, 16 bits, una muestra por beat, canales en orden
    // ascendente y repitiendo. Inerte mientras `ddr_mode` esté en 0.
    input  logic                          s_axis_valid,
    output logic                          s_axis_ready,
    input  logic signed [SAMPLE_BITS-1:0] s_axis_data,
    input  logic                          s_axis_last,

    input  logic                          ready[N_CH],
    output logic                          valid[N_CH],
    output logic signed [SAMPLE_BITS-1:0] data [N_CH],
    output logic                          last [N_CH]
);

  localparam int AddrBits = $clog2(DEPTH);
  localparam int ChBits   = (N_CH > 1) ? $clog2(N_CH) : 1;

  // --- Modo Throttled(DDR) --------------------------------------------------
  //
  // Dos estados y nada más: llenando el conjunto de N_CH muestras, o
  // presentándolo. No hay doble buffer a propósito — con backpressure AXIS y
  // un modo que ya es más lento que tiempo real, un segundo conjunto solo
  // añadiría un camino de datos más que verificar sin comprar nada medible.
  logic [ChBits-1:0]            ddr_fill_idx;
  logic                         ddr_presenting;
  logic                         ddr_last_set;
  logic signed [SAMPLE_BITS-1:0] ddr_set[N_CH];

  // El conjunto se retira cuando TODOS los consumidores lo han tomado (ver la
  // cabecera sobre por qué en bloque y no por canal).
  logic ddr_all_taken;
  always_comb begin
    ddr_all_taken = 1'b1;
    for (int c = 0; c < N_CH; c = c + 1) begin
      if (!ready[c]) ddr_all_taken = 1'b0;
    end
  end

  assign s_axis_ready = ddr_mode && !ddr_presenting;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ddr_fill_idx   <= '0;
      ddr_presenting <= 1'b0;
      ddr_last_set   <= 1'b0;
    end else if (!ddr_mode) begin
      // Modo BRAM: se mantiene rearmado, para que una conmutación con la
      // cadena parada empiece siempre en el canal 0 de un conjunto nuevo.
      ddr_fill_idx   <= '0;
      ddr_presenting <= 1'b0;
      ddr_last_set   <= 1'b0;
    end else if (!ddr_presenting) begin
      if (s_axis_valid) begin
        if (s_axis_last) ddr_last_set <= 1'b1;
        if (ddr_fill_idx == ChBits'(N_CH - 1)) begin
          ddr_fill_idx   <= '0;
          ddr_presenting <= 1'b1;
        end else begin
          ddr_fill_idx <= ddr_fill_idx + 1'b1;
        end
      end
    end else if (ddr_all_taken) begin
      ddr_presenting <= 1'b0;
      ddr_last_set   <= 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    if (ddr_mode && !ddr_presenting && s_axis_valid) begin
      ddr_set[ddr_fill_idx] <= s_axis_data;
    end
  end

  genvar gc;
  generate
    for (gc = 0; gc < N_CH; gc = gc + 1) begin : g_ch

      logic [SAMPLE_BITS-1:0] mem[0:DEPTH-1];

      initial $readmemh(INIT_FILE, mem);

      logic [AddrBits-1:0] rd_ptr;
      logic                out_valid_r;
      logic [SAMPLE_BITS-1:0] out_data_r;
      logic                out_last_r;

      logic can_advance;
      assign can_advance = !ddr_mode && (!out_valid_r || ready[gc]);

      // Puerto de lectura registrado a propósito (ver cabecera): `out_data_r`
      // se carga desde `mem[rd_ptr]` solo cuando el dato anterior ya se
      // consumió o todavía no hay ninguno, nunca pisa uno no leído.
      //
      // Dos procesos, no uno: `mem` no puede vivir en un proceso con reset
      // asíncrono en su sensibilidad (confirmado contra Vivado real,
      // 19-sep-2026, sobre `drx_range_gate.sv` — mismo síntoma, misma causa:
      // "RAM is sensitive to asynchronous reset signal", con o sin que el
      // reset toque la memoria). Ninguna BRAM real de Xilinx tiene borrado
      // asíncrono de contenido. `out_data_r` se mueve al proceso sin reset
      // junto con la lectura — su valor tras reset nunca se observa de
      // todas formas, porque `out_valid_r` (que sí se resetea) se lo impide
      // a cualquier consumidor.
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          rd_ptr      <= '0;
          out_valid_r <= 1'b0;
          out_last_r  <= 1'b0;
        end else if (can_advance) begin
          out_last_r  <= (rd_ptr == AddrBits'(DEPTH - 1));
          out_valid_r <= 1'b1;
          rd_ptr      <= (rd_ptr == AddrBits'(DEPTH - 1)) ? '0 : rd_ptr + 1'b1;
        end
      end

      always_ff @(posedge clk) begin
        if (can_advance) begin
          out_data_r <= mem[rd_ptr];
        end
      end

      // El contador de BRAM se congela en modo DDR: así no consume el vector
      // precargado por detrás ni deja el puntero en un sitio arbitrario al
      // volver.
      assign valid[gc] = ddr_mode ? ddr_presenting : out_valid_r;
      assign data[gc]  = ddr_mode ? ddr_set[gc] : signed'(out_data_r);
      assign last[gc]  = ddr_mode ? (ddr_presenting && ddr_last_set)
                                  : (out_valid_r && out_last_r);

    end
  endgenerate

endmodule : vector_source

`endif  // VECTOR_SOURCE_SV
