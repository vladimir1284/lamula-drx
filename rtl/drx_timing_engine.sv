// Motor de timing de Z2 (fases.md#z2): la composición de las piezas ya
// verificadas por separado -- `drx_prf_batch_seq.sv` (2 lotes de PRF/radial,
// D-13), `drx_trigger_gen.sv` (N_TRIGGERS de retardo+ancho independientes) y,
// desde el 22-sep-2026 (más tarde), `drx_timing_config_valid.sv` (D-09,
// checks autocontenidos) -- en el único bloque que se integra en `drx_top`.
// Cablea `pulse_trig` del secuenciador como `arm` del generador de triggers.
//
// Ese cableado (los 4 triggers se arman con CADA pulso de PRF, de cualquiera
// de los 2 lotes, no una vez por radial) es la lectura más razonable dado el
// propósito de medida con osciloscopio del hito ZM2 -- ver la cabecera de
// `drx_trigger_gen.sv` -- pero ningún documento de `docs/alcance/` la fija
// como decisión. Si resulta ser el criterio equivocado, cambia esta única
// línea de cableado, no los módulos que envuelve.
//
// D-09 completo: `enable` real del secuenciador de lotes es `enable &&
// config_valid_low && config_valid_high` -- si cualquiera de los 2 lotes
// tiene un `pulse_width` fuera de tabla, que no cabe en su propio PRI, un
// `prf_div` que viola el piso de rango no ambiguo de su lote, o (D-15) un
// `bin_count` que supera el techo físico de BRAM de `drx_range_gate`, el
// secuenciador simplemente no corre (mismo efecto que `enable` en bajo,
// `drx_prf_batch_seq.sv` ya lo deja todo congelado y `tx_gate` a 0 en ese
// caso). `config_invalid_low`/`config_invalid_high` exponen el motivo hacia
// arriba para que `drx_axil_regs` los latchee en TIMING_STATUS.
//
// Cada instancia de `drx_timing_config_valid` toma su propio piso de rango
// (`PrfDivMinRangeLow`/`PrfDivMinRangeHigh`, por defecto PRF_DIV_MIN_LOW/
// PRF_DIV_MIN_HIGH del paquete de parámetros -- 460 km / 115 km WSR-88D-
// NEXRAD, ver config/params.toml): el lote bajo y el alto no tienen el mismo
// requisito de rango por diseño (D-13). El piso del lote alto queda hoy por
// debajo de PRF_DIV_MIN (el techo de PRF ya congelado en 1200 Hz) -- ningún
// `prf_div` válido en el rango existente puede violarlo, así que ese check
// no rechaza nada en la práctica todavía; se deja cableado igual por si
// PRF_DIV_MIN cambia. Ver docs/implementacion/fases.md#z2.
//
// `bin_count`/`BinsMaxLow`/`BinsMaxHigh` (D-15, 25-sep-2026): a diferencia del
// piso de PRF, el techo de bins es el MISMO requisito físico para los dos
// lotes (la BRAM de `drx_range_gate` tiene una única profundidad real,
// BINS_MODE_FINE), no dos requisitos de producto distintos -- por eso las dos
// instancias de `drx_timing_config_valid` comparten el mismo `BinsMax` por
// defecto. El conteo de bins en sí (`bins_low`/`bins_high`) SÍ es distinto por
// lote y configurable en runtime: viene de DSP, que a su vez lo recibe de RCP
// según el VCP -- la proporción entre el rango del lote bajo y el del lote
// alto nunca es la misma. `bin_count` (salida) es el conteo del lote ACTIVO,
// mismo mux que ya hace `drx_prf_batch_seq.sv` para `pulse_width` -- lo
// consume `drx_range_gate_quad_top` en vez de un `mode_coarse` estático (ver
// D-15 en decisiones.md y la cabecera de `drx_range_gate.sv`). Se llama
// `bin_count`, no `bins`: SystemVerilog reserva `bins` como palabra clave de
// coverpoints/randomize.

`ifndef DRX_TIMING_ENGINE_SV
`define DRX_TIMING_ENGINE_SV

module drx_timing_engine
  import drx_params_pkg::*;
