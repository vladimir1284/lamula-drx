#!/usr/bin/env bash
# Carga por JTAG el bitstream de PRODUCCIÓN y el firmware, sobre una ZedBoard
# RECIÉN ENCENDIDA.
#
#   tools/cargar.sh
#
# Hermano de `tools/cargar_dbg.sh`, que hace lo mismo con el bitstream de
# depuración. Desde el 4-oct-2026 el de depuración ya no engancha ningún ILA
# —la sonda de P-21 salió del diseño con el canal MM2S—, así que éste es el
# que hay que usar salvo que alguien vuelva a instanciar `drx_debug_probe`.
#
# UN SOLO INTENTO, y es deliberado. Si esto falla a mitad -- por ejemplo después
# del `fpga` y antes del `con` -- NO lo relances: un segundo `fpga -file` puede
# caer sobre un firmware anterior con el S2MM transmitiendo, y reconfigurar la
# PL con transacciones vivas en HP0 deja la transacción colgada del lado PS,
# donde no llegan ni la reconfiguración ni `ps7_init`. Comprobado el 3-oct-2026
# que no se recupera por software (cuatro recargas y un ciclo de
# FPGA_RST_CTRL). De ahí solo se sale apagando y encendiendo la placa (SW8).
# Ver docs/implementacion/ila.md.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bit="$repo_root/build/gw/zedboard_zynq/drx_zynq_top.bit"
elf="$repo_root/build/fw/zedboard/drx_app.elf"
xsa="$repo_root/build/gw/zedboard_zynq/drx_zynq_top.xsa"

command -v xsct >/dev/null || { echo "falta xsct en el PATH" >&2; exit 1; }
for f in "$bit" "$elf" "$xsa"; do
    [[ -f "$f" ]] || { echo "falta $f" >&2; exit 1; }
done

# El bitstream y el XSA tienen que salir de la MISMA corrida de Vivado: un XSA
# viejo con un bitstream nuevo da un `xparameters.h` que no describe la PL
# cargada, y el síntoma es un mapa de registros que lee basura sin ningún
# error. Barato de comprobar, caro de diagnosticar en placa.
if [[ "$bit" -nt "$xsa" ]]; then
    echo "AVISO: el .bit es más nuevo que el .xsa; ¿corrida de Vivado a medias?" >&2
fi

echo "bit: $bit  ($(date -r "$bit" +%Y-%m-%dT%H:%M:%S))"
echo "elf: $elf  ($(date -r "$elf" +%Y-%m-%dT%H:%M:%S))"
echo "xsa: $xsa  ($(date -r "$xsa" +%Y-%m-%dT%H:%M:%S))"

# `run_jtag.tcl` usa `rst -cores` (seguro, no toca el SLCR) y extrae
# `ps7_init.tcl` del propio XSA con `unzip`, así que no depende de que
# build/fw/zedboard/ps7_init/ siga ahí -- es un artefacto de build sin versionar.
exec xsct "$repo_root/bringup/tcl/run_jtag.tcl" "$bit" "$elf" "$xsa"
