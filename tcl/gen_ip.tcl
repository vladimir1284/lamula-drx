# Crea la IP de Xilinx del DDC de un canal (Z1) como XCI versionados en `ip/`.
#
# Complementa a `tcl/ip.tcl`, que solo REGENERA productos de XCI ya existentes.
# Este script los CREA la primera vez, uno por tipo de core (no uno por rama
# I/Q: `rtl/drx_ddc_top.sv` instancia el MISMO module_name dos veces, una por
# rama, así que basta con un XCI por tipo):
#
#   dds_compiler_nco       DDS Compiler, generador de fase libre, cos+sin
#   cic_compiler_ddc       CIC Compiler, N/R/M de config/params.toml
#   fir_compiler_droop     FIR Compiler, compensador de droop + ÷4
#   fir_compiler_halfband  FIR Compiler, semibanda ÷2 del modo grueso
#
# Los coeficientes se leen de config/coeffs/*.txt — la misma fuente que usa el
# modelo dorado — para que no haya un tercer sitio con los mismos números.
#
#   vivado -mode batch -source tcl/gen_ip.tcl -tclargs -platform zedboard
#
# Los nombres de propiedad `CONFIG.*` de este script están confirmados contra
# el catálogo de IP real de Vivado 2022.2 (no de la documentación a ciegas):
# hay inconsistencias reales entre cores que solo se ven generando IP de
# verdad — `Has_ARESETn` (FIR/DDS) frente a `HAS_ARESETN` (CIC, todo
# mayúsculas), `CoefficientVector` sin guion bajo, y el "ancho de precisión
# completa" que cada core reporta NO es la fórmula de crecimiento de Hogenauer
# ni `ceil(log2(taps))` a mano: depende de si el core detecta la estructura de
# coeficientes como simétrica (la semibanda lo es; el droop no) y de a qué
# múltiplo de 8 bits redondea el bus de salida. Por eso este script no intenta
# adivinar esos anchos: los LEE del `.veo` que genera la propia IP tras
# configurarla, y los deja en `rtl/generated/drx_ddc_ip_pkg.sv` para que
# `rtl/drx_ddc_top.sv` los consuma en vez de recalcularlos.

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
set ip_dir [file join $repo_root ip]
file mkdir $ip_dir

# HALLAZGO (2-oct-2026, Z4.5): `create_ip -module_name X` con `ip/X/` ya
# presente NO reconfigura esa IP -- crea `ip/X_1/` en silencio y sigue, así que
# el `.veo` que lee la parte de abajo de este script sería el VIEJO y el XCI
# versionado se quedaría como estaba. Este script se había corrido una sola vez
# (Z1) y nadie lo había vuelto a ejecutar hasta Z4.5, que es la primera vez que
# hace falta CAMBIAR la personalización de un core ya creado.
#
# `ensure_ip` lo hace idempotente sin borrar nada: si el XCI ya existe lo abre
# con `read_ip` y los `set_property` de abajo lo reescriben en su sitio; si no
# existe, lo crea como la primera vez. En los dos casos el objeto que devuelve
# `get_ips` es el mismo y el resto del script no cambia.
proc ensure_ip {core_name version module_name} {
  set xci [file join $::ip_dir $module_name $module_name.xci]
  if {[file exists $xci]} {
    read_ip $xci
  } else {
    create_ip -name $core_name -vendor xilinx.com -library ip -version $version \
        -module_name $module_name -dir $::ip_dir
  }
}

create_project -in_memory -part $part

# --- coeficientes: una sola fuente, config/coeffs/*.txt ---------------------
# Formato de tools/gen_coeffs.py: un entero por línea, comentarios `#` sueltos
# o al final de línea, líneas en blanco permitidas.
proc read_coeffs {path} {
  set values {}
  set fh [open $path r]
  foreach line [split [read $fh] "\n"] {
    set value [string trim [lindex [split $line "#"] 0]]
    if {$value eq {}} { continue }
    lappend values $value
  }
  close $fh
  return $values
}

