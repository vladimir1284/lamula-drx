#!/usr/bin/env bash
# Encadena selecciones de estímulo contra la placa hasta una fecha límite.
#
#   tools/conductor_p21.sh <dir-de-la-corrida> <segundos>
#
# Es el estímulo de la corrida nocturna de P-21: `tools/sweep_catalogo.py` hace
# UNA pasada de 8 vectores y termina, sin bucle propio. Esto lo repite.
#
# Dos cosas que no son obvias:
#
# 1. El CÓDIGO DE SALIDA NO DISCRIMINA. `sweep_catalogo.py` devuelve 1 para tres
#    cosas distintas: P-16 esperado (hoy 0/8 coinciden con el modelo porque el
#    DDS Compiler no tiene `aclken`), "no se pudo conectar", y el atasco. En el
#    atasco, `DrxStimulus_Select` devuelve NOT_CONFIGURED, eso viaja como
#    `config_ack` con error y el barrido lo clasifica `RECHAZADO (...)` -- que
#    acaba en el código 1, NO en el 4 (el 4 pide `sin_rayo == len(resultados)`,
#    y en el atasco los vectores mueren antes, en el ack). O sea que "tolerar el
#    código 1" dejaría pasar el atasco toda la noche sin enterarse. Lo que
#    discrimina está en el STDOUT del hijo.
#
# 2. Ese stdout es la ÚNICA traza por selección de todo el sistema: los
#    `config_ack` no salen por UART (`fw/src/app/drx_control.c` no tiene ni un
#    `xil_printf`). Por eso se guarda una pasada por fichero.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="${1:?falta el directorio de la corrida}"
segundos="${2:-36000}"
host="${DRX_HOST:-192.168.1.10}"
venv="$repo_root/.venv/bin/python"

[[ -x "$venv" ]] || { echo "falta $venv: correr 'make venv'" >&2; exit 1; }
mkdir -p "$dir/pasadas"

fin=$(( $(date +%s) + segundos ))
n=0
rapidas=0
extra=0          # pasadas que quedan tras detectar el atasco
log="$dir/conductor.log"

echo "$(date -Is) conductor arranca, hasta $(date -d "@$fin" -Is)" >> "$log"

while (( $(date +%s) < fin )); do
    [[ -e "$dir/parar-conductor" ]] && { echo "$(date -Is) parada pedida" >> "$log"; break; }
    n=$(( n + 1 ))
    salida="$dir/pasadas/pasada-$(printf %05d "$n").log"
    inicio=$SECONDS
    rc=0
    "$venv" "$repo_root/tools/sweep_catalogo.py" \
        --host "$host" --settle 1 > "$salida" 2>&1 || rc=$?
    dur=$(( SECONDS - inicio ))
    echo "$(date -Is) pasada $n rc=$rc dur=${dur}s" >> "$log"

    if grep -qE 'RECHAZADO|SIN ACK' "$salida"; then
        if (( extra == 0 )); then
            # Firma del atasco permanente. Tres pasadas más antes de parar: cada
            # `test_stimulus_select` hace bajar y subir `ddr_mode`
            # (`DrxStimulus_Stop` termina en `set_modo_ddr(false)` y `Select`
            # pone `true`), o sea que REGENERA el flanco de `stalled` y le da al
            # ILA dos o tres oportunidades más de capturar con historia por
            # delante. Después se para, y la placa queda quieta para poder
            # volcar MM2S_CURDESC/TAILDESC por la mañana sobre un estado que
            # nadie está tocando.
            echo "$(date -Is) ATASCO en la pasada $n: tres pasadas más y paro" >> "$log"
            extra=3
        fi
    fi

    if (( extra > 0 )); then
        extra=$(( extra - 1 ))
        if (( extra == 0 )); then
            date -Is > "$dir/bandera-ila"
            echo "$(date -Is) atasco confirmado tras pasadas extra" > "$dir/parar-conductor"
            break
        fi
    fi

    # Una pasada real son ~24 s. Mucho más corta es un fallo de conexión, y sin
    # suelo eso sería un bucle apretado toda la noche contra una placa muerta.
    if (( dur < 6 )); then
        rapidas=$(( rapidas + 1 ))
        sleep 30
    else
        rapidas=0
    fi
    if (( rapidas >= 5 )); then
        echo "$(date -Is) cinco pasadas rápidas seguidas: la placa no responde" \
            | tee -a "$log" > "$dir/parar-conductor"
        break
    fi
done

echo "$(date -Is) conductor termina tras $n pasadas" >> "$log"
