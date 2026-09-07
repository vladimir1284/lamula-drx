// Redondeo al más cercano con desplazamiento a la derecha, empate hacia
// +infinito — el mismo `shift_round` de `model/drx_model/fixed.py`, y el modo
// «round half up» de la IP de Xilinx. Un solo módulo para los cuatro puntos de
// recorte de la cadena DDC (mezclador, CIC, FIR droop, semibanda) en vez de
// repetir la fórmula, para que un error de signo en el redondeo se corrija en
// un sitio y no en cuatro.
//
// SHIFT es constante de elaboración: cada instancia se liga a un `shift`
// concreto de la cadena (`NCO_OUT_BITS-1`, `CIC_GROWTH_BITS`, `FIR_GROWTH_BITS`
// o `HALFBAND_GROWTH_BITS`, todos generados por `tools/gen_params.py` desde el
// mismo modelo dorado — nunca un número copiado a mano). Solo cubre SHIFT >= 1
// porque es lo único que usa la cadena; `fixed.shift_round` sí admite
// SHIFT <= 0 pero eso es generalidad de librería que aquí no hace falta.
//
// No satura: igual que `chain._decimate`, el recorte de ganancia entre etapas
// no recorta rango, solo quita bits de fondo de escala que ya no hacen falta.
// La saturación a IQ_BITS es de `drx_saturate`, y solo se aplica una vez, al
// final de la cadena — exactamente donde la aplica `Ddc.process`.

`ifndef DRX_ROUND_SV
`define DRX_ROUND_SV

module drx_round #(
    parameter int IN_W  = 16,
    parameter int SHIFT = 1,
    parameter int OUT_W = IN_W - SHIFT
) (
    input  logic signed [IN_W-1:0]  in_data,
    output logic signed [OUT_W-1:0] out_data
);

  // Un bit de margen para la suma de sesgo: en el peor caso (in_data en su
  // extremo positivo) in_data + bias no cabe en IN_W bits, y truncarlo ahí
  // sería un error de redondeo, no de rango — el recorte a OUT_W ya llega
  // después, con el `>>>` hecho.
  localparam int SumW = IN_W + 1;

  logic signed [SumW-1:0] biased;

  assign biased   = SumW'(in_data) + (SumW'(1) <<< (SHIFT - 1));
  assign out_data = OUT_W'(biased >>> SHIFT);

endmodule : drx_round

`endif  // DRX_ROUND_SV
