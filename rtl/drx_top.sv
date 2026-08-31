// Top del LAMULA DRx.
//
// FASE Z0: DISEÑO VACÍO A PROPÓSITO. El hito ZM0 es CI verde sobre un diseño sin
// funcionalidad que produce un BOOT.BIN reproducible byte a byte. Aquí no va el
// DDC, ni el motor de timing, ni los lectores SSI: eso es Z1 en adelante.
//
// Lo único que hace este módulo es cerrar el lazo del substrato — parámetros ->
// RTL -> síntesis -> placa — con el latido, y exponer la identidad del diseño en
// constantes para que el firmware pueda contrastarla.

`ifndef DRX_TOP_SV
`define DRX_TOP_SV

module drx_top
  import drx_params_pkg::*;
#(
    parameter int HEARTBEAT_DIV = int'(FS_HZ / 2)
) (
    input  logic clk,
    input  logic rst_n,
    output logic led_heartbeat
);

  drx_heartbeat #(
      .DIV(HEARTBEAT_DIV)
  ) u_heartbeat (
      .clk  (clk),
      .rst_n(rst_n),
      .level(led_heartbeat)
  );

endmodule : drx_top

`endif  // DRX_TOP_SV
