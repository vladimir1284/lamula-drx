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
