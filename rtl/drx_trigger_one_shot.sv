// Un canal de "retardo + ancho" independiente — la unidad detrás del generador
// de 4 triggers de Z2 (fases.md#z2: "Generador de 4 triggers configurables con
// retardo y ancho independientes"). Oráculo:
// `model/drx_model/timing.py::one_shot_active_cycles` (D-03), verificado en
// `sim/tb/tb_drx_trigger_gen.py`.
//
// `arm` es el evento de referencia: cada vez que sube, este canal vuelve a
// contar desde cero, incluso si el pulso anterior seguía activo (last-arm-wins,
// igual que el resto de módulos de este repo que priorizan el evento nuevo
// sobre el estado en curso -- ver `drx_range_gate.sv` con `clear`/overrun). No
// es un caso de uso real: cada `arm` (un pulso de PRF) debería estar separado
// por muchos ciclos más que `delay+width` de cualquier canal, y ese margen es
// responsabilidad de quien configura los registros, no de este módulo.
//
// La salida es registrada, con 1 ciclo de latencia entre `arm` y el primer
// ciclo de `delay=0` -- no hay forma de tener menos de 1 ciclo con una entrada
// también registrada (`arm` en sí, si viene de `drx_prf_batch_seq`, ya es una
// salida combinacional de OTRO módulo capturada aquí de forma síncrona). El
// modelo dorado fija ese +1 como parte de la definición, no como un detalle
// que un testbench redescubra por separado.

`ifndef DRX_TRIGGER_ONE_SHOT_SV
`define DRX_TRIGGER_ONE_SHOT_SV

module drx_trigger_one_shot #(
    parameter int DelayBits = 32,
    parameter int WidthBits = 32
) (
    input logic clk,
    input logic rst_n,

    input logic arm,

    // P-16: un "paso" del canal, igual que en `drx_prf_batch_seq.sv`. Con
    // `advance` constante a 1 este modulo es el de v1..v9. Se pacea junto con
    // el secuenciador y no al margen: si `tx_gate` se estira con el avance de
    // muestras y `trig_out` siguiera contando ciclos, las dos salidas que
    // describen el MISMO pulso de PRF dejarian de coincidir, y el unico sitio
    // donde eso se ve es un osciloscopio en los pines del Pmod (ZM2).
    //
    // `arm` llega ya alineado con un avance -- `pulse_trig` lleva el mismo
    // termino -- asi que gatear aqui no pierde ningun armado.
    input logic advance,

    // Se asume `width >= 1` (igual que `Batch.pulse_width_cycles` en el
    // modelo): con `width == 0`, `width_cnt <= width - 1'b1` envolvería. Ese
    // invariante lo garantiza quien escribe el registro, no este módulo --
    // mismo criterio que `drx_prf_batch_seq.sv` (ver su cabecera).
    input logic [DelayBits-1:0] delay,
    input logic [WidthBits-1:0] width,

    output logic trig_out
);

  logic pending;
  logic [DelayBits-1:0] delay_cnt;
  logic [WidthBits-1:0] width_cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pending  <= 1'b0;
      delay_cnt <= '0;
      width_cnt <= '0;
      trig_out <= 1'b0;
    end else if (advance) begin
      if (arm) begin
        // Un `arm` nuevo manda siempre, esté pendiente o activo lo que hubiera
        // antes (ver la cabecera).
        if (delay == '0) begin
          pending   <= 1'b0;
          width_cnt <= width - 1'b1;
          trig_out  <= 1'b1;
        end else begin
          pending   <= 1'b1;
          delay_cnt <= delay - 1'b1;
          trig_out  <= 1'b0;
        end
      end else if (pending) begin
        if (delay_cnt == '0) begin
          pending   <= 1'b0;
          width_cnt <= width - 1'b1;
          trig_out  <= 1'b1;
        end else begin
          delay_cnt <= delay_cnt - 1'b1;
        end
      end else if (trig_out) begin
        if (width_cnt == '0) begin
          trig_out <= 1'b0;
        end else begin
          width_cnt <= width_cnt - 1'b1;
        end
      end
    end
  end

endmodule : drx_trigger_one_shot

`endif  // DRX_TRIGGER_ONE_SHOT_SV