set droop_coeffs    [read_coeffs [file join $repo_root config coeffs droop_decim_fir.txt]]
set halfband_coeffs [read_coeffs [file join $repo_root config coeffs halfband_decim2.txt]]

if {[llength $droop_coeffs] != $::drx::FIR_TAPS} {
  error "droop_decim_fir.txt tiene [llength $droop_coeffs] coeficientes, se esperaban $::drx::FIR_TAPS"
}

# CoefficientVector: lista separada por comas, SIN llaves — así es como la
# devuelve get_property por defecto, y así es como hay que dársela de vuelta.
set droop_coeff_str    [join $droop_coeffs ,]
set halfband_coeff_str [join $halfband_coeffs ,]

# --- entero a cadena binaria de N bits, para PINC1 del DDS Compiler ---------
proc to_binary {value bits} {
  set result {}
  for {set i [expr {$bits - 1}]} {$i >= 0} {incr i -1} {
    append result [expr {($value >> $i) & 1}]
  }
  return $result
}

# --- ancho real de un puerto, leído del .veo que genera la propia IP -------
# La única fuente fiable: ni "Output_Width" ni una fórmula de taps/coeficiente
# predicen el ancho real (ver el aviso de cabecera). Se parsea la plantilla de
# instanciación, que es exactamente el texto que va a usar quien instancie el
# core a mano — y que aquí generamos automáticamente en su lugar.
proc veo_port_width {veo_path port_name} {
  set fh [open $veo_path r]
  set text [read $fh]
  close $fh
  if {[regexp "// \\w+ wire \\\[(\\d+) : (\\d+)\\\] ${port_name}\[^\\w\]" $text -> hi lo]} {
    return [expr {$hi - $lo + 1}]
  }
  if {[regexp "// \\w+ wire ${port_name}\[^\\w\]" $text]} {
    return 1
  }
  error "no se encontró el puerto '$port_name' en $veo_path"
}

