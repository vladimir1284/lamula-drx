// D-09, validación completa por lote: que `pulse_width` esté en la tabla de
// `config/params.toml` (`PULSE_WIDTH_CYCLES`), que quepa en su propio PRI
// (`pulse_width < prf_div`), que `prf_div` no viole el piso de rango no
// ambiguo del lote (`prf_div >= PrfDivMinRange`), y (D-15) que `bin_count` no
// supere el techo físico de la BRAM de `drx_range_gate` (`bin_count >= 1 &&
// bin_count <= BinsMax`). Puro combinacional y sin estado, mismo patrón que
// `drx_saturate.sv` -- si hace falta latchear esto para AXI-Lite, el sticky
// vive en `drx_axil_regs` (mismo motivo que ya documenta OVERFLOW en su
// cabecera), no aquí. Se llama `bin_count`, no `bins`: SystemVerilog reserva
// `bins` como palabra clave de coverpoints/randomize.
//
// `PrfDivMinRange`/`BinsMax` son PARÁMETROS, no entradas: los dos son
// requisitos fijos (460 km / 115 km WSR-88D-NEXRAD para el primero; la
// profundidad real de BRAM para el segundo), no algo configurable en runtime
// por AXI-Lite. En producción (`drx_timing_engine.sv`) toman
// PRF_DIV_MIN_LOW/HIGH y BINS_MODE_FINE del paquete de parámetros; los L0
// que no prueban D-09 en sí los overridean a valores pequeños para no forzar
// simulaciones de cientos de miles de ciclos (mismo motivo que
// BINS_FINE/BINS_COARSE en tb_drx_range_gate.py).
//
// Oráculo: `model/drx_model/timing.py::batch_config_valid` (D-03), verificado
// bit a bit en `sim/tb/tb_drx_timing_config_valid.py`.

`ifndef DRX_TIMING_CONFIG_VALID_SV
`define DRX_TIMING_CONFIG_VALID_SV

module drx_timing_config_valid
  import drx_params_pkg::*;
#(
    parameter int PrfDivBits     = 32,
    parameter int PulseWidthBits = 16,
    parameter int BinsBits       = 32,
    // Sin piso de rango por defecto (1 ciclo): un valor de arranque inocuo
    // para elaboración/lint fuera de `drx_timing_engine`, que siempre lo
    // overridea explícitamente.
    parameter int PrfDivMinRange = 1,
    // Sin techo de bins por defecto (todo-unos: el valor más grande
    // representable en BinsBits, nunca rechaza nada por sí solo).
    parameter logic [BinsBits-1:0] BinsMax = '1
) (
    input  logic [ PrfDivBits-1:0] prf_div,
    input  logic [PulseWidthBits-1:0] pulse_width,
    input  logic [   BinsBits-1:0] bin_count,
    output logic                    valid
);

  logic pulse_width_in_table;

  always_comb begin
    pulse_width_in_table = 1'b0;
    for (int i = 0; i < $size(PULSE_WIDTH_CYCLES); i++) begin
      if (pulse_width == PulseWidthBits'(PULSE_WIDTH_CYCLES[i])) begin
        pulse_width_in_table = 1'b1;
      end
    end
  end

  logic fits_in_pri;
  assign fits_in_pri = (PrfDivBits'(pulse_width) < prf_div);

  logic meets_range_floor;
  assign meets_range_floor = (prf_div >= PrfDivBits'(PrfDivMinRange));

  logic bins_in_range;
  assign bins_in_range = (bin_count >= BinsBits'(1)) && (bin_count <= BinsMax);

  assign valid = pulse_width_in_table && fits_in_pri && meets_range_floor && bins_in_range;

endmodule : drx_timing_config_valid

`endif  // DRX_TIMING_CONFIG_VALID_SV
