#!/usr/bin/env python3
"""Genera los vectores del nivel L1 desde el modelo dorado.

L1 valida la cadena DDC construida con IP de Xilinx, que Verilator no puede
elaborar. Como cocotb no habla con xsim (P-09), el oráculo cruza a fichero: este
script escribe estímulo y salida esperada, y `sim/tb_sv/tb_l1_ddc.sv` los lee.

    python3 tools/gen_l1_vectors.py                 # todas las plataformas
    python3 tools/gen_l1_vectors.py --platform zu9
    python3 tools/gen_l1_vectors.py --check         # gate: ¿están al día?

La salida va a `build/l1-vectors/`, que es directorio de build y no se versiona:
los vectores se regeneran, no se guardan. Lo que se versiona es este generador,
que es lo que los hace reproducibles.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "model"))

from drx_model import chain, l1_vectors, vectors  # noqa: E402
from drx_model import params as params_mod  # noqa: E402

OUT_ROOT = ROOT / "build" / "l1-vectors"

#: Longitud del estímulo, en muestras de entrada. Suficiente para pasar el
#: transitorio de la cadena y dejar salida en régimen permanente en modo grueso,
#: que es el que más diezma.
N_SAMPLES = 65536

#: Semilla única para todo el conjunto. Un oráculo que cambia entre ejecuciones
#: no es un oráculo (ver la nota de determinismo en drx_model.vectors).
SEED = 20260830


def _cases(params: params_mod.Params) -> dict[str, object]:
    """Los casos de L1, por nombre.

    El conjunto es deliberadamente pequeño: L1 no es la suite funcional —esa es
    L0 y el modelo— sino la prueba de que la IP real de Xilinx da el mismo bit
    que el modelo. Cada caso ataca una parte distinta de la aritmética.
    """
    return {
        # El caso base: el IF nominal, que es lo que el NCO tiene que llevar a
        # continua exactamente.
        "tono_if": vectors.tone(params, N_SAMPLES),
        # Desplazado dentro de la banda de paso: ejercita el FIR fuera de
        # continua, donde un error de coeficiente sí se ve.
        "tono_desplazado": vectors.tone(
            params, N_SAMPLES, freq_norm=float(params.if_norm) + 0.001
        ),
        # Dos tonos: rechazo de imagen e intermodulación del mezclador complejo.
        "dos_tonos": vectors.two_tone(
            params,
            N_SAMPLES,
            freq_norm_a=float(params.if_norm) - 0.0008,
            freq_norm_b=float(params.if_norm) + 0.0008,
        ),
        # Simétrico de "tono_desplazado" al otro lado del IF. No ataca una
        # aritmética nueva — existe para que tb_l1_ddc_quad.sv tenga un cuarto
        # estímulo distinto de los otros tres y así un canal del `generate`
        # de drx_ddc_quad_top.sv que lea el estímulo de otro canal se vea como
        # discrepancia en vez de colar por casualidad de datos iguales.
        "tono_desplazado_neg": vectors.tone(
            params, N_SAMPLES, freq_norm=float(params.if_norm) - 0.001
        ),
    }


def generate(platform: str, out_root: Path = OUT_ROOT) -> list[l1_vectors.L1Case]:
    params = params_mod.load(platform)
    out: list[l1_vectors.L1Case] = []
    for mode in (chain.MODE_FINE, chain.MODE_COARSE):
        for name, stimulus in _cases(params).items():
            out.append(
                l1_vectors.export_case(
                    params=params,
                    name=f"{name}__{mode}",
                    stimulus=stimulus,
                    out_root=out_root,
                    mode=mode,
                )
            )
    return out


def check(platform: str, out_root: Path = OUT_ROOT) -> list[str]:
    """Devuelve los problemas encontrados; lista vacía significa al día."""
    problems: list[str] = []
    params = params_mod.load(platform)
    for mode in (chain.MODE_FINE, chain.MODE_COARSE):
        for name in _cases(params):
            directory = out_root / platform / f"{name}__{mode}"
            if not (directory / l1_vectors.MANIFEST_FILE).exists():
                problems.append(f"falta {directory}")
                continue
            try:
                l1_vectors.load_manifest(directory)
            except ValueError as exc:
                problems.append(str(exc))
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--platform",
        action="append",
        help="plataforma a generar; por defecto todas las de config/params.toml",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="no escribe nada: falla si los vectores faltan o están caducados",
    )
    args = parser.parse_args(argv)

    platforms = args.platform or sorted(params_mod.load_all())

    if args.check:
        problems = [p for platform in platforms for p in check(platform)]
        for problem in problems:
            print(f"vectores L1 no están al día: {problem}", file=sys.stderr)
        return 1 if problems else 0

    for platform in platforms:
        for case in generate(platform):
            print(f"{case.directory.relative_to(ROOT)}  n={case.manifest['n_expected']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
