#!/usr/bin/env python3
"""Lee la captura del ILA de P-21 y la decodifica. Ver docs/implementacion/ila.md.

    tools/ila_p21_leer.py build/soak/ila-p21.csv

El CSV que escribe `write_hw_ila_data` trae una columna por probe con el valor
entero del bus. Esto lo descompone en los nombres de `drx_debug_pkg` y saca
las dos cosas que contestan P-21:

1. **La muestra del disparo**, que es el estado congelado de la cadena cuando
   ya lleva 67 ms sin mover una muestra. Quién tiene `valid` alto y `ready`
   bajo en ese ciclo es la respuesta.
2. **El final del tramo con actividad**, para ver cómo se llegó ahí.

No decide nada por su cuenta sobre la causa: imprime el estado y contrasta la
predicción escrita en P-21 antes de medir.
"""

from __future__ import annotations

import csv
import sys
from pathlib import Path

# Orden de los bits dentro de cada probe, LSB primero. Es el de
# `rtl/drx_debug_pkg.sv`; duplicarlo aquí es lo mismo que hace el testbench, y
# por el mismo motivo: un lector que importara el troceado del RTL no
# comprobaría nada.
CAMPOS = {
    "dbg_s_vec": ["s_vec_valid", "s_vec_ready", "s_vec_last"],
    "dbg_m_ray": ["m_ray_valid", "m_ray_ready", "m_ray_last"],
    "dbg_ctrl": [
        "ddr_mode",
        "timing_enable",
        "timing_paced",
        "moved",
        "pulse_trig",
        "stalled",
    ],
}
POR_CANAL = [
    "dbg_vs_valid",
    "dbg_vs_ready",
    "dbg_ddc_valid",
    "dbg_gate_valid",
    "dbg_gate_ready",
    "dbg_overrun",
    "dbg_truncated",
]


def lee_csv(ruta: Path) -> tuple[list[dict[str, str]], dict[str, str]]:
    """Devuelve las filas y el radix por columna.

    `write_hw_ila_data` mete una fila `Radix - UNSIGNED,...` JUSTO debajo de
    la cabecera, y cada columna puede venir en una base distinta (los probes
    salen en HEX, los contadores de muestra en UNSIGNED). Leerlo todo como
    decimal daría valores plausibles y equivocados.
    """
    lineas = ruta.read_text().splitlines()
    for i, linea in enumerate(lineas):
        if linea.startswith("Sample in Buffer"):
            filas = list(csv.DictReader(lineas[i:]))
            break
    else:
        raise SystemExit(f"{ruta}: no encuentro la cabecera 'Sample in Buffer'")

    radix = {}
    if filas and str(filas[0].get("Sample in Buffer", "")).startswith("Radix"):
        cabecera = filas.pop(0)
        for clave, valor in cabecera.items():
            if clave:
                radix[clave] = valor.split("-")[-1].strip()
    return filas, radix


def columna(fila: dict[str, str], prefijo: str, radix: dict[str, str]) -> int | None:
    """Las columnas salen con el rango pegado: `dbg_ctrl[5:0]`."""
    for clave, valor in fila.items():
        if clave and clave.split("[")[0].endswith(prefijo):
            base = 16 if radix.get(clave, "HEX") == "HEX" else 10
            return int(valor, base)
    return None


def decodifica(fila: dict[str, str], radix: dict[str, str]) -> dict[str, int]:
    out: dict[str, int] = {}
    for probe, nombres in CAMPOS.items():
        valor = columna(fila, probe, radix)
        if valor is None:
            continue
        for bit, nombre in enumerate(nombres):
            out[nombre] = (valor >> bit) & 1
    for probe in POR_CANAL:
        valor = columna(fila, probe, radix)
        if valor is not None:
            out[probe.removeprefix("dbg_")] = valor
    cnt = columna(fila, "dbg_idle_cnt", radix)
    if cnt is not None:
        out["idle_cnt"] = cnt
    return out


def imprime(titulo: str, d: dict[str, int]) -> None:
    print(f"--- {titulo} ---")
    print(
        "  s_vec: valid={s_vec_valid} ready={s_vec_ready} last={s_vec_last}".format(**d)
    )
    print(
        "  m_ray: valid={m_ray_valid} ready={m_ray_ready} last={m_ray_last}".format(**d)
    )
    print(
        "  ctrl : ddr_mode={ddr_mode} timing_enable={timing_enable} "
        "timing_paced={timing_paced} moved={moved} pulse_trig={pulse_trig} "
        "stalled={stalled}".format(**d)
    )
    for nombre in ("vs_valid", "vs_ready", "ddc_valid", "gate_valid", "gate_ready",
                   "overrun", "truncated"):
        if nombre in d:
            print(f"  {nombre:<11}= {d[nombre]:#05b}")
    if "idle_cnt" in d:
        ms = d["idle_cnt"] / 62.5e6 * 1e3
        print(f"  idle_cnt   = {d['idle_cnt']} ciclos ({ms:.1f} ms a 62,5 MHz)")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    filas, radix = lee_csv(Path(sys.argv[1]))
    if not filas:
        print("captura vacía")
        return 1

    print(f"{len(filas)} muestras almacenadas")

    disparo = None
    for fila in filas:
        trigger = fila.get("TRIGGER") or fila.get("Trigger")
        if trigger and int(trigger, 10):
            disparo = fila
            break
    if disparo is None:
        print("AVISO: ninguna muestra marcada como disparo; se usa la última")
        disparo = filas[-1]

    d = decodifica(disparo, radix)
    imprime("muestra del disparo (cadena parada)", d)

    print()
    anterior = decodifica(filas[max(0, filas.index(disparo) - 1)], radix)
    imprime("última muestra con actividad antes del disparo", anterior)

    print()
    print("--- contraste con la predicción de P-21 ---")
    pred = d["s_vec_valid"] == 1 and d["s_vec_ready"] == 0 and d["ddr_mode"] == 0
    if pred:
        print("  SE CUMPLE: s_vec_valid=1, s_vec_ready=0, ddr_mode=0.")
        print("  El MM2S ofrece un beat que vector_source ya no puede aceptar")
        print("  porque el firmware bajó CTRL bit 1 con la pasada sin drenar.")
    elif d["s_vec_valid"] == 0:
        print("  REFUTADA: s_vec_valid=0 -- el DMA no está entregando nada.")
        print("  El atasco está aguas arriba de la PL (descriptores o SG).")
    elif d["s_vec_ready"] == 0 and d["ddr_mode"] == 1:
        print("  REFUTADA: ddr_mode sigue en 1 y vector_source no acepta.")
        print(f"  Mira vs_ready = {d.get('vs_ready', 0):#05b}: contrapresión del DDC.")
    else:
        print("  No encaja en ninguna de las lecturas previstas; ver la tabla")
        print("  de docs/implementacion/ila.md.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
