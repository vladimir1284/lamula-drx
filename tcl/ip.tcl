# Regeneración de la IP de Xilinx a partir de los XCI versionados.
#
# `ip/` guarda XCI y NADA MÁS: los productos de `generate_target` son artefactos
# de build. La regeneración está guionizada, no es manual, porque una IP
# regenerada a mano en una máquina distinta es la forma más barata de perder la
# reproducibilidad del bitstream.
#
#   vivado -mode batch -source tcl/ip.tcl -tclargs -platform zedboard
#
# En Z0 no hay IP. El script existe ya porque Z1 crea DDS/CIC/FIR Compiler y el
# sitio donde se crean tiene que estar decidido antes, no después.

set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root tcl generated drx_params.tcl]

array set opt {platform zedboard}
for {set i 0} {$i < [llength $argv]} {incr i} {
  set flag [string trimleft [lindex $argv $i] -]
  if {[info exists opt($flag)]} {
    incr i
    set opt($flag) [lindex $argv $i]
  }
}
set part [::drx::get PART $opt(platform)]

create_project -in_memory -part $part

# `create_ip -dir` crea un subdirectorio por core (`ip/<module_name>/*.xci`),
# no `ip/*.xci` directamente — confirmado generando IP de verdad con
# tcl/gen_ip.tcl (ver el hallazgo en tcl/sim_l1.tcl).
set xci_files [glob -nocomplain [file join $repo_root ip * *.xci]]
if {![llength $xci_files]} {
  puts "no hay XCI en ip/: nada que regenerar (esperado en Z0)"
  exit 0
}

read_ip $xci_files
foreach ip [get_ips] {
  puts "regenerando $ip"
  generate_target all [get_ips $ip]
  synth_ip [get_ips $ip]
}
puts "IP regenerada"