#(
    parameter int PrfDivBits     = 32,
    parameter int PulseWidthBits = 16,
    parameter int NPulsesBits    = 16,
    parameter int BinsBits       = 32,
    parameter int NTriggers      = N_TRIGGERS,
    parameter int TrigDelayBits  = 32,
    parameter int TrigWidthBits  = 32,
    // D-09: piso de rango no ambiguo por lote, en unidades de `prf_div` --
    // ver la cabecera de este fichero y la de `drx_timing_config_valid.sv`.
    parameter int PrfDivMinRangeLow  = PRF_DIV_MIN_LOW,
    parameter int PrfDivMinRangeHigh = PRF_DIV_MIN_HIGH,
    // D-15: techo de bins -- el mismo para los dos lotes (una sola BRAM real).
    parameter logic [BinsBits-1:0] BinsMaxLow  = BinsBits'(BINS_MODE_FINE),
    parameter logic [BinsBits-1:0] BinsMaxHigh = BinsBits'(BINS_MODE_FINE)
) (
    input logic clk,
    input logic rst_n,
    input logic enable,

    // Lote bajo / lote alto -- ver `drx_prf_batch_seq.sv`.
    input logic [ PrfDivBits-1:0] prf_div_low,
    input logic [PulseWidthBits-1:0] pulse_width_low,
    input logic [ NPulsesBits-1:0] n_pulses_low,
    input logic [ PrfDivBits-1:0] prf_div_high,
    input logic [PulseWidthBits-1:0] pulse_width_high,
    input logic [ NPulsesBits-1:0] n_pulses_high,

    // Conteo de bins de range-gate por lote (D-15) -- ver la cabecera.
    input logic [BinsBits-1:0] bins_low,
    input logic [BinsBits-1:0] bins_high,

    // Retardo/ancho de cada uno de los NTriggers -- ver `drx_trigger_gen.sv`.
    input logic [TrigDelayBits-1:0] trig_delay[NTriggers],
    input logic [TrigWidthBits-1:0] trig_width[NTriggers],

    output logic pulse_trig,
    output logic batch_sel,
    output logic [PulseWidthBits-1:0] pulse_width,
    output logic [BinsBits-1:0] bin_count,
    output logic tx_gate,
    output logic radial_done,

    // D-09 completo: alto cuando el lote correspondiente NO es válido hoy
    // (`pulse_width` fuera de tabla, no cabe en su propio PRI, `prf_div` bajo
    // el piso de rango de su lote, o `bin_count` sobre el techo de BRAM).
    // Nivel, no pulso -- pensado para que `drx_axil_regs` lo latchee (mismo
    // patrón que `overflow_in`).
    output logic config_invalid_low,
    output logic config_invalid_high,

    output logic [NTriggers-1:0] trig_out
);

  logic config_valid_low, config_valid_high;

  drx_timing_config_valid #(
      .PrfDivBits(PrfDivBits),
      .PulseWidthBits(PulseWidthBits),
      .BinsBits(BinsBits),
      .PrfDivMinRange(PrfDivMinRangeLow),
      .BinsMax(BinsMaxLow)
  ) u_config_valid_low (
      .prf_div(prf_div_low),
      .pulse_width(pulse_width_low),
      .bin_count(bins_low),
      .valid(config_valid_low)
  );

  drx_timing_config_valid #(
      .PrfDivBits(PrfDivBits),
      .PulseWidthBits(PulseWidthBits),
      .BinsBits(BinsBits),
      .PrfDivMinRange(PrfDivMinRangeHigh),
      .BinsMax(BinsMaxHigh)
  ) u_config_valid_high (
      .prf_div(prf_div_high),
      .pulse_width(pulse_width_high),
      .bin_count(bins_high),
      .valid(config_valid_high)
  );

  assign config_invalid_low  = ~config_valid_low;
  assign config_invalid_high = ~config_valid_high;

  logic enable_gated;
  assign enable_gated = enable && config_valid_low && config_valid_high;

  drx_prf_batch_seq #(
      .PrfDivBits(PrfDivBits),
      .PulseWidthBits(PulseWidthBits),
      .NPulsesBits(NPulsesBits),
      .BinsBits(BinsBits)
  ) u_batch_seq (
      .clk(clk),
      .rst_n(rst_n),
      .enable(enable_gated),

      .prf_div_low(prf_div_low),
      .pulse_width_low(pulse_width_low),
      .n_pulses_low(n_pulses_low),
      .prf_div_high(prf_div_high),
      .pulse_width_high(pulse_width_high),
      .n_pulses_high(n_pulses_high),

      .bins_low(bins_low),
      .bins_high(bins_high),

      .pulse_trig(pulse_trig),
      .batch_sel(batch_sel),
      .pulse_width(pulse_width),
      .bin_count(bin_count),
      .tx_gate(tx_gate),
      .radial_done(radial_done)
  );

  drx_trigger_gen #(
      .NTriggers(NTriggers),
      .DelayBits(TrigDelayBits),
      .WidthBits(TrigWidthBits)
  ) u_trigger_gen (
      .clk(clk),
      .rst_n(rst_n),

      .arm(pulse_trig),

      .delay(trig_delay),
      .width(trig_width),

      .trig_out(trig_out)
  );

endmodule : drx_timing_engine

`endif  // DRX_TIMING_ENGINE_SV