# --- DDS Compiler: NCO en modo generador de fase libre ----------------------
#
# HALLAZGO, primera ejecución real contra IP de verdad: la primera
# `nco_cos`/`nco_sin` válida tras `aresetn` no cae en el índice de fase 0 de
# la LUT que usa `model/drx_model/nco.py` — cae en el índice 656, un desfase
# FIJO y reproducible (se comprobó por simulación, con y sin `Has_TREADY`,
# el valor no cambia: no es la FIFO de contrapresión, es intrínseco al
# arranque del propio Phase Generator y `tcl/gen_ip.tcl` no logró explicarlo
# con una cuenta cerrada de ciclos · PINC — hasta donde se pudo determinar
# sin la documentación interna del core, del lado de fuera de la IP no hay
# forma de derivarlo por fórmula). Medido: la muestra corresponde a
# LUT[656] = (32702, 2059) contra la LUT del propio modelo (`Nco.lut()`,
# búsqueda inversa exacta — no una constante inventada).
#
# NCO_POFF cancela ese desfase en el propio Phase Generator en vez de
# arrastrarlo hasta el mezclador: solo hace falta corregir la mitad alta del
# acumulador de 32 bits (la que sobrevive al truncamiento de fase a
# NCO_PHASE_BITS-16 bits antes de indexar la LUT), así que los 16 bits bajos
# quedan en 0 y el resultado es exacto sea cual sea el valor real —
# desconocido— de los 16 bits bajos del acumulador en ese instante.
#
# Si algún día cambia la versión de la IP, `Has_TREADY`, `Latency` o
# cualquier otro parámetro que toque el arranque del Phase Generator, este
# desfase puede cambiar y hay que volver a medirlo — `tcl/sim_l1.tcl` lo
# detectaría de inmediato como una discrepancia bit a bit, no hace falta un
# test aparte para este número.
# HALLAZGO #2: la primera vuelta con `POFF1 = (65536-K)<<16` (asumiendo que
# el core SUMA el offset al acumulador) dejó el error de fase PEOR, casi el
# doble (Q pasó de -272 a -543 en régimen permanente) — evidencia directa de
# que el core RESTA el offset del acumulador, no lo suma. Con el signo
# corregido (`POFF1 = +K<<16`) el mismo desfase medido cancela exactamente.
# CORRECCIÓN, 8-sep-2026 (P-10): 656 (arriba) se calibró con UNA sola muestra
# reconstruida a mano (LUT[656]) — suficiente para fijar el orden de magnitud
# del desfase de arranque, pero sin margen para detectar un error de UNA
# posición de LUT sobre esa única muestra. Instrumentando 4096 muestras
# crudas de `nco_cos`/`nco_sin` (sonda temporal en `tb_l1_ddc.sv`, no
# comiteada) y ajustando el error contra `sin`/`cos` del modelo salió una
# firma de error de ángulo sistemática (mismo signo y orden de magnitud en I
# y en Q, R²~0.8), equivalente a un paso de LUT de menos. Confirmado
# empíricamente contra xsim real en las dos direcciones — `K=657` empeora
# (el desfase residual crece), `K=655` lo corrige: cae de ±5 LSB a ±2 LSB en
# la salida cruda del NCO, y en el caso degenerado `tono_if__fine` el canal Q
# en régimen permanente pasa de +3 LSB de sesgo a 0 exacto (`I` mantiene un
# residuo de -2, mismo orden que el suelo de cuantización ya caracterizado).
# Detalle completo, con los números, en docs/alcance/pendientes.md (P-10).
#
# NO CAMBIA con Taylor (ver abajo): recalibrado el 9-sep-2026 con
# `Noise_Shaping {Taylor_Series_Corrected}` activo, el mejor K sigue siendo
# 655 (medido como 64881 ≡ -655 mod 65536, mismo signo que ya documenta el
# hallazgo #2 de arriba) para los dos anchos de salida probados. Detalle en
# docs/alcance/pendientes.md (P-11).
set NCO_LUT_OFFSET_K 655
set NCO_POFF [expr {($NCO_LUT_OFFSET_K % 65536) << 16}]

ensure_ip dds_compiler 6.0 dds_compiler_nco

