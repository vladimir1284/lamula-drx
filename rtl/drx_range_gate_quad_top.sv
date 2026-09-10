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
// `BINS_FINE`/`BINS_COARSE` se reexportan como parámetros (en vez de fijar
// `drx_range_gate` a los valores del paquete) por la misma razón que en
// `drx_range_gate.sv`: que un testbench pueda instanciar esto con rayos
// cortos.

`ifndef DRX_RANGE_GATE_QUAD_TOP_SV
`define DRX_RANGE_GATE_QUAD_TOP_SV

module drx_range_gate_quad_top
  import drx_params_pkg::*;
#(
    parameter int N_CH        = N_RX_CH,
    parameter int BINS_FINE   = BINS_MODE_FINE,
    parameter int BINS_COARSE = BINS_MODE_COARSE
) (
    input logic clk,
    input logic rst_n,

    input logic                      s_valid[N_CH],
    input logic signed [IQ_BITS-1:0] s_i    [N_CH],
    input logic signed [IQ_BITS-1:0] s_q    [N_CH],

    input logic mode_coarse,

    output logic                      m_valid[N_CH],
    input  logic                      m_ready[N_CH],
    output logic signed [IQ_BITS-1:0] m_i    [N_CH],
    output logic signed [IQ_BITS-1:0] m_q    [N_CH],
    output logic                      m_last [N_CH],

    output logic overrun[N_CH]
);

  genvar gc;
  generate
    for (gc = 0; gc < N_CH; gc = gc + 1) begin : g_ch
      drx_range_gate #(
          .BINS_FINE  (BINS_FINE),
          .BINS_COARSE(BINS_COARSE)
      ) u_gate (
          .clk (clk),
          .rst_n(rst_n),

          .s_valid(s_valid[gc]),
          .s_i    (s_i[gc]),
          .s_q    (s_q[gc]),

          .mode_coarse(mode_coarse),

          .m_valid(m_valid[gc]),
          .m_ready(m_ready[gc]),
          .m_i    (m_i[gc]),
          .m_q    (m_q[gc]),
          .m_last (m_last[gc]),

          .overrun(overrun[gc])
      );
    end
  endgenerate

endmodule : drx_range_gate_quad_top

`endif  // DRX_RANGE_GATE_QUAD_TOP_SV
