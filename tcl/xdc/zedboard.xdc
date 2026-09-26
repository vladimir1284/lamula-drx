# Restricciones físicas de la ZedBoard (rev. D, XC7Z020-CLG484-1).
#
# Aquí NO hay periodo de reloj: el `create_clock` lo emite el flujo a partir de
# `tcl/generated/drx_params.tcl`, que deriva de config/params.toml (D-02). Un
# periodo literal en este fichero falla el gate de CI.

set_property -dict {PACKAGE_PIN Y9  IOSTANDARD LVCMOS33} [get_ports clk]

# BTNC como reset activo a nivel bajo: el pulsador da alto, se invierte en el flujo.
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS25} [get_ports rst_n]

# LD0.
set_property -dict {PACKAGE_PIN T22 IOSTANDARD LVCMOS33} [get_ports led_heartbeat]

# `trig_out[3:0]` (D-13/Z2, ZM2) a Pmod JA -- los 4 pines de la fila superior
# del conector (JA1/JA2/JA3/JA4), single-ended, Banco 13 (3,3 V). Pinout
# tomado del ZedBoard Hardware User's Guide oficial de Digilent/Avnet (Tabla
# 16, "Pmod Connections"): JA1=Y11, JA2=AA11, JA3=Y10, JA4=AA9. Se eligió JA
# (no JC/JD) porque esos dos son diferenciales (routeados para LVDS, D-13 no
# necesita eso) y JB queda libre para otro uso futuro. El orden trig_out[0]->
# JA1..trig_out[3]->JA4 es arbitrario (ningún documento de docs/alcance/ fija
# un mapeo canal->pin de trigger) -- lo único que importa para el osciloscopio
# del hito ZM2 es que cada trigger tenga un pin físico estable y documentado.
set_property -dict {PACKAGE_PIN Y11  IOSTANDARD LVCMOS33} [get_ports {trig_out[0]}]
set_property -dict {PACKAGE_PIN AA11 IOSTANDARD LVCMOS33} [get_ports {trig_out[1]}]
set_property -dict {PACKAGE_PIN Y10  IOSTANDARD LVCMOS33} [get_ports {trig_out[2]}]
set_property -dict {PACKAGE_PIN AA9  IOSTANDARD LVCMOS33} [get_ports {trig_out[3]}]
