# BSP + FSBL + app de Vitis para el DRx, desde el XSA de `-top zynq -step xsa`
# (tcl/build.tcl). Cierra el punto que CLAUDE.md marcaba como "lo primero que
# hay que hacer" (BSP/FSBL, 26-sep-2026) y ahora genera el firmware real de
# Z4.2: FreeRTOS + lwIP + el driver de registros AXI-Lite de fw/, no ya el
# "Hello World" de Vitis.
#
#   xsct tcl/gen_bsp.tcl <xsa_path> <outdir>
#
# Dos dominios sobre la misma plataforma, no uno solo: `fsbl` tiene que
# seguir siendo standalone (el FSBL de Xilinx no admite FreeRTOS, confirmado
# por la propia plantilla "Zynq FSBL"); `drx_app` pasa a freertos10_xilinx +
# lwip211 -- la plantilla "FreeRTOS lwIP Echo Server" de Vitis (misma familia
# que ya usa `xilffs`/"Zynq FSBL": IP-first, no reinventar el stack de red)
# da el bring-up de Ethernet (servidor echo TCP puerto 7 + respuesta ICMP de
# la propia pila lwIP -- primer ping/echo real que pide Z4.2). Los parámetros
# de la librería lwip211 NO los aplica `app create -template` solo con crear
# el proyecto (confirmado: el .tcl de esta plantilla no llama a `bsp config`
# por su cuenta) -- de ahí los `bsp config` explícitos de abajo, con los
# mismos valores que trae la plantilla de referencia
# ($XILINX_VITIS/data/embeddedsw/lib/sw_apps/freertos_lwip_echo_server/data/
# freertos_lwip_echo_server.mss): api_mode=SOCKET_API (echo.c usa
# lwip_socket/accept/read/write, no la RAW API por defecto de lwip211),
# lwip_dhcp=true con caída a IP estática 192.168.1.10/24 si no hay servidor
# DHCP (ver main.c, main_thread()) -- topología de red real todavía no
# verificada (P-13), este es el default de Xilinx, no una decisión de
# dominio tomada aquí.
#
# `fw/src/app/` (nuevo, versionado, no generado) trae el firmware real:
# `main.c` (adaptado de la plantilla: arranca drx_status_task antes que
# lwIP) y `drx_regs_hw.c` (driver de fw/include/drx_regs_hw.h sobre
# XPAR_M_AXI_REGS_BASEADDR -- la base que Vivado asigna al puerto externo
# `m_axi_regs` de tcl/gen_zynq_bd.tcl, capturada por Vitis en xparameters.h
# a partir del XSA). Se copian DESPUÉS de `app create` (que trae el resto de
# la plantilla: echo.c, platform_config.h, lscript.ld) y ANTES de
# `app build`, igual que fsbl no se toca -- ese sigue siendo 100% la
# plantilla de Xilinx.

if {[llength $argv] != 2} {
  error "uso: xsct tcl/gen_bsp.tcl <xsa_path> <outdir>"
}
set repo_root [file normalize [file join [file dirname [info script]] ..]]
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

domain create -name freertos_domain -os freertos10_xilinx -proc ps7_cortexa9_0
domain active freertos_domain
bsp setlib -name lwip211
bsp config api_mode SOCKET_API
bsp config lwip_dhcp true
bsp config dhcp_does_arp_check true
bsp config ipv6_enable false
bsp config pbuf_pool_size 2048

platform generate

app create -name fsbl -platform drx_zynq -domain standalone_domain -template {Zynq FSBL}
app create -name drx_app -platform drx_zynq -domain freertos_domain -template {FreeRTOS lwIP Echo Server}

set app_src   [file join $proj_dir drx_app src]
set fw_src    [file join $repo_root fw src app]
set fw_inc    [file join $repo_root fw include]

foreach f {main.c drx_regs_hw.c drx_status_task.c drx_timing_cfg.c} {
  file copy -force [file join $fw_src $f] [file join $app_src $f]
}
foreach f {drx_regs_hw.h drx_status_task.h drx_timing_cfg.h drx_regs.h drx_params.h} {
  file copy -force [file join $fw_inc $f] [file join $app_src $f]
}

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
