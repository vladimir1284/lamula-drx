# Workspace de Vitis propio del bring-up, dominio standalone.
#
#   xsct bringup/tcl/gen_bringup_bsp.tcl <xsa> <fuente.c> [nombre_app] [ocm]
#
# El cuarto argumento `ocm` reenlaza la aplicacion a OCM (`ps7_ram_0`, 192 KiB)
# en vez de a DDR. Hace falta mientras la DDR de esta placa no sea de fiar
# (ver `bringup/README.md`, escalon 3): sin el, `dow` falla con
# "Memory write error at 0x100000".
#
# Deliberadamente NO comparte nada con `tcl/gen_bsp.tcl`: ese script borra y
# recrea su workspace en cada corrida (`build/fw/<plataforma>/vitis_ws`), así que
# compartirlo rompería el flujo de Vitis del DRx. Aquí el workspace vive en
# `build/bringup/vitis_ws` y es igual de desechable.
#
# Un solo dominio `standalone`: ni FreeRTOS ni lwIP. El escalón 3 y el 4 no
# necesitan planificador, y meterlo solo añadiría capas que, si fallan, hay que
# descartar a mano.
#
# `xsct` en esta máquina necesita `Xvfb` y `libtinfo.so.5` instalados (ver
# CLAUDE.md, cierre de BSP/FSBL del 26-sep-2026). No es una dependencia de este
# script; es estado de la máquina.

if {[llength $argv] < 2} {
  error "uso: xsct bringup/tcl/gen_bringup_bsp.tcl <xsa> <fuente.c> \[nombre_app\]"
}
set xsa_path [file normalize [lindex $argv 0]]
set src_path [file normalize [lindex $argv 1]]
set app_name [expr {[llength $argv] >= 3 ? [lindex $argv 2] : "bringup_app"}]
set link_ocm [expr {[llength $argv] >= 4 && [lindex $argv 3] eq "ocm"}]

foreach f [list $xsa_path $src_path] {
  if {![file exists $f]} { error "no existe: $f" }
}

set repo_root [file normalize [file join [file dirname [info script]] .. ..]]
set ws         [file join $repo_root build bringup vitis_ws]

file delete -force $ws
file mkdir $ws
setws $ws

platform create -name bringup_plat -hw $xsa_path
domain create -name standalone_domain -os standalone -proc ps7_cortexa9_0
platform generate

# Plantilla "Hello World": trae ya el linker script y el arranque correctos para
# este procesador. Su `helloworld.c` se sustituye entero por la fuente pedida.
app create -name $app_name -platform bringup_plat -domain standalone_domain \
  -template {Hello World}

set app_src [file join $ws $app_name src]
foreach stale [glob -nocomplain [file join $app_src *.c]] {
  file delete -force $stale
}
file copy -force $src_path $app_src

# El linker script de la plantilla manda todas las secciones a `ps7_ddr_0`. Para
# `ocm` se reescribe el destino a `ps7_ram_0` (ORIGIN 0x0, LENGTH 0x30000): el
# script generado no es fuente versionada, se regenera en cada corrida, asi que
# parchearlo aqui no viola la regla de "nada generado se edita a mano".
if {$link_ocm} {
  set ld [file join $ws $app_name src lscript.ld]
  set fh [open $ld r]; set text [read $fh]; close $fh
  set n [regsub -all {> ps7_ddr_0} $text {> ps7_ram_0} text]
  set fh [open $ld w]; puts -nonewline $fh $text; close $fh
  puts "lscript.ld: $n secciones reenlazadas a ps7_ram_0 (OCM)"
}

app build $app_name

set elf [file join $ws $app_name Debug ${app_name}.elf]
if {![file exists $elf]} {
  error "el build no produjo $elf"
}
set out [file join $repo_root build bringup ${app_name}.elf]
file copy -force $elf $out
puts "ELF: $out"
