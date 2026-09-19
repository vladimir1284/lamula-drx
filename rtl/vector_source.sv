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

    input  logic                          ready[N_CH],
    output logic                          valid[N_CH],
    output logic signed [SAMPLE_BITS-1:0] data [N_CH],
    output logic                          last [N_CH]
);

  localparam int AddrBits = $clog2(DEPTH);

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
      assign can_advance = !out_valid_r || ready[gc];

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

      assign valid[gc] = out_valid_r;
      assign data[gc]  = signed'(out_data_r);
      assign last[gc]  = out_valid_r && out_last_r;

    end
  endgenerate

endmodule : vector_source

`endif  // VECTOR_SOURCE_SV
