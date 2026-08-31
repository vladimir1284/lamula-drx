// Divisor de latido. Existe para una sola cosa: demostrar de punta a punta que
// el paquete de parámetros llega al RTL, que el flujo de síntesis produce un
// bitstream y que el periodo derivado de `FS_HZ` es el correcto en las dos
// plataformas. No es funcionalidad del receptor.
//
// El divisor NO se escribe: se deriva de FS_HZ (D-02). En ZedBoard son 100e6
// ciclos por segundo y en ZU9 son 250e6, y el RTL es el mismo.

`ifndef DRX_HEARTBEAT_SV
`define DRX_HEARTBEAT_SV

module drx_heartbeat #(
    // Ciclos por medio periodo del latido. Por defecto medio segundo derivado de
    // FS_HZ; los testbenches lo bajan para no simular 10^8 ciclos.
    parameter int DIV = int'(drx_params_pkg::FS_HZ / 2)
) (
    input  logic clk,
    input  logic rst_n,
    output logic level  // conmuta cada DIV ciclos: apto para un LED
);

  localparam int CntBits = (DIV <= 1) ? 1 : $clog2(DIV);

  logic [CntBits-1:0] count;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count <= '0;
      level <= 1'b0;
    end else if (count == CntBits'(DIV - 1)) begin
      count <= '0;
      level <= ~level;
    end else begin
      count <= count + 1'b1;
    end
  end

endmodule : drx_heartbeat

`endif  // DRX_HEARTBEAT_SV
