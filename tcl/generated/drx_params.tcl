# GENERADO por tools/gen_params.py a partir de config/params.toml. NO EDITAR A MANO.
# Cambia config/params.toml y vuelve a generar; el CI comprueba que coinciden.
#
# El flujo de tcl/ deriva de aquí el periodo de reloj y la pieza. Ningún
# fichero de tcl/ ni ningún XDC puede llevar un periodo literal (D-02).

namespace eval ::drx {
  variable SCHEMA_VERSION 1
  variable PARAMS_SHA256 e90ab8bb9c31092b8cab9c74acc55f0c917f5db1e544915f775296748a10b95a

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