# HALLAZGO, primera ejecución real contra IP de verdad: con `Has_TREADY
# {true}` (el valor de esta pasada hasta ahora), pg141 (v6.0), "Latency
# Options", dice explícitamente: "When TREADY is selected the AXI interfaces
# buffer data as a FIFO. This buffering results in NON-DETERMINISTIC latency."
# Eso es justo lo que se midió por simulación: la primera `nco_cos`/`nco_sin`
# válida tras reset no correspondía a fase 0, y el sesgo no se pudo explicar
# con ninguna cuenta cerrada de ciclos — porque no lo es, es el estado de
# llenado de un FIFO interno que Xilinx documenta como no determinista.
#
# No hace falta esa FIFO: `drx_ddc_mixer` nunca contrapresura al NCO (su
# `nco_ready` va atado a 1'b1 sin condición, ver el hallazgo de cabecera de
# ese fichero), así que pedir `Has_TREADY` aquí solo compra latencia no
# determinista sin beneficio. Con `Has_TREADY {false}` el core queda con
# latencia FIJA (`Latency`, ver XCI) y sin FIFO de por medio, así que la
# primera muestra válida tras `aresetn` corresponde de verdad a fase 0 — el
# mezclador ya no necesita autocalibrarse contra un sesgo de arranque.
#
# `Noise_Shaping {Taylor_Series_Corrected}` (D-11, 18-sep-2026): modo
# principal del NCO desde esta decisión, en vez de `{None}` (el valor de
# fábrica que documentaba P-10 hasta ahora). Sube `Latency` de 8 a 9 ciclos
# -- no hace falta fijarlo aparte, lo decide el propio core -- y reduce el
# residuo de cuantización medido de ~5,7 a ~1,15 LSB rms (P-11) sin mover
# `NCO_LUT_OFFSET_K` (ver el comentario de arriba). Coste: +3 DSP48 / +1
# RAMB18 (0,5 tile) por canal, ya dentro del presupuesto de 3 canales de
# ZedBoard (P-12).
# `Phase_Increment {Programmable}` (Z4.5, 2-oct-2026), en vez del `{Fixed}` que
# tuvo este core desde Z1: la actuación AFC necesita reescribir la palabra de
# fase en tiempo de ejecución y con `{Fixed}` el incremento queda congelado en
# la personalización de la IP -- no hay ningún puerto por el que cambiarlo.
# Medido sobre la IP generada de verdad, no supuesto: el cambio añade
# `s_axis_config_tvalid` + `s_axis_config_tdata[31:0]` (un canal AXI4-Stream de
# configuración, sin TREADY porque `Has_TREADY {false}` sigue valiendo para
# todas las interfaces del core) y NO mueve nada más -- `Latency` sigue en 9,
# `Phase_offset` sigue `{Fixed}` con el mismo POFF1, `Noise_Shaping` igual. Por
# eso `NCO_LUT_OFFSET_K` (arriba) no se recalibra: la matriz de 16 corridas de
# D-12 es la que tiene la última palabra, y se vuelve a correr entera tras este
# cambio.
#
# PINC1 deja de ser "el" incremento y pasa a ser el VALOR INICIAL tras
# `aresetn`, hasta que alguien escriba por `s_axis_config`. Eso es lo que hace
# que el camino sin AFC siga siendo bit a bit el de siempre: `drx_ddc_top` no
# escribe ninguna configuración al arrancar, solo cuando el mapa de registros
# se lo pide.
set_property -dict [list \
  CONFIG.Parameter_Entry  {Hardware_Parameters} \
  CONFIG.Output_Selection {Sine_and_Cosine} \
  CONFIG.Amplitude_Mode   {Full_Range} \
  CONFIG.Phase_Width      $::drx::NCO_PHASE_BITS \
  CONFIG.Output_Width     $::drx::NCO_OUT_BITS \
  CONFIG.Phase_Increment  {Programmable} \
  CONFIG.PINC1            [to_binary $::drx::NCO_PHASE_INC $::drx::NCO_PHASE_BITS] \
  CONFIG.Has_Phase_Out    {false} \
  CONFIG.Has_ARESETn      {true} \
  CONFIG.Has_ACLKEN       {false} \
  CONFIG.Has_TREADY       {false} \
  CONFIG.Phase_offset     {Fixed} \
  CONFIG.POFF1            [to_binary $NCO_POFF $::drx::NCO_PHASE_BITS] \
  CONFIG.Noise_Shaping    {Taylor_Series_Corrected} \
] [get_ips dds_compiler_nco]

# --- CIC Compiler: N/R/M fijos, precisión completa a la salida --------------
# Dos propiedades gobiernan cosas DISTINTAS y las dos hay que fijarlas:
#
#   `Fixed_Or_Initial_Rate` — el factor de diezmado R (52). El nombre sugiere
#   «tasa inicial» pero es la propiedad que de verdad gobierna el hardware;
#   `SamplePeriod` NO la cambia, aunque en la GUI parezca relacionada —
#   confirmado generando la IP.
#
#   `RateSpecification`/`SamplePeriod` — CUÁNTOS CICLOS DE RELOJ hay entre
#   una muestra de entrada y la siguiente (1 = tasa completa, back-to-back,
#   que es justo lo que entrega `drx_ddc_mixer`). El valor por defecto,
#   `Frequency_Specification`, deriva ese número de `Input_Sample_Frequency`/
#   `Clock_Frequency` — dos propiedades que aquí nunca se tocan y se quedan
#   con sus valores de fábrica sin relación con el diseño real. HALLAZGO,
#   primera simulación real: dejarlo así hace que `s_axis_data_tready` se
#   quede en 0 para siempre tras aceptar un puñado de muestras — el core
#   entra en un patrón de «esperar el próximo hueco» que su propia
#   configuración de frecuencia le dice que tiene que haber, y ese hueco
#   nunca llega porque el mezclador entrega cada ciclo. `RateSpecification
#   {Sample_Period}` + `SamplePeriod {1}` se lo dice explícitamente.
ensure_ip cic_compiler 4.0 cic_compiler_ddc

