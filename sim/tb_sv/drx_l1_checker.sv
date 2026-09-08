// Comparador bit a bit contra la salida esperada del modelo dorado (D-03).
//
// La otra mitad del camino de P-09: lee `expected_i.hex` / `expected_q.hex` y
// compara cada muestra que sale del DUT. No hay tolerancia, no hay ventana, no
// hay «se parece»: o es el mismo entero o es un fallo, que es lo que dice D-03.
//
// Cuenta discrepancias en vez de abortar en la primera: un fallo de escalado da
// error en todas las muestras y un fallo de coeficiente solo en algunas, y esa
// diferencia es diagnóstico. El testbench decide si aborta.
//
// Plusargs:
//   +expected_i_path=<ruta>  +expected_q_path=<ruta>  +expected_count=<n>
//   +settling=<n>   muestras iniciales que se comparan igual pero se reportan
//                   como transitorio de arranque si fallan
//
// CH (Z1, réplica a los cuatro canales, ver drx_l1_file_source.sv): -1 (por
// defecto) usa los nombres de plusarg de siempre, sin sufijo — tb_l1_ddc.sv y
// tb_l1_harness.sv no cambian de comportamiento. 0..3 los lee con sufijo
// `_N` para tb_l1_ddc_quad.sv, mismo truco de literal-por-rama por el
// hallazgo P-09 de xsim con `$value$plusargs`.

`ifndef DRX_L1_CHECKER_SV
`define DRX_L1_CHECKER_SV

module drx_l1_checker #(
    parameter int WIDTH = 16,
    parameter int MAX_SAMPLES = 1 << 14,
    // Discrepancias a imprimir antes de callar. Un log de 300 líneas iguales no
    // ayuda a nadie.
    parameter int MAX_REPORTS = 16,
    parameter int CH = -1
) (
    input logic                    clk,
    input logic                    rst_n,
    input logic                    valid,
    input logic signed [WIDTH-1:0] i_data,
    input logic signed [WIDTH-1:0] q_data,

    output logic        done,
    output int unsigned checked,
    output int unsigned mismatches
);

  logic [WIDTH-1:0] expected_i[0:MAX_SAMPLES-1];
  logic [WIDTH-1:0] expected_q[0:MAX_SAMPLES-1];

  string path_i;
  string path_q;
  int    count;
  int    settling;
  int    reports;

  initial begin
    case (CH)
      0: begin
        if (!$value$plusargs("expected_i_path_0=%s", path_i)) $fatal(1, "falta el plusarg +expected_i_path_0");
        if (!$value$plusargs("expected_q_path_0=%s", path_q)) $fatal(1, "falta el plusarg +expected_q_path_0");
        if (!$value$plusargs("expected_count_0=%d", count)) $fatal(1, "falta el plusarg +expected_count_0");
        if (!$value$plusargs("settling_0=%d", settling)) settling = 0;
      end
      1: begin
        if (!$value$plusargs("expected_i_path_1=%s", path_i)) $fatal(1, "falta el plusarg +expected_i_path_1");
        if (!$value$plusargs("expected_q_path_1=%s", path_q)) $fatal(1, "falta el plusarg +expected_q_path_1");
        if (!$value$plusargs("expected_count_1=%d", count)) $fatal(1, "falta el plusarg +expected_count_1");
        if (!$value$plusargs("settling_1=%d", settling)) settling = 0;
      end
      2: begin
        if (!$value$plusargs("expected_i_path_2=%s", path_i)) $fatal(1, "falta el plusarg +expected_i_path_2");
        if (!$value$plusargs("expected_q_path_2=%s", path_q)) $fatal(1, "falta el plusarg +expected_q_path_2");
        if (!$value$plusargs("expected_count_2=%d", count)) $fatal(1, "falta el plusarg +expected_count_2");
        if (!$value$plusargs("settling_2=%d", settling)) settling = 0;
      end
      3: begin
        if (!$value$plusargs("expected_i_path_3=%s", path_i)) $fatal(1, "falta el plusarg +expected_i_path_3");
        if (!$value$plusargs("expected_q_path_3=%s", path_q)) $fatal(1, "falta el plusarg +expected_q_path_3");
        if (!$value$plusargs("expected_count_3=%d", count)) $fatal(1, "falta el plusarg +expected_count_3");
        if (!$value$plusargs("settling_3=%d", settling)) settling = 0;
      end
      default: begin
        if (!$value$plusargs("expected_i_path=%s", path_i)) $fatal(1, "falta el plusarg +expected_i_path");
        if (!$value$plusargs("expected_q_path=%s", path_q)) $fatal(1, "falta el plusarg +expected_q_path");
        if (!$value$plusargs("expected_count=%d", count)) $fatal(1, "falta el plusarg +expected_count");
        if (!$value$plusargs("settling=%d", settling)) settling = 0;
      end
    endcase
    if (count > MAX_SAMPLES) begin
      $fatal(1, "%0d muestras esperadas no caben en MAX_SAMPLES=%0d", count, MAX_SAMPLES);
    end
    $readmemh(path_i, expected_i, 0, count - 1);
    $readmemh(path_q, expected_q, 0, count - 1);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      checked    <= 0;
      mismatches <= 0;
      reports    <= 0;
    end else if (valid && checked < unsigned'(count)) begin
      if (i_data !== signed'(expected_i[checked]) || q_data !== signed'(expected_q[checked])) begin
        mismatches <= mismatches + 1;
        if (reports < MAX_REPORTS) begin
          reports <= reports + 1;
          $display(
              "[drx_l1_checker] muestra %0d%s: dut=(%0d,%0d) modelo=(%0d,%0d)", checked,
              (checked < unsigned'(settling)) ? " (transitorio de arranque)" : "", i_data, q_data,
              signed'(expected_i[checked]), signed'(expected_q[checked]));
        end
      end
      checked <= checked + 1;
    end
  end

  always_comb done = (checked >= unsigned'(count));

endmodule : drx_l1_checker

`endif  // DRX_L1_CHECKER_SV
