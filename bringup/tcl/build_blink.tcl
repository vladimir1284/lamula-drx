# Escalón 2: síntesis + implementación + bitstream del blinker de PL puro.
#
#   vivado -mode batch -source bringup/tcl/build_blink.tcl
#
# Mismo flujo NO-PROJECT que `tcl/build.tcl` (D-07: cero clicks, cero .xpr),
# recortado a lo mínimo. No comparte código con él a propósito: `tcl/build.tcl`
# depende del paquete de parámetros del DRx y este proyecto es desechable.

set repo_root [file normalize [file join [file dirname [info script]] .. ..]]
set outdir    [file join $repo_root build bringup]
set part      xc7z020clg484-1
file mkdir $outdir

puts "== bring-up: blinker de PL =="
puts "   pieza  : $part"
puts "   salida : $outdir"

create_project -in_memory -part $part
set_property target_language Verilog [current_project]

read_verilog -sv [file join $repo_root bringup rtl blink.sv]
read_xdc      [file join $repo_root bringup xdc blink.xdc]

synth_design -top blink -part $part
write_checkpoint -force [file join $outdir blink_post_synth.dcp]

opt_design
place_design
route_design
write_checkpoint -force [file join $outdir blink_post_route.dcp]
report_timing_summary -file [file join $outdir blink_timing.rpt]

# Mismo gate que `tcl/build.tcl`: la temporización se comprueba, no se informa.
set wns [get_property SLACK [get_timing_paths -delay_type max]]
puts "WNS = $wns ns"
if {$wns < 0} {
  error "temporización no cerrada: WNS = $wns ns"
}

write_bitstream -force [file join $outdir blink.bit]
puts "bitstream escrito en [file join $outdir blink.bit]"
