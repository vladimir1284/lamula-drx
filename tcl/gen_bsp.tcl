# BSP + FSBL + app de Vitis para el DRx, desde el XSA de `-top zynq -step xsa`
# (tcl/build.tcl). Cierra el punto que CLAUDE.md marca como "lo primero que
# hay que hacer": tools/make_boot.sh falla hasta que existan fsbl.elf y
# drx_app.elf.
#
#   xsct tcl/gen_bsp.tcl <xsa_path> <outdir>
#
# `drx_app` es la plantilla "Hello World" de Vitis, no el firmware real
# (FreeRTOS + ensamblado de rayos): eso es el resto de Z4, sin empezar. Lo
# único que este paso demuestra es que el BOOT.BIN se puede empaquetar con un
# ELF real, cross-compilado contra el BSP de este hardware.

if {[llength $argv] != 2} {
  error "uso: xsct tcl/gen_bsp.tcl <xsa_path> <outdir>"
}
set xsa_path [lindex $argv 0]
set outdir   [lindex $argv 1]
set proj_dir [file join $outdir vitis_ws]

file mkdir $outdir
file delete -force $proj_dir
file mkdir $proj_dir

setws $proj_dir
platform create -name drx_zynq -hw $xsa_path
domain create -name standalone_domain -os standalone -proc ps7_cortexa9_0
bsp setlib -name xilffs
platform generate

app create -name fsbl -platform drx_zynq -domain standalone_domain -template {Zynq FSBL}
app create -name drx_app -platform drx_zynq -domain standalone_domain -template {Hello World}

app build -name fsbl
app build -name drx_app

proc find_elf {proj_dir app_name} {
  set matches [glob -nocomplain [file join $proj_dir $app_name * ${app_name}.elf]]
  if {[llength $matches] == 0} {
    error "no se encontro ${app_name}.elf bajo $proj_dir/$app_name"
  }
  return [lindex $matches 0]
}

file copy -force [find_elf $proj_dir fsbl]    [file join $outdir fsbl.elf]
file copy -force [find_elf $proj_dir drx_app] [file join $outdir drx_app.elf]

puts "fsbl.elf y drx_app.elf escritos en $outdir"
