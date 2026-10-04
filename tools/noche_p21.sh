#!/usr/bin/env bash
# Corrida nocturna desatendida de P-21: encadena miles de selecciones de
# estímulo con el ILA armado y deja toda la evidencia en disco.
#
#   tools/noche_p21.sh [horas]        # por defecto 10
#
# PRECONDICIÓN, y no es negociable: la placa tiene que estar RECIÉN APAGADA Y
# ENCENDIDA (SW8). Este script programa la PL una sola vez, sobre una placa
# fría, y no vuelve a tocarla en toda la noche. Reconfigurar la PL con el S2MM
# transmitiendo traba HP0 y de ahí solo se sale con otro ciclo de alimentación
# -- que es justamente lo que no habrá nadie para hacer.
#
# Condición de cierre que esto persigue (docs/alcance/pendientes.md#p-21):
# reproducir el atasco PERMANENTE con el ILA armado, o, si no vuelve a aparecer
# con el sondeo de 1 ms, cerrar por consecuencia como se hizo con P-18.
#
# Cuatro procesos, en este orden y por estas razones:
#   1. `cat` del UART -- arranca ANTES de cargar, para que el banner de
#      arranque quede en el log.
#   2. bucle del ILA -- ANTES del conductor: el hallazgo original aparecía "a
#      partir de la tercera" selección, y arrancar el estímulo con el
#      instrumento desarmado quema la ventana más probable.
#   3. vigía del UART.
#   4. conductor del estímulo.
# Se paran en orden inverso, y el ILA por fichero de parada y no por señal,
# para que llegue a su `close_hw_manager`: si Vivado se queda con el
# `hw_target` abierto, por la mañana no se puede lanzar `xsct` sin pelearse por
# el DAP.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
horas="${1:-10}"
segundos=$(( ${horas%.*} * 3600 ))
tty_ps="${DRX_TTY:-/dev/ttyACM0}"
host="${DRX_HOST:-192.168.1.10}"
ltx="$repo_root/build/gw/zedboard_zynq_dbg/drx_zynq_top.ltx"
dir="$repo_root/build/soak/noche-$(date +%Y%m%d-%H%M%S)"

vivado_bin="$(command -v vivado || true)"
hw_server_bin="/home/orlando/tools/Xilinx_Vitis/Vivado/2022.2/bin/hw_server"

abortar() { echo "ABORTA: $*" >&2; exit 1; }

[[ -n "$vivado_bin" ]]      || abortar "falta vivado en el PATH"
[[ -x "$hw_server_bin" ]]   || abortar "falta $hw_server_bin"
[[ -f "$ltx" ]]             || abortar "falta $ltx (build sin -debug 1)"
[[ -e "$tty_ps" ]]          || abortar "no existe $tty_ps (el ttyUSB0 es el JTAG)"

# --- gate 0: el firmware tiene que ser el de 1 ms -----------------------------
# Sin esto la noche no vale nada: con el tick a 100 Hz `pdMS_TO_TICKS(1)` es 0 y
# el sondeo de 1 ms degenera en un `taskYIELD`. Y el ELF de 10 ms y el de 1 ms
# se parecen demasiado como para distinguirlos de vista.
ws="$repo_root/build/fw/zedboard/vitis_ws"
grep -q '#define DRX_STIMULUS_POLL_MS 1$' "$ws/drx_app/src/drx_stimulus.c" \
    || abortar "el workspace no tiene DRX_STIMULUS_POLL_MS 1: correr tools/build_vitis.sh zedboard"
grep -q '#define configTICK_RATE_HZ (1000)' \
    "$ws/drx_zynq/ps7_cortexa9_0/freertos_domain/bsp/ps7_cortexa9_0/include/FreeRTOSConfig.h" \
    || abortar "el BSP no tiene configTICK_RATE_HZ (1000)"

mkdir -p "$dir"
echo "corrida en $dir"
{
    echo "inicio   : $(date -Is)"
    echo "duracion : ${horas} h"
    echo "git      : $(git -C "$repo_root" rev-parse --short HEAD) $(git -C "$repo_root" status --porcelain | wc -l) ficheros sucios"
    echo "elf      : $(date -r "$repo_root/build/fw/zedboard/drx_app.elf" -Is)"
    echo "bit      : $(date -r "$repo_root/build/gw/zedboard_zynq_dbg/drx_zynq_top.bit" -Is)"
} > "$dir/corrida.txt"

