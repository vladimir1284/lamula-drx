#!/usr/bin/env python3
"""Cota de la salida del DDC para cualquier entrada acotada (P-22).

La cadena del modelo dorado es lineal salvo los redondeos, así que la salida
`I[k]` es `sum_j g[k][j] * x[j]`. Con `|x[j]| <= fs`, el máximo posible es
`fs * sum_j |g[k][j]|`, y se alcanza con `x[j] = fs * sign(g[k][j])`. Si esa
cota es menor que 1 (fondo de escala de salida), NINGÚN vector de estímulo
puede levantar `overflow`: no es cuestión de elegir otro vector.

`g` se mide con un impulso de fondo de escala en cada posición de entrada: una
pasada del modelo da la respuesta de todas las salidas a la vez. Se barren las
25 fases del NCO (`if_norm_den`), porque la cota depende de la fase.

Uso: python3 tools/bound_ddc_overflow.py [--platform zedboard]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "model"))

from drx_model import chain  # noqa: E402
from drx_model import params as params_mod  # noqa: E402

#: Entradas por salida que se dan por soporte de la respuesta. Holgado: el CIC
#: de 5 etapas y el FIR de droop caben de sobra.
_SOPORTE_SALIDAS = 60


def cota(params: params_mod.Params, mode: str) -> float:
    """Salida máxima posible de I, en fracciones de fondo de escala."""
    fs = (1 << (params.sample_bits - 1)) - 1
    r = chain.Ddc(params=params, mode=mode).decimation
    fases = int(params.invariant["if_norm_den"])
    primera = _SOPORTE_SALIDAS + 1
    ks = range(primera, primera + fases)
    n = (primera + fases + 2) * r
    g = np.zeros((fases, n))
    for j in range(n):
        x = np.zeros(n, dtype=np.int64)
        x[j] = fs
        out = chain.Ddc(params=params, mode=mode).process(x)
        for a, k in enumerate(ks):
            g[a, j] = out.i[k] / fs
    return float(np.abs(g).sum(axis=1).max())


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--platform", default="zedboard")
    args = ap.parse_args()
    params = params_mod.load(args.platform)
    saturable = False
    for mode in (chain.MODE_FINE, chain.MODE_COARSE):
        c = cota(params, mode)
        print(f"{mode:7s} salida maxima posible = {c:.4f} fs")
        saturable |= c >= 1.0
    print("overflow alcanzable por estimulo" if saturable else "overflow INALCANZABLE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
