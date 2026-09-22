// Motor de timing de Z2 (fases.md#z2): la composición de las dos piezas ya
// verificadas por separado -- `drx_prf_batch_seq.sv` (2 lotes de PRF/radial,
// D-13) y `drx_trigger_gen.sv` (N_TRIGGERS de retardo+ancho independientes) --
// en el único bloque que se integrará en `drx_top` el día que exista el mapa
// de registros de Z2 (P-15). Sin lógica propia: solo cablea `pulse_trig` del
// secuenciador como `arm` del generador de triggers.
//
// Ese cableado (los 4 triggers se arman con CADA pulso de PRF, de cualquiera
// de los 2 lotes, no una vez por radial) es la lectura más razonable dado el
// propósito de medida con osciloscopio del hito ZM2 -- ver la cabecera de
// `drx_trigger_gen.sv` -- pero ningún documento de `docs/alcance/` la fija
// como decisión. Si resulta ser el criterio equivocado, cambia esta única
// línea de cableado, no los dos módulos que envuelve.

`ifndef DRX_TIMING_ENGINE_SV
`define DRX_TIMING_ENGINE_SV

module drx_timing_engine
  import drx_params_pkg::*;
#(
    parameter int PrfDivBits     = 32,
    parameter int PulseWidthBits = 16,
    parameter int NPulsesBits    = 16,
    parameter int NTriggers      = N_TRIGGERS,
    parameter int TrigDelayBits  = 32,
    parameter int TrigWidthBits  = 32
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

    // Retardo/ancho de cada uno de los NTriggers -- ver `drx_trigger_gen.sv`.
    input logic [TrigDelayBits-1:0] trig_delay[NTriggers],
    input logic [TrigWidthBits-1:0] trig_width[NTriggers],

    output logic pulse_trig,
    output logic batch_sel,
    output logic [PulseWidthBits-1:0] pulse_width,
    output logic tx_gate,
    output logic radial_done,

    output logic [NTriggers-1:0] trig_out
);

  drx_prf_batch_seq #(
      .PrfDivBits(PrfDivBits),
      .PulseWidthBits(PulseWidthBits),
      .NPulsesBits(NPulsesBits)
  ) u_batch_seq (
      .clk(clk),
      .rst_n(rst_n),
      .enable(enable),

      .prf_div_low(prf_div_low),
      .pulse_width_low(pulse_width_low),
      .n_pulses_low(n_pulses_low),
      .prf_div_high(prf_div_high),
      .pulse_width_high(pulse_width_high),
      .n_pulses_high(n_pulses_high),

      .pulse_trig(pulse_trig),
      .batch_sel(batch_sel),
      .pulse_width(pulse_width),
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
