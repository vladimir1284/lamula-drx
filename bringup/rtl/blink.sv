// Escalón 2 del bring-up: contador puro sobre el reloj de 100 MHz de la
// ZedBoard, sin PS7, sin AXI y sin una sola línea de software.
//
// Es deliberadamente el diseño más tonto que puede fallar de forma informativa.
// Si los LEDs parpadean, están probados a la vez: los drivers de cable JTAG, la
// carga de bitstream, que el oscilador de `Y9` vive, y que el mapa de pines de
// los LEDs es correcto. Ninguna de esas cuatro cosas se ha verificado nunca en
// este repositorio sobre hardware real.
//
// Este fichero vive en `bringup/` y NO en `rtl/` a propósito: un divisor de
// reloj necesita por definición una constante de reloj, y
// `tools/check_hardcoded_clock.py` falla el CI ante cualquier literal >= 1e6 en
// `rtl/`, `fw/`, `sim/`, `model/`, `tcl/` y `contract/`. `bringup/` queda fuera
// de ese barrido porque es un proyecto desechable de bring-up, no parte del DRx.

`timescale 1ns / 1ps

module blink #(
    // 100 MHz / 2**25 ~= 3 Hz en el bit más bajo del patrón visible. El rango
    // elegido hace que LD0 cambie varias veces por segundo y LD7 cada medio
    // minuto largo: así se distingue de un vistazo "cuenta" de "un LED se quedó
    // encendido".
    parameter int unsigned COUNTER_W = 33
) (
    input  logic       clk,
    output logic [7:0] led
);

  logic [COUNTER_W-1:0] count = '0;

  always_ff @(posedge clk) begin
    count <= count + 1'b1;
  end

  // Los ocho bits altos: un contador binario visible.
  assign led = count[COUNTER_W-1-:8];

endmodule
