// Auto-prueba del arnés de L1. NO prueba el DDC.
//
// El arnés de P-09 —lector de `.hex`, comparador bit a bit, plusargs— es código
// que puede estar mal, y si está mal falla en la dirección peligrosa: un
// comparador que no compara da verde con cualquier DUT. Este top lo prueba sin
// necesitar ni xsim ni IP de Xilinx: alimenta al comparador con los propios
// ficheros esperados y comprueba dos cosas opuestas.
//
//   1. Sin corrupción, cero discrepancias sobre las N muestras.
//   2. Con `+corrupt_index=k`, exactamente una discrepancia, y en la muestra k.
//
// El segundo caso es el que importa: demuestra que el comparador sabe fallar.
// Corre en L0 sobre Verilator, en el mismo `make sim` que todo lo demás.
//
// Plusargs propios: `+corrupt_index=<k>` (por defecto ninguno).

`ifndef TB_L1_HARNESS_SV
`define TB_L1_HARNESS_SV

module tb_l1_harness #(
    parameter int WIDTH = 16,
    parameter int MAX_SAMPLES = 1 << 14
) (
    input  logic        clk,
    input  logic        rst_n,
    output logic        done,
    output int unsigned checked,
    output int unsigned mismatches
);

  logic src_ready;
  logic i_valid, q_valid;
  logic i_last, i_done, q_last, q_done;
  logic signed [WIDTH-1:0] i_raw, q_raw;
  logic signed [WIDTH-1:0] i_data;

  int corrupt_index;

  initial begin
    if (!$value$plusargs("corrupt_index=%d", corrupt_index)) begin
      corrupt_index = -1;
    end
  end

  // Las dos ramas se leen de los mismos ficheros que el comparador espera, así
  // que el DUT simulado aquí es la identidad.
  drx_l1_file_source #(
      .WIDTH(WIDTH),
      .MAX_SAMPLES(MAX_SAMPLES),
      .KIND("expected_i")
  ) u_src_i (
      .clk(clk),
      .rst_n(rst_n),
      .ready(src_ready),
      .valid(i_valid),
      .data(i_raw),
      .last(i_last),
      .done(i_done)
  );

  drx_l1_file_source #(
      .WIDTH(WIDTH),
      .MAX_SAMPLES(MAX_SAMPLES),
      .KIND("expected_q")
  ) u_src_q (
      .clk(clk),
      .rst_n(rst_n),
      .ready(src_ready),
      .valid(q_valid),
      .data(q_raw),
      .last(q_last),
      .done(q_done)
  );

  // La corrupción invierte el bit menos significativo de una sola muestra: el
  // error más pequeño que un comparador bit a bit tiene que ver.
  always_comb begin
    i_data = i_raw;
    if (corrupt_index >= 0 && checked == unsigned'(corrupt_index)) begin
      i_data[0] = ~i_raw[0];
    end
  end

  assign src_ready = 1'b1;

  drx_l1_checker #(
      .WIDTH(WIDTH),
      .MAX_SAMPLES(MAX_SAMPLES)
  ) u_checker (
      .clk(clk),
      .rst_n(rst_n),
      .valid(i_valid && q_valid),
      .i_data(i_data),
      .q_data(q_raw),
      .done(done),
      .checked(checked),
      .mismatches(mismatches)
  );

  // Silencia las señales que este top no usa pero el arnés real sí.
  logic unused;
  assign unused = &{1'b0, i_last, i_done, q_last, q_done};

endmodule : tb_l1_harness

`endif  // TB_L1_HARNESS_SV
