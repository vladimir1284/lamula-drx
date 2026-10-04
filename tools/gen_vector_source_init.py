#!/usr/bin/env python3
"""Genera el `.hex` de precarga de `rtl/vector_source.sv` (BRAM-loop).

Distinto de `tools/gen_l1_vectors.py`: aquel dimensiona el estímulo para que
una simulación L1 alcance régimen permanente (65536 muestras); este dimensiona
un bucle corto y sin discontinuidad de fase al envolver, porque lo que va a
BRAM real se repite indefinidamente en hardware, no se reproduce una vez.

Reutiliza `model/drx_model/vectors.tone()` (el mismo generador que ya usa
`gen_l1_vectors.py`) y `model/drx_model/l1_vectors.to_hex_lines()` (el mismo
formato `$readmemh` que ya usa L1) — no se reinventa ni la matemática del tono
ni la codificación hexadecimal.

    python3 tools/gen_vector_source_init.py                 # todas las plataformas
    python3 tools/gen_vector_source_init.py --platform zedboard

La salida va a `build/vector-source-init/`, directorio de build no versionado:
se regenera, no se guarda — igual que `build/l1-vectors/`.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "model"))

from drx_model import l1_vectors, vectors  # noqa: E402
from drx_model import params as params_mod  # noqa: E402

OUT_ROOT = ROOT / "build" / "vector-source-init"

INIT_FILE = "vector_source_init.hex"


def _loop_depth(params: params_mod.Params) -> int:
    """Longitud del bucle, de `config/params.toml`.

    Hasta el 4-oct-2026 esto era un `MIN_DEPTH = 4000` local redondeado al
    múltiplo de `if_norm.denominator` más cercano. Ahora el número vive en
    `config/params.toml` como `vector_loop_len` porque lo consumen también el
    RTL (valor de reset de VEC_LEN, mapa v11) y el firmware (cuántas
    escrituras hace una carga), y `tools/gen_params.py` es quien comprueba
    que sea múltiplo del denominador y que quepa en la BRAM.
    """
    return params.vector_loop_len


def generate(platform: str, out_root: Path = OUT_ROOT) -> Path:
    params = params_mod.load(platform)
    loop = _loop_depth(params)
    depth = params.vector_bram_depth
    stimulus = vectors.tone(params, loop)

    # El fichero tiene `depth` líneas, no `loop`: el array de
    # `rtl/vector_source.sv` es de la profundidad FÍSICA del banco, y un
    # `$readmemh` más corto deja el resto del array indefinido -- X en xsim,
    # ruido en lint, y palabras que un VEC_LEN cargado en caliente sí podría
    # llegar a leer. Las posiciones por encima del bucle van a cero: nunca se
    # leen con el VEC_LEN de reset, y si alguien amplía el bucle sin cargar
    # nada se oye silencio, que es un síntoma inequívoco.
    padded = np.zeros(depth, dtype=stimulus.dtype)
    padded[:loop] = stimulus

    directory = out_root / params.name
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / INIT_FILE
    l1_vectors._write_hex(path, padded, params.sample_bits)
    periods = loop // params.if_norm.denominator
    print(
        f"{platform}: {loop} muestras de tono ({periods} periodos de IF) "
        f"+ {depth - loop} de relleno = {depth} -> {path}"
    )
    return path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["zedboard", "zu9"], default=None)
    args = parser.parse_args(argv)

    platforms = [args.platform] if args.platform else ["zedboard", "zu9"]
    for platform in platforms:
        generate(platform)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
