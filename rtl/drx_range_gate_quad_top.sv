// Réplica de `drx_range_gate` a N_CH canales — mismo patrón que
// `drx_ddc_quad_top.sv` para `drx_ddc_top`: un `generate` con N_CH instancias
// independientes, sin lógica propia. Fichero nuevo en vez de tocar
// `drx_ddc_quad_top.sv` a propósito: ese fichero es el cierre ya verificado
// de la réplica del DDC (`sim/tb_sv/tb_l1_ddc_quad.sv` / `tb_l1_ddc_tri.sv`,
// ver su propia cabecera "no se toca este fichero") y el gating es una etapa
// aguas abajo, no una variación de esa misma réplica.
//
// N_CH por defecto es N_RX_CH por lo mismo que en `drx_ddc_quad_top.sv`: el
// caso real de la ZU9. Las dos configuraciones de 3 canales de ZedBoard
// (P-12) lo instancian con N_CH=3 exactamente igual que instancian
// `drx_ddc_quad_top` — mismo módulo, otro generic.
//
// `BINS_MAX` se reexporta como parámetro (en vez de fijar `drx_range_gate` al
// valor del paquete) por la misma razón que en `drx_range_gate.sv`: que un
// testbench pueda instanciar esto con rayos cortos.
//
// `bin_count` (D-15, 25-sep-2026) es COMPARTIDO entre los N_CH canales, igual
// que `ray_start`: un solo conteo de bins del lote activo (de
// `drx_timing_engine`) para todos los canales de un mismo radial. Reemplaza
// `mode_coarse`, que ya no llega hasta `drx_range_gate` -- ver la cabecera de
// ese fichero y D-15 en decisiones.md.

`ifndef DRX_RANGE_GATE_QUAD_TOP_SV
`define DRX_RANGE_GATE_QUAD_TOP_SV

module drx_range_gate_quad_top
  import drx_params_pkg::*;
#(
    parameter int N_CH     = N_RX_CH,
    parameter int BINS_MAX = BINS_MODE_FINE,
    parameter int BinsBits = 32
) (
    input logic clk,
    input logic rst_n,

    input logic                      s_valid[N_CH],
    input logic signed [IQ_BITS-1:0] s_i    [N_CH],
    input logic signed [IQ_BITS-1:0] s_q    [N_CH],

    input logic [BinsBits-1:0] bin_count,

    output logic                      m_valid[N_CH],
    input  logic                      m_ready[N_CH],
    output logic signed [IQ_BITS-1:0] m_i    [N_CH],
    output logic signed [IQ_BITS-1:0] m_q    [N_CH],
    output logic                      m_last [N_CH],

    // Write-1-to-clear por canal, desde el mapa de registros AXI-Lite — ver
    // la cabecera de `drx_range_gate.sv`.
    input  logic clear  [N_CH],
    output logic overrun[N_CH],

    // `ray_start` (D-14) es COMPARTIDO entre los N_CH canales, igual que
    // `bin_count`: un solo `pulse_trig` de `drx_timing_engine` marca el mismo
    // instante de disparo para todos los canales de un mismo radial.
    input logic ray_start
);

  genvar gc;
  generate
    for (gc = 0; gc < N_CH; gc = gc + 1) begin : g_ch
      drx_range_gate #(
          .BINS_MAX(BINS_MAX),
          .BinsBits(BinsBits)
      ) u_gate (
          .clk (clk),
          .rst_n(rst_n),

          .s_valid(s_valid[gc]),
          .s_i    (s_i[gc]),
          .s_q    (s_q[gc]),

          .bin_count(bin_count),

          .m_valid(m_valid[gc]),
          .m_ready(m_ready[gc]),
          .m_i    (m_i[gc]),
          .m_q    (m_q[gc]),
          .m_last (m_last[gc]),

          .clear  (clear[gc]),
          .overrun(overrun[gc]),

          .ray_start(ray_start)
      );
    end
  endgenerate

endmodule : drx_range_gate_quad_top

`endif  // DRX_RANGE_GATE_QUAD_TOP_SV