pids=()
parar_todo() {
    echo "parando en orden inverso..."
    # 1. conductor: SIGINT -> KeyboardInterrupt -> `with sock:` cierra con FIN
    #    limpio y el firmware reacepta y recicla el anillo. Nunca -9.
    [[ -n "${pid_cond:-}" ]] && kill -INT "$pid_cond" 2>/dev/null || true
    sleep 2
    [[ -n "${pid_vig:-}" ]]  && kill -TERM "$pid_vig" 2>/dev/null || true
    # 3. el ILA por fichero, para que llegue a close_hw_manager.
    touch "$dir/parar-ila"
    if [[ -n "${pid_ila:-}" ]]; then
        for _ in $(seq 1 120); do kill -0 "$pid_ila" 2>/dev/null || break; sleep 1; done
        kill -TERM "$pid_ila" 2>/dev/null || true
    fi
    # 4. el UART el último, con margen para una línea de contadores final.
    sleep 3
    [[ -n "${pid_uart:-}" ]] && kill -TERM "$pid_uart" 2>/dev/null || true
    echo "evidencia en $dir"
}
trap parar_todo EXIT INT TERM

# --- hw_server propio ---------------------------------------------------------
# Arrancado aquí y no por xsct/Vivado: así el cable lo posee un proceso
# persistente y no hay duda sobre si xsct, al salir, se lleva el que él mismo
# lanzó.
if ! pgrep -f "[h]w_server" >/dev/null; then
    setsid "$hw_server_bin" -d -s tcp::3121 >"$dir/hw_server.log" 2>&1 || true
    sleep 3
fi
pgrep -f "[h]w_server" >/dev/null || abortar "hw_server no arrancó"

# --- 1. UART, antes de cargar -------------------------------------------------
if fuser "$tty_ps" >/dev/null 2>&1; then
    fuser -v "$tty_ps" >&2 || true
    abortar "alguien ya tiene abierto $tty_ps; dos lectores entrelazan los bytes"
fi
stty -F "$tty_ps" 115200 cs8 -cstopb -parenb -echo raw
stdbuf -oL cat "$tty_ps" > "$dir/uart.log" &
pid_uart=$!
sleep 1

# --- 2. carga en frío, UN SOLO INTENTO ----------------------------------------
# DRX_SIN_CARGA=1 cuando la placa YA se cargó a mano (por ejemplo para hacer
# antes el ensayo de humo del ILA). Un segundo `fpga -file` sobre una placa que
# ya está entregando rayos es exactamente la trampa de HP0.
if [[ -n "${DRX_SIN_CARGA:-}" ]]; then
    echo "DRX_SIN_CARGA: se da por cargada, no se toca la PL"
else
    echo "cargando (un solo intento; si falla, NO relanzar: hace falta SW8)"
    if ! "$repo_root/tools/cargar_dbg.sh" > "$dir/carga.log" 2>&1; then
        tail -20 "$dir/carga.log" >&2
        abortar "la carga por JTAG falló. NO la relances: apaga y enciende la placa."
    fi
fi

# --- 3. puerta de arranque en frío --------------------------------------------
# Sin esto se pueden medir diez horas sobre un arranque malo. La tercera línea
# de `drx_status` solo se imprime si algún contador fino es distinto de cero, o
# sea que su AUSENCIA es el indicador de trig_gaps=0 / ray_gaps=0.
echo "puerta de arranque en frío (60 s)..."
sleep 60
if [[ -z "${DRX_SIN_CARGA:-}" ]]; then
    grep -qa 'drx_transport: escuchando en el puerto' "$dir/uart.log" \
        || abortar "el transporte no llegó a escuchar"
fi
grep -qa 'drx_status: BITE' "$dir/uart.log" \
    || abortar "no hay líneas de drx_status: el firmware no arrancó bien"
if grep -qa 'no se pudo encolar la primera pasada' "$dir/uart.log"; then
    abortar "ya hay atasco en el arranque: la carga salió mal, apaga y enciende"
