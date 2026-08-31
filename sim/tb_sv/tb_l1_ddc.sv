// L1 — testbench de integración de la cadena DDC construida con IP de Xilinx.
//
// Este es el testbench que cierra el hito ZM1: coincidencia bit a bit entre la
// IP real (DDS / CIC / FIR Compiler) y el modelo dorado. No pasa por cocotb —
// ver P-09— sino que es SystemVerilog nativo y lo lanza `tcl/sim_l1.tcl` sobre
// xsim. El arnés que usa (`drx_l1_file_source` + `drx_l1_checker`) es el mismo
// que la auto-prueba de `tb_l1_harness`, que sí corre hoy sobre Verilator: el
// lector y el comparador ya están verificados antes de que exista el DUT.
//
// ESTADO: no elabora todavía. `drx_ddc_top` es trabajo de Z1 y aún no existe;
// la instancia está tras `DRX_HAVE_DDC` para que este fichero pueda pasar el
// lint mientras tanto, y ese guardia se borra el día que Z1 escriba el módulo.
// Igual que el flujo de `tcl/`, esto está escrito y revisado pero NO EJECUTADO.
//
// Plusargs (los pone tcl/sim_l1.tcl desde el manifiesto del caso):
//   +stimulus_path=  +stimulus_count=
//   +expected_i_path=  +expected_q_path=  +expected_count=  +settling=
//   +mode=0|1   0 = fino (R1), 1 = grueso (R2)

`ifndef TB_L1_DDC_SV
`define TB_L1_DDC_SV

module tb_l1_ddc;

  import drx_params_pkg::*;

  // El periodo sale de FS_HZ como todo lo demás (D-02): un testbench con el
  // periodo escrito a mano miente en cuanto se cambia de plataforma. Se calcula
  // en picosegundos y con enteros para no arrastrar coma flotante al eje de
  // tiempos. La unidad de tiempo NO se declara aquí: la fija el simulador
  // (`-timescale 1ps/1ps` en xelab, `--timescale 1ps/1ps` en el lint), porque
  // declararla solo en este módulo y no en el RTL mezcla escalas.
  localparam longint ClkHalfPeriodPs = 64'd1_000_000_000_000 / (2 * FS_HZ);

  logic clk = 1'b0;
  logic rst_n = 1'b0;

  /* verilator lint_off BLKSEQ */
  // Generador de reloj de testbench: la asignación bloqueante es la forma
  // canónica y aquí no hay carrera porque nada más escribe `clk`.
  always #(ClkHalfPeriodPs) clk = ~clk;
  /* verilator lint_on BLKSEQ */

  // --- estímulo -------------------------------------------------------------
  logic                          stim_valid;
  logic                          stim_ready;
  logic                          stim_last;
  logic                          stim_done;
  logic signed [SAMPLE_BITS-1:0] stim_data;

  drx_l1_file_source #(
      .WIDTH(SAMPLE_BITS),
      .PATH_FMT("stimulus_path=%s"),
      .COUNT_FMT("stimulus_count=%d")
  ) u_stimulus (
      .clk(clk),
      .rst_n(rst_n),
      .ready(stim_ready),
      .valid(stim_valid),
      .data(stim_data),
      .last(stim_last),
      .done(stim_done)
  );

  // --- DUT ------------------------------------------------------------------
  logic                       iq_valid;
  logic signed [IQ_BITS-1:0]  iq_i;
  logic signed [IQ_BITS-1:0]  iq_q;
  logic                       mode_coarse;

  int mode_arg;
  initial begin
    if (!$value$plusargs("mode=%d", mode_arg)) mode_arg = 0;
    mode_coarse = (mode_arg != 0);
  end

`ifdef DRX_HAVE_DDC
  drx_ddc_top u_dut (
      .clk(clk),
      .rst_n(rst_n),
      .s_valid(stim_valid),
      .s_ready(stim_ready),
      .s_data(stim_data),
      .s_last(stim_last),
      .mode_coarse(mode_coarse),
      .m_valid(iq_valid),
      .m_i(iq_i),
      .m_q(iq_q)
  );
`else
  // Sin DUT no hay nada que comparar, y un testbench que termina en verde sin
  // DUT es peor que uno que no compila. Aborta en cuanto arranca.
  assign stim_ready = 1'b1;
  assign iq_valid   = 1'b0;
  assign iq_i       = '0;
  assign iq_q       = '0;
  logic unused_no_dut;
  assign unused_no_dut = &{1'b0, stim_valid, stim_last, stim_done, mode_coarse, stim_data};
  initial begin
    $fatal(1,
           "tb_l1_ddc: falta drx_ddc_top (trabajo de Z1). Elabora con +define+DRX_HAVE_DDC cuando exista.");
  end
`endif

  // --- comparación ----------------------------------------------------------
  logic        check_done;
  int unsigned checked;
  int unsigned mismatches;

  drx_l1_checker #(
      .WIDTH(IQ_BITS)
  ) u_checker (
      .clk(clk),
      .rst_n(rst_n),
      .valid(iq_valid),
      .i_data(iq_i),
      .q_data(iq_q),
      .done(check_done),
      .checked(checked),
      .mismatches(mismatches)
  );

  // --- secuencia ------------------------------------------------------------
  initial begin
    repeat (8) @(posedge clk);
    rst_n = 1'b1;

    wait (check_done);
    repeat (4) @(posedge clk);

    if (mismatches != 0) begin
      $fatal(1, "L1: %0d discrepancias de %0d muestras contra el modelo dorado", mismatches,
             checked);
    end
    $display("L1: %0d muestras coinciden bit a bit con el modelo dorado", checked);
    $finish;
  end

  // Red de seguridad: sin esto un DUT que no saca nada cuelga el runner de CI en
  // vez de fallar. El límite es generoso a propósito.
  // El tiempo de pared que representa lo fija ClkHalfPeriodPs, que sí deriva de FS_HZ.
  localparam longint TimeoutCycles = 4_000_000;  // clock-const-ok: ciclos, no frecuencia

  initial begin
    #(TimeoutCycles * 2 * ClkHalfPeriodPs);
    $fatal(1, "L1: timeout; el DUT entregó %0d muestras", checked);
  end

endmodule : tb_l1_ddc

`endif  // TB_L1_DDC_SV
