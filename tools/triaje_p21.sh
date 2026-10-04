#!/usr/bin/env bash
# Resumen de la mañana de una corrida de tools/noche_p21.sh.
#
#   tools/triaje_p21.sh <dir-de-la-corrida>
#
# Cruza las tres fuentes, que dicen cosas distintas:
#   - uart.log       : contadores de la placa y los dos mensajes de drx_stimulus
#   - pasadas/*.log  : los `config_ack` por selección, que NO salen por UART
#   - disparos.tsv   : una línea por iteración del ILA, con su estado
set -euo pipefail

dir="${1:?falta el directorio de la corrida}"
cd "$dir"

echo "=== la corrida ==="
cat corrida.txt 2>/dev/null || true
echo "fin del log: $(date -r uart.log -Is 2>/dev/null || echo '?')"

echo
echo "=== selecciones encadenadas ==="
sel=$(grep -ac 'drx_stimulus: vector ' uart.log 2>/dev/null || echo 0)
pas=$(ls pasadas/ 2>/dev/null | wc -l)
echo "selecciones aceptadas : $sel   (contra las 80 del A/B del 3-oct)"
echo "pasadas del barrido   : $pas"

echo
echo "=== el atasco permanente ==="
if grep -qa 'no se pudo encolar la primera pasada' uart.log 2>/dev/null; then
    echo "REPRODUJO:"
    grep -an 'no se pudo encolar la primera pasada' uart.log | head -5
    grep -a 'VIGIA' uart-ts.log 2>/dev/null | head -5
else
    echo "no reprodujo"
fi
pre=$(grep -ac 'pasada sin completar tras' uart.log 2>/dev/null || echo 0)
echo "precursores ('pasada sin completar'): $pre"

echo
echo "=== veredictos del barrido (DISCREPA = P-16, es ruido esperado) ==="
for v in RECHAZADO 'SIN ACK' 'SIN RAYO' 'RAYO MALFORMADO' DISCREPA coincide; do
    printf "%-18s %s\n" "$v" "$(grep -rhac "$v" pasadas/*.log 2>/dev/null | paste -sd+ | bc 2>/dev/null || echo 0)"
done

echo
echo "=== contadores de la placa, última línea de cada tipo ==="
grep -a 'drx_status: BITE' uart.log 2>/dev/null | tail -1 || true
grep -a 'drx_status: red'  uart.log 2>/dev/null | tail -1 || true
echo "--- líneas 'drx_status: rayo' (solo salen si algo es != 0) ---"
grep -a 'drx_status: rayo' uart.log 2>/dev/null | tail -5 || echo "ninguna: trig_gaps=0 ray_gaps=0 cola=0"
echo "--- rayos sin enmarcar (P-18) ---"
grep -ac 'rayo sin enmarcar' uart.log 2>/dev/null || echo 0

echo
echo "=== el ILA ==="
echo "último latido: $(cat latido-ila 2>/dev/null || echo 'ninguno')"
echo "ventana ciega: desde el último latido hasta $(date -Is)"
echo "--- disparos.tsv ---"
cat disparos.tsv 2>/dev/null | grep -v '^#' | awk '{print $3}' | sort | uniq -c || true
echo "--- capturas ---"
ls -la ila-*.csv 2>/dev/null || echo "ninguna"

repo_root="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
for csv in ila-*.csv; do
    [[ -e "$csv" ]] || break
    echo
    echo "=== $csv ==="
    "$repo_root/.venv/bin/python" "$repo_root/tools/ila_p21_leer.py" "$csv" || true
done
