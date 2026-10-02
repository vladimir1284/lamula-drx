// L1 — cierre del top-level de 3 canales para ZM1 en ZedBoard (P-12, decisión
// del 9-sep-2026: dos configuraciones de 3 canales, Config A = Tx+H+V, Config
// B = Tx+nominal+atenuado, en vez de los 4-5 canales reales a la vez).
//
// `drx_ddc_quad_top.sv` ya es genérico en N_CH (el `generate` no asume nada
// de "Rx" ni de 4): este testbench solo confirma, con tres estímulos
// DISTINTOS a la vez (mismo argumento que `tb_l1_ddc_quad.sv` para N_CH=4),
// que instanciarlo con N_CH=3 no cruza canales entre sí. No hace falta un
// módulo de top-level nuevo — "el mismo con generics", la opción que ya
// contemplaba docs/alcance/pendientes.md#p-12.
//
// Config A y Config B comparten este mismo DUT y este mismo testbench: la
// diferencia entre ellas es qué fuente analógica alimenta cada canal
// (frontend, fuera de este repo), no la cadena digital — confirmado que la
// muestra de Tx usa el mismo ancho/framing que un canal Rx (P-12, "lo que
// falta para ejecutar esto", punto 2), así que las tres entradas de este
// módulo son intercambiables a efectos de RTL.
//
// Plusargs (los pone tcl/sim_l1_tri.tcl desde tres manifiestos, uno por
// canal, con sufijo `_0`..`_2` salvo `+mode`, compartido):
//   +stimulus_path_N=  +stimulus_count_N=
//   +expected_i_path_N=  +expected_q_path_N=  +expected_count_N=
//   +settling_N=
//   +mode=0|1   0 = fino (R1), 1 = grueso (R2), igual para los 3 canales

`ifndef TB_L1_DDC_TRI_SV
`define TB_L1_DDC_TRI_SV

module tb_l1_ddc_tri;

  import drx_params_pkg::*;

  // Deliberadamente NO N_RX_CH: este top-level de 3 canales es el de las
  // configs A/B de ZedBoard, no una réplica del frontal Rx completo (eso
  // sigue siendo tb_l1_ddc_quad.sv / drx_ddc_quad_top con N_CH=N_RX_CH).
  localparam int N_CH = 3;

  // Igual que tb_l1_ddc_quad.sv: el periodo sale de FS_HZ (D-02).
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

  // --- DUT: drx_ddc_quad_top con N_CH=3 (Config A / Config B) --------------
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

      // Actuación AFC (Z4.5): este testbench no la ejercita -- el NCO queda
      // con el PINC1 inicial de la IP, el comportamiento verificado bajo D-12.
      .nco_pinc   (NCO_PHASE_BITS'(NCO_PHASE_INC)),
      .nco_pinc_we(1'b0),

      .m_valid(iq_valid),
      .m_i    (iq_i),
      .m_q    (iq_q)
  );
`else
  // Mismo razonamiento que tb_l1_ddc_quad.sv: sin DUT no hay nada que
  // comparar, y un testbench que termina en verde sin DUT es peor que uno
  // que no compila. Aborta en cuanto arranca.
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
           "tb_l1_ddc_tri: falta drx_ddc_quad_top (trabajo de Z1). Elabora con +define+DRX_HAVE_DDC cuando exista.");
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
          .CH   (gc),
          .TOLERANCE_LSB(5)  // D-12: techo aceptado del residuo de cuantización del NCO
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
        $fatal(1, "L1 tri: canal %0d, %0d discrepancias de %0d muestras contra el modelo dorado (fuera de la tolerancia de D-12)", c,
               mismatches[c], checked[c]);
      end
      $display("L1 tri: canal %0d, %0d muestras dentro de tolerancia (D-12) contra el modelo dorado", c, checked[c]);
    end
    $finish;
  end

  // Red de seguridad, igual que tb_l1_ddc_quad.sv.
  localparam longint TimeoutCycles = 4_000_000;  // clock-const-ok: ciclos, no frecuencia

  initial begin
    #(TimeoutCycles * 2 * ClkHalfPeriodPs);
    $fatal(1, "L1 tri: timeout");
  end

endmodule : tb_l1_ddc_tri

`endif  // TB_L1_DDC_TRI_SV
