# GENERADO por tools/gen_params.py a partir de config/params.toml. NO EDITAR A MANO.
# Cambia config/params.toml y vuelve a generar; el CI comprueba que coinciden.
#
# El flujo de tcl/ deriva de aquí el periodo de reloj y la pieza. Ningún
# fichero de tcl/ ni ningún XDC puede llevar un periodo literal (D-02).

namespace eval ::drx {
  variable SCHEMA_VERSION 1
  variable PARAMS_SHA256 32f277ddd53e943f63e7352663ba588ddb4637284284f9b8756149d5e9379499

  # Invariantes de dilatación y de la cadena de diezmado (D-02): idénticos
  # en las dos plataformas, y de aquí los toma tcl/gen_ip.tcl para
  # configurar la IP del DDC sin repetir un número a mano.
  variable NCO_PHASE_BITS 32
  variable NCO_OUT_BITS 16
  variable NCO_PHASE_INC 1030792151
  variable SAMPLE_BITS 16
  variable IQ_BITS 16
  variable CIC_STAGES 5
  variable CIC_RATE 52
  variable CIC_DIFF_DELAY 1
  variable FIR_DECIM 4
  variable FIR_TAPS 63
  variable COARSE_EXTRA_DECIM 2

  # Anchos derivados (Hogenauer, ganancia de continua de cada FIR),
  # calculados por model/drx_model/chain.py: mismo número que consume
  # rtl/generated/drx_params_pkg.sv, para tcl/gen_ip.tcl.
  variable CIC_GAIN 380204032
  variable CIC_GROWTH_BITS 29
  variable CIC_REGISTER_BITS 45
  variable FIR_COEFF_BITS 18
  variable FIR_DC_GAIN 552725
  variable FIR_GROWTH_BITS 20
  variable HALFBAND_COEFF_BITS 18
  variable HALFBAND_DC_GAIN 328067
  variable HALFBAND_GROWTH_BITS 19

  # Ajuste de ganancia fina (Z1: escalado a fondo de escala), ver
  # model/drx_model/chain.py::Ddc._residual_gain.
  variable GAIN_TRIM_BITS 18
  variable FINE_GAIN_COEFF 43890
  variable FINE_GAIN_FRAC_BITS 14
  variable COARSE_GAIN_COEFF 35070
  variable COARSE_GAIN_FRAC_BITS 13

  # zedboard: Digilent ZedBoard rev. D
  variable FS_HZ_ZEDBOARD 100000000
  variable IF_HZ_ZEDBOARD 24000000
  variable CLK_PERIOD_NS_ZEDBOARD 10.000000
  variable PART_ZEDBOARD xc7z020clg484-1

  # zu9: portadora ZU9 + 2x VadaTech FMC213 (no comprada)
  variable FS_HZ_ZU9 250000000
  variable IF_HZ_ZU9 60000000
  variable CLK_PERIOD_NS_ZU9 4.000000
  variable PART_ZU9 xczu9eg-ffvb1156-2-e

  variable PLATFORMS [list zedboard zu9]
}

# Resuelve una variable por plataforma: [::drx::get FS_HZ zedboard]
proc ::drx::get {name platform} {
  set var ::drx::${name}_[string toupper $platform]
  if {![info exists $var]} {
    error "parámetro desconocido: $name para la plataforma $platform"
  }
  return [set $var]
}
