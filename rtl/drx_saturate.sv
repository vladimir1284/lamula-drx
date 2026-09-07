// Saturación al rango con signo de OUT_W bits — el `fixed.saturate` del
// modelo dorado. En la cadena DDC se aplica una sola vez, al final (a
// IQ_BITS), igual que `Ddc.process`: los recortes intermedios son
// `drx_round`, sin saturar, porque el modelo tampoco satura ahí.
//
// `overflow` queda reservado para el status/BITE de Z1 («escalado de ganancia
// y saturación con reporte de overflow», fases.md#z1); `drx_ddc_top` no lo
// expone todavía porque no hay ningún consumidor — se conecta el día que haya
// un mapa de registros que lo reciba.

`ifndef DRX_SATURATE_SV
`define DRX_SATURATE_SV

module drx_saturate #(
    parameter int IN_W  = 24,
    parameter int OUT_W = 16
) (
    input  logic signed [IN_W-1:0]  in_data,
    output logic signed [OUT_W-1:0] out_data,
    output logic                    overflow
);

  localparam logic signed [IN_W-1:0] Low  = -(IN_W'(1) <<< (OUT_W - 1));
  localparam logic signed [IN_W-1:0] High = (IN_W'(1) <<< (OUT_W - 1)) - 1;

  always_comb begin
    if (in_data < Low) begin
      out_data = OUT_W'(Low);
      overflow = 1'b1;
    end else if (in_data > High) begin
      out_data = OUT_W'(High);
      overflow = 1'b1;
    end else begin
      out_data = OUT_W'(in_data);
      overflow = 1'b0;
    end
  end

endmodule : drx_saturate

`endif  // DRX_SATURATE_SV
