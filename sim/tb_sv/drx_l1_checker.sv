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

`ifndef DRX_L1_CHECKER_SV
`define DRX_L1_CHECKER_SV

module drx_l1_checker #(
    parameter int WIDTH = 16,
    parameter int MAX_SAMPLES = 1 << 14,
    // Discrepancias a imprimir antes de callar. Un log de 300 líneas iguales no
    // ayuda a nadie.
    parameter int MAX_REPORTS = 16
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
    if (!$value$plusargs("expected_i_path=%s", path_i)) begin
      $fatal(1, "falta el plusarg +expected_i_path");
    end
    if (!$value$plusargs("expected_q_path=%s", path_q)) begin
      $fatal(1, "falta el plusarg +expected_q_path");
    end
    if (!$value$plusargs("expected_count=%d", count)) begin
      $fatal(1, "falta el plusarg +expected_count");
    end
    if (!$value$plusargs("settling=%d", settling)) begin
      settling = 0;
    end
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
