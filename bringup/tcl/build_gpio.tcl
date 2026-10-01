# Escalón 4: síntesis, implementación, bitstream y XSA del BD PS7 + AXI GPIO.
#
#   vivado -mode batch -source bringup/tcl/build_gpio.tcl
#
# Deja en build/bringup/: bringup_bd_wrapper.bit y bringup_bd_wrapper.xsa.
# El XSA es el que consume `bringup/tcl/gen_bringup_bsp.tcl`.

set repo_root [file normalize [file join [file dirname [info script]] .. ..]]
set outdir    [file join $repo_root build bringup]
set part      xc7z020clg484-1
set top       bringup_bd_wrapper
file mkdir $outdir

puts "== bring-up: PS7 + AXI GPIO =="
puts "   pieza  : $part"
puts "   salida : $outdir"

create_project -in_memory -part $part
set_property target_language Verilog [current_project]

# Sin XDC propio: todos los pines de usuario (LEDs y switches) los saca
# `apply_board_connection` desde el board file, y DDR/FIXED_IO los fija el
# propio modelo del PS7.
source [file join $repo_root bringup tcl gen_bringup_bd.tcl]

synth_design -top $top -part $part
write_checkpoint -force [file join $outdir gpio_post_synth.dcp]

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $outdir gpio_post_route.dcp]
report_timing_summary -file [file join $outdir gpio_timing.rpt]

set wns [get_property SLACK [get_timing_paths -delay_type max]]
puts "WNS = $wns ns"
if {$wns < 0} {
  error "temporización no cerrada: WNS = $wns ns"
}

set bit_file [file join $outdir ${top}.bit]
write_bitstream -force $bit_file
puts "bitstream escrito en $bit_file"

set xsa_file [file join $outdir ${top}.xsa]
write_hw_platform -fixed -include_bit -force $xsa_file
puts "XSA escrito en $xsa_file"
