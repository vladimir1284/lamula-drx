#!/usr/bin/env bash
# Genera BSP + FSBL + drx_app vía Vitis/xsct (tcl/gen_bsp.tcl), a partir del
# XSA que produce `vivado ... tcl/build.tcl -tclargs -platform <p> -top zynq
# -step xsa`. Precondición de tools/make_boot.sh: sin esto falla con "falta
# fsbl.elf/drx_app.elf" (ver CLAUDE.md, "Lo primero que hay que hacer").
#
# Desde Z4.2, drx_app ya no es el "Hello World" de Vitis: es FreeRTOS +
# lwIP (dominio freertos10_xilinx) + el driver de registros AXI-Lite de
# fw/src/app/ -- ver la cabecera de tcl/gen_bsp.tcl.
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

# Catálogo de estímulos (Z4.3): 62 KiB de C generados del modelo, consumidos por
# fw/src/app/drx_stimulus.c. No se versionan -- se regeneran, igual que el .hex
# de precarga de la BRAM. tcl/gen_bsp.tcl falla con un mensaje claro si faltan.
# El generador necesita numpy (sale del modelo dorado), que vive en el venv del
# repo -- el mismo que usa el Makefile. Fuera de él, `python3` pelado falla con
# ModuleNotFoundError y no con algo que se pueda confundir con un fallo de Vitis.
py="$repo_root/.venv/bin/python"
[[ -x "$py" ]] || {
  # Antes caía a `python3` pelado, y el fallo salía como
  # `ModuleNotFoundError: No module named 'numpy'` en mitad de un script que
  # dice llamarse build_vitis: parecía un problema de Vitis. El venv del repo
  # es la única forma soportada de correr los generadores (dependencias
  # pinadas en requirements-dev.txt), así que se pide explícitamente.
  echo "falta $py: correr primero 'make venv'" >&2
  exit 1
}
"$py" "$repo_root/tools/gen_stimulus_catalog.py" --platform "$platform"

xsct "$repo_root/tcl/gen_bsp.tcl" "$xsa" "$outdir"
