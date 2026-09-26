#!/usr/bin/env bash
# Genera BSP + FSBL + drx_app vía Vitis/xsct (tcl/gen_bsp.tcl), a partir del
# XSA que produce `vivado ... tcl/build.tcl -tclargs -platform <p> -top zynq
# -step xsa`. Precondición de tools/make_boot.sh: sin esto falla con "falta
# fsbl.elf/drx_app.elf" (ver CLAUDE.md, "Lo primero que hay que hacer").
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
platform="${1:-zedboard}"
xsa="$repo_root/build/gw/${platform}_zynq/drx_zynq_top.xsa"
outdir="$repo_root/build/fw/$platform"

for tool in xsct; do
  command -v "$tool" >/dev/null || { echo "falta $tool en el PATH" >&2; exit 1; }
done
[[ -f "$xsa" ]] || {
  echo "falta $xsa: correr primero 'vivado -mode batch -source tcl/build.tcl -tclargs -platform $platform -top zynq -step xsa'" >&2
  exit 1
}

mkdir -p "$outdir"
xsct "$repo_root/tcl/gen_bsp.tcl" "$xsa" "$outdir"
