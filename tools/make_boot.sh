#!/usr/bin/env bash
# Empaqueta BOOT.BIN y comprueba que es reproducible byte a byte.
#
# El hito ZM0 es «un git push produce un BOOT.BIN reproducible byte a byte». Eso
# no sale gratis y depende de tres cosas:
#
#   1. Versión de Vivado/Vitis PINADA. Dos versiones distintas dan bitstreams
#      distintos aunque el RTL sea idéntico.
#   2. Usar el `.bin` crudo y no el `.bit`: la cabecera del .bit lleva marca de
#      tiempo y por sí sola rompe la reproducibilidad.
#   3. Semilla de implementación fija (`-seed`) y sin pasos dependientes del
#      número de hilos.
#
# ESTADO: ejecutado por primera vez el 21-sep-2026 (CI, self-hosted). Llega
# hasta donde puede llegar hoy: falta fsbl.elf/drx_app.elf (Z4), así que el
# empaquetado real de BOOT.BIN -- y con él ZM0 -- sigue pendiente de eso.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
platform="${1:-zedboard}"
outdir="${2:-$repo_root/build/boot/$platform}"
gwdir="$repo_root/build/gw/$platform"

for tool in bootgen; do
  command -v "$tool" >/dev/null || { echo "falta $tool en el PATH" >&2; exit 1; }
done

mkdir -p "$outdir"
cp "$repo_root/tcl/boot/boot.bif" "$outdir/boot.bif"
cp "$gwdir/drx_top_tieoff.bin" "$outdir/drx_top.bin"

missing=0
for artefact in fsbl.elf drx_app.elf; do
  if [[ ! -f "$outdir/$artefact" ]]; then
    echo "falta $artefact: lo produce Z4, no Z0" >&2
    missing=1
  fi
done
[[ $missing -eq 0 ]] || exit 2

cd "$outdir"
bootgen -image boot.bif -arch zynq -o BOOT.BIN -w on
sha256sum BOOT.BIN > BOOT.BIN.sha256

# Segunda pasada: el mismo comando tiene que dar el mismo hash.
bootgen -image boot.bif -arch zynq -o BOOT.repeat.bin -w on
if ! cmp -s BOOT.BIN BOOT.repeat.bin; then
  echo "BOOT.BIN NO es reproducible: dos empaquetados dieron ficheros distintos" >&2
  exit 3
fi
rm -f BOOT.repeat.bin
echo "BOOT.BIN reproducible: $(cat BOOT.BIN.sha256)"
