# Block design del PS7 para el puente PS7<->AXI de `rtl/drx_axil_regs.sv`.
#
# `source`d desde `tcl/build.tcl` cuando se pide `-top zynq`, ANTES de
# `synth_design` -- reutiliza `$part`, `$period_ns`, `$opt(outdir)` del script
# que lo invoca, no los redefine.
#
# El BD contiene SOLO IP (PS7 + interconnect + reset), nada de RTL propio:
# probado en esta misma sesión que `create_bd_cell -type module -reference`
# no admite un top SystemVerilog en Vivado 2022.2 ("This type is not allowed
# as the top file in the reference") -- `drx_top` NO puede vivir dentro del
# BD. Por eso `rtl/drx_zynq_top.sv` existe: instancia el wrapper de este BD
# más `drx_top` por fuera, y los conecta en SystemVerilog normal.
#
# Nada de esto se persiste como `.bd`: D-07 es "cero clicks, todo por
# argumentos", así que el BD se reconstruye entero por TCL en cada build en
# vez de guardar un `.bd` binario que sincronizar a mano con este script. La
# fuente de verdad es este fichero, igual que `tcl/gen_ip.tcl` lo es para los
# `.xci` versionados en `ip/`.
#
# Board file: instalado a mano en esta máquina desde el repo público
# `github.com/Digilent/vivado-boards` (`new/board_files/zedboard/`), copiado a
# `$XILINX_VIVADO/data/boards/board_files/zedboard/`. No viene con Vivado por
# defecto (es de Digilent, no de Xilinx) -- si `get_board_parts` no encuentra
# nada, este script para con un error explícito en vez de sintetizar sin
# preset de MIO/DDR.

set board_parts [get_board_parts *zedboard*]
if {[llength $board_parts] == 0} {
  error "no hay ningún board file de ZedBoard registrado en Vivado (se esperaba\
         instalado a mano en \$XILINX_VIVADO/data/boards/board_files/zedboard/,\
         ver la cabecera de este fichero)"
}
set board_part [lindex $board_parts 0]
puts "   board_part : $board_part"
set_property board_part $board_part [current_project]

set bd_name drx_zynq_bd
create_bd_design $bd_name
current_bd_design [get_bd_designs $bd_name]

# --- PS7: preset de MIO/DDR del board file, GP0 habilitado, FCLK0 a la
#     frecuencia de fabric del proyecto (misma que $period_ns, D-02: no se
#     inventa un reloj nuevo, es el que ya usa todo el datapath). ------------
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]

apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
  -config [list make_external "FIXED_IO, DDR" apply_board_preset "1" \
                Master "Disable" Slave "Disable"] \
  [get_bd_cells $ps7]

set fclk_mhz [expr {1000.0 / $period_ns}]
set_property -dict [list \
  CONFIG.PCW_USE_M_AXI_GP0 {1} \
  CONFIG.PCW_USE_FABRIC_INTERRUPT {0} \
  CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $fclk_mhz \
] [get_bd_cells $ps7]

# --- Interconnect 1x1: un solo maestro (GP0), un solo slave (`drx_axil_regs`,
#     fuera del BD, dentro de `drx_top`). No hace falta un crossbar de
#     verdad, pero sí la traducción de ID/ancho de AXI GP0 -> AXI-Lite que un
#     interconnect resuelve de forma estándar. ------------------------------
set axi_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_ic]
set_property -dict [list CONFIG.NUM_MI {1}] [get_bd_cells $axi_ic]

connect_bd_intf_net [get_bd_intf_pins $ps7/M_AXI_GP0] \
                     [get_bd_intf_pins $axi_ic/S00_AXI]

# Reloj y reset cableados a mano, sin automation: un solo dominio (FCLK_CLK0)
# para PS7 y el interconnect, con `proc_sys_reset` sincronizando
# FCLK_RESET0_N -- explícito en vez de fiarse de una regla de automation cuya
# sintaxis exacta de `-config` no está verificada contra esta versión de
# Vivado (2022.2).
# `axi_interconnect` expone un ACLK global Y uno por interfaz (S00_ACLK,
# M00_ACLK) -- los tres necesitan reloj, confirmado corriendo esto de verdad
# ("clock pins are not connected to a valid clock source" solo con el global
# conectado).
set ic_clk_pins [get_bd_pins -of_objects [get_bd_cells $axi_ic] \
                              -filter {NAME =~ "*ACLK*"}]
connect_bd_net [get_bd_pins $ps7/FCLK_CLK0] $ic_clk_pins
connect_bd_net [get_bd_pins $ps7/FCLK_CLK0] [get_bd_pins $ps7/M_AXI_GP0_ACLK]

