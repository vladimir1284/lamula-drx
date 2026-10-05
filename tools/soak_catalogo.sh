#!/usr/bin/env bash
# Encadena barridos del catálogo contra la placa durante N segundos.
#
#   tools/soak_catalogo.sh [segundos]        # por defecto 1800 (30 min)
#
# Para qué: confirmar que con el canal MM2S fuera del diseño (4-oct-2026) no
# queda nada en el camino de estímulo que se pueda atascar. Es la afirmación
# que P-21 deja implícita al quedar inalcanzable, y hasta esta corrida no
# estaba medida.
#
# Qué lo distingue de `tools/conductor_p21.sh`, que hacía algo parecido: aquel
# toleraba `rc=1` porque con Throttled(DDR) el barrido daba 0/8 por P-16, y
# buscaba la firma del atasco (`RECHAZADO`/`SIN ACK`) en el stdout del hijo
# porque el código de salida no discriminaba. Aquí la premisa es la contraria:
# desde el 4-oct-2026 el barrido cierra 8/8, así que **cualquier rc != 0 es un
# fallo de verdad** y el código de salida sí sirve como criterio.
#
# No para en el primer fallo: el dato que interesa es si degrada con las horas,
# y una pasada suelta perdida por un hipo de red no es lo mismo que un atasco.
# Sí para tras TRES fallos seguidos -- a partir de ahí algo está trabado y
# seguir media hora no añade información.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
segundos="${1:-1800}"
host="${DRX_HOST:-192.168.1.10}"
tty_ps="${DRX_TTY:-/dev/ttyACM0}"
venv="$repo_root/.venv/bin/python"

[[ -x "$venv" ]] || { echo "falta $venv: correr 'make venv'" >&2; exit 1; }

destino="$repo_root/build/soak/catalogo-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$destino/pasadas"

# UART: un solo lector. Dos `cat` sobre el mismo tty se reparten los bytes y
# entrelazan la salida, que ya costó una sesión confundirlo con un problema de
# baudios.
if [[ -e "$tty_ps" ]]; then
    if fuser "$tty_ps" >/dev/null 2>&1; then
        echo "aviso: alguien ya tiene abierto $tty_ps; esta corrida va sin UART" >&2
    else
        stty -F "$tty_ps" 115200 cs8 -cstopb -parenb -echo raw
        stdbuf -oL cat "$tty_ps" > "$destino/uart.log" &
        uart_pid=$!
        # shellcheck disable=SC2064
        trap "kill $uart_pid 2>/dev/null || true" EXIT
    fi
else
    echo "aviso: no existe $tty_ps; esta corrida va sin UART" >&2
fi

log="$destino/soak.log"
fin=$(( $(date +%s) + segundos ))
n=0; fallos=0; seguidos=0

echo "$(date -Is) soak del catálogo, ${segundos} s, hasta $(date -d "@$fin" -Is)" | tee -a "$log"
echo "parar a mano: touch $destino/parar" | tee -a "$log"

while (( $(date +%s) < fin )); do
    [[ -e "$destino/parar" ]] && { echo "$(date -Is) parada pedida" | tee -a "$log"; break; }
    n=$(( n + 1 ))
    salida="$destino/pasadas/pasada-$(printf %05d "$n").log"
    inicio=$SECONDS
    rc=0
    "$venv" "$repo_root/tools/sweep_catalogo.py" \
        --host "$host" --settle 1 > "$salida" 2>&1 || rc=$?
    dur=$(( SECONDS - inicio ))
    coinciden=$(grep -oE '^[0-9]+/8 coinciden' "$salida" | head -1 || true)
    echo "$(date -Is) pasada $n rc=$rc dur=${dur}s ${coinciden:-sin-resumen}" | tee -a "$log"

    if (( rc != 0 )); then
        fallos=$(( fallos + 1 )); seguidos=$(( seguidos + 1 ))
        if (( seguidos >= 3 )); then
            echo "$(date -Is) TRES fallos seguidos, parando" | tee -a "$log"
            break
        fi
    else
        seguidos=0
    fi
done

sleep 3   # deja entrar una línea de contadores con el cliente ya desconectado

echo "" | tee -a "$log"
echo "$(date -Is) fin: $n pasadas, $fallos fallos" | tee -a "$log"
if [[ -s "$destino/uart.log" ]]; then
    echo "--- últimos contadores por UART ---" | tee -a "$log"
    grep -a 'drx_status: rayo' "$destino/uart.log" | tail -1 | tee -a "$log"
    grep -a 'drx_status: BITE' "$destino/uart.log" | tail -1 | tee -a "$log"
fi
echo "evidencia en $destino" | tee -a "$log"

exit $(( fallos > 0 ? 1 : 0 ))
