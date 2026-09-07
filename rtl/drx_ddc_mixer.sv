// Mezclador complejo (D-06: el HDL propio se reserva para esto; NCO, CIC y
// FIR son IP de Xilinx). Baja `s_data` a banda base multiplicando por
// cos/sin del NCO — el mismo cálculo que `Ddc.mix()`:
//
//   i[n] = x[n]·cos(wn),   q[n] = x[n]·sin(wn)
//
// P-10, 7-sep-2026: esta nota decía `q[n] = −x[n]·sin(wn)` antes de medirlo
// contra xsim real. El DDS Compiler entrega el seno con la convención de
// signo de `e^{+jwn}`, no `e^{-jwn}` — confirmado bit a bit reconstruyendo
// `nco_sin` a partir del producto crudo del mezclador (`prod_q`) contra un
// estímulo conocido. `prod_q <= -(... * nco_sin)`, más abajo, SIGUE
// llevando el signo menos explícito a propósito: ese menos cancela el
// signo que ya trae `nco_sin` de la IP, y el resultado neto es
// `+x·sin(wn)` en la convención de `Ddc.mix()`. No toques ese signo en el
// RTL sin cambiar también el modelo — es el modelo el que se ajustó, no el
// RTL, porque el RTL ya se comporta como la IP real.
//
// HALLAZGO, primera ejecución real contra IP de verdad (xsim, sonda de señal
// sobre `nco_cos`/`nco_sin` en el primer `nco_valid` consumido): la primera
// pasada de este fichero ataba `nco_ready` al mismo `pop` que vaciaba el FIFO
// de entrada, asumiendo que el DDS Compiler congela su acumulador de fase
// interno mientras `tready` está bajo. Esa muestra no correspondía a fase 0
// como debía (cos/sin distintos del máximo/cero esperados) — el acumulador
// de fase avanza un paso por ciclo en cuanto sale de reset, lo acepte o no
// quien está aguas abajo; como mucho se congela el registro de salida, y ni
// eso se pudo confirmar. Un core que no repite fase cuando no se lo consume
// no puede usarse como elemento elástico: si un ciclo de `nco_valid` no se
// empareja con una muestra ese mismo ciclo, ese paso de fase se pierde para
// siempre y la muestra siguiente que sí se empareje queda desalineada.
//
// Rediseño: `nco_ready` va atado a 1'b1 sin condición (el DDS corre libre) y
// el emparejamiento muestra↔fase ya no puede depender de la disponibilidad
// de aguas abajo. La elasticidad se resuelve con DOS FIFO propios, uno a
// cada lado del único punto que de verdad tiene que ir en lockstep con el
// NCO:
//
//   - FIFO de entrada: absorbe que `s_data` ya esté fluyendo (según
//     `tb_l1_ddc.sv`, muestra a muestra desde el fin de su propio reset de 8
//     ciclos) mucho antes de que el DDS entregue su primera fase válida
//     (tras el estirador de reset de `drx_ddc_top` más la latencia propia
//     del core). Emparejar consume de aquí solo cuando hay muestra Y
//     `nco_valid`, nunca al revés — así nunca se salta un paso de fase por
//     falta de muestra.
//   - FIFO de salida: absorbe la contrapresión real de aguas abajo (que el
//     CIC no pueda aceptar un ciclo dado) SIN que eso le cueste un paso de
//     fase al NCO: el producto ya calculado se encola aquí y se drena contra
//     `m_ready` de forma completamente separada del emparejamiento. Para no
//     comprometerse a un hueco que todavía no se ha escrito (el producto
//     tarda un ciclo registrado en llegar desde el emparejamiento), el hueco
//     se reserva de antemano tratando el FIFO como si tuviera un sitio menos
//     de profundidad real (`OUT_FIFO_DEPTH-1`) a efectos de admitir un nuevo
//     emparejamiento — el sitio de más siempre está libre para la escritura
//     en vuelo, así que la escritura en sí nunca hace falta volver a
//     comprobarla.
//
// `drx_l1_checker` compara valores en el orden en que llegan, no el ciclo en
// que llegan, así que una FIFO más profunda de lo necesario en cualquiera de
// los dos lados no puede romper la comparación bit a bit — como mucho baja
// el throughput, y eso se ve y se corrige ajustando profundidad, no
// revisando la aritmética. Igual que antes, el único caso realista en que
// esto sí rompería la corrección es que el CIC se quedara sin aceptar
// entrada más ciclos de los que `OUT_FIFO_DEPTH` puede absorber — no
// esperado en régimen permanente (el CIC decima ×52 de un flujo continuo),
// y si pasara se vería como un `m_valid` que se queda atrás, no como un
// valor incorrecto.

`ifndef DRX_DDC_MIXER_SV
`define DRX_DDC_MIXER_SV

