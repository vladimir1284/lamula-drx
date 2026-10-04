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

# `PCW_UIPARAM_DDR_USE_INTERNAL_VREF` no lo fija `apply_board_preset`: el board
# file de Digilent (`zedboard/1.3`) no menciona VREF ni en `board.xml` ni en
# `preset.xml`, así que el parámetro cae al default del IP, que es 0 (VREF
# externo). En la ZedBoard eso deja la DDR3 inservible: el controlador llega a
# "normal operation" (`0xF8006054` = 0x121), `ps7_init` no reporta ningún error,
# y toda lectura devuelve basura porque el PHY muestrea contra una referencia
# que no llega. Verificado en placa el 1-oct-2026, aislado hasta un único
# registro: con `DDRIOB_DDR_CTRL` (`0xF8000B6C`) = 0x260 la sonda de DDR falla
# 6/6; con 0xE09 -- `VREF_INT_EN=1`, `VREF_SEL=4` -- pasa 6/6 en todo el mapa.
#
# El preset propio de Xilinx para esta placa sí lo pone
# (`processing_system7_v5_5/preset/ZedBoard.tcl:218`); el de Digilent, no. Todo
# XSA, BSP, FSBL, `drx_app.elf` y `BOOT.BIN` generado por este repositorio antes
# de esta línea lleva un `ps7_init` que no entrena la DDR de verdad. Detalle del
# diagnóstico y de las hipótesis descartadas en `bringup/README.md`.
#
# Segundo parámetro que el preset de Digilent deja mal, misma familia que el
# anterior y encontrado igual: midiendo (Z4.6, 2-oct-2026).
# `PCW_ENET0_GRP_MDIO_ENABLE` sí lo pone a 1, pero deja
# `PCW_ENET0_GRP_MDIO_IO` en `EMIO` -- es decir, saca el MDIO del PHY por la
# FÁBRICA, donde no hay nada conectado. En la ZedBoard el PHY (Marvell 88E1518)
# tiene el MDIO cableado a MIO 52/53, igual que los datos RGMII van por
# MIO 16..27, que el preset sí enruta bien.
#
# Síntoma: `Auto negotiation error` -> `Phy setup failure init_emacps` ->
# `unable to determine type of EMAC with baseaddress 0xE000B000` en cada
# arranque, con el cable puesto y el otro extremo con portadora. El último
# mensaje engaña: parece que el EMAC no está en el XSA, y sí está. Lo que
# falta es el camino de gestión para hablar con el PHY.
#
# Comprobado leyendo los MIO por JTAG antes de tocar nada: `MIO_PIN_52` y
# `MIO_PIN_53` valían 0x200 -- los cuatro campos `L*_SEL` a cero, o sea pin sin
# muxear a ningún periférico-- mientras `MIO_PIN_16` valía 0x2902, con
# `L0_SEL = 1` (ENET0). Datos sí, gestión no.
set fclk_mhz [expr {1000.0 / $period_ns}]
set_property -dict [list \
  CONFIG.PCW_UIPARAM_DDR_USE_INTERNAL_VREF {1} \
  CONFIG.PCW_ENET0_GRP_MDIO_IO {MIO 52 .. 53} \
  CONFIG.PCW_USE_M_AXI_GP0 {1} \
  CONFIG.PCW_USE_S_AXI_HP0 {1} \
  CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {32} \
  CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
  CONFIG.PCW_IRQ_F2P_INTR {1} \
  CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $fclk_mhz \
] [get_bd_cells $ps7]

# --- Interconnect de GP0: dos maestros derivados de un solo maestro (GP0) --
#     M00 hacia `drx_axil_regs` (fuera del BD, dentro de `drx_top`, como
#     siempre), M01 (Z4.0, nuevo) hacia el registro de control AXI-Lite del
#     AXI DMA (`dma/S_AXI_LITE`, más abajo -- ese sí vive DENTRO del BD, así
#     que no hace falta puerto externo para él). No hace falta un crossbar de
#     verdad para M00, pero sí la traducción de ID/ancho de AXI GP0 ->
#     AXI-Lite que un interconnect resuelve de forma estándar. --------------
set axi_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_ic]
set_property -dict [list CONFIG.NUM_MI {2}] [get_bd_cells $axi_ic]

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