set_property -dict [list \
  CONFIG.Filter_Type           {Decimation} \
  CONFIG.Fixed_Or_Initial_Rate $::drx::CIC_RATE \
  CONFIG.RateSpecification     {Sample_Period} \
  CONFIG.SamplePeriod          {1} \
  CONFIG.Number_Of_Stages      $::drx::CIC_STAGES \
  CONFIG.Differential_Delay    $::drx::CIC_DIFF_DELAY \
  CONFIG.Input_Data_Width      $::drx::SAMPLE_BITS \
  CONFIG.Quantization          {Full_Precision} \
  CONFIG.HAS_ARESETN           {true} \
  CONFIG.HAS_DOUT_TREADY       {true} \
] [get_ips cic_compiler_ddc]

# --- FIR Compiler: droop + ÷4, precisión completa a la salida ---------------
ensure_ip fir_compiler 7.2 fir_compiler_droop

set_property -dict [list \
  CONFIG.Filter_Type          {Decimation} \
  CONFIG.Decimation_Rate      $::drx::FIR_DECIM \
  CONFIG.RateSpecification    {Input_Sample_Period} \
  CONFIG.SamplePeriod         {1} \
  CONFIG.Coefficient_Width    $::drx::FIR_COEFF_BITS \
  CONFIG.CoefficientVector    $droop_coeff_str \
  CONFIG.Data_Width           $::drx::SAMPLE_BITS \
  CONFIG.Output_Rounding_Mode {Full_Precision} \
  CONFIG.Quantization         {Integer_Coefficients} \
  CONFIG.Has_ARESETn          {true} \
  CONFIG.M_DATA_Has_TREADY    {true} \
] [get_ips fir_compiler_droop]

# --- FIR Compiler: semibanda ÷2 del modo grueso -----------------------------
# El ancho de entrada real es el que declara rtl/drx_ddc_top.sv para
# `fir_rounded` (el redondeo tras el FIR de droop) — se pasa por variable, no
# a mano, para que los dos ficheros no puedan divergir.
set halfband_in_width [expr {$::drx::SAMPLE_BITS + $::drx::FIR_COEFF_BITS + \
    int(ceil(log($::drx::FIR_TAPS) / log(2))) - $::drx::FIR_GROWTH_BITS}]

ensure_ip fir_compiler 7.2 fir_compiler_halfband

set_property -dict [list \
  CONFIG.Filter_Type          {Decimation} \
  CONFIG.Decimation_Rate      $::drx::COARSE_EXTRA_DECIM \
  CONFIG.RateSpecification    {Input_Sample_Period} \
  CONFIG.SamplePeriod         {1} \
  CONFIG.Coefficient_Width    $::drx::HALFBAND_COEFF_BITS \
  CONFIG.CoefficientVector    $halfband_coeff_str \
  CONFIG.Data_Width           $halfband_in_width \
  CONFIG.Output_Rounding_Mode {Full_Precision} \
  CONFIG.Quantization         {Integer_Coefficients} \
  CONFIG.Has_ARESETn          {true} \
  CONFIG.M_DATA_Has_TREADY    {true} \
] [get_ips fir_compiler_halfband]

