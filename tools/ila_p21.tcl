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

array set opt {ltx {} out {} timeout 600 url localhost:3121}
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
refresh_hw_device -update_hw_probes false $dev

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
set_property CONTROL.TRIGGER_POSITION  4095  $ila
set_property CONTROL.TRIGGER_MODE      BASIC_ONLY $ila
set_property CONTROL.TRIGGER_CONDITION AND   $ila
set_property CONTROL.CAPTURE_MODE      BASIC $ila
set_property CONTROL.CAPTURE_CONDITION AND   $ila

set p2 [get_hw_probes *dbg_ctrl* -of_objects $ila]
set_property TRIGGER_COMPARE_VALUE eq6'bR_____ $p2
set_property CAPTURE_COMPARE_VALUE eq6'b__1___ $p2

puts "armado; esperando disparo (hasta $opt(timeout) s)"
run_hw_ila $ila
wait_on_hw_ila -timeout [expr {$opt(timeout) / 60.0}] $ila

# `wait_on_hw_ila` vuelve igual si disparó que si se le acabó el tiempo. La
# diferencia está en CORE_STATUS, y hay que mirarla: subir una captura sin
# disparo daría 4096 muestras del estado sano y una conclusión al revés.
set estado [get_property CORE_STATUS $ila]
puts "CORE_STATUS = $estado"
if {[string match "*Full*" $estado] == 0} {
  puts "AVISO: el ILA no llegó a llenarse (sin disparo en $opt(timeout) s)."
  puts "       La cadena no se atascó, o el umbral de `stalled` no se alcanzó."
}

set data [upload_hw_ila_data $ila]
write_hw_ila_data -csv_file -force $opt(out) $data

puts "captura escrita en $opt(out)"
close_hw_manager
