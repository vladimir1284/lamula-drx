# Carga bitstream + ELF por JTAG y arranca el A9, en una sola sesión de xsct.
#
#   xsct bringup/tcl/run_jtag.tcl <fichero.bit> <fichero.elf> [xsa]
#
# Sirve para los escalones 3, 4 y 5. El XSA es opcional: si se pasa, se usa
# `loadhw`, que es lo que hace que `ps7_init` esté disponible desde el propio
# target (sin él habría que cargar a mano `ps7_init.tcl` del BSP).
#
# ANTES de lanzarlo, abre la consola en otra terminal:
#
#   picocom -b 115200 /dev/ttyACM0        (salir: Ctrl-A Ctrl-X)
#
# `/dev/ttyACM0` es el USB-UART Cypress de la ZedBoard, cableado a UART1 del PS.
# `/dev/ttyUSB0` NO es un segundo puerto serie: es el FT232H del JTAG de
# Digilent, y si existe es que los drivers de cable no están instalados.

if {[llength $argv] < 2} {
  error "uso: xsct bringup/tcl/run_jtag.tcl <fichero.bit> <fichero.elf> \[xsa\]"
}
set bit_file [file normalize [lindex $argv 0]]
set elf_file [file normalize [lindex $argv 1]]
set xsa_file [expr {[llength $argv] >= 3 ? [file normalize [lindex $argv 2]] : ""}]

foreach f [list $bit_file $elf_file] {
  if {![file exists $f]} { error "no existe: $f" }
}

connect

# NO uses `rst -system` aqui. Verificado en esta ZedBoard el 1-oct-2026: en modo
# de arranque JTAG, `rst -system` resetea el SLCR y corta las relojes de
# depuracion; sin imagen de arranque valida la BootROM nunca los restaura, y el
# DAP queda en "APB AP transaction error, DAP status 0x30000021". A partir de
# ahi `targets` ya no lista ni el APU ni los dos A9, `rst -por` no existe para
# el target `xc7z020`, y matar `hw_server` no arregla nada: solo lo recupera un
# apagado y encendido fisico de la placa (SW8).
#
# `rst -cores` resetea los dos A9 y los deja parados, sin tocar el SLCR. Es
# suficiente para que una segunda corrida no arranque sobre los restos de la
# anterior, que es lo unico que se buscaba aqui.
targets -set -filter {name =~ "APU*"}
rst -cores
after 1000

# Orden que importa: primero el bitstream, después `ps7_init`. La PL tiene que
# estar configurada antes de que el PS empiece a direccionar esclavos AXI que
# viven en ella.
fpga -file $bit_file

targets -set -filter {name =~ "*Cortex-A9*#0" || name =~ "ARM*#0"}
if {$xsa_file ne ""} {
  loadhw -hw $xsa_file -mem-ranges [list {0x40000000 0xBFFFFFFF}]
}

# `loadhw` NO define `ps7_init` en xsct 2022.2 (verificado: "invalid command
# name \"ps7_init\"" justo despues de un loadhw correcto). El procedimiento vive
# en `ps7_init.tcl`, que el XSA lleva dentro -- el XSA es un zip. Se extrae y se
# carga a mano, asi el init siempre corresponde al mismo XSA que se acaba de
# cargar, sin depender de que exista un workspace de Vitis al lado.
if {[llength [info commands ps7_init]] == 0} {
  if {$xsa_file eq ""} {
    error "sin XSA no hay ps7_init: pasa el XSA como tercer argumento"
  }
  set init_dir [file join [file dirname $elf_file] ps7_init]
  file mkdir $init_dir
  exec unzip -o -j $xsa_file ps7_init.tcl -d $init_dir
  source [file join $init_dir ps7_init.tcl]
}

ps7_init
ps7_post_config

dow $elf_file
con

puts "corriendo: $elf_file"
puts "mira la salida en /dev/ttyACM0 (115200 8N1)"
