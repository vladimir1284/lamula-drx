// Saturación al rango con signo de OUT_W bits — el `fixed.saturate` del
// modelo dorado. En la cadena DDC se aplica una sola vez, al final (a
// IQ_BITS), igual que `Ddc.process`: los recortes intermedios son
// `drx_round`, sin saturar, porque el modelo tampoco satura ahí.
//
// `overflow` es status/BITE de Z1 («escalado de ganancia y saturación con
// reporte de overflow», fases.md#z1): ahora tiene un consumidor real, el
// registro OVERFLOW de `rtl/drx_axil_regs.sv` (mapa de registros AXI-Lite,
// v2 — ver `docs/implementacion/registros.md`), vía el puerto homónimo de
// `drx_ddc_top`/`drx_ddc_quad_top`. Deliberadamente combinacional y sin
// estado aquí: el latch sticky + write-1-to-clear vive en `drx_axil_regs`,
// no en este módulo ni en `drx_ddc_top` — mantener este núcleo, ya
// verificado bit a bit (D-12), libre de estado nuevo evita tocar más de lo
// necesario para un registro de solo lectura.

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