# --- AXI DMA S2MM, Z4.0 (fases.md#z4) ---------------------------------------
#
# Primer consumidor real del AXI4-Stream de `drx_ray_packer`
# (`drx_top.m_ray_*`, N_CH canales entrelazados, 32 bits/palabra -- ver la
# cabecera de `rtl/drx_ray_packer.sv`). Scatter-gather (D-07/fases.md#z4:
# "AXI DMA scatter-gather S2MM hacia buffers circulares en la DDR del PS")
# aunque el firmware que gestiona descriptores todavía no existe (Z4.2+) --
# mismo criterio que `drx_axil_regs`, que se sintetizó semanas antes de que
# hubiera firmware real que lo leyera.
#
# UN SOLO canal, S2MM, desde el 4-oct-2026. Saca el rayo empaquetado hacia la
# DDR: 32 bits (`2*IQ_BITS`, una pareja I/Q por palabra, ver
# `drx_ray_packer.sv`) del lado del stream y 32 del lado de memoria.
#
# MM2S existió entre Z4.3 (1-oct-2026) y hoy: leía de la DDR los vectores de
# estímulo y los metía en el modo Throttled(DDR) de `rtl/vector_source.sv`,
# para que barrer el catálogo costara un DMA y no ocho corridas de Vivado. Se
# retira porque entregaba una muestra cada N_CH ciclos y el DDS Compiler, que
# no tiene `aclken`, avanza un paso de fase por ciclo mire o no `valid`: el DDC
# mezclaba a ~N_CH veces el IF y la salida caía al suelo de ruido (P-16, -87,3
# dBFS medidos contra -9,02 del modelo). El estímulo se carga ahora por la
# ventana AXI-Lite del mapa v11 directamente a la BRAM de `vector_source`, que
# reproduce a una muestra por ciclo.
#
# CONSECUENCIA ACEPTADA: después de esto nada en el diseño ejercita el camino
# DMA PS->PL. `M_AXI_MM2S` contra `S_AXI_HP0` era la única cobertura que había
# de ese sentido.
# `c_sg_length_width` 23 (Z4.4, sube desde el 14 por defecto): el campo de
# longitud de un descriptor pasa de 16383 B a 8 MiB - 1. Un rayo completo en
# modo fino son 16 B de cabecera en banda + 3689 bins x 3 canales x 4 B =
# 44284 B, que con 14 bits habria obligado a trocear cada rayo en tres
# descriptores encadenados y a reensamblarlos en el manejador. Con 23 bits
# cabe uno por descriptor y el fin de rayo (RXEOF, puesto por el hardware a
# partir de TLAST) coincide con el fin de descriptor, que es justo la
# equivalencia de la que depende el manejador de Z4.4.
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 dma]
set_property -dict [list \
  CONFIG.c_include_mm2s          {0} \
  CONFIG.c_include_s2mm          {1} \
  CONFIG.c_include_sg            {1} \
  CONFIG.c_sg_length_width       {23} \
  CONFIG.c_sg_include_stscntrl_strm {0} \
  CONFIG.c_s_axis_s2mm_tdata_width  {32} \
  CONFIG.c_m_axi_s2mm_data_width    {32} \
] [get_bd_cells $dma]

