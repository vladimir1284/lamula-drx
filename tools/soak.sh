#!/usr/bin/env bash
# Corre un soak del transporte DRx<->DSP y deja TODA la evidencia en disco.
#
# Por que existe: el soak 5 del 3-oct-2026 escribia en /tmp. La maquina se
# reinicio y se perdieron el log del cliente y la captura de UART enteros. Los
# contadores se pudieron recuperar porque la placa no se apago, pero eso fue
# suerte, no diseno. Aqui todo va a build/soak/, que sobrevive al reinicio.
#
# Captura las DOS fuentes, porque dicen cosas distintas:
#
#   - El cliente (tools/mock_dsp.py) ve lo que llega por el cable: rayos,
#     caudal y huecos de `seq`. No ve nada de lo que la placa descarto.
#   - La UART ve los contadores de la placa: dma_overruns, trig_gaps,
#     cortos/largos, sink_drops, cola. Ahi es donde se diagnostica.
#
# La UART se abre ANTES que el cliente y se cierra DESPUES, para que la ultima
# linea de contadores quede capturada con el cliente ya desconectado.
#
# Ademas de las dos fuentes de arriba:
#
#   - host.log: cada 60 s, contadores del enlace del host (errores, drops,
#     retransmisiones TCP) y carga. Si reaparecen descartes, es lo que separa
#     "la placa" de "el host", que el soak de 72 h del 8-oct no pudo hacer.
#   - Preflight de 20 s ANTES de empezar: si las cabeceras no son las
#     esperadas, hay TRUNCATED o no llegan rayos, aborta. Sin esto el error de
#     config se descubria a las 72 h.
#   - Modo estricto del cliente: un cierre del socket o una parada de la placa
#     da codigo 5, no una corrida "corta pero limpia".
#
# Uso:  tools/soak.sh [segundos] [opciones extra para mock_dsp.py]
#   p.ej.  tools/soak.sh 5400 --spectrum
# Entorno: DRX_ESPERADO (pares prf_div:bins permitidos), DRX_IF (enlace al DRx),
#   DRX_TTY (consola del PS).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
segundos="${1:-600}"
shift || true

tty_ps="${DRX_TTY:-/dev/ttyACM0}"
esperado="${DRX_ESPERADO:-208416:1002,767312:3689}"
iface="${DRX_IF:-enp1s0}"
destino="$repo_root/build/soak/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$destino"

if [[ ! -e "$tty_ps" ]]; then
    echo "error: no existe $tty_ps (consola del PS; el ttyUSB0 es el JTAG)" >&2
    exit 1
fi

# Sin esto la captura sale como basura binaria. Y UN SOLO lector: dos `cat`
# sobre el mismo tty se reparten los bytes y entrelazan la salida, que ya
# costo una sesion confundirlo con un problema de baudios.
if fuser "$tty_ps" >/dev/null 2>&1; then
    echo "error: alguien ya tiene abierto $tty_ps. Dos lectores entrelazan" >&2
    echo "       los bytes y la captura sale ilegible." >&2
    fuser -v "$tty_ps" >&2 || true
    exit 1
fi
stty -F "$tty_ps" 115200 cs8 -cstopb -parenb -echo raw

# Hora de pared en cada linea: sin ella los contadores de la placa no se pueden
# cruzar con los huecos del cliente ni con lo que corria en el host.
stdbuf -oL cat "$tty_ps" | while IFS= read -r linea; do
    printf '%s %s\n' "$(date +%H:%M:%S)" "$linea"
done > "$destino/uart.log" &
uart_pid=$!
# shellcheck disable=SC2064
host_pid=""
trap 'kill $uart_pid $host_pid 2>/dev/null || true' EXIT

