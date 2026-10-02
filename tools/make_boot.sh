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
# ESTADO: ejecutado por primera vez el 21-sep-2026 (CI, self-hosted). Desde el
# 26-sep-2026 empaqueta fsbl.elf y drx_app.elf reales (Z4.2) y BOOT.BIN sale
# reproducible byte a byte. NUNCA se ha arrancado una ZedBoard desde SD: el
# bring-up físico del 1-oct-2026 fue por JTAG (ver bringup/README.md).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
platform="${1:-zedboard}"
outdir="${2:-$repo_root/build/boot/$platform}"
# El bitstream tiene que ser el del flujo `-top zynq`, que es el que lleva el
# PS7 y, con él, el esclavo AXI-Lite `m_axi_regs` que direcciona el firmware
# (fw/src/app/drx_regs_hw.c). `build/gw/$platform/` guarda el otro flujo,
# `drx_top_tieoff`: mismo datapath, pero sin PS7 y con el AXI-Lite atado a
# valores inertes. Hasta el 1-oct-2026 este script empaquetaba ese, así que
# todo BOOT.BIN anterior lleva un bitstream en el que el esclavo AXI que
# drx_app direcciona no existe. Nadie lo detectó porque nunca se arrancó
# desde SD.
#
# Es además el mismo directorio del que tools/build_vitis.sh saca el XSA: el
# bitstream y el BSP/FSBL/app que van dentro de BOOT.BIN salen de la misma
# corrida de Vivado, que es la única forma de que el mapa de direcciones del
# firmware case con el del hardware.
gwdir="$repo_root/build/gw/${platform}_zynq"
fwdir="$repo_root/build/fw/$platform"

for tool in bootgen; do
  command -v "$tool" >/dev/null || { echo "falta $tool en el PATH" >&2; exit 1; }
done

bit="$gwdir/drx_zynq_top.bin"
[[ -f "$bit" ]] || {
  echo "falta $bit: correr primero 'vivado -mode batch -source tcl/build.tcl \
-tclargs -platform $platform -top zynq -step xsa'" >&2
  exit 1
}

mkdir -p "$outdir"
cp "$repo_root/tcl/boot/boot.bif" "$outdir/boot.bif"
cp "$bit" "$outdir/drx_top.bin"
for artefact in fsbl.elf drx_app.elf; do
  [[ -f "$fwdir/$artefact" ]] && cp "$fwdir/$artefact" "$outdir/$artefact"
done

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
