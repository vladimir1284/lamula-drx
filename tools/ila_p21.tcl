# Arma el ILA de P-21 y espera el disparo. Ver docs/implementacion/ila.md.
#
#   vivado -mode batch -source tools/ila_p21.tcl -tclargs \
#          -ltx build/gw/zedboard_zynq_dbg/drx_zynq_top.ltx \
#          -out build/soak/ila-p21.csv [-timeout 600]
#
# Scriptado y no por GUI a propósito: el armado tiene tres decisiones no
# obvias (condición de disparo, condición de almacenamiento y posición del
# disparo) y hacerlas a mano en un diálogo no deja constancia de cuáles
# fueron. Aquí se leen con la captura.
#
# PRECONDICIÓN: `xsct` CERRADO. Los dos hablan con el mismo `hw_server`, y el
# ILA se lee sin parar el Cortex-A9 solo si nadie más tiene cogido el DAP --
# justamente el efecto que ya contaminó las lecturas de `MM2S_DMASR` (ver
# fases.md, 2-oct-2026).
#
# La placa tiene que estar YA cargada y corriendo con el bitstream de
# depuración; este script no programa nada.

array set opt {ltx {} out {} timeout 600 url localhost:3121 trigger flanco}
for {set i 0} {$i < [llength $argv]} {incr i} {
  set flag [string trimleft [lindex $argv $i] -]
  if {[info exists opt($flag)]} {
    incr i
    set opt($flag) [lindex $argv $i]
  } else {
    error "argumento desconocido: [lindex $argv $i]"
  }
}
foreach k {ltx out} {
  if {$opt($k) eq {}} { error "falta -$k" }
}
if {![file exists $opt(ltx)]} {
  error "no existe $opt(ltx): ¿build sin -debug 1?"
}
file mkdir [file dirname $opt(out)]

open_hw_manager
connect_hw_server -url $opt(url)
open_hw_target

set dev [lindex [get_hw_devices xc7z020*] 0]
current_hw_device $dev
set_property PROBES.FILE      $opt(ltx) $dev
set_property FULL_PROBES.FILE $opt(ltx) $dev
# Refresca SIN reprogramar: el bitstream y el firmware ya están corriendo.
# Sin `-update_hw_probes false`: ese flag le dice a Vivado que NO lea la
# información de probes, y entonces `get_hw_probes` devuelve vacío y el
# armado por nombre falla.
refresh_hw_device $dev

set ila [lindex [get_hw_ilas -of_objects $dev] 0]
if {$ila eq {}} {
  error "el dispositivo no expone ningún ILA: el bitstream cargado no es el de -debug 1"
}
puts "ILA: $ila"
puts "probes: [get_hw_probes -of_objects $ila]"

# --- armado -----------------------------------------------------------------
#
# Disparo: flanco de subida de `stalled`, el bit más significativo de probe2
# (orden de `drx_debug_pkg`: ddr_mode, timing_enable, timing_paced, moved,
# pulse_trig, stalled -> en la cadena de Vivado, MSB primero, `stalled` es el
# primer carácter).
#
# Almacenamiento: solo los ciclos en que un conjunto de muestras AVANZÓ
# (`moved`, tercer carácter). Es lo que hace útil la captura -- con
# almacenamiento continuo las 4096 muestras (65 µs) caerían enteras dentro del
# silencio que sigue a la parada, porque el umbral de `stalled` son 67 ms. Con
# esta calificación, las 4096 muestras son el último avance de muestra por
# avance de muestra antes de la parada: ~16 k ciclos de reloj, una pasada
# entera del vector.
#
# Y la muestra del disparo se guarda SIEMPRE, avance o no. Esa sola muestra ya
# contesta la pregunta de P-21: enseña el estado congelado de los once probes
# en el instante en que la cadena lleva 67 ms sin moverse.
#
# Condición AND en los dos casos: un probe con todos los bits a "no importa"
# evalúa a verdadero y no estorba en un AND -- en un OR forzaría a capturar
# siempre.
# CONTROL.TRIGGER_MODE no se toca: es de solo lectura, y con
# C_ADV_TRIGGER=false ya vale BASIC_ONLY.
set_property CONTROL.TRIGGER_POSITION  4095  $ila
set_property CONTROL.TRIGGER_CONDITION AND   $ila
set_property CONTROL.CAPTURE_MODE      BASIC $ila
set_property CONTROL.CAPTURE_CONDITION AND   $ila

# `-trigger flanco` (por defecto) dispara con la SUBIDA de `stalled`: es lo
# que hay que usar con la placa sana, porque deja todo el buffer de
# almacenamiento calificado por delante del atasco.
#
# `-trigger nivel` dispara con `stalled` ya alto. Hace falta cuando la cadena
# YA esta parada al armar -- entonces no hay flanco que esperar y el disparo
# por flanco no llegaria nunca. Se pierde la historia previa, pero la muestra
# del disparo sigue enseñando el estado congelado de los once probes, que es
# lo que contesta "quien tiene valid alto y ready bajo".
set p2 [get_hw_probes *dbg_ctrl* -of_objects $ila]
#
# `-trigger ya` no espera nada: dispara en el acto y guarda 4096 ciclos
# consecutivos del estado actual, sin calificar. Es una foto, no una
# investigación -- sirve para leer de una vez quién tiene `valid` alto y
# `ready` bajo AHORA MISMO, sin saber todavía si hay atasco.
if {$opt(trigger) eq "nivel"} {
  set_property TRIGGER_COMPARE_VALUE eq6'b1XXXXX $p2
  set_property CAPTURE_COMPARE_VALUE eq6'bXX1XXX $p2
} elseif {$opt(trigger) eq "flanco"} {
  set_property TRIGGER_COMPARE_VALUE eq6'bRXXXXX $p2
  set_property CAPTURE_COMPARE_VALUE eq6'bXX1XXX $p2
} elseif {$opt(trigger) eq "ya"} {
  set_property CONTROL.TRIGGER_POSITION 0 $ila
  set_property CONTROL.CAPTURE_MODE ALWAYS $ila
  set_property TRIGGER_COMPARE_VALUE eq6'bXXXXXX $p2
} else {
  error "-trigger desconocido: $opt(trigger) (flanco | nivel | ya)"
}

puts "armado; esperando disparo (hasta $opt(timeout) s)"
run_hw_ila $ila
wait_on_hw_ila -timeout [expr {$opt(timeout) / 60.0}] $ila

# `wait_on_hw_ila` vuelve igual si disparó que si se le acabó el tiempo. La
# diferencia está en CORE_STATUS, y hay que mirarla: subir una captura sin
# disparo daría 4096 muestras del estado sano y una conclusión al revés.
# El nombre de la propiedad de estado cambia entre versiones de Vivado, y
# `get_property` sobre una que no existe aborta el script.
set estado "desconocido"
foreach prop {STATUS.CORE_STATUS CORE_STATUS CAPTURE_STATUS} {
  if {![catch {set v [get_property $prop $ila]}]} {
    set estado $v
    puts "$prop = $v"
    break
  }
}
if {$estado eq "desconocido"} {
  puts "no encuentro la propiedad de estado; propiedades del ILA:"
  report_property $ila
}
if {[string match -nocase "*full*" $estado] == 0} {
  puts "AVISO: el ILA no llegó a llenarse (sin disparo en $opt(timeout) s)."
  puts "       La cadena no se atascó, o el umbral de `stalled` no se alcanzó."
}

set data [upload_hw_ila_data $ila]
write_hw_ila_data -csv_file -force $opt(out) $data

puts "captura escrita en $opt(out)"
close_hw_manager