fi
# La tercera línea de `drx_status` solo se imprime si algún contador fino es
# distinto de cero, pero su mera presencia NO es un fallo: un arranque en frío
# sano imprime `resync=1` (medido el 3-oct-2026 en el arranque de esta misma
# corrida). Lo que descalifica el arranque es cualquiera de los demás.
ultima_rayo="$(grep -a 'drx_status: rayo' "$dir/uart.log" | tail -1 || true)"
if [[ -n "$ultima_rayo" ]]; then
    echo "contadores finos: $ultima_rayo"
    # Solo los contadores del lado PL/DMA. `resync`, `snd_fail` y `sink_drops`
    # son artefactos de la interacción con el cliente: un `send` en vuelo
    # cuando el DSP se desconecta incrementa `snd_fail`, y esta corrida hace
    # ~1500 conexiones y desconexiones, así que subirán toda la noche sin que
    # eso signifique nada. Medido el 3-oct-2026: una sola pasada de prueba del
    # barrido dejó `resync=1 snd_fail=1` en una placa perfectamente sana.
    for campo in dma_err magic n_ch cortos largos trig_gaps ray_gaps cola; do
        v="$(sed -n "s/.*[^_a-z]${campo}=\([0-9]*\).*/\1/p" <<< "$ultima_rayo")"
        if [[ -n "$v" && "$v" != "0" ]]; then
            abortar "arranque sucio: ${campo}=${v}"
        fi
    done
fi
ultima_bite="$(grep -a 'drx_status: BITE' "$dir/uart.log" | tail -1)"
echo "$ultima_bite"
for campo in dma_overruns ddc_overflows ssa_underruns; do
    v="$(sed -n "s/.*${campo}=\([0-9]*\).*/\1/p" <<< "$ultima_bite")"
    [[ -n "$v" && "$v" != "0" ]] && abortar "arranque sucio: ${campo}=${v}"
done
timeout 5 ping -c1 -W2 "$host" >/dev/null || abortar "la placa no responde al ping"
echo "puerta pasada"

# --- 4. bucle del ILA, y esperar su primer latido -----------------------------
setsid "$vivado_bin" -mode batch -source "$repo_root/tools/ila_p21.tcl" \
    -log "$dir/vivado-ila.log" -journal "$dir/vivado-ila.jou" \
    -tclargs -ltx "$ltx" -dir "$dir" -duracion "$segundos" \
    -bandera "$dir/bandera-ila" -parar "$dir/parar-ila" \
    -latido "$dir/latido-ila" > "$dir/ila.log" 2>&1 &
pid_ila=$!
for _ in $(seq 1 180); do [[ -f "$dir/latido-ila" ]] && break; sleep 1; done
[[ -f "$dir/latido-ila" ]] || abortar "el ILA no dio su primer latido en 180 s"
echo "ILA armado: $(cat "$dir/latido-ila")"

# --- 5. vigía -----------------------------------------------------------------
setsid "$repo_root/tools/vigia_uart.py" "$dir" > "$dir/vigia.log" 2>&1 &
pid_vig=$!

# --- 6. conductor -------------------------------------------------------------
# Se reinicia hasta 5 veces; la carga por JTAG NUNCA se reintenta.
# Si muere el ILA la noche se degrada pero no se anula: la condición de cierre
# por consecuencia se satisface con el UART y el log del conductor, que son
# continuos e independientes. El ILA solo hace falta para el caso POSITIVO.
(
    intentos=0
    fin=$(( $(date +%s) + segundos ))
    while (( $(date +%s) < fin )) && (( intentos < 5 )); do
        [[ -e "$dir/parar-conductor" ]] && break
        restante=$(( fin - $(date +%s) ))
        (( restante > 60 )) || break
        "$repo_root/tools/conductor_p21.sh" "$dir" "$restante" || true
        intentos=$(( intentos + 1 ))
    done
) &
pid_cond=$!

echo "los cuatro procesos en marcha. Fin previsto: $(date -d "+${horas} hours" -Is)"
echo "parar a mano:  touch $dir/parar-conductor $dir/parar-ila"
echo "triaje:        tools/triaje_p21.sh $dir"
wait "$pid_cond" || true
