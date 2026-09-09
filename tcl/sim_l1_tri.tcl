# Flujo de simulación L1 del top-level de TRES canales sobre xsim — Config A
# (Tx+H+V) / Config B (Tx+nominal+atenuado) de ZedBoard (P-12, decisión del
# 9-sep-2026: docs/alcance/pendientes.md#p-12, docs/implementacion/fases.md
# nota "9-sep-2026: dos configuraciones de 3 canales").
#
# Réplica de tcl/sim_l1_quad.tcl (que no se toca: sigue siendo el hito
# original de N_RX_CH canales homogéneos, vivo para la ZU9) para
# tb_l1_ddc_tri.sv en vez de tb_l1_ddc_quad.sv: mismo manejo de IP/XCI, mismo
# gate de "VALOR DE ARRANQUE", mismo -timescale y el mismo hallazgo de
# verilog_define. La diferencia es N_CH=3 en vez de N_RX_CH, con tres casos
# fijos y distintos por canal para que un cruce entre ramas del `generate` de
# drx_ddc_quad_top.sv (instanciado aquí con N_CH=3, "el mismo con generics")
# se vea como discrepancia en vez de colar por casualidad de datos iguales.
#
# Config A y Config B comparten este mismo flujo: la diferencia entre ellas
# es la fuente analógica de cada canal (fuera de este repo, ver P-12), no la
# cadena digital ni este testbench — se corre una sola vez por -mode, no una
# vez por config.
#
#   vivado -mode batch -source tcl/sim_l1_tri.tcl -tclargs \
#          -platform zedboard -mode fine

set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root tcl generated drx_params.tcl]

# Asignación fija canal -> caso: no es un barrido de casos (eso ya lo hace
# tcl/sim_l1.tcl canal a canal), es la prueba de que los TRES canales del
# `generate` de drx_ddc_quad_top.sv (N_CH=3) no se cruzan entre sí. Se
# reutilizan tres de los cuatro casos que ya genera tools/gen_l1_vectors.py
# para el flujo quad — no hace falta un caso nuevo.
set case_by_channel {tono_if tono_desplazado dos_tonos}

# --- argumentos -------------------------------------------------------------
array set opt {platform zedboard mode {} outdir {} gui 0}
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
if {$opt(mode) ni {fine coarse}} {
  error "falta -mode {fine|coarse}"
}
if {$opt(outdir) eq {}} {
  set opt(outdir) [file join $repo_root build sim xsim $opt(platform) tri__$opt(mode)]
}
file mkdir $opt(outdir)

set mode_arg [expr {$opt(mode) eq "coarse" ? 1 : 0}]

# --- manifiestos, uno por canal ---------------------------------------------
array set vectors_dir {}
array set n_stimulus {}
array set n_expected {}
array set settling {}

proc manifest_get {json key} {
  # Mismo extractor mínimo que sim_l1.tcl: json.dumps con indent=2 pone cada
  # clave en su línea, y Vivado no trae paquete JSON.
  if {[regexp "\"$key\"\\s*:\\s*\"?(\[^\",\\n\]+)\"?" $json -> value]} {
    return [string trim $value]
  }
  error "el manifiesto no tiene la clave $key"
}

for {set ch 0} {$ch < 3} {incr ch} {
  set case_name [lindex $case_by_channel $ch]
  set dir [file join $repo_root build l1-vectors $opt(platform) "${case_name}__$opt(mode)"]
  set manifest_path [file join $dir manifest.json]
  if {![file exists $manifest_path]} {
    error "no hay vectores en $dir; corre antes: python3 tools/gen_l1_vectors.py"
  }
  set manifest [read [set fh [open $manifest_path r]]]
  close $fh

  set params_sha [manifest_get $manifest params_sha256]
  if {$params_sha ne $::drx::PARAMS_SHA256} {
    error "canal $ch ($case_name): vectores de otro config/params.toml ($params_sha != $::drx::PARAMS_SHA256); regenéralos"
  }

  set vectors_dir($ch) $dir
  set n_stimulus($ch) [manifest_get $manifest n_stimulus]
  set n_expected($ch) [manifest_get $manifest n_expected]
  set settling($ch)   [manifest_get $manifest settling_out_samples]
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
  [file join $repo_root sim tb_sv tb_l1_ddc_tri.sv]]

# Mismo aviso que sim_l1.tcl: drx_ddc_ip_pkg.sv trae un valor de arranque
# hasta que corre tcl/gen_ip.tcl contra la IP real; comprobar que ya no lo
# sea es justo lo que hace esto.
set have_ddc 0
foreach src $rtl_sources {
  if {[file tail $src] eq "drx_ddc_top.sv"} { set have_ddc 1 }
}
if {$have_ddc} {
  set ip_pkg [file join $repo_root rtl generated drx_ddc_ip_pkg.sv]
  set fh [open $ip_pkg r]
  set ip_pkg_body [read $fh]
  close $fh
  if {[string match "*VALOR DE ARRANQUE*" $ip_pkg_body]} {
    error "rtl/generated/drx_ddc_ip_pkg.sv sigue siendo el valor de arranque; corre tcl/gen_ip.tcl antes de sim_l1_tri.tcl"
  }
}

# --- elaboración y ejecución -------------------------------------------------
cd $opt(outdir)

set part [::drx::get PART $opt(platform)]
create_project sim_l1_tri -part $part -force

set xci_files [glob -nocomplain [file join $repo_root ip * *.xci]]
if {[llength $xci_files]} {
  read_ip $xci_files
  generate_target {simulation instantiation_template} [get_ips]
}

add_files -norecurse -fileset [current_fileset -simset] [concat $rtl_sources $tb_sources]
set_property top tb_l1_ddc_tri [current_fileset -simset]

set xelab_options {-timescale 1ps/1ps}
set xvlog_options {}
if {$have_ddc} {
  lappend xelab_options -d DRX_HAVE_DDC
  lappend xvlog_options -d DRX_HAVE_DDC
  set_property verilog_define {DRX_HAVE_DDC} [current_fileset -simset]
} else {
  puts "AVISO: no hay drx_ddc_top en rtl/filelist.f; el testbench abortará (trabajo de Z1)"
}
set_property -name {xsim.elaborate.xelab.more_options} \
             -value $xelab_options -objects [current_fileset -simset]
set_property -name {xsim.compile.xvlog.more_options} \
             -value $xvlog_options -objects [current_fileset -simset]

set plusargs [list "mode=$mode_arg"]
for {set ch 0} {$ch < 3} {incr ch} {
  set dir $vectors_dir($ch)
  lappend plusargs \
    "stimulus_path_${ch}=[file join $dir stimulus.hex]" \
    "stimulus_count_${ch}=$n_stimulus($ch)" \
    "expected_i_path_${ch}=[file join $dir expected_i.hex]" \
    "expected_q_path_${ch}=[file join $dir expected_q.hex]" \
    "expected_count_${ch}=$n_expected($ch)" \
    "settling_${ch}=$settling($ch)"
}

# xsim exige -testplusarg delante de cada uno (ver la nota en sim_l1.tcl).
set testplusarg_opts {}
foreach pa $plusargs { lappend testplusarg_opts "-testplusarg" $pa }

set_property -name {xsim.simulate.xsim.more_options} \
             -value [join $testplusarg_opts " "] -objects [current_fileset -simset]

launch_simulation
run all

puts "L1 tri $opt(platform)/$opt(mode) (Config A/B, N_CH=3): terminado (canales: $case_by_channel). Log en $opt(outdir)"