# Procedencia: que codigo y que ELF corrian. El soak de 72 h no lo registro.
{
    echo "inicio: $(date --iso-8601=seconds)"
    echo "commit: $(git -C "$repo_root" rev-parse HEAD)$(git -C "$repo_root" diff --quiet || echo ' (arbol sucio)')"
    for elf in "$repo_root"/build/boot/zedboard/drx_app.elf "$repo_root"/build/fw/zedboard/drx_app.elf; do
        [[ -e "$elf" ]] && echo "elf: $elf $(sha256sum "$elf" | cut -c1-16) $(date -r "$elf" --iso-8601=seconds)"
    done
    for art in "$repo_root"/build/gw/zedboard_zynq/drx_zynq_top.bit "$repo_root"/build/gw/zedboard_zynq/drx_zynq_top.xsa; do
        [[ -e "$art" ]] && echo "gw: $art $(sha256sum "$art" | cut -c1-16) $(date -r "$art" --iso-8601=seconds)"
    done
    echo "esperado (prf_div:bins): $esperado"
    echo "host: $(uname -rn) enlace=$iface"
    echo "suspension: $(gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 2>&1) timeout=$(gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 2>&1)"
    echo "comando: soak.sh $segundos $*"
} > "$destino/procedencia.txt"

# Contadores del enlace del host a lo largo del soak.
muestra_host() {
    local st="/sys/class/net/$iface/statistics"
    printf '%s load=%s rx_err=%s rx_drop=%s rx_miss=%s tcp_retrans=%s\n' \
        "$(date +%H:%M:%S)" "$(cut -d' ' -f1 /proc/loadavg)" \
        "$(cat $st/rx_errors)" "$(cat $st/rx_dropped)" "$(cat $st/rx_missed_errors)" \
        "$(awk '/^Tcp:/ && !h {for(i=1;i<=NF;i++) if($i=="RetransSegs") c=i; h=1; next} /^Tcp:/ {print $c}' /proc/net/snmp)"
}
[[ -d "/sys/class/net/$iface" ]] || { echo "error: no existe el enlace $iface (DRX_IF)" >&2; exit 1; }

echo "soak de ${segundos} s -> $destino"
sleep 2  # deja entrar una linea de contadores previa al cliente

# Preflight: 20 s con las mismas comprobaciones que el soak. Si falla, no se
# gastan 72 h para descubrir que la config no era la que se creia.
if ! "$repo_root/.venv/bin/python" "$repo_root/tools/mock_dsp.py" \
        --seconds 20 --quiet --esperar "$esperado" > "$destino/preflight.log" 2>&1; then
    echo "PREFLIGHT FALLIDO, no se lanza el soak. Ver $destino/preflight.log" >&2
    tail -15 "$destino/preflight.log" >&2
    exit 2
fi
echo "preflight OK: $(grep -a 'configs vistas' -A3 "$destino/preflight.log" | tail -3 | tr '\n' ' ')"
sleep 3

( while :; do muestra_host; sleep 60; done ) > "$destino/host.log" 2>&1 &
host_pid=$!

"$repo_root/.venv/bin/python" "$repo_root/tools/mock_dsp.py" \
    --seconds "$segundos" --quiet --estricto --esperar "$esperado" "$@" > "$destino/cliente.log" 2>&1 &
cliente_pid=$!
wait "$cliente_pid" && estado=0 || estado=$?

sleep 3  # una linea de contadores con el cliente ya desconectado
kill "$uart_pid" "$host_pid" 2>/dev/null || true
muestra_host >> "$destino/host.log"
trap - EXIT

{
    echo "=== cliente ==="
    cat "$destino/cliente.log"
    echo
    echo "=== contadores de la placa: primera y ultima lectura ==="
    for patron in "drx_status: BITE" "drx_status: red" "drx_status: rayo"; do
        grep -a "$patron" "$destino/uart.log" | head -1
        grep -a "$patron" "$destino/uart.log" | tail -1
    done
    echo
    echo "=== host: primera y ultima muestra ==="
    head -1 "$destino/host.log"
    tail -1 "$destino/host.log"
    echo
    echo "=== procedencia ==="
    cat "$destino/procedencia.txt"
    echo "fin: $(date --iso-8601=seconds)"
    echo "codigo del cliente: $estado (0 limpio, 3 huecos de seq, 4 sin rayos, 5 config/paradas/fin temprano)"
    echo
    echo "=== eventos ==="
    echo "rayos sin enmarcar: $(grep -ac 'rayo sin enmarcar' "$destino/uart.log" || true)"
} | tee "$destino/resumen.txt"

echo
echo "evidencia en $destino"
exit "$estado"
