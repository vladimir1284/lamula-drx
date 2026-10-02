// Shim SOLO de testbench para `vector_source` (L0, cocotb+Verilator) — no
// entra en `rtl/filelist.f` (no es RTL de producción, ver la cabecera de
// `sim/runner.py` sobre `extra_sources`).
//
// Mismo motivo y mismo patrón que `drx_ray_packer_tb_dut.sv`: los puertos por
// canal de `vector_source` son arrays SIN empaquetar (`logic valid[N_CH]`), y
// la VPI que genera `--public-flat-rw` no los expone como objetos indexables
// desde cocotb. Este módulo solo re-empaqueta puerto a puerto; no toca ni un
// bit de `vector_source`.
//
// `DEPTH` e `INIT_FILE` son parámetros para que el test pueda usar un vector
// corto y propio en vez del de `tools/gen_vector_source_init.py`: la BRAM real
// son 4000 muestras por canal y recorrerla entera para ver un `last` costaría
// 4000 ciclos por cada caso.
//
// Orden de bits: canal 0 en el grupo menos significativo de cada bus
// empaquetado, el mismo convenio que el shim del empaquetador de rayo.

`ifndef VECTOR_SOURCE_TB_DUT_SV
`define VECTOR_SOURCE_TB_DUT_SV

module vector_source_tb_dut
  import drx_params_pkg::*;
#(
    parameter int N_CH = 3,
    parameter int DEPTH = 8,
    parameter string INIT_FILE = ""
) (
    input logic clk,
    input logic rst_n,

    input logic ddr_mode,

    input  logic                          s_axis_valid,
    output logic                          s_axis_ready,
    input  logic signed [SAMPLE_BITS-1:0] s_axis_data,
    input  logic                          s_axis_last,

    input  logic [N_CH-1:0]                       ready,
    output logic [N_CH-1:0]                       valid,
    output logic [N_CH-1:0][SAMPLE_BITS-1:0]      data,
    output logic [N_CH-1:0]                       last
);

  logic                          ready_arr[N_CH];
  logic                          valid_arr[N_CH];
  logic signed [SAMPLE_BITS-1:0] data_arr [N_CH];
  logic                          last_arr [N_CH];

  genvar gc;
  generate
    for (gc = 0; gc < N_CH; gc = gc + 1) begin : g_map
      assign ready_arr[gc] = ready[gc];
      assign valid[gc]     = valid_arr[gc];
      assign data[gc]      = data_arr[gc];
      assign last[gc]      = last_arr[gc];
    end
  endgenerate

  vector_source #(
      .N_CH(N_CH),
      .DEPTH(DEPTH),
      .INIT_FILE(INIT_FILE)
  ) u_dut (
      .clk  (clk),
      .rst_n(rst_n),

      .ddr_mode(ddr_mode),

      .s_axis_valid(s_axis_valid),
      .s_axis_ready(s_axis_ready),
      .s_axis_data (s_axis_data),
      .s_axis_last (s_axis_last),

      .ready(ready_arr),
      .valid(valid_arr),
      .data (data_arr),
      .last (last_arr)
  );

endmodule : vector_source_tb_dut

`endif  // VECTOR_SOURCE_TB_DUT_SV
