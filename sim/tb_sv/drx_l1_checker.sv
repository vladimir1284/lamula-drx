// Comparador contra la salida esperada del modelo dorado (D-03).
//
// La otra mitad del camino de P-09: lee `expected_i.hex` / `expected_q.hex` y
// compara cada muestra que sale del DUT. Por defecto (`TOLERANCE_LSB=0`) sigue
// siendo bit a bit estricto, que es lo que dice D-03: `tb_l1_harness.sv` (el
// auto-test del propio arnés, que prueba que sabe fallar cuando cambia un solo
// bit) no toca este parámetro y depende de que el default se quede en 0.
//
// `TOLERANCE_LSB` (D-12, 19-sep-2026): el residuo de cuantización del NCO bajo
// `Taylor_Series_Corrected`, medido contra xsim real en la matriz de P-11
// (hasta ±5 LSB, 14/16 combinaciones), se acepta como techo del bloque en vez
// de exigirle bit a bit — ver D-12 para la decisión completa. Los testbenches
// de integración de la cadena DDC (`tb_l1_ddc*.sv`) instancian este módulo con
// `TOLERANCE_LSB=5`; el auto-test del arnés y cualquier bloque sin
// cuantización de fase de por medio (framing, range gating) siguen en 0.
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
    parameter int CH = -1,
    // D-12: 0 preserva el bit a bit estricto de D-03/D-05. Distinto de 0 solo en
    // los testbenches de integración de la cadena DDC (ver cabecera).
    parameter int TOLERANCE_LSB = 0
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

  // Combinacional a propósito, separado de la actualización de estado de abajo:
  // `exact_mismatch` conserva la semántica de `!==` (una X en cualquiera de los
  // dos lados SIEMPRE cuenta como discrepancia, tolerancia o no — una X nunca
  // es "está dentro de banda"). `diff_i`/`diff_q` solo tienen sentido cuando
  // ambos lados están completamente conocidos.
  logic exact_mismatch;
  logic reported_mismatch;
  int   diff_i;
  int   diff_q;

  always_comb begin
    exact_mismatch = (i_data !== signed'(expected_i[checked])) || (q_data !== signed'(expected_q[checked]));
    diff_i = int'(i_data) - int'(signed'(expected_i[checked]));
    diff_q = int'(q_data) - int'(signed'(expected_q[checked]));
    if (TOLERANCE_LSB > 0 && !$isunknown(i_data) && !$isunknown(q_data)) begin
      reported_mismatch = (diff_i > TOLERANCE_LSB) || (diff_i < -TOLERANCE_LSB) ||
                           (diff_q > TOLERANCE_LSB) || (diff_q < -TOLERANCE_LSB);
    end else begin
      reported_mismatch = exact_mismatch;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      checked    <= 0;
      mismatches <= 0;
      reports    <= 0;
    end else if (valid && checked < unsigned'(count)) begin
      if (reported_mismatch) begin
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