# Reloj único de todo el BD (FCLK0, D-02) para las interfaces de reloj del
# DMA -- sin automation, mismo criterio explícito que el resto de este
# fichero. `m_axi_mm2s_aclk` ya no está en la lista: sin `c_include_mm2s` ese
# pin no existe y `connect_bd_net` fallaría. En modo síncrono (por defecto,
# sin "Enable Multi Channel"/relojes asíncronos) `S_AXIS_S2MM` vive en el
# dominio de `m_axi_s2mm_aclk`, sin pin de reloj propio -- confirmado
# listando los pines reales de la IP generada (no hay `s_axis_s2mm_aclk`).
foreach clk_pin {s_axi_lite_aclk m_axi_sg_aclk m_axi_s2mm_aclk} {
  connect_bd_net [get_bd_pins $ps7/FCLK_CLK0] [get_bd_pins $dma/$clk_pin]
}
connect_bd_net [get_bd_pins $rst_ic/peripheral_aresetn] [get_bd_pins $dma/axi_resetn]

# --- Registro de control del DMA: segundo maestro de GP0 (M01), vía su
#     propio protocol converter -- mismo motivo que `axi_pc` para
#     `drx_axil_regs`: M01_AXI del interconnect es AXI4 completo,
#     `dma/S_AXI_LITE` es AXI4-Lite puro. ------------------------------------
set axi_pc_dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_protocol_converter:2.1 axi_pc_dma]
connect_bd_intf_net [get_bd_intf_pins $axi_ic/M01_AXI] [get_bd_intf_pins $axi_pc_dma/S_AXI]
connect_bd_intf_net [get_bd_intf_pins $axi_pc_dma/M_AXI] [get_bd_intf_pins $dma/S_AXI_LITE]
connect_bd_net [get_bd_pins $ps7/FCLK_CLK0] [get_bd_pins $axi_pc_dma/aclk]
connect_bd_net [get_bd_pins $rst_ic/peripheral_aresetn] [get_bd_pins $axi_pc_dma/aresetn]

# --- Camino de datos del DMA hacia DDR: S_AXI_HP0, vía su propio
#     interconnect -- dos maestros del lado del DMA (M_AXI_SG, motor de
#     scatter-gather; M_AXI_S2MM, los propios datos) contra un solo slave
#     (HP0). --------------------------------------------------------------
#
# Fueron tres maestros entre Z4.3 y el 4-oct-2026, con `M_AXI_MM2S` en
# S02_AXI; ese maestro se fue con el canal.
set axi_ic_hp [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_ic_hp]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] [get_bd_cells $axi_ic_hp]

connect_bd_intf_net [get_bd_intf_pins $dma/M_AXI_SG]   [get_bd_intf_pins $axi_ic_hp/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $dma/M_AXI_S2MM] [get_bd_intf_pins $axi_ic_hp/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins $axi_ic_hp/M00_AXI] [get_bd_intf_pins $ps7/S_AXI_HP0]

set ic_hp_clk_pins [get_bd_pins -of_objects [get_bd_cells $axi_ic_hp] \
                                 -filter {NAME =~ "*ACLK*"}]
connect_bd_net [get_bd_pins $ps7/FCLK_CLK0] $ic_hp_clk_pins
connect_bd_net [get_bd_pins $ps7/FCLK_CLK0] [get_bd_pins $ps7/S_AXI_HP0_ACLK]

set ic_hp_rst_pins [get_bd_pins -of_objects [get_bd_cells $axi_ic_hp] \
                                 -filter {NAME =~ "*ARESETN*"}]
connect_bd_net [get_bd_pins $rst_ic/peripheral_aresetn] $ic_hp_rst_pins

# --- Interrupción de fin de descriptor. Una sola fuente: S2MM (Z4.0) dice
#     cuándo un rayo terminó de escribirse en DDR.
#
#     El `xlconcat` que Z4.3 metió aquí para juntar S2MM y MM2S se va con el
#     canal MM2S: con una sola red, conectarla directamente a IRQ_F2P es
#     legal, y es lo que había antes de Z4.3.
#
#     S2MM sigue siendo el bit 0 de IRQ_F2P, así que el ID de interrupción no
#     debería moverse y `drx_ray.c` no cambia. AUN ASÍ hay que comprobarlo
#     contra el `xparameters.h` regenerado: ese número sale del XSA, no de
#     este fichero. ----------------------------------------------------------
connect_bd_net [get_bd_pins $dma/s2mm_introut] [get_bd_pins $ps7/IRQ_F2P]

