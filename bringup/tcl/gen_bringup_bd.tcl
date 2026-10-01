# Escalón 4: block design mínimo PS7 + AXI GPIO.
#
# `source`d desde `bringup/tcl/build_gpio.tcl`, que ya ha creado el proyecto en
# memoria y fijado la pieza. Mismo patrón que `tcl/gen_zynq_bd.tcl`, pero sin
# nada del DRx: aquí solo hay un PS7 con el preset del board file y un AXI GPIO
# de doble canal contra los LEDs y los switches de la placa.
#
# Por qué AXI GPIO y no GPIO EMIO del PS, que necesitaría menos IP: lo que este
# escalón tiene que ejercitar es una transacción AXI-Lite del PS a un registro
# que vive en la PL. Es exactamente el mecanismo que usa
# `fw/src/app/drx_regs_hw.c` contra el mapa de registros del DRx. El EMIO se
# saltaría justo la capa que interesa probar.

set board_parts [get_board_parts *zedboard*]
if {[llength $board_parts] == 0} {
  error "no hay ningún board file de ZedBoard registrado en Vivado; se esperaba\
         en \$XILINX_VIVADO/data/boards/board_files/zedboard/ (ver la cabecera\
         de tcl/gen_zynq_bd.tcl)"
}
set board_part [lindex $board_parts 0]
set_property board_part $board_part [current_project]

set bd_name bringup_bd
create_bd_design $bd_name
current_bd_design [get_bd_designs $bd_name]

# --- PS7 -------------------------------------------------------------------
# El preset del board file es el que trae MIO/DDR y, entre otras cosas,
# `PCW_UART1_PERIPHERAL_ENABLE = 1` -- verificado leyendo su `preset.xml`. De ahí
# sale el `stdout` del BSP, y por tanto el `xil_printf` del escalón 4.
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
  -config [list make_external "FIXED_IO, DDR" apply_board_preset "1" \
                Master "Disable" Slave "Disable"] \
  [get_bd_cells $ps7]

# `PCW_UIPARAM_DDR_USE_INTERNAL_VREF` NO lo fija `apply_board_preset`: el board
# file de Digilent (`zedboard/1.3`) no menciona VREF en `board.xml` ni en
# `preset.xml`, asi que el parametro cae al default del IP, que es 0 (VREF
# externo). En esta placa eso deja la DDR3 inservible: el controlador alcanza
# "normal operation" (`0xF8006054` = 0x121) y las lecturas devuelven basura,
# porque el PHY muestrea contra una referencia que no llega. Verificado en placa
# el 1-oct-2026 aislandolo hasta un unico registro: con `DDRIOB_DDR_CTRL`
# (`0xF8000B6C`) = 0x260 la DDR falla 6/6; con 0xE09 -- `VREF_INT_EN=1`,
# `VREF_SEL=4` -- pasa 6/6 en todo el mapa de 512 MiB.
#
# El preset propio de Xilinx para esta placa si lo pone:
# `processing_system7_v5_5/preset/ZedBoard.tcl:218`. Ver `bringup/README.md`.
set_property -dict [list \
  CONFIG.PCW_UIPARAM_DDR_USE_INTERNAL_VREF {1} \
  CONFIG.PCW_USE_M_AXI_GP0 {1} \
  CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.0} \
] [get_bd_cells $ps7]

# --- AXI GPIO de doble canal ----------------------------------------------
# Canal 1 -> `leds_8bits` (salida), canal 2 -> `sws_8bits` (entrada).
# `C_IS_DUAL` tiene que estar puesto ANTES de la segunda `apply_board_connection`:
# sin él el pin de interfaz `GPIO2` no existe todavía y la conexión falla.
set gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0]
set_property -dict [list CONFIG.C_IS_DUAL {1}] [get_bd_cells $gpio]

# `apply_board_connection` saca el puerto externo, le pone el nombre de la
# interfaz del board file y fija ancho y dirección del canal. Gracias a eso este
# proyecto no escribe ni un solo PACKAGE_PIN: los LOC salen del board file, que
# es la misma fuente que ya verificamos a mano para `bringup/xdc/blink.xdc`.
apply_board_connection -board_interface "leds_8bits" \
  -ip_intf "axi_gpio_0/GPIO"  -diagram $bd_name
apply_board_connection -board_interface "sws_8bits" \
  -ip_intf "axi_gpio_0/GPIO2" -diagram $bd_name

# --- GP0 -> AXI GPIO -------------------------------------------------------
# La automatización crea el interconnect y el `proc_sys_reset` por su cuenta.
# Aquí no hay nada que ganar montándolos a mano, al contrario que en
# `tcl/gen_zynq_bd.tcl`, donde el maestro se reparte entre varios esclavos y uno
# de ellos vive fuera del BD.
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
  -config [list Master "/ps7/M_AXI_GP0" Clk "Auto"] \
  [get_bd_intf_pins axi_gpio_0/S_AXI]

assign_bd_address
validate_bd_design

set bd_file [get_files ${bd_name}.bd]
generate_target all $bd_file
set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper

puts "   BD         : $bd_name ($board_part)"
puts "   BD wrapper : $wrapper"