# --- generar y leer los anchos reales ---------------------------------------
foreach ip [get_ips] {
  generate_target {instantiation_template} [get_ips $ip]
}

set dds_veo      [file join $ip_dir dds_compiler_nco dds_compiler_nco.veo]
set cic_veo      [file join $ip_dir cic_compiler_ddc cic_compiler_ddc.veo]
set droop_veo    [file join $ip_dir fir_compiler_droop fir_compiler_droop.veo]
set halfband_veo [file join $ip_dir fir_compiler_halfband fir_compiler_halfband.veo]

set dds_w      [veo_port_width $dds_veo m_axis_data_tdata]
set dds_cfg_w  [veo_port_width $dds_veo s_axis_config_tdata]
set cic_in_w   [veo_port_width $cic_veo s_axis_data_tdata]
set cic_w      [veo_port_width $cic_veo m_axis_data_tdata]
set droop_in_w [veo_port_width $droop_veo s_axis_data_tdata]
set droop_w    [veo_port_width $droop_veo m_axis_data_tdata]
set hb_in_w    [veo_port_width $halfband_veo s_axis_data_tdata]
set hb_w       [veo_port_width $halfband_veo m_axis_data_tdata]

puts "anchos reales de TDATA (leídos de la IP generada):"
puts "  DDS m_axis (cos+sin empaquetados)      : $dds_w bits"
puts "  DDS s_axis_config (PINC programable)   : $dds_cfg_w bits"
puts "  CIC s_axis / m_axis                    : $cic_in_w / $cic_w bits (precisión: $::drx::CIC_REGISTER_BITS)"
puts "  FIR droop s_axis / m_axis               : $droop_in_w / $droop_w bits"
puts "  FIR semibanda s_axis / m_axis           : $hb_in_w / $hb_w bits"

set pkg_path [file join $repo_root rtl generated drx_ddc_ip_pkg.sv]
set fh [open $pkg_path w]
puts $fh "// GENERADO por tcl/gen_ip.tcl a partir de la IP real generada en ip/*.xci. NO EDITAR A MANO."
puts $fh "//"
puts $fh "// Anchos de TDATA que de verdad produce cada core una vez configurado — no"
puts $fh "// una fórmula de taps/coeficientes: el crecimiento interno de un FIR Compiler"
puts $fh "// depende de si detecta la estructura de coeficientes como simétrica, y el"
puts $fh "// bus se redondea a un múltiplo de 8 bits. rtl/drx_ddc_top.sv consume estos"
puts $fh "// valores en vez de recalcularlos."
puts $fh ""
puts $fh "`ifndef DRX_DDC_IP_PKG_SV"
puts $fh "`define DRX_DDC_IP_PKG_SV"
puts $fh ""
puts $fh "package drx_ddc_ip_pkg;"
puts $fh ""
puts $fh "  localparam int DDS_TDATA_BITS = $dds_w;"
puts $fh "  localparam int DDS_CONFIG_TDATA_BITS = $dds_cfg_w;"
puts $fh "  localparam int CIC_IN_BITS = $cic_in_w;"
puts $fh "  localparam int CIC_TDATA_BITS = $cic_w;"
puts $fh "  localparam int FIR_DROOP_IN_BITS = $droop_in_w;"
puts $fh "  localparam int FIR_DROOP_TDATA_BITS = $droop_w;"
puts $fh "  localparam int FIR_HALFBAND_IN_BITS = $hb_in_w;"
puts $fh "  localparam int FIR_HALFBAND_TDATA_BITS = $hb_w;"
puts $fh ""
puts $fh "endpackage : drx_ddc_ip_pkg"
puts $fh ""
puts $fh "`endif  // DRX_DDC_IP_PKG_SV"
close $fh
puts "escrito $pkg_path"

puts "IP creada en $ip_dir:"
foreach ip [get_ips] {
  puts "  $ip"
}
