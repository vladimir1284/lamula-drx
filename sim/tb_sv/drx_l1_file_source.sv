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
// binario elaborado corre todos los casos. Los formatos van completos como
// parámetro en vez de componerse con concatenación de strings, que no todos los
// simuladores aceptan dentro de `$value$plusargs`.
//
//   +stimulus_path=<ruta al .hex>
//   +stimulus_count=<número de muestras a entregar>

`ifndef DRX_L1_FILE_SOURCE_SV
`define DRX_L1_FILE_SOURCE_SV

module drx_l1_file_source #(
    parameter int WIDTH = 16,
    parameter int MAX_SAMPLES = 1 << 17,
    // Formatos de plusarg completos. Permiten varias instancias (estímulo, I, Q)
    // en el mismo testbench sin que se pisen.
    parameter string PATH_FMT  = "stimulus_path=%s",
    parameter string COUNT_FMT = "stimulus_count=%d"
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
    if (!$value$plusargs(PATH_FMT, path)) begin
      $fatal(1, "falta el plusarg +%s", PATH_FMT);
    end
    if (!$value$plusargs(COUNT_FMT, count)) begin
      $fatal(1, "falta el plusarg +%s", COUNT_FMT);
    end
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
