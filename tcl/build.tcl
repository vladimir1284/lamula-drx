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
# Pasos: synth | impl | bitstream | xsa. Cada uno incluye los anteriores.
# `xsa` solo tiene sentido con `-top zynq` (exporta la plataforma de hardware
# para Vitis; sin PS7 no hay nada que exportar).
#
# `-top`: `drx_top` (por defecto, sin PS7, AXI-Lite del mapa de registros
# atado a valores inertes vía `drx_top_tieoff`) o `zynq` (PS7 real vía
# `tcl/gen_zynq_bd.tcl`, solo zedboard hoy — ver docs/implementacion/registros.md).

set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root tcl generated drx_params.tcl]

# --- argumentos -------------------------------------------------------------
# `-top drx_top` (por defecto): datapath solo, AXI-Lite del mapa de registros
# atado a valores inertes vía `drx_top_tieoff` -- el flujo de siempre, sin PS7.
# `-top zynq`: `tcl/gen_zynq_bd.tcl` construye un PS7 de verdad (AXI GP0 -> el
# mapa de registros); ver `docs/implementacion/registros.md`.
array set opt {platform zedboard step bitstream outdir {} jobs 4 seed 1 top drx_top}
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
  if {$opt(top) eq "zynq"} {
    # Directorio propio: no pisar los artefactos de `-top drx_top` (mismo
    # `outdir` por defecto para las dos si no se namespacea aquí).
    set opt(outdir) [file join $repo_root build gw ${opt(platform)}_zynq]
  } else {
    set opt(outdir) [file join $repo_root build gw $opt(platform)]
  }
}
file mkdir $opt(outdir)

set part        [::drx::get PART       $opt(platform)]
set period_ns   [::drx::get CLK_PERIOD_NS $opt(platform)]
if {$opt(top) eq "drx_top"} {
  set top drx_top_tieoff
} elseif {$opt(top) eq "zynq"} {
  if {$opt(platform) ne "zedboard"} {
    error "-top zynq solo tiene sentido en zedboard hoy (PS7 = processing_system7;\
           la ZU9 usa zynq_ultra_ps_e, puente distinto, sin diseñar todavía)"
  }
  set top drx_zynq_top
} else {
  error "-top desconocido: $opt(top) (valores válidos: drx_top, zynq)"
}

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

# `drx_zynq_top.sv` NO entra en `rtl/filelist.f` (instancia el wrapper del BD
# de `tcl/gen_zynq_bd.tcl`, que no existe todavía en este punto del script, y
# de todas formas Verilator no puede elaborar `processing_system7`).
if {$opt(top) eq "zynq"} {
  read_verilog -sv [file join $repo_root rtl drx_zynq_top.sv]
}

# IP versionada como XCI. En Z0 no hay ninguna; el bucle queda listo para Z1.
# `create_ip -dir` crea un subdirectorio por core (`ip/<module_name>/*.xci`),
# no `ip/*.xci` directamente — confirmado generando IP de verdad con
# tcl/gen_ip.tcl (ver el hallazgo en tcl/sim_l1.tcl).
# AVISO (2-oct-2026, Z4.5): ver la nota equivalente en tcl/sim_l1.tcl -- los dos
# flujos escriben en `ip/<core>/` y no se pueden correr en paralelo.
set xci_files [glob -nocomplain [file join $repo_root ip * *.xci]]
if {[llength $xci_files]} {
  read_ip $xci_files
  generate_target all [get_ips]
  synth_ip [get_ips]
}

if {$opt(top) eq "zynq"} {
  # `drx_zynq_bd_wrapper` no tiene puertos `clk`/`rst_n` de nivel superior (el
  # reloj/reset son internos al BD, FCLK0/peripheral_aresetn del PS7) — el
  # `create_clock` sintético de más abajo no aplica, y `zedboard.xdc`
  # constriñe justo esos dos puertos que ya no existen en este top. XDC propio,
  # solo con lo que de verdad sigue siendo un pin de usuario en este top
  # (`led_heartbeat`; `debug_probe` ya se deja sin restringir hoy también en
  # el flujo sin PS7). El reloj de fabric lo cierra Vivado solo, a partir del
  # modelo de temporización del propio PS7 con el board preset aplicado — no
  # hace falta (ni tiene sentido) escribir un `create_clock` a mano aquí.
  set xdc [file join $repo_root tcl xdc zedboard_zynq.xdc]
  if {[file exists $xdc]} {
    read_xdc $xdc
  } else {
    puts "AVISO: no hay XDC para el top zynq; se sintetiza sin restricciones físicas"
  }
  source [file join $repo_root tcl gen_zynq_bd.tcl]
} else {
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
}

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
# `debug_probe` se deja sin restringir a propósito (ver tcl/xdc/zedboard.xdc y
# zedboard_zynq.xdc): es el único puerto de top-level sin IOSTANDARD/LOC, y el
# DRC de write_bitstream lo trata como error (NSTD-1/UCIO-1) por defecto. Bajar
# estas dos reglas a Warning es lo que el propio mensaje de Vivado sugiere para
# este caso. ADVERTENCIA: esto no se puede acotar por puerto -- si en el futuro
# se agrega un puerto de top-level nuevo sin XDC, este mismo cambio deja que el
# bitstream se genere igual, sin avisar.
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]

# `-bin_file` produce además el .bin crudo, sin la cabecera del .bit que lleva
# marca de tiempo: es el que se usa para el BOOT.BIN reproducible byte a byte.
set bit_file [file join $opt(outdir) ${top}.bit]
write_bitstream -force -bin_file $bit_file
puts "bitstream escrito en $opt(outdir)"

if {$opt(step) eq "bitstream"} {
  exit 0
}

# --- xsa (solo -top zynq) ----------------------------------------------------
# Entregable de este paso: el XSA para que Vitis genere BSP/FSBL (Z4, no aquí
# -- ver docs/implementacion/registros.md). No tiene sentido para `-top
# drx_top`: sin PS7 no hay plataforma de hardware que exportar.
if {$opt(top) eq "zynq"} {
  set xsa_file [file join $opt(outdir) ${top}.xsa]
  write_hw_platform -fixed -include_bit -force $xsa_file
  puts "XSA escrito en $xsa_file"
}
