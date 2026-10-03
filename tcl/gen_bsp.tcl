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
# lwip_dhcp=false con IP estática 192.168.1.10/24 (ver main.c, main_thread()).
# Lo heredamos en true de la plantilla y se bajó en Z4.6, con el enlace ya
# montado: el DRx habla punto a punto con el DSP (D-16), no hay servidor DHCP
# y la espera no compraba nada. La dirección sigue siendo el default de
# Xilinx, no una decisión de dominio tomada aquí -- la topología real sigue
# sin verificar (P-13).
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
# DHCP APAGADO desde Z4.6 (2-oct-2026). Lo heredamos en true de la plantilla de
# Vitis y funcionaba, pero el enlace del DRx es punto a punto contra el DSP: no
# hay ni va a haber servidor DHCP, asi que cada arranque esperaba el timeout
# completo antes de caer a la IP estatica ("Configuring default IP of
# 192.168.1.10" en el log) y el puerto del contrato tardaba lo mismo en
# escuchar. La direccion que se usa es la misma de siempre; lo unico que
# desaparece es la espera.
bsp config lwip_dhcp false
bsp config dhcp_does_arp_check false
bsp config ipv6_enable false
bsp config pbuf_pool_size 2048

platform generate

app create -name fsbl -platform drx_zynq -domain standalone_domain -template {Zynq FSBL}
app create -name drx_app -platform drx_zynq -domain freertos_domain -template {FreeRTOS lwIP Echo Server}

set app_src   [file join $proj_dir drx_app src]
set fw_src    [file join $repo_root fw src app]
set fw_inc    [file join $repo_root fw include]

foreach f {main.c drx_regs_hw.c drx_status_task.c drx_timing_cfg.c drx_contract_io.c
            drx_control.c drx_stimulus.c drx_dma.c drx_ray.c drx_ray_frame.c
            drx_control_boot.c drx_afc.c drx_afc_app.c drx_status_frame.c
            drx_ray_ctx.c drx_transport.c} {
  file copy -force [file join $fw_src $f] [file join $app_src $f]
}
foreach f {drx_regs_hw.h drx_status_task.h drx_timing_cfg.h drx_contract_io.h
            drx_control.h drx_stimulus.h drx_regs.h drx_params.h drx_dma.h
            drx_ray.h drx_ray_frame.h drx_control_boot.h drx_afc.h drx_afc_app.h
            drx_status_frame.h drx_ray_ctx.h drx_transport.h} {
  file copy -force [file join $fw_inc $f] [file join $app_src $f]
}

# La cabecera del contrato vive fuera de fw/: la genera tools/gen_contract.py a
# partir de contract/schema/, igual que la de Python y la de Rust. Se copia, no
# se anade por -I, porque `app create` fija los includes del proyecto de Vitis y
# anadir una ruta externa a mano obligaria a tocar el .cproject generado -- que
# es justo lo que AGENTS.md prohibe. Copiarla no la duplica como fuente: el
# original sigue siendo el unico versionado, y el CI ya falla si esta desfasado
# respecto del esquema.
file copy -force [file join $repo_root contract generated drx_dsp_v0_1.h] \
                 [file join $app_src drx_dsp_v0_1.h]

# El catalogo de estimulos (Z4.3) lo genera tools/gen_stimulus_catalog.py en
# build/, no se versiona -- son 62 KiB de numeros que salen del modelo, igual
# que el `.hex` de precarga de la BRAM. tools/build_vitis.sh lo regenera antes
# de llamar a xsct; si falta, el fallo es aqui y no un error de compilacion
# oscuro mas adelante.
# La plataforma sale del nombre del directorio de salida -- tools/build_vitis.sh
# llama con `build/fw/<plataforma>`, el mismo convenio que usa para localizar el
# XSA. No se pasa como tercer argumento para no cambiar la firma del script.
set platform [file tail $outdir]
set stim_dir [file join $repo_root build fw stimulus $platform]
foreach f {drx_stimulus_catalog.c drx_stimulus_catalog.h} {
  set src [file join $stim_dir $f]
  if {![file exists $src]} {
    error "falta $src: correr 'python3 tools/gen_stimulus_catalog.py --platform $platform'"
  }
  file copy -force $src [file join $app_src $f]
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
