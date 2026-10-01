# Carga un bitstream en la PL por JTAG, sin tocar el PS.
#
#   vivado -mode batch -source bringup/tcl/program.tcl -tclargs <fichero.bit>
#
# Sirve para el escalón 2 (blinker) y para el 5 (el bitstream real del DRx).
# Para los escalones que además descargan un ELF, usa `bringup/tcl/run_jtag.tcl`,
# que hace las dos cosas desde xsct en una sola sesión.
#
# Precondición: los drivers de cable de Xilinx instalados, corriendo
# `install_drivers` DESDE SU PROPIO DIRECTORIO (llama a sus ayudantes por ruta
# relativa). Lo que instalan es `MODE:="666"` sobre el nodo USB del cable, y hace
# falta un evento udev `add` real para que se aplique: ni `udevadm trigger` a
# secas vale (emite `change`), sí `udevadm trigger --action=add
# --subsystem-match=usb` o un desenchufe físico.

if {[llength $argv] != 1} {
  error "uso: vivado -mode batch -source bringup/tcl/program.tcl -tclargs <fichero.bit>"
}
set bit_file [file normalize [lindex $argv 0]]
if {![file exists $bit_file]} {
  error "no existe el bitstream: $bit_file"
}

open_hw_manager
connect_hw_server
open_hw_target

# El nombre del device lleva sufijo de posición en la cadena (`xc7z020_1`),
# así que se busca por patrón en vez de a pelo.
set dev [lindex [get_hw_devices xc7z020*] 0]
if {$dev eq {}} {
  error "ningún xc7z020 en la cadena JTAG. Prueba a repetir el comando: si\
         `ftdi_sio` todavía tenía el cable, la primera corrida de hw_server lo\
         desengancha pero devuelve la cadena vacía. Si se repite, revisa\
         alimentación y jumpers de modo de arranque"
}
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

set_property PROGRAM.FILE $bit_file $dev
program_hw_devices $dev
refresh_hw_device $dev

puts "programado: $bit_file"
puts "DONE = [get_property REGISTER.IR.BIT5_DONE [current_hw_device]]"

close_hw_target
disconnect_hw_server
close_hw_manager
