// Saturación al rango con signo de OUT_W bits — el `fixed.saturate` del
// modelo dorado. En la cadena DDC se aplica una sola vez, al final (a
// IQ_BITS), igual que `Ddc.process`: los recortes intermedios son
// `drx_round`, sin saturar, porque el modelo tampoco satura ahí.
//
// `overflow` queda reservado para el status/BITE de Z1 («escalado de ganancia
// y saturación con reporte de overflow», fases.md#z1). El mapa de registros
// AXI-Lite ya existe (`rtl/drx_axil_regs.sv`, v1, Z1), pero deliberadamente NO
// lo cubre todavía: exponer `overflow` fuera de `drx_ddc_top` obliga a tocar
// sus puertos y los de `drx_ddc_quad_top.sv`, ya verificados bit-exacto contra
// el modelo dorado (matriz L1, D-12) — pendiente explícito, ver la cabecera de
// `config/registers.toml`. `drx_ddc_top` sigue sin exponerlo por lo mismo.

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
