// Generador de N_TRIGGERS triggers independientes — Z2 (fases.md#z2):
// "Generador de 4 triggers configurables con retardo y ancho independientes".
// Mismo patrón que `drx_range_gate_quad_top.sv`: un `generate` de instancias
// independientes de `drx_trigger_one_shot`, sin lógica propia.
//
// Los 4 comparten el mismo `arm`: la referencia de tiempo es un único evento
// (en la integración real, `pulse_trig` de `drx_prf_batch_seq.sv` -- cada
// pulso de PRF, de cualquiera de los 2 lotes, vuelve a armar los 4 canales),
// y cada uno aplica su propio `delay`/`width` de registro sobre ese mismo
// instante -- así es como el contrato DRx↔DSP ya modela esto
// (`trigger_delay_0..3`/`trigger_width_0..3` en el mensaje `config`,
// congelado desde Z0/D-08, antes de que este RTL existiera).
//
// Igual que `drx_prf_batch_seq.sv`: todavía no lo instancia `drx_top` -- no
// hay mapa de registros de Z2 que alimente `delay`/`width` (P-15) -- así que
// por ahora es una unidad suelta con su propio L0
// (`sim/tb/tb_drx_trigger_gen.py`).

`ifndef DRX_TRIGGER_GEN_SV
`define DRX_TRIGGER_GEN_SV

module drx_trigger_gen
  import drx_params_pkg::*;
#(
    parameter int NTriggers = N_TRIGGERS,
    parameter int DelayBits = 32,
    parameter int WidthBits = 32
) (
    input logic clk,
    input logic rst_n,

    input logic arm,

    input logic [DelayBits-1:0] delay[NTriggers],
    input logic [WidthBits-1:0] width[NTriggers],

    // Vector empaquetado, no un array de 1 bit por canal: Verilator/cocotb
    // (VPI `--public-flat-rw`) no expone un array de salidas escalares como
    // objetos indexables — confirmado en `sim/tb/tb_drx_trigger_gen.py`, que
    // sí puede indexar `delay[NTriggers]`/`width[NTriggers]` (arrays de
    // vectores anchos) sin problema. Un bus de NTriggers bits es además
    // exactamente lo que hace falta para cablear a un Pmod plano.
    output logic [NTriggers-1:0] trig_out
);

  genvar gt;
  generate
    for (gt = 0; gt < NTriggers; gt = gt + 1) begin : g_trig
      drx_trigger_one_shot #(
          .DelayBits(DelayBits),
          .WidthBits(WidthBits)
      ) u_one_shot (
          .clk(clk),
          .rst_n(rst_n),

          .arm(arm),

          .delay(delay[gt]),
          .width(width[gt]),

          .trig_out(trig_out[gt])
      );
    end
  endgenerate

endmodule : drx_trigger_gen

`endif  // DRX_TRIGGER_GEN_SV
