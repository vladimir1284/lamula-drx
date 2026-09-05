// Fuente de muestras leídas de fichero, para los testbenches nativos de L1.
//
// P-09: cocotb no tiene backend para xsim, así que en L1 el oráculo del modelo
// dorado cruza al simulador por fichero (`tools/gen_l1_vectors.py`) en vez de
// por VPI. Este módulo es la mitad de entrada de ese camino: lee un `.hex` de
// `$readmemh` y lo entrega como stream con handshake, para que el DUT reciba
// backpressure real y no una carga en bloque.
//
// Es código de testbench, no de síntesis: vive en `sim/tb_sv/` y no está en
// `rtl/filelist.f`.
//
// Configuración por plusargs, no por parámetros de elaboración: así el mismo
// binario elaborado corre todos los casos.
//
//   +stimulus_path=<ruta al .hex>
//   +stimulus_count=<número de muestras a entregar>
//
// xsim (hallazgo P-09, 5-sep-2026): `$value$plusargs` revienta el kernel
// (`FATAL_ERROR: ... exceptional condition`, no un `$fatal` propio) si el
// argumento de formato no es un literal del propio código fuente — un
// `parameter string`, aunque sea constante de elaboración, ya lo rompe.
// Reproducido en aislado con Vivado 2022.2: mismo `$value$plusargs`, mismo
// valor, la única diferencia es literal vs. parámetro. Por eso el formato ya
// no se parametriza: KIND selecciona en runtime, con un `case`, entre
// llamadas que llevan el literal escrito a mano en cada rama.

`ifndef DRX_L1_FILE_SOURCE_SV
`define DRX_L1_FILE_SOURCE_SV

module drx_l1_file_source #(
    parameter int WIDTH = 16,
    parameter int MAX_SAMPLES = 1 << 17,
    // Cerrado a los tres usos reales del arnés (stimulus en tb_l1_ddc.sv;
    // expected_i/expected_q en tb_l1_harness.sv), no una enumeración abierta.
    parameter string KIND = "stimulus"  // "stimulus" | "expected_i" | "expected_q"
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    ready,
    output logic                    valid,
    output logic signed [WIDTH-1:0] data,
    output logic                    last,
    output logic                    done
);

  logic [WIDTH-1:0] memory[0:MAX_SAMPLES-1];

  string path;
  int    count;
  int    index;

  initial begin
    case (KIND)
      "stimulus": begin
        if (!$value$plusargs("stimulus_path=%s", path)) $fatal(1, "falta el plusarg +stimulus_path");
        if (!$value$plusargs("stimulus_count=%d", count)) $fatal(1, "falta el plusarg +stimulus_count");
      end
      "expected_i": begin
        if (!$value$plusargs("expected_i_path=%s", path)) $fatal(1, "falta el plusarg +expected_i_path");
        if (!$value$plusargs("expected_count=%d", count)) $fatal(1, "falta el plusarg +expected_count");
      end
      "expected_q": begin
        if (!$value$plusargs("expected_q_path=%s", path)) $fatal(1, "falta el plusarg +expected_q_path");
        if (!$value$plusargs("expected_count=%d", count)) $fatal(1, "falta el plusarg +expected_count");
      end
      default: $fatal(1, "KIND desconocido: %s", KIND);
    endcase
    if (count > MAX_SAMPLES) begin
      $fatal(1, "%0d muestras no caben en MAX_SAMPLES=%0d", count, MAX_SAMPLES);
    end
    $readmemh(path, memory, 0, count - 1);
  end

  // `index` cuenta muestras ya aceptadas. `done` sube cuando se han entregado
  // todas: el testbench lo usa para terminar sin depender de un timeout.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      index <= 0;
    end else if (valid && ready) begin
      index <= index + 1;
    end
  end

  always_comb begin
    valid = (index < count);
    data  = signed'(memory[index[$clog2(MAX_SAMPLES)-1:0]]);
    last  = (index == count - 1);
    done  = (index >= count);
  end

endmodule : drx_l1_file_source

`endif  // DRX_L1_FILE_SOURCE_SV