set rst_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ic]
connect_bd_net [get_bd_pins $ps7/FCLK_CLK0] [get_bd_pins $rst_ic/slowest_sync_clk]
connect_bd_net [get_bd_pins $ps7/FCLK_RESET0_N] [get_bd_pins $rst_ic/ext_reset_in]

set ic_rst_pins [get_bd_pins -of_objects [get_bd_cells $axi_ic] \
                              -filter {NAME =~ "*ARESETN*"}]
if {[llength $ic_rst_pins] == 0} {
  error "no se encontró ningún pin *ARESETN* en $axi_ic -- revisar el nombre\
         de puerto de reset de axi_interconnect:2.1 en esta versión de Vivado"
}
connect_bd_net [get_bd_pins $rst_ic/peripheral_aresetn] $ic_rst_pins

# --- M00_AXI del interconnect es AXI4 completo (ID/burst/len/lock/cache/qos/
#     region/size/last) -- `axi_interconnect:2.1` no tiene ninguna propiedad
#     de protocolo por puerto (confirmado listando sus CONFIG.*, no existe
#     "M00_AXI_PROTOCOL" ni nada parecido). `drx_axil_regs`/`drx_top` son
#     AXI4-LITE puro, sin esas señales. `axi_protocol_converter:2.1` traduce
#     entre los dos -- y por defecto ya viene configurado
#     SI_PROTOCOL=AXI4/MI_PROTOCOL=AXI4LITE (confirmado, no hace falta tocar
#     su CONFIG). -----------------------------------------------------------
set axi_pc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_protocol_converter:2.1 axi_pc]
connect_bd_intf_net [get_bd_intf_pins $axi_ic/M00_AXI] [get_bd_intf_pins $axi_pc/S_AXI]
connect_bd_net [get_bd_pins $ps7/FCLK_CLK0] [get_bd_pins $axi_pc/aclk]
connect_bd_net [get_bd_pins $rst_ic/peripheral_aresetn] [get_bd_pins $axi_pc/aresetn]

set m00_name m_axi_regs
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 $m00_name
# Sin esto, el puerto externo hereda por defecto el AXI4 completo del VLNV
# `aximm_rtl` (con ID/burst/len/...) aunque lo conectemos a `axi_pc/M_AXI`
# (que sí es AXI4-Lite) -- `connect_bd_intf_net` solo cablea el subconjunto
# que coincide, deja el resto colgando en vez de encoger el puerto. El
# wrapper generado sin esto seguía teniendo esas señales de más, confirmado
# corriendo esto (`grep m_axi_regs_ ... | sort -u` mostraba arid/awid/etc.).
set_property CONFIG.PROTOCOL AXI4LITE [get_bd_intf_ports $m00_name]
connect_bd_intf_net [get_bd_intf_pins $axi_pc/M_AXI] [get_bd_intf_ports $m00_name]

# `-type clk` (no un puerto genérico) es lo que da acceso a las propiedades
# CONFIG.FREQ_HZ/ASSOCIATED_BUSIF de abajo -- con puerto genérico, Vivado dice
# "The parameter does not exist" (confirmado corriendo esto).
create_bd_port -dir O -type clk pl_clk0
connect_bd_net [get_bd_pins $ps7/FCLK_CLK0] [get_bd_ports pl_clk0]

# Sin esto, `m_axi_regs` queda sin dominio de reloj asociado y su FREQ_HZ por
# defecto (100 MHz) no coincide con el de verdad (FCLK0, aquí 62,5 MHz) --
# confirmado corriendo esto: "Bus Interface property FREQ_HZ does not match".
set fclk_hz [expr {int(round($fclk_mhz * 1e6))}]  ; # clock-const-ok: 1e6 es conversión MHz->Hz de $fclk_mhz (ya derivado de $period_ns), no un reloj nuevo
set_property CONFIG.FREQ_HZ $fclk_hz [get_bd_ports pl_clk0]
set_property CONFIG.ASSOCIATED_BUSIF $m00_name [get_bd_ports pl_clk0]

create_bd_port -dir O pl_resetn0
connect_bd_net [get_bd_pins $rst_ic/peripheral_aresetn] [get_bd_ports pl_resetn0]

# Vivado elige la dirección dentro del mapa de GP0 del PS7 -- no se fija a
# mano aquí (Z2/firmware es quien la necesitará de verdad). `assign_bd_address`
# ya imprime a qué dirección queda mapeado `m_axi_regs` ("Slave segment ...
# is being assigned into address space ... at <0x...>"), no hace falta
# repetirlo con un `puts` propio.
assign_bd_address

validate_bd_design

set bd_file [get_files ${bd_name}.bd]
generate_target all $bd_file
set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper

puts "   BD Zynq    : $bd_name ($board_part, FCLK0 = $fclk_mhz MHz)"
puts "   BD wrapper : $wrapper"
