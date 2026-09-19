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
# Ejecutado de verdad y en verde muchas veces desde el 5-sep-2026 (A7
# resuelto) — la nota de fase que decía "escrito pero no ejecutado" ya no
# aplica, se deja este párrafo solo para que no reaparezca la duda.
#
# CUIDADO con la caché de `launch_simulation` (19-sep-2026, ver P-09 en
# pendientes.md): si cambias un parámetro de un testbench (p. ej.
# `TOLERANCE_LSB` en `drx_l1_checker.sv`) o `config/params.toml`, xelab puede
# decidir que "no hay nada que recompilar" y reutilizar en silencio el
# kernel viejo del directorio `build/sim/xsim/<platform>/<case>/` de una
# corrida anterior — sin ningún aviso más allá de que `elaborate.log` no
# muestra el parámetro nuevo en el nombre del módulo compilado
# (`drx_l1_checker` a secas en vez de `drx_l1_checker(TOLERANCE_LSB=5)`, por
# ejemplo). Si el resultado de una corrida no cuadra con lo esperado tras un
# cambio así, borra el directorio de ese caso en `build/sim/xsim/` antes de
# desconfiar del diseño.

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

# `rtl/generated/drx_ddc_ip_pkg.sv` ya viene en rtl/filelist.f (como
# drx_params_pkg.sv). Antes de que exista `drx_ddc_top.sv` de verdad lleva un
# valor de arranque que escribe tools/gen_params.py; en cuanto corre
# tcl/gen_ip.tcl contra la IP real, ese script lo sustituye por los anchos
# reales de TDATA — comprobar que no siga siendo el de arranque cuando
# have_ddc es cierto es justo lo que hace este aviso.
set have_ddc 0
foreach src $rtl_sources {
  if {[file tail $src] eq "drx_ddc_top.sv"} { set have_ddc 1 }
}
if {$have_ddc} {
  set ip_pkg [file join $repo_root rtl generated drx_ddc_ip_pkg.sv]
  if {[string match "*VALOR DE ARRANQUE*" [read [set fh [open $ip_pkg r]]]]} {
    close $fh
    error "rtl/generated/drx_ddc_ip_pkg.sv sigue siendo el valor de arranque; corre tcl/gen_ip.tcl antes de sim_l1.tcl"
  }
  close $fh
}

# --- elaboración y ejecución ------------------------------------------------
cd $opt(outdir)

set part [::drx::get PART $opt(platform)]
# Proyecto en disco, no -in_memory: launch_simulation necesita la estructura de
# ficheros del proyecto (xsim.compile/elaborate/simulate escriben ahí) y falla
# con «No open project» sobre un proyecto en memoria. Vive dentro de
# $opt(outdir), que ya es directorio de build, así que sigue sin dejar estado
# fuera de build/ (D-07).
create_project sim_l1 -part $part -force

# La IP se lee de los XCI versionados, igual que en tcl/build.tcl: una sola
# fuente de verdad para los cores, y simulación contra exactamente lo que se
# sintetiza. Sin XCI —el caso de Z0— el testbench no tiene DUT y falla solo.
# HALLAZGO, primera ejecución real: `create_ip -dir` crea un subdirectorio
# por core (`ip/<module_name>/<module_name>.xci`) — es el comportamiento
# normal de Vivado, confirmado generando IP de verdad con tcl/gen_ip.tcl.
# `ip/*.xci` (sin el subdirectorio) nunca encontraba nada; no se notó antes
# porque en Z0 `ip/` estaba vacío y daba lo mismo. El mismo fallo está en
# tcl/build.tcl y tcl/ip.tcl.
set xci_files [glob -nocomplain [file join $repo_root ip * *.xci]]
if {[llength $xci_files]} {
  read_ip $xci_files
  generate_target {simulation instantiation_template} [get_ips]
}

# HALLAZGO, primera ejecución real: `read_verilog` (pensado para el flujo
# no-project de tcl/build.tcl) no deja los ficheros donde `launch_simulation`
# los busca en un proyecto EN DISCO como este — el compilador de xvlog solo
# veía tb_l1_ddc.sv y drx_params_pkg.sv (lo único que la rama `` `else `` de
# antes necesitaba) y nunca llegaba a `drx_ddc_top.sv` ni a sus dependencias.
# `add_files` contra el fileset de simulación es la forma correcta en modo
# proyecto.
add_files -norecurse -fileset [current_fileset -simset] [concat $rtl_sources $tb_sources]

set_property top tb_l1_ddc [current_fileset -simset]

# `have_ddc` ya se calculó arriba, antes de leer las fuentes, para poder
# anteponer drx_ddc_ip_pkg.sv cuando hiciera falta.
#
# El define solo se pone si el DUT existe. Sin él el testbench aborta con un
# mensaje que dice qué falta; con él puesto sobre un DUT inexistente el fallo
# sería un «module not found» de xelab, que dice mucho menos.
# La escala de tiempo se fija aquí y no en el testbench: declararla solo en un
# módulo y no en el RTL mezcla escalas, y el periodo del reloj sale de FS_HZ en
# picosegundos.
#
# HALLAZGO, primera ejecución real contra IP de verdad — dos capas del mismo
# problema, no una:
#
# 1. `` `ifdef `` es una directiva de PREPROCESADOR, y en el flujo de dos
#    pasos de xsim se resuelve en xvlog (compilación), no en xelab
#    (elaboración). Poner `-d` solo en `xsim.elaborate.xelab.more_options`
#    (como estaba) define la macro demasiado tarde para el propio xvlog.
# 2. Aun pasando `-d` a xvlog vía `xsim.compile.xvlog.more_options`, launch_
#    simulation hace ANTES su propio barrido de qué ficheros hacen falta
#    («Fetching design files»), y ese barrido usa `verilog_define` del
#    fileset — no las `more_options` del binario — para decidir qué rama de
#    un `` `ifdef `` es la real. Sin ponerlo ahí, el barrido decide que
#    `drx_ddc_top.sv` no hace falta (ve la rama `` `else ``) y ni siquiera lo
#    pasa a xvlog, así que el error visible es «xelab: module not found» en
#    vez de un error de compilación — engañoso, porque parece que falta el
#    módulo cuando en realidad falta pasarlo a compilar.
#
# Las tres propiedades tienen que decir lo mismo para que no se repita esto.
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

set plusargs [list \
  "stimulus_path=[file join $opt(vectors) stimulus.hex]" \
  "stimulus_count=$n_stimulus" \
  "expected_i_path=[file join $opt(vectors) expected_i.hex]" \
  "expected_q_path=[file join $opt(vectors) expected_q.hex]" \
  "expected_count=$n_expected" \
  "settling=$settling" \
  "mode=$mode_arg"]

# xsim exige el flag -testplusarg delante de cada uno; pasarlos como tokens
# +clave=valor sueltos rompe su parser de opciones posicionales a partir del
# séptimo (xsim --help documenta -testplusarg para esto).
set testplusarg_opts {}
foreach pa $plusargs { lappend testplusarg_opts "-testplusarg" $pa }

set_property -name {xsim.simulate.xsim.more_options} \
             -value [join $testplusarg_opts " "] -objects [current_fileset -simset]

launch_simulation
run all

puts "L1 $opt(platform)/$opt(case): terminado. Log en $opt(outdir)"
