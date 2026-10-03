# Crea el ILA de depuración de P-21 como XCI versionado en `ip_debug/`.
#
#   vivado -mode batch -source tcl/gen_ip_debug.tcl -tclargs -platform zedboard
#
# Directorio aparte de `ip/` a propósito, y es la pieza que mantiene la build
# normal intacta: `tcl/build.tcl` hace `glob ip/*/*.xci` y sintetiza todo lo
# que encuentre, así que un ILA ahí dentro costaría un `synth_ip` en CADA
# corrida y dejaría un core sin instanciar en el netlist. Con `ip_debug/`, el
# XCI solo se lee con `-debug 1`.
#
# Lo que engancha está en `rtl/drx_zynq_top.sv` (bajo `ifdef DRX_DEBUG_ILA`) y
# el bus que mira, en `rtl/drx_debug_probe.sv`. El troceado en probes es el de
# `drx_debug_pkg`; los anchos de aquí tienen que cuadrar con él, y por eso
# N_CH sale de `tcl/generated/drx_params.tcl` y no escrito a mano.
#
# Configuración, y el porqué de cada decisión que no es el default:
#
#   C_EN_STRG_QUAL = 1 (almacenamiento calificado). Es lo que hace útil la
#     captura. El atasco se DETECTA decenas de milisegundos después de
#     empezar (el umbral de `drx_debug_probe` son 2**22 ciclos = 67 ms), y la
#     ventana de 4096 muestras a 62,5 MHz son 65 µs. Disparando con `stalled`
#     y guardando todas las muestras, el buffer entero caería dentro del
#     silencio y no se vería nada. Calificando el almacenamiento por
#     "algo se movió", esas 4096 muestras son los últimos 4096 ciclos CON
#     actividad antes de la parada, que es justo la evidencia que falta.
#
#   ALL_PROBE_SAME_MU_CNT = 2. Una unidad de comparación por probe no basta
#     cuando el mismo probe participa en la condición de disparo y en la de
#     almacenamiento; con una sola, Vivado rechaza una de las dos.
#
#   C_INPUT_PIPE_STAGES = 1. El bus sale de un `always_comb` sobre handshakes
#     que ya están en el camino crítico de nadie, pero el ILA añade fanout a
#     57 señales; una etapa de registro lo aísla del cierre de temporización.
#     El coste es un ciclo de latencia uniforme en TODOS los probes, así que
#     las relaciones entre ellos — que es lo que se va a leer — no cambian.

set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root tcl generated drx_params.tcl]

array set opt {platform zedboard}
for {set i 0} {$i < [llength $argv]} {incr i} {
  set flag [string trimleft [lindex $argv $i] -]
  if {[info exists opt($flag)]} {
    incr i
    set opt($flag) [lindex $argv $i]
  } else {
    error "argumento desconocido: [lindex $argv $i]"
  }
}
if {[lsearch -exact $::drx::PLATFORMS $opt(platform)] < 0} {
  error "plataforma desconocida: $opt(platform); hay $::drx::PLATFORMS"
}

set part   [::drx::get PART $opt(platform)]
set ip_dir [file join $repo_root ip_debug]
file mkdir $ip_dir

create_project -in_memory -part $part

# Mismo `ensure_ip` idempotente que tcl/gen_ip.tcl, por el hallazgo de Z4.5:
# `create_ip` sobre una IP ya presente crea `<nombre>_1/` en silencio.
set xci [file join $ip_dir drx_debug_ila drx_debug_ila.xci]
if {[file exists $xci]} {
  read_ip $xci
} else {
  create_ip -name ila -vendor xilinx.com -library ip -version 6.2 \
      -module_name drx_debug_ila -dir $ip_dir
}

set n_ch $::drx::N_CH_TOP

# Anchos, en el orden de `drx_debug_pkg`. Los tres primeros son campos de bits
# sueltos; del 3 al 9, uno por canal; el 10, el contador de ciclos sin avance.
set widths [list 3 3 6 $n_ch $n_ch $n_ch $n_ch $n_ch $n_ch $n_ch 24]

set cfg [list \
  CONFIG.C_NUM_OF_PROBES      [llength $widths] \
  CONFIG.C_DATA_DEPTH         {4096} \
  CONFIG.C_INPUT_PIPE_STAGES  {1} \
  CONFIG.C_EN_STRG_QUAL       {1} \
  CONFIG.C_ADV_TRIGGER        {false} \
  CONFIG.C_TRIGIN_EN          {false} \
  CONFIG.C_TRIGOUT_EN         {false} \
  CONFIG.ALL_PROBE_SAME_MU    {true} \
  CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
]
for {set i 0} {$i < [llength $widths]} {incr i} {
  lappend cfg CONFIG.C_PROBE${i}_WIDTH [lindex $widths $i]
}

set_property -dict $cfg [get_ips drx_debug_ila]
generate_target all [get_ips drx_debug_ila]

puts "ILA de depuración creado en $ip_dir/drx_debug_ila ([llength $widths] probes)"
