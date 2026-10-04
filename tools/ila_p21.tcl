# Arma el ILA de P-21 y espera el disparo. Ver docs/implementacion/ila.md.
#
# Una sola captura:
#
#   vivado -mode batch -source tools/ila_p21.tcl -tclargs \
#          -ltx build/gw/zedboard_zynq_dbg/drx_zynq_top.ltx \
#          -out build/soak/ila-p21.csv [-timeout 600]
#
# Vigilancia larga, desatendida (una captura por disparo, re-armando):
#
#   vivado -mode batch -source tools/ila_p21.tcl -tclargs \
#          -ltx build/gw/zedboard_zynq_dbg/drx_zynq_top.ltx \
#          -dir build/soak/noche-<ts> -duracion 36000 \
#          -bandera <dir>/bandera-ila -parar <dir>/parar-ila \
#          -latido <dir>/latido-ila
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
# depuración; este script no programa nada. `refresh_hw_device` NO reprograma;
# `program_hw_devices` sí, y por eso no aparece aquí ni debe aparecer nunca:
# reconfigurar la PL con el S2MM transmitiendo traba HP0 y de ahí solo se sale
# apagando y encendiendo la placa (docs/implementacion/ila.md).

array set opt {
  ltx {} out {} dir {} timeout 600 duracion 0 max_csv 40
  url localhost:3121 trigger flanco bandera {} parar {} latido {}
}
for {set i 0} {$i < [llength $argv]} {incr i} {
  set flag [string trimleft [lindex $argv $i] -]
  if {[info exists opt($flag)]} {
    incr i
    set opt($flag) [lindex $argv $i]
  } else {
    error "argumento desconocido: [lindex $argv $i]"
  }
}
if {$opt(ltx) eq {}} { error "falta -ltx" }
if {![file exists $opt(ltx)]} {
  error "no existe $opt(ltx): ¿build sin -debug 1?"
}
set en_bucle [expr {$opt(dir) ne {}}]
if {$en_bucle} {
  file mkdir $opt(dir)
  if {$opt(duracion) <= 0} { error "-dir requiere -duracion en segundos" }
} else {
  if {$opt(out) eq {}} { error "falta -out (o -dir para el modo de vigilancia)" }
  file mkdir [file dirname $opt(out)]
}

# Vivado corta cada ID de mensaje a las 100 ocurrencias. Lo que se perdería es
# precisamente `Labtools 27-1966` ("The ILA core ... triggered at <fecha>"),
# que es un registro de disparos fechado y gratuito, independiente del CSV.
foreach id {{Labtools 27-1964} {Labtools 27-1966}} {
  catch {set_msg_config -id $id -limit 100000}
}

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
# silencio que sigue a la parada, porque el umbral de `stalled` son 2**20
# ciclos = 16,78 ms a 62,5 MHz (rtl/drx_debug_probe.sv, STALL_LOG2 = 20). Con
# esta calificación, las 4096 muestras son el último avance de muestra por
# avance de muestra antes de la parada: ~16 k ciclos de reloj, una pasada
# entera del vector.
#
# Y la muestra del disparo se guarda SIEMPRE, avance o no. Esa sola muestra ya
# contesta la pregunta de P-21: enseña el estado congelado de los once probes
# en el instante en que la cadena lleva 16,78 ms sin moverse.
#
# Condición AND en los dos casos: un probe con todos los bits a "no importa"
# evalúa a verdadero y no estorba en un AND -- en un OR forzaría a capturar
# siempre.
# CONTROL.TRIGGER_MODE no se toca: es de solo lectura, y con
# C_ADV_TRIGGER=false ya vale BASIC_ONLY.
#
# Los tres modos viven en un solo proc a propósito: el camino de la bandera
# tiene que rearmar ENTERO, y hacerlo a medias es un error silencioso (ver el
# comentario del modo `ya`).
proc arma {ila p2 modo} {
  set_property CONTROL.TRIGGER_CONDITION AND $ila
  set_property CONTROL.CAPTURE_CONDITION AND $ila
  switch -- $modo {
    flanco {
      # Con la placa sana: deja todo el buffer calificado por delante del
      # atasco, que es la historia que hace falta para saber DÓNDE paró.
      set_property CONTROL.TRIGGER_POSITION  4095  $ila
      set_property CONTROL.CAPTURE_MODE      BASIC $ila
      set_property TRIGGER_COMPARE_VALUE eq6'bRXXXXX $p2
      set_property CAPTURE_COMPARE_VALUE eq6'bXX1XXX $p2
    }
    nivel {
      # Cuando la cadena YA está parada al armar: no hay flanco que esperar.
      set_property CONTROL.TRIGGER_POSITION  4095  $ila
      set_property CONTROL.CAPTURE_MODE      BASIC $ila
      set_property TRIGGER_COMPARE_VALUE eq6'b1XXXXX $p2
      set_property CAPTURE_COMPARE_VALUE eq6'bXX1XXX $p2
    }
    ya {
      # TRIGGER_POSITION 0, CAPTURE_MODE ALWAYS y la condición de
      # almacenamiento en "no importa" van JUNTOS y no son opcionales.
      # Con la calificación sobre `moved` puesta, un `-trigger_now` sobre el
      # atasco permanente dispara y NO recoge ni una muestra: `moved` vale 0
      # desde que empezó el atasco, el core nunca llega a FULL y el CSV sale
      # vacío. El modo `ya` es el único que sirve para fotografiar un estado
      # congelado, y por eso el camino de la bandera rearma con él.
      set_property CONTROL.TRIGGER_POSITION  0      $ila
      set_property CONTROL.CAPTURE_MODE      ALWAYS $ila
      set_property TRIGGER_COMPARE_VALUE eq6'bXXXXXX $p2
      set_property CAPTURE_COMPARE_VALUE eq6'bXXXXXX $p2
    }
    default { error "-trigger desconocido: $modo (flanco | nivel | ya)" }
  }
}

