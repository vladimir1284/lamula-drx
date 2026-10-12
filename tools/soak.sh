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
# Uso:  tools/soak.sh [segundos] [opciones extra para mock_dsp.py]
#   p.ej.  tools/soak.sh 5400 --spectrum
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
segundos="${1:-600}"
shift || true

tty_ps="${DRX_TTY:-/dev/ttyACM0}"
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
trap "kill $uart_pid 2>/dev/null || true" EXIT

# Procedencia: que codigo y que ELF corrian. El soak de 72 h no lo registro.
{
    echo "inicio: $(date --iso-8601=seconds)"
    echo "commit: $(git -C "$repo_root" rev-parse HEAD)$(git -C "$repo_root" diff --quiet || echo ' (arbol sucio)')"
    for elf in "$repo_root"/build/boot/zedboard/drx_app.elf "$repo_root"/build/fw/zedboard/drx_app.elf; do
        [[ -e "$elf" ]] && echo "elf: $elf $(sha256sum "$elf" | cut -c1-16) $(date -r "$elf" --iso-8601=seconds)"
    done
    echo "comando: soak.sh $segundos $*"
} > "$destino/procedencia.txt"

echo "soak de ${segundos} s -> $destino"
sleep 2  # deja entrar una linea de contadores previa al cliente

"$repo_root/.venv/bin/python" "$repo_root/tools/mock_dsp.py" \
    --seconds "$segundos" --quiet "$@" > "$destino/cliente.log" 2>&1 &
cliente_pid=$!
wait "$cliente_pid" && estado=0 || estado=$?

sleep 3  # una linea de contadores con el cliente ya desconectado
kill "$uart_pid" 2>/dev/null || true
trap - EXIT

{
    echo "=== cliente ==="
    cat "$destino/cliente.log"
    echo
    echo "=== ultimos contadores de la placa ==="
    grep -a "drx_status: BITE" "$destino/uart.log" | tail -1
    grep -a "drx_status: red" "$destino/uart.log" | tail -1
    grep -a "drx_status: rayo" "$destino/uart.log" | tail -1
    echo
    echo "=== procedencia ==="
    cat "$destino/procedencia.txt"
    echo "fin: $(date --iso-8601=seconds)"
    echo
    echo "=== eventos ==="
    echo "rayos sin enmarcar: $(grep -ac 'rayo sin enmarcar' "$destino/uart.log" || true)"
} | tee "$destino/resumen.txt"

echo
echo "evidencia en $destino"
exit "$estado"
