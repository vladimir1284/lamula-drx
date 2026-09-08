// L1 — cierre real de ZM1: "coincide bit a bit con el modelo NumPy, en los
// cuatro canales y en ambos tamaños de celda" (docs/implementacion/fases.md).
//
// `tb_l1_ddc.sv` ya prueba bit a bit UN canal y no se toca (su propio aviso
// de cabecera lo dice). Este fichero es su réplica a N_RX_CH canales: mismo
// arnés (`drx_l1_file_source` / `drx_l1_checker`, con el parámetro CH que
// añaden para esto), mismo DUT por canal (`drx_ddc_top`, vía
// `drx_ddc_quad_top`), pero con CUATRO estímulos DISTINTOS a la vez — uno por
// canal — para que un cruce entre ramas del `generate` de
// `drx_ddc_quad_top.sv` (p. ej. el canal 2 leyendo la salida o el estímulo
// del canal 0) se vea como discrepancia en vez de colar por casualidad de
// datos iguales.
//
// Lo lanza `tcl/sim_l1_quad.tcl`, que fija qué caso de
// `tools/gen_l1_vectors.py` va en cada canal (tono_if -> 0, tono_desplazado
// -> 1, dos_tonos -> 2, tono_desplazado_neg -> 3) y corre una vez por modo
// (fino/grueso).
//
// Plusargs (los pone tcl/sim_l1_quad.tcl desde los cuatro manifiestos, uno
// por canal, con sufijo `_0`.._3` salvo `+mode`, compartido):
//   +stimulus_path_N=  +stimulus_count_N=
//   +expected_i_path_N=  +expected_q_path_N=  +expected_count_N=
//   +settling_N=
//   +mode=0|1   0 = fino (R1), 1 = grueso (R2), igual para los 4 canales

`ifndef TB_L1_DDC_QUAD_SV
`define TB_L1_DDC_QUAD_SV

module tb_l1_ddc_quad;

  import drx_params_pkg::*;

  localparam int N_CH = N_RX_CH;

  // Igual que tb_l1_ddc.sv: el periodo sale de FS_HZ (D-02), no de un
  // literal. La unidad de tiempo la fija el simulador (`-timescale
  // 1ps/1ps`), no este módulo.
  localparam longint ClkHalfPeriodPs = 64'd1_000_000_000_000 / (2 * FS_HZ);

  logic clk = 1'b0;
  logic rst_n = 1'b0;

  /* verilator lint_off BLKSEQ */
  always #(ClkHalfPeriodPs) clk = ~clk;
  /* verilator lint_on BLKSEQ */

  // --- estímulo, uno por canal ----------------------------------------------
  logic                          stim_valid[N_CH];
  logic                          stim_ready[N_CH];
  logic                          stim_last [N_CH];
  logic                          stim_done [N_CH];
  logic signed [SAMPLE_BITS-1:0] stim_data [N_CH];

  genvar gs;
  generate
    for (gs = 0; gs < N_CH; gs = gs + 1) begin : g_stimulus
      drx_l1_file_source #(
          .WIDTH(SAMPLE_BITS),
          .KIND ("stimulus"),
          .CH   (gs)
      ) u_stimulus (
          .clk  (clk),
          .rst_n(rst_n),
          .ready(stim_ready[gs]),
          .valid(stim_valid[gs]),
          .data (stim_data[gs]),
          .last (stim_last[gs]),
          .done (stim_done[gs])
      );
    end
  endgenerate

  // --- DUT: réplica de drx_ddc_top a los N_CH canales -----------------------
  logic                      iq_valid[N_CH];
  logic signed [IQ_BITS-1:0] iq_i    [N_CH];
  logic signed [IQ_BITS-1:0] iq_q    [N_CH];
  logic                      mode_coarse;

  int mode_arg;
  initial begin
    if (!$value$plusargs("mode=%d", mode_arg)) mode_arg = 0;
    mode_coarse = (mode_arg != 0);
  end

`ifdef DRX_HAVE_DDC
  drx_ddc_quad_top #(
      .N_CH(N_CH)
  ) u_dut (
      .clk (clk),
      .rst_n(rst_n),

      .s_valid(stim_valid),
      .s_ready(stim_ready),
      .s_data (stim_data),
      .s_last (stim_last),

      .mode_coarse(mode_coarse),

      .m_valid(iq_valid),
      .m_i    (iq_i),
      .m_q    (iq_q)
  );
`else
  // Mismo razonamiento que tb_l1_ddc.sv: sin DUT no hay nada que comparar, y
  // un testbench que termina en verde sin DUT es peor que uno que no
  // compila. Aborta en cuanto arranca.
  genvar gu;
  generate
    for (gu = 0; gu < N_CH; gu = gu + 1) begin : g_no_dut
      assign stim_ready[gu] = 1'b1;
      assign iq_valid[gu]   = 1'b0;
      assign iq_i[gu]       = '0;
      assign iq_q[gu]       = '0;

      logic unused_no_dut_ch;
      assign unused_no_dut_ch = &{1'b0, stim_valid[gu], stim_last[gu], stim_done[gu], stim_data[gu]};
    end
  endgenerate

  logic unused_no_dut;
  assign unused_no_dut = &{1'b0, mode_coarse};

  initial begin
    $fatal(1,
           "tb_l1_ddc_quad: falta drx_ddc_quad_top (trabajo de Z1). Elabora con +define+DRX_HAVE_DDC cuando exista.");
  end
`endif

  // --- comparación, una por canal -------------------------------------------
  logic        check_done [N_CH];
  int unsigned checked    [N_CH];
  int unsigned mismatches [N_CH];

  genvar gc;
  generate
    for (gc = 0; gc < N_CH; gc = gc + 1) begin : g_checker
      drx_l1_checker #(
          .WIDTH(IQ_BITS),
          .CH   (gc)
      ) u_checker (
          .clk       (clk),
          .rst_n     (rst_n),
          .valid     (iq_valid[gc]),
          .i_data    (iq_i[gc]),
          .q_data    (iq_q[gc]),
          .done      (check_done[gc]),
          .checked   (checked[gc]),
          .mismatches(mismatches[gc])
      );
    end
  endgenerate

  logic all_channels_done;
  always_comb begin
    all_channels_done = 1'b1;
    for (int c = 0; c < N_CH; c++) all_channels_done &= check_done[c];
  end

  // --- secuencia -------------------------------------------------------------
  initial begin
    repeat (8) @(posedge clk);
    rst_n = 1'b1;

    wait (all_channels_done);
    repeat (4) @(posedge clk);

    for (int c = 0; c < N_CH; c++) begin
      if (mismatches[c] != 0) begin
        $fatal(1, "L1 quad: canal %0d, %0d discrepancias de %0d muestras contra el modelo dorado", c,
               mismatches[c], checked[c]);
      end
      $display("L1 quad: canal %0d, %0d muestras coinciden bit a bit con el modelo dorado", c, checked[c]);
    end
    $finish;
  end

  // Red de seguridad, igual que tb_l1_ddc.sv.
  localparam longint TimeoutCycles = 4_000_000;  // clock-const-ok: ciclos, no frecuencia

  initial begin
    #(TimeoutCycles * 2 * ClkHalfPeriodPs);
    $fatal(1, "L1 quad: timeout");
  end

endmodule : tb_l1_ddc_quad

`endif  // TB_L1_DDC_QUAD_SV