# El nombre de la propiedad de estado cambia entre versiones de Vivado, y
# `get_property` sobre una que no existe aborta el script.
proc estado_ila {ila} {
  foreach prop {STATUS.CORE_STATUS CORE_STATUS CAPTURE_STATUS} {
    if {![catch {set v [get_property $prop $ila]}]} { return $v }
  }
  return DESCONOCIDO
}

# Abrir y cerrar en cada vuelta: 600 vueltas no pueden dejar descriptores.
proc latido {ruta n st} {
  if {$ruta eq {}} return
  if {[catch {
    set f [open $ruta w]
    puts $f "[clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S}] iter=$n estado=$st"
    close $f
  } err]} {
    puts "aviso: no se pudo escribir el latido: $err"
  }
}

set rc 0
if {[catch {

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
  set p2 [get_hw_probes *dbg_ctrl* -of_objects $ila]

  if {!$en_bucle} {
    # --- modo de una sola captura, el de siempre ---
    arma $ila $p2 $opt(trigger)
    puts "armado; esperando disparo (hasta $opt(timeout) s)"
    run_hw_ila $ila
    catch {wait_on_hw_ila -timeout [expr {$opt(timeout) / 60.0}] $ila}
    set estado [estado_ila $ila]
    puts "CORE_STATUS = $estado"
    if {[string match -nocase "*full*" $estado] == 0} {
      puts "AVISO: el ILA no llegó a llenarse (sin disparo en $opt(timeout) s)."
      puts "       La cadena no se atascó, o el umbral de `stalled` no se alcanzó."
    }
    set data [upload_hw_ila_data $ila]
    write_hw_ila_data -csv_file -force $opt(out) $data
    puts "captura escrita en $opt(out)"
  } else {
    # --- modo de vigilancia larga ---
    set fin   [expr {[clock seconds] + $opt(duracion)}]
    set tally [open [file join $opt(dir) disparos.tsv] a]
    puts $tally "# marca\titer\testado\tmodo"
    flush $tally
    set n 0 ; set escritos 0 ; set errores 0

    while {[clock seconds] < $fin && ![file exists $opt(parar)]} {
      incr n
      arma $ila $p2 $opt(trigger)
      run_hw_ila $ila
      set forzado 0
      set st WAIT

      while {1} {
        # `wait_on_hw_ila` es la primitiva de sondeo a propósito: no está
        # verificado que `get_property` refresque el estado por su cuenta, y
        # un bucle de `after` podría leer un valor rancio toda la noche.
        # Entero (1 minuto) y no fraccionario: tampoco está verificado cómo
        # trata Vivado 2022.2 un -timeout de 0,0833 min, y un minuto de
        # latencia sobre un estado congelado permanente no cuesta nada.
        #
        # Caducar NO es un fallo, y no está verificado si vuelve limpio o con
        # error Tcl -- el `catch` cubre los dos casos. Pero si se cae el
        # enlace con `hw_server` esto también pasa por aquí, así que se cuenta
        # y se corta a los 20 seguidos.
        if {[catch {wait_on_hw_ila -timeout 1 $ila}]} {
          incr errores
        } else {
          set errores 0
        }
        set st [estado_ila $ila]
        latido $opt(latido) $n $st
        if {[string match -nocase "*full*" $st]} { set errores 0 ; break }
        if {$errores >= 20} { set st ENLACE_CAIDO ; break }
        if {!$forzado && $opt(bandera) ne {} && [file exists $opt(bandera)]} {
          # El caso que la bandera existe para cubrir: el flanco de `stalled`
          # cayó en el hueco de re-armado y ya no habrá otro -- si el
          # conductor paró, `ddr_mode` se queda en 1 y `stalled` en 1 para
          # siempre. Rearmado COMPLETO en modo `ya`, no un `-trigger_now`
          # suelto (ver el comentario del proc `arma`).
          puts "bandera vista en la iteración $n: foto forzada del estado congelado"
          catch {reset_hw_ila $ila}
          arma $ila $p2 ya
          run_hw_ila -trigger_now $ila
          set forzado 1
          continue
        }
        if {[clock seconds] >= $fin || [file exists $opt(parar)]} { set st AGOTADO ; break }
      }

      # Medido el 3-oct-2026: sin disparo, CORE_STATUS vale "WAITING FOR
      # TRIGGER" -- CON ESPACIOS. Va al nombre de un fichero, asi que se
      # normaliza. El valor crudo queda en disparos.tsv.
      set st_archivo [string map {{ } _} $st]
      set marca [clock format [clock seconds] -format {%Y%m%dT%H%M%S}]
      puts $tally "$marca\t$n\t$st\t[expr {$forzado ? {forzado} : $opt(trigger)}]"
      flush $tally
      puts "iter $n: $st"

      # `$forzado` entra aunque el estado salga AGOTADO: la foto del estado
      # congelado es la unica evidencia que queda de ese instante, y tirarla
      # por no haber visto un FULL seria perderla para siempre.
      if {$forzado || $st ni {AGOTADO ENLACE_CAIDO}} {
        # El estado va en el NOMBRE del fichero, no en un `if`. El enum de
        # CORE_STATUS solo está verificado para el caso positivo (FULL, cuatro
        # veces en los logs del 3-oct-2026); ramificar sobre lo que no está
        # verificado es exactamente como salió el AVISO falso de las 13:47
        # sobre una captura buena. 370 kB por CSV sobre 225 GB libres: no hay
        # ninguna razón para arriesgarse a tirar una captura válida.
        set data [upload_hw_ila_data $ila]
        if {$escritos < $opt(max_csv)} {
          write_hw_ila_data -csv_file -force \
            [file join $opt(dir) [format "ila-%04d-%s-%s.csv" $n $marca $st_archivo]] $data
          incr escritos
        }
        # Por barrido y no solo sobre el que se acaba de crear: si una vuelta
        # falla a mitad, el objeto huérfano se va igualmente.
        foreach d [get_hw_ila_datas] { catch {delete_hw_ila_data $d} }
      }
      if {$st eq "ENLACE_CAIDO"} break
      # El estado está congelado: re-armar no aporta ninguna captura nueva.
      if {$forzado} break
    }
    close $tally
    puts "fin del bucle: $n iteraciones, $escritos CSV escritos"
  }

} err]} {
  puts "ERROR en el ILA: $err"
  set rc 1
}
catch {close_hw_manager}
exit $rc
