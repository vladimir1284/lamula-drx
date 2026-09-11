# Flujo de simulación L1 de `tb_l1_ddc_range_tri.sv` sobre xsim: drx_ddc_quad_top
# (N_CH=3, configs A/B de ZedBoard) seguido de drx_range_gate_quad_top — el
# cierre de ZM1 que compara por RAYO (dato + TLAST), no solo la muestra
# decimada suelta que ya cubre tcl/sim_l1_tri.tcl.
#
# Réplica de tcl/sim_l1_tri.tcl (que no se toca: sigue siendo el cierre del
# DDC solo) para tb_l1_ddc_range_tri.sv — mismos manifiestos, mismos tres
# casos fijos por canal, mismo manejo de IP/XCI y del hallazgo de
# verilog_define. La única diferencia real es el testbench de arriba.
#
#   vivado -mode batch -source tcl/sim_l1_range_tri.tcl -tclargs \
#          -platform zedboard -mode fine

set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root tcl generated drx_params.tcl]

# Mismos tres casos que sim_l1_tri.tcl, y por la misma razón: los valores I/Q
# que produce drx_range_gate son idénticos a los de drx_ddc_top (el gating
# reordena en el tiempo, no toca el dato), así que reutiliza el mismo mapeo
# canal -> caso en vez de inventar uno.
#
# Hallazgo del 10-sep-2026: se probó cambiar tono_if (canal 0, el que trae el
# residuo de ±2-3 LSB ya documentado en P-10/P-12) por tono_desplazado_neg,
# asumiendo que tono_desplazado/dos_tonos estaban limpios frente al modelo
# dorado. Falso: nunca se habían comprobado hasta el final (el mismo
# `$fatal` en el primer canal con discrepancias que tapa TLAST también tapaba
# esto), y al correr con tono_desplazado en el canal 0 salieron 44/288
# discrepancias de la MISMA clase (±1-3 LSB) — proporcionalmente peor que el
# ~12/315 ya aceptado de tono_if. El residuo no es específico de tono_if; ver
# docs/alcance/pendientes.md para el seguimiento. Por eso se vuelve al mapeo
# original: cambiar de caso no evita el residuo, así que no hay razón para
# divergir de sim_l1_tri.tcl. La comprobación de TLAST limpia se consigue
# reordenando las comprobaciones en tb_l1_ddc_range_tri.sv (TLAST antes que
# dato), no eligiendo casos.
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
  set opt(outdir) [file join $repo_root build sim xsim $opt(platform) range_tri__$opt(mode)]
}
file mkdir $opt(outdir)

set mode_arg [expr {$opt(mode) eq "coarse" ? 1 : 0}]

# --- manifiestos, uno por canal ---------------------------------------------
array set vectors_dir {}
array set n_stimulus {}
array set n_expected {}
array set settling {}

proc manifest_get {json key} {
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

# Hallazgo de la primera corrida real: el ping-pong de drx_range_gate no
# entrega un rayo hasta llenarlo entero. Si `n_expected` (315/157, heredado
# de un manifiesto pensado para muestra suelta, no para rayo) no es múltiplo
# exacto del tamaño de rayo de ESTE testbench, el resto sobrante se queda
# escrito en el banco para siempre — no llega ninguna muestra más que lo
# complete — y el checker esperaría una cuenta que nunca se puede alcanzar:
# `wait(all_channels_done)` no vuelve nunca y lo único que para la simulación
# es el timeout de 4 000 000 de ciclos, a la velocidad medida de esta IP real
# en xsim (~15 ciclos/s) son >70 horas, no un cuelgue de verdad. Se trunca
# aquí al múltiplo de rayo completo más cercano — MISMOS L1TestBinsFine/
# L1TestBinsCoarse que sim/tb_sv/tb_l1_ddc_range_tri.sv; si cambian ahí,
# cambian aquí.
set l1_test_bins [expr {$opt(mode) eq "coarse" ? 16 : 32}]
for {set ch 0} {$ch < 3} {incr ch} {
  set n_expected($ch) [expr {($n_expected($ch) / $l1_test_bins) * $l1_test_bins}]
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
  [file join $repo_root sim tb_sv tb_l1_ddc_range_tri.sv]]

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
    error "rtl/generated/drx_ddc_ip_pkg.sv sigue siendo el valor de arranque; corre tcl/gen_ip.tcl antes de sim_l1_range_tri.tcl"
  }
}

# --- elaboración y ejecución -------------------------------------------------
cd $opt(outdir)

set part [::drx::get PART $opt(platform)]
create_project sim_l1_range_tri -part $part -force

set xci_files [glob -nocomplain [file join $repo_root ip * *.xci]]
if {[llength $xci_files]} {
  read_ip $xci_files
  generate_target {simulation instantiation_template} [get_ips]
}

add_files -norecurse -fileset [current_fileset -simset] [concat $rtl_sources $tb_sources]
set_property top tb_l1_ddc_range_tri [current_fileset -simset]

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

set testplusarg_opts {}
foreach pa $plusargs { lappend testplusarg_opts "-testplusarg" $pa }

set_property -name {xsim.simulate.xsim.more_options} \
             -value [join $testplusarg_opts " "] -objects [current_fileset -simset]

launch_simulation
run all

puts "L1 range-tri $opt(platform)/$opt(mode) (Config A/B, N_CH=3, con range gating): terminado (canales: $case_by_channel). Log en $opt(outdir)"
