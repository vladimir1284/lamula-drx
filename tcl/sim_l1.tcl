# Flujo de simulación L1 sobre xsim (P-09).
#
# L0 corre en Verilator bajo cocotb; L1 no puede, porque los cores del DDC son
# cajas negras que Verilator no elabora, y cocotb no tiene backend para xsim.
# La salida adoptada es testbench nativo de SystemVerilog más oráculo por
# fichero:
#
#   1. `python3 tools/gen_l1_vectors.py` escribe estímulo y salida esperada.
#   2. Este script elabora `sim/tb_sv/tb_l1_ddc.sv` con la IP generada.
#   3. El testbench lee los `.hex` con `$readmemh` y compara bit a bit.
#
#   vivado -mode batch -source tcl/sim_l1.tcl -tclargs \
#          -platform zedboard -case tono_if__fine
#
# NOTA DE FASE: igual que `tcl/build.tcl`, este flujo está ESCRITO Y REVISADO
# PERO NO EJECUTADO — no hay Vivado en el entorno (supuesto A7). Y el DUT
# `drx_ddc_top` es trabajo de Z1: hasta que exista, la elaboración falla a
# propósito. Lo que sí está verificado hoy es el arnés que usa, en
# `sim/tests/test_l1_harness.py` sobre Verilator.

set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root tcl generated drx_params.tcl]

# --- argumentos -------------------------------------------------------------
array set opt {platform zedboard case {} outdir {} vectors {} gui 0}
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
if {$opt(case) eq {}} {
  error "falta -case; los casos los nombra tools/gen_l1_vectors.py"
}
if {$opt(vectors) eq {}} {
  set opt(vectors) [file join $repo_root build l1-vectors $opt(platform) $opt(case)]
}
if {$opt(outdir) eq {}} {
  set opt(outdir) [file join $repo_root build sim xsim $opt(platform) $opt(case)]
}
file mkdir $opt(outdir)

# --- manifiesto -------------------------------------------------------------
# El manifiesto lleva los conteos, el modo y la huella del paquete de parámetros.
# Se lee aquí en vez de pasarlo por argumentos para que no haya dos fuentes de
# verdad sobre el mismo caso.
set manifest_path [file join $opt(vectors) manifest.json]
if {![file exists $manifest_path]} {
  error "no hay vectores en $opt(vectors); corre antes: python3 tools/gen_l1_vectors.py"
}
set manifest [read [set fh [open $manifest_path r]]][close $fh]

proc manifest_get {json key} {
  # Extractor mínimo: el manifiesto lo escribe json.dumps con indent=2, así que
  # cada clave está en su línea. Vivado no trae paquete JSON y no se va a añadir
  # una dependencia por cuatro campos.
  if {[regexp "\"$key\"\\s*:\\s*\"?(\[^\",\\n\]+)\"?" $json -> value]} {
    return [string trim $value]
  }
  error "el manifiesto no tiene la clave $key"
}

set n_stimulus [manifest_get $manifest n_stimulus]
set n_expected [manifest_get $manifest n_expected]
set settling   [manifest_get $manifest settling_out_samples]
set mode       [manifest_get $manifest mode]
set mode_arg   [expr {$mode eq "coarse" ? 1 : 0}]

set params_sha [manifest_get $manifest params_sha256]
if {$params_sha ne $::drx::PARAMS_SHA256} {
  error "los vectores son de otro config/params.toml ($params_sha != $::drx::PARAMS_SHA256); regenéralos"
}

# --- fuentes ----------------------------------------------------------------
set rtl_sources {}
set fh [open [file join $repo_root rtl filelist.f] r]
foreach line [split [read $fh] \n] {
  set line [string trim $line]
  if {$line eq {} || [string index $line 0] eq "#"} { continue }
  lappend rtl_sources [file join $repo_root $line]
}
close $fh

set tb_sources [list \
  [file join $repo_root sim tb_sv drx_l1_file_source.sv] \
  [file join $repo_root sim tb_sv drx_l1_checker.sv] \
  [file join $repo_root sim tb_sv tb_l1_ddc.sv]]

# --- elaboración y ejecución ------------------------------------------------
cd $opt(outdir)

set part [::drx::get PART $opt(platform)]
create_project -in_memory -part $part

# La IP se lee de los XCI versionados, igual que en tcl/build.tcl: una sola
# fuente de verdad para los cores, y simulación contra exactamente lo que se
# sintetiza. Sin XCI —el caso de Z0— el testbench no tiene DUT y falla solo.
set xci_files [glob -nocomplain [file join $repo_root ip *.xci]]
if {[llength $xci_files]} {
  read_ip $xci_files
  generate_target {simulation instantiation_template} [get_ips]
}

foreach src [concat $rtl_sources $tb_sources] {
  read_verilog -sv $src
}

set_property top tb_l1_ddc [current_fileset -simset]

# El define solo se pone si el DUT existe. Sin él el testbench aborta con un
# mensaje que dice qué falta; con él puesto sobre un DUT inexistente el fallo
# sería un «module not found» de xelab, que dice mucho menos.
set have_ddc 0
foreach src $rtl_sources {
  if {[file tail $src] eq "drx_ddc_top.sv"} { set have_ddc 1 }
}
# La escala de tiempo se fija aquí y no en el testbench: declararla solo en un
# módulo y no en el RTL mezcla escalas, y el periodo del reloj sale de FS_HZ en
# picosegundos.
set xelab_options {-timescale 1ps/1ps}
if {$have_ddc} {
  lappend xelab_options -d DRX_HAVE_DDC
} else {
  puts "AVISO: no hay drx_ddc_top en rtl/filelist.f; el testbench abortará (trabajo de Z1)"
}
set_property -name {xsim.elaborate.xelab.more_options} \
             -value $xelab_options -objects [current_fileset -simset]

set plusargs [list \
  "+stimulus_path=[file join $opt(vectors) stimulus.hex]" \
  "+stimulus_count=$n_stimulus" \
  "+expected_i_path=[file join $opt(vectors) expected_i.hex]" \
  "+expected_q_path=[file join $opt(vectors) expected_q.hex]" \
  "+expected_count=$n_expected" \
  "+settling=$settling" \
  "+mode=$mode_arg"]

set_property -name {xsim.simulate.xsim.more_options} \
             -value [join $plusargs " "] -objects [current_fileset -simset]

launch_simulation
run all

puts "L1 $opt(platform)/$opt(case): terminado. Log en $opt(outdir)"
