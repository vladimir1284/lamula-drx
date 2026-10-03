// Troceado del bus de depuración de `drx_debug_probe` — P-21, 3-oct-2026.
//
// Una sola definición del orden de los bits, consumida por los dos extremos:
// `rtl/drx_debug_probe.sv` lo escribe y `rtl/drx_zynq_top.sv` lo trocea en
// probes del ILA. Con los números repetidos en los dos sitios, un cambio de
// orden daría una captura perfectamente legible y equivocada -- diría que se
// para `ddc_valid` donde se para `vs_ready`.
//
// Paquete propio y no dentro del módulo porque el ancho (`DbgWidth`) está en
// la lista de puertos de `drx_top`, o sea que hace falta antes de elaborar
// nada. Ver la cabecera de `drx_debug_probe.sv` para qué mide cada campo.

`ifndef DRX_DEBUG_PKG_SV
`define DRX_DEBUG_PKG_SV

package drx_debug_pkg;
  import drx_params_pkg::*;

  // El bus solo existe en el top, donde N_CH es siempre N_CH_TOP. Fijarlo
  // aquí (en vez de parametrizar el paquete, que SystemVerilog no permite sin
  // artificios) hace que un `drx_top` con otro N_CH falle por ancho de puerto
  // en elaboración en vez de producir un bus mal troceado en silencio.
  localparam int DbgNCh = N_CH_TOP;

  localparam int DbgIdleBits = 24;

  // Campos de un bit.
  localparam int DbgSVecValid = 0;   // MM2S -> vector_source: hay beat
  localparam int DbgSVecReady = 1;   // vector_source lo acepta
  localparam int DbgSVecLast = 2;    // fin de la transferencia (TLAST)
  localparam int DbgMRayValid = 3;   // drx_ray_packer -> S2MM
  localparam int DbgMRayReady = 4;
  localparam int DbgMRayLast = 5;
  localparam int DbgDdrMode = 6;     // CTRL bit 1
  localparam int DbgTimingEnable = 7;
  localparam int DbgTimingPaced = 8;  // TIMING_CTRL bit 1 (P-16)
  localparam int DbgSampleMoved = 9;  // un conjunto de N_CH muestras avanzó
  localparam int DbgPulseTrig = 10;
  localparam int DbgStalled = 11;
  localparam int DbgFlagBits = 12;

  // Campos de N_CH bits, en el orden de la cadena.
  localparam int DbgVsValid = DbgFlagBits;
  localparam int DbgVsReady = DbgVsValid + DbgNCh;
  localparam int DbgDdcValid = DbgVsReady + DbgNCh;
  localparam int DbgGateValid = DbgDdcValid + DbgNCh;
  localparam int DbgGateReady = DbgGateValid + DbgNCh;
  localparam int DbgOverrun = DbgGateReady + DbgNCh;
  localparam int DbgTruncated = DbgOverrun + DbgNCh;

  localparam int DbgIdleCnt = DbgTruncated + DbgNCh;
  localparam int DbgWidth = DbgIdleCnt + DbgIdleBits;
endpackage

`endif  // DRX_DEBUG_PKG_SV