# --- AXI4-Stream externo: entra el rayo empaquetado desde `drx_top`
#     (`rtl/drx_zynq_top.sv`) hacia `dma/S_AXIS_S2MM`. TDATA_NUM_BYTES=4
#     (32 bits, `2*IQ_BITS`, ver `drx_ray_packer.sv`) -- `s_axis_ray_tkeep`
#     lo ata `drx_zynq_top.sv` a `4'hF` (el stream nunca trae bytes
#     parciales), no algo que `drx_top`/`drx_ray_packer` deban saber. El
#     interfaz `axis_rtl` no lleva reloj propio (a diferencia de `aximm_rtl`,
#     tampoco) -- mismo dominio que `pl_clk0` (drx_top entero ya corre de ese
#     reloj), así que se suma a su MISMA lista de ASSOCIATED_BUSIF en vez de
#     crear un puerto de reloj nuevo.
set s_axis_name s_axis_ray
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 $s_axis_name
# HAS_TLAST no es verdadero por defecto en el VLNV `axis_rtl` -- sin fijarlo,
# `axi_dma` avisó en corrida real ("Interface connected to S_AXIS_S2MM does
# not have TLAST port"), y TLAST es justo lo que cierra cada descriptor de
# scatter-gather (el fin de rayo de `drx_ray_packer`). Imprescindible, no
# cosmético.
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.HAS_TKEEP {1} \
                          CONFIG.HAS_TSTRB {0} CONFIG.HAS_TLAST {1}] \
  [get_bd_intf_ports $s_axis_name]
connect_bd_intf_net [get_bd_intf_ports $s_axis_name] [get_bd_intf_pins $dma/S_AXIS_S2MM]

# El puerto externo `m_axis_vec` (salida de `dma/M_AXIS_MM2S` hacia
# `drx_top.s_vec_*`) vivió aquí entre Z4.3 y el 4-oct-2026, y con él la
# comprobación de ancho que iba después de `validate_bd_design`. Se fue con el
# canal MM2S.
#
# Vale la pena no perder el hallazgo que costó una corrida de Vivado entera el
# 1-oct-2026, por si vuelve a hacer falta un puerto de interfaz de SALIDA: en
# modo **Master** los parámetros del interfaz son de SOLO LECTURA -- se
# derivan del pin maestro al que se conecta. Fijar
# TDATA_NUM_BYTES/HAS_TKEEP/HAS_TSTRB/HAS_TLAST a mano produce cuatro
# CRITICAL WARNING `[BD 41-737] ... It is read-only.` y no tiene ningún
# efecto. Es lo contrario del puerto Slave `s_axis_ray` de arriba, donde
# fijarlos SÍ hace falta. Y si se quiere comprobar el ancho resultante, la
# comprobación tiene que ir DESPUÉS de `validate_bd_design`: la propagación de
# parámetros del BD corre ahí, así que leído antes el puerto todavía dice 1
# byte.

set_property CONFIG.ASSOCIATED_BUSIF "${m00_name}:${s_axis_name}" \
  [get_bd_ports pl_clk0]

# Vivado elige la dirección dentro del mapa de GP0 del PS7 -- no se fija a
# mano aquí (Z2/firmware es quien la necesitará de verdad). `assign_bd_address`
# ya imprime a qué dirección queda mapeado `m_axi_regs`/el registro de
# control del DMA ("Slave segment ... is being assigned into address space
# ... at <0x...>"), no hace falta repetirlo con un `puts` propio. También
# asigna la ventana de `M_AXI_SG`/`M_AXI_S2MM` contra la DDR vista por HP0.
assign_bd_address

validate_bd_design

set bd_file [get_files ${bd_name}.bd]
generate_target all $bd_file
set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper

puts "   BD Zynq    : $bd_name ($board_part, FCLK0 = $fclk_mhz MHz)"
puts "   BD wrapper : $wrapper"
