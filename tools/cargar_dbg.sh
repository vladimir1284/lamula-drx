#!/usr/bin/env bash
# Carga por JTAG el bitstream de DEPURACIÓN (el que lleva el ILA) y el firmware,
# sobre una ZedBoard RECIÉN ENCENDIDA.
#
#   tools/cargar_dbg.sh
#
# UN SOLO INTENTO, y es deliberado. Si esto falla a mitad -- por ejemplo después
# del `fpga` y antes del `con` -- NO lo relances: un segundo `fpga -file` puede
# caer sobre un firmware anterior con el S2MM transmitiendo, y reconfigurar la
# PL con transacciones vivas en HP0 deja la transacción colgada del lado PS,
# donde no llegan ni la reconfiguración ni `ps7_init`. Comprobado el 3-oct-2026
# que no se recupera por software (cuatro recargas y un ciclo de
# FPGA_RST_CTRL). De ahí solo se sale apagando y encendiendo la placa (SW8).
# Ver docs/implementacion/ila.md.
#
# El bitstream es el de depuración pero el XSA es el de PRODUCCIÓN, a propósito:
# `tcl/build.tcl -step bitstream` sale antes de `write_hw_platform`, así que
# build/gw/zedboard_zynq_dbg/ no tiene XSA, y el block design es el mismo -- el
# ILA no toca el mapa de direcciones del PS7.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bit="$repo_root/build/gw/zedboard_zynq_dbg/drx_zynq_top.bit"
elf="$repo_root/build/fw/zedboard/drx_app.elf"
xsa="$repo_root/build/gw/zedboard_zynq/drx_zynq_top.xsa"

command -v xsct >/dev/null || { echo "falta xsct en el PATH" >&2; exit 1; }
for f in "$bit" "$elf" "$xsa"; do
    [[ -f "$f" ]] || { echo "falta $f" >&2; exit 1; }
done

echo "bit: $bit"
echo "elf: $elf  ($(date -r "$elf" +%Y-%m-%dT%H:%M:%S))"
echo "xsa: $xsa"

# `run_jtag.tcl` usa `rst -cores` (seguro, no toca el SLCR) y extrae
# `ps7_init.tcl` del propio XSA con `unzip`, así que no depende de que
# build/fw/zedboard/ps7_init/ siga ahí -- es un artefacto de build sin versionar.
exec xsct "$repo_root/bringup/tcl/run_jtag.tcl" "$bit" "$elf" "$xsa"
