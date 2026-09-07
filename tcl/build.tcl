# Flujo Vivado NO-PROJECT del LAMULA DRx (D-07).
#
# Cero clicks: no hay .xpr, no hay estado en la GUI, todo entra por argumentos y
# sale a un directorio de build. Es precondición del modelo de entrega acelerado
# por agentes, no burocracia: sobre un proyecto GUI no hay reproducibilidad ni
# regresión.
#
#   vivado -mode batch -source tcl/build.tcl -tclargs \
#          -platform zedboard -step bitstream -outdir build/gw/zedboard
#
# Pasos: synth | impl | bitstream. Cada uno incluye los anteriores.
#
# NOTA DE FASE Z0: en este repositorio no hay Vivado instalado, así que este
# flujo está ESCRITO Y REVISADO PERO NO EJECUTADO. La primera ejecución real es
# el cierre del hito ZM0 y hay que hacerla en una máquina con Vivado antes de dar
# Z0 por terminada.

set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root tcl generated drx_params.tcl]

# --- argumentos -------------------------------------------------------------
array set opt {platform zedboard step bitstream outdir {} jobs 4 seed 1}
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
if {$opt(outdir) eq {}} {
  set opt(outdir) [file join $repo_root build gw $opt(platform)]
}
file mkdir $opt(outdir)

set part        [::drx::get PART       $opt(platform)]
set period_ns   [::drx::get CLK_PERIOD_NS $opt(platform)]
set top         drx_top

puts "== LAMULA DRx =="
puts "   plataforma : $opt(platform)"
puts "   pieza      : $part"
puts "   periodo    : $period_ns ns  (derivado de FS_HZ, D-02)"
puts "   paso       : $opt(step)"
puts "   salida     : $opt(outdir)"

# --- fuentes ----------------------------------------------------------------
proc read_filelist {path root} {
  set files {}
  set handle [open $path r]
  foreach line [split [read $handle] \n] {
    set line [string trim $line]
    if {$line eq {} || [string index $line 0] eq "#"} continue
    lappend files [file join $root $line]
  }
  close $handle
  return $files
}

create_project -in_memory -part $part
set_property target_language Verilog [current_project]

# La MISMA lista que consume Verilator en sim/. Si divergen, un backend compila
# algo que el otro no ve.
read_verilog -sv [read_filelist [file join $repo_root rtl filelist.f] $repo_root]

# IP versionada como XCI. En Z0 no hay ninguna; el bucle queda listo para Z1.
# `create_ip -dir` crea un subdirectorio por core (`ip/<module_name>/*.xci`),
# no `ip/*.xci` directamente — confirmado generando IP de verdad con
# tcl/gen_ip.tcl (ver el hallazgo en tcl/sim_l1.tcl).
set xci_files [glob -nocomplain [file join $repo_root ip * *.xci]]
if {[llength $xci_files]} {
  read_ip $xci_files
  generate_target all [get_ips]
  synth_ip [get_ips]
}

set xdc [file join $repo_root tcl xdc $opt(platform).xdc]
if {[file exists $xdc]} {
  read_xdc $xdc
} else {
  puts "AVISO: no hay XDC para $opt(platform); se sintetiza sin restricciones físicas"
}

# El periodo NO se escribe en el XDC: sale del paquete de parámetros.
set clk_xdc [file join $opt(outdir) clock_generated.xdc]
set handle [open $clk_xdc w]
puts $handle "# Generado por tcl/build.tcl desde tcl/generated/drx_params.tcl."
puts $handle "create_clock -period $period_ns -name clk \[get_ports clk\]"
close $handle
read_xdc $clk_xdc

# --- síntesis ---------------------------------------------------------------
set synth_args [list -top $top -part $part]
if {$opt(platform) eq "zu9"} {
  lappend synth_args -verilog_define DRX_PLATFORM_ZU9
}
synth_design {*}$synth_args
write_checkpoint -force [file join $opt(outdir) post_synth.dcp]
report_utilization -file [file join $opt(outdir) post_synth_utilization.rpt]
report_timing_summary -file [file join $opt(outdir) post_synth_timing.rpt]

if {$opt(step) eq "synth"} {
  puts "síntesis terminada"
  exit 0
}

# --- implementación ---------------------------------------------------------
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $opt(outdir) post_route.dcp]
report_utilization -file [file join $opt(outdir) post_route_utilization.rpt]
report_timing_summary -file [file join $opt(outdir) post_route_timing.rpt]

# El cierre de temporización tiene que ser un gate, no un informe que nadie lee.
set wns [get_property SLACK [get_timing_paths -delay_type max]]
puts "WNS = $wns ns"
if {$wns < 0} {
  error "temporización no cerrada en $opt(platform): WNS = $wns ns"
}

if {$opt(step) eq "impl"} {
  puts "implementación terminada"
  exit 0
}

# --- bitstream --------------------------------------------------------------
# `-bin_file` produce además el .bin crudo, sin la cabecera del .bit que lleva
# marca de tiempo: es el que se usa para el BOOT.BIN reproducible byte a byte.
write_bitstream -force -bin_file [file join $opt(outdir) drx_top.bit]
puts "bitstream escrito en $opt(outdir)"
