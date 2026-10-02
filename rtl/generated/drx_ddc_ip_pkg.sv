// GENERADO por tcl/gen_ip.tcl a partir de la IP real generada en ip/*.xci. NO EDITAR A MANO.
//
// Anchos de TDATA que de verdad produce cada core una vez configurado — no
// una fórmula de taps/coeficientes: el crecimiento interno de un FIR Compiler
// depende de si detecta la estructura de coeficientes como simétrica, y el
// bus se redondea a un múltiplo de 8 bits. rtl/drx_ddc_top.sv consume estos
// valores en vez de recalcularlos.

`ifndef DRX_DDC_IP_PKG_SV
`define DRX_DDC_IP_PKG_SV

package drx_ddc_ip_pkg;

  localparam int DDS_TDATA_BITS = 32;
  localparam int DDS_CONFIG_TDATA_BITS = 32;
  localparam int CIC_IN_BITS = 16;
  localparam int CIC_TDATA_BITS = 48;
  localparam int FIR_DROOP_IN_BITS = 16;
  localparam int FIR_DROOP_TDATA_BITS = 40;
  localparam int FIR_HALFBAND_IN_BITS = 24;
  localparam int FIR_HALFBAND_TDATA_BITS = 40;

endpackage : drx_ddc_ip_pkg

`endif  // DRX_DDC_IP_PKG_SV