module drx_ddc_mixer #(
    parameter int SAMPLE_BITS    = 16,
    parameter int NCO_OUT_BITS   = 16,
    parameter int FIFO_DEPTH     = 32,
    parameter int OUT_FIFO_DEPTH = 8
) (
    input logic clk,
    input logic rst_n,

    // entrada de muestras reales, a fs
    input  logic                          s_valid,
    output logic                          s_ready,
    input  logic signed [SAMPLE_BITS-1:0] s_data,

    // NCO: DDS Compiler en modo generador de fase libre — corre sin
    // condición, ver el hallazgo de cabecera.
    input  logic                           nco_valid,
    output logic                           nco_ready,
    input  logic signed [NCO_OUT_BITS-1:0] nco_cos,
    input  logic signed [NCO_OUT_BITS-1:0] nco_sin,

    // salida mezclada, a SAMPLE_BITS — mismo ancho que la entrada, como
    // `Ddc.mix()`
    output logic                          m_valid,
    input  logic                          m_ready,
    output logic signed [SAMPLE_BITS-1:0] m_i,
    output logic signed [SAMPLE_BITS-1:0] m_q
);

  assign nco_ready = 1'b1;

  // --- FIFO de entrada: absorbe el arranque del NCO ------------------------
  localparam int InPtrW = $clog2(FIFO_DEPTH);
  // Un bit más que InPtrW: InPtrW solo indexa 0..FIFO_DEPTH-1, pero el
  // CONTEO tiene que poder representar FIFO_DEPTH (lleno) además de 0
  // (vacío).
  localparam int InCountW = InPtrW + 1;

  logic signed [SAMPLE_BITS-1:0] in_mem[0:FIFO_DEPTH-1];
  logic [InPtrW-1:0] in_wr_ptr, in_rd_ptr;
  logic [InCountW-1:0] in_count;

  wire in_full  = (in_count == InCountW'(FIFO_DEPTH));
  wire in_empty = (in_count == '0);

  assign s_ready = !in_full;
  wire in_wr_en = s_valid && s_ready;

  // --- FIFO de salida: absorbe la contrapresión de aguas abajo -------------
  localparam int OutPtrW = $clog2(OUT_FIFO_DEPTH);
  localparam int OutCountW = OutPtrW + 1;

  logic signed [SAMPLE_BITS-1:0] out_mem_i[0:OUT_FIFO_DEPTH-1];
  logic signed [SAMPLE_BITS-1:0] out_mem_q[0:OUT_FIFO_DEPTH-1];
  logic [OutPtrW-1:0] out_wr_ptr, out_rd_ptr;
  logic [OutCountW-1:0] out_count;

  wire out_empty = (out_count == '0);
  // Un sitio de margen permanente: reserva el hueco para la escritura que
  // ya está "en vuelo" (el producto del emparejamiento de este mismo ciclo,
  // que no llega al FIFO hasta el ciclo siguiente) sin tener que volver a
  // comprobar la ocupación en el momento de escribir — ver el hallazgo de
  // cabecera.
  wire out_pair_full = (out_count >= OutCountW'(OUT_FIFO_DEPTH - 1));

  // Empareja UNA muestra en cola con EL paso de fase que el NCO entrega este
  // mismo ciclo. Nunca se salta un `nco_valid` a propósito: eso desalinearía
  // fase↔muestra para siempre, porque el NCO no repite paso.
  wire pair_en = !in_empty && nco_valid && !out_pair_full;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      in_wr_ptr <= '0;
      in_rd_ptr <= '0;
      in_count  <= '0;
    end else begin
      if (in_wr_en) begin
        in_mem[in_wr_ptr] <= s_data;
        in_wr_ptr <= (in_wr_ptr == InPtrW'(FIFO_DEPTH - 1)) ? '0 : in_wr_ptr + 1'b1;
      end
      if (pair_en) begin
        in_rd_ptr <= (in_rd_ptr == InPtrW'(FIFO_DEPTH - 1)) ? '0 : in_rd_ptr + 1'b1;
      end
      unique case ({in_wr_en, pair_en})
        2'b10:   in_count <= in_count + 1'b1;
        2'b01:   in_count <= in_count - 1'b1;
        default: in_count <= in_count;
      endcase
    end
  end

  // ---------------------------------------------------------------------
  // HALLAZGO, primera ejecución real contra IP de verdad: con `Has_TREADY
  // {true}` en `dds_compiler_nco` (como estaba configurada la IP hasta este
  // punto), la primera `nco_cos`/`nco_sin` válida tras reset NO correspondía
  // a fase 0 (se midió un sesgo de varios grados, no reproducible con una
  // cuenta cerrada de ciclos). La causa está documentada en pg141 (v6.0),
  // "Latency Options": "When TREADY is selected the AXI interfaces buffer
  // data as a FIFO. This buffering results in NON-DETERMINISTIC latency."
  // Es decir, el sesgo no era un offset de fase fijo que se pudiera
  // compensar girando la muestra — era el estado de llenado de una FIFO
  // interna que la propia documentación de Xilinx describe como no
  // determinista. Un giro complejo por una referencia capturada en caliente
  // llegó a cancelar el canal Q por completo, pero dejaba un sesgo de ±1 LSB
  // en régimen permanente (y uno bastante mayor en el transitorio, por
  // acumulación en el CIC): girar dos valores de LUT ya cuantizados no
  // reconstruye el valor exacto de la LUT en el índice deseado, así que
  // nunca iba a cerrar bit a bit contra el modelo.
  //
  // La solución de verdad es no depender de esa FIFO: este mezclador nunca
  // contrapresura al NCO (`nco_ready` va atado a 1'b1 más arriba desde el
  // primer rediseño), así que pedir `Has_TREADY` en la IP no compraba nada.
  // `tcl/gen_ip.tcl` ahora genera `dds_compiler_nco` con `Has_TREADY
  // {false}` — latencia FIJA, sin FIFO — y con eso la primera muestra válida
  // tras `aresetn` es de verdad fase 0. Sin sesgo que compensar, el
  // mezclador vuelve a ser la mezcla directa de `Ddc.mix()`, un solo
  // `drx_round`.
  logic signed [SAMPLE_BITS+NCO_OUT_BITS-1:0] prod_i, prod_q;
  logic prod_valid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      prod_valid <= 1'b0;
      prod_i     <= '0;
      prod_q     <= '0;
    end else begin
      prod_valid <= pair_en;
      if (pair_en) begin
        prod_i <= in_mem[in_rd_ptr] * nco_cos;
        prod_q <= -(in_mem[in_rd_ptr] * nco_sin);
      end
    end
  end

  // OUT_W se fija a SAMPLE_BITS a propósito, no al SumW-SHIFT natural de
  // drx_round (que daría SAMPLE_BITS+1): `Ddc.mix()` devuelve `(i, q)` "a
  // sample_bits" y así los consume el CIC. El único caso en que el resultado
  // matemático de redondear no cabe en SAMPLE_BITS es la esquina extrema —
  // entrada y LUT del NCO a la vez en su valor negativo máximo—, que ni el
  // modelo satura aquí (ver chain.py: `mix()` no llama a `fixed.saturate`) ni
  // ejercitan los vectores de aceptación de `tools/gen_l1_vectors.py`.
  logic signed [SAMPLE_BITS-1:0] round_i, round_q;

  drx_round #(
      .IN_W (SAMPLE_BITS + NCO_OUT_BITS),
      .SHIFT(NCO_OUT_BITS - 1),
      .OUT_W(SAMPLE_BITS)
  ) u_round_i (
      .in_data (prod_i),
      .out_data(round_i)
  );

  drx_round #(
      .IN_W (SAMPLE_BITS + NCO_OUT_BITS),
      .SHIFT(NCO_OUT_BITS - 1),
      .OUT_W(SAMPLE_BITS)
  ) u_round_q (
      .in_data (prod_q),
      .out_data(round_q)
  );

  // Escritura sin condición: el hueco ya quedó reservado por `pair_en`
  // (`out_pair_full` deja siempre libre el último sitio real), así que no
  // hace falta volver a comprobar ocupación aquí.
  wire out_wr_en = prod_valid;
  wire out_rd_en = !out_empty && m_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_wr_ptr <= '0;
      out_rd_ptr <= '0;
      out_count  <= '0;
    end else begin
      if (out_wr_en) begin
        out_mem_i[out_wr_ptr] <= round_i;
        out_mem_q[out_wr_ptr] <= round_q;
        out_wr_ptr <= (out_wr_ptr == OutPtrW'(OUT_FIFO_DEPTH - 1)) ? '0 : out_wr_ptr + 1'b1;
      end
      if (out_rd_en) begin
        out_rd_ptr <= (out_rd_ptr == OutPtrW'(OUT_FIFO_DEPTH - 1)) ? '0 : out_rd_ptr + 1'b1;
      end
      unique case ({out_wr_en, out_rd_en})
        2'b10:   out_count <= out_count + 1'b1;
        2'b01:   out_count <= out_count - 1'b1;
        default: out_count <= out_count;
      endcase
    end
  end

  assign m_valid = !out_empty;
  assign m_i = out_mem_i[out_rd_ptr];
  assign m_q = out_mem_q[out_rd_ptr];

endmodule : drx_ddc_mixer

`endif  // DRX_DDC_MIXER_SV
