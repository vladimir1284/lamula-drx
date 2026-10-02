// Shim SOLO de testbench para `drx_ray_packer` (L0, cocotb+Verilator) — no
// entra en `rtl/filelist.f` (no es RTL de producción, ver la cabecera de
// `sim/runner.py` sobre `extra_sources`).
//
// Por qué hace falta: `drx_ray_packer` (como el resto de los módulos "quad"
// de N_CH canales de este repo) usa arrays SIN empaquetar
// (`logic s_valid[N_CH]`) para sus puertos por canal — el mismo patrón que
// `drx_range_gate_quad_top`/`drx_ddc_quad_top`, que por eso tampoco tienen
// test L0 propio, solo L1 (xsim). Probado en esta sesión: la VPI que genera
// `--public-flat-rw` (Verilator) no expone los elementos de un array SIN
// empaquetar de un puerto de TOP como objetos indexables desde cocotb
// ("IndexError: s_valid(GPI_REGISTER) contains no object at index 0") — un
// array CON empaquetar sí (mismo patrón que ya usan `overrun_in`/
// `ray_truncated_in` de `drx_axil_regs.sv`, con test L0 real). Este módulo
// solo re-empaqueta puerto a puerto, sin tocar ni un bit de `drx_ray_packer`.
//
// Orden de bits: canal 0 en el grupo menos significativo de cada bus
// empaquetado (`s_i[N_CH-1:0][IQ_BITS-1:0]`, canal 0 en `[IQ_BITS-1:0]`) —
// el testbench de Python empaqueta/desempaqueta con ese mismo convenio.

`ifndef DRX_RAY_PACKER_TB_DUT_SV
`define DRX_RAY_PACKER_TB_DUT_SV

module drx_ray_packer_tb_dut
  import drx_params_pkg::*;
#(
    parameter int N_CH = 3
) (
    input logic clk,
    input logic rst_n,

    input  logic [N_CH-1:0]                     s_valid,
    output logic [N_CH-1:0]                     s_ready,
    input  logic        [N_CH-1:0][IQ_BITS-1:0] s_i,
    input  logic        [N_CH-1:0][IQ_BITS-1:0] s_q,
    input  logic [N_CH-1:0]                     s_last,

    input logic [31:0] meta_trig_count,
    input logic [15:0] meta_bin_count,
    input logic        meta_batch_high,
    input logic        meta_mode_coarse,

    output logic                 m_valid,
    input  logic                 m_ready,
    output logic [2*IQ_BITS-1:0] m_data,
    output logic                 m_last
);

  logic                      s_valid_arr[N_CH];
  logic                      s_ready_arr[N_CH];
  logic signed [IQ_BITS-1:0] s_i_arr    [N_CH];
  logic signed [IQ_BITS-1:0] s_q_arr    [N_CH];
  logic                      s_last_arr [N_CH];

  genvar gc;
  generate
    for (gc = 0; gc < N_CH; gc = gc + 1) begin : g_map
      assign s_valid_arr[gc] = s_valid[gc];
      assign s_ready[gc]     = s_ready_arr[gc];
      assign s_i_arr[gc]     = s_i[gc];
      assign s_q_arr[gc]     = s_q[gc];
      assign s_last_arr[gc]  = s_last[gc];
    end
  endgenerate

  drx_ray_packer #(
      .N_CH(N_CH)
  ) u_dut (
      .clk  (clk),
      .rst_n(rst_n),

      .s_valid(s_valid_arr),
      .s_ready(s_ready_arr),
      .s_i    (s_i_arr),
      .s_q    (s_q_arr),
      .s_last (s_last_arr),

      .meta_trig_count (meta_trig_count),
      .meta_bin_count  (meta_bin_count),
      .meta_batch_high (meta_batch_high),
      .meta_mode_coarse(meta_mode_coarse),

      .m_valid(m_valid),
      .m_ready(m_ready),
      .m_data (m_data),
      .m_last (m_last)
  );

endmodule : drx_ray_packer_tb_dut

`endif  // DRX_RAY_PACKER_TB_DUT_SV
