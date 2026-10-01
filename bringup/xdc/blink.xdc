# Escalón 2 del bring-up. LOC e IOSTANDARD copiados literalmente de
# `$XILINX_VIVADO/data/boards/board_files/zedboard/1.3/part0_pins.xml`
# (interfaces `leds_8bits` y `sys_clock`), no de memoria ni de un tutorial.
#
# El reloj sí lleva su periodo escrito aquí, al contrario que en `tcl/build.tcl`
# (que lo genera desde `tcl/generated/drx_params.tcl`): este proyecto es ajeno al
# paquete de parámetros del DRx a propósito. Es el oscilador físico de la placa,
# 100 MHz, y no se dilata con `FS_HZ`.

set_property -dict {PACKAGE_PIN Y9  IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

set_property -dict {PACKAGE_PIN T22 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN T21 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN U22 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN U21 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN V22 IOSTANDARD LVCMOS33} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN W22 IOSTANDARD LVCMOS33} [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {led[7]}]
