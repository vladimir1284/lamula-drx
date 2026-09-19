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

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "model"))

from drx_model import l1_vectors, vectors  # noqa: E402
from drx_model import params as params_mod  # noqa: E402

OUT_ROOT = ROOT / "build" / "vector-source-init"

#: Piso de profundidad del bucle. El valor real se redondea hacia arriba al
#: múltiplo de `if_norm.denominator` más cercano (ver `_loop_depth`), para que
#: el tono complete un número entero de periodos y no haya salto de fase al
#: envolver en `vector_source.sv`. El contenido en sí no importa para el cierre
#: de temporización (STA es estructural, no depende de los datos) — esto solo
#: deja bien planteada la fase de bring-up físico que viene después.
MIN_DEPTH = 4000

INIT_FILE = "vector_source_init.hex"


def _loop_depth(params: params_mod.Params) -> int:
    den = params.if_norm.denominator
    reps = -(-MIN_DEPTH // den)  # ceil sin importar float
    return reps * den


def generate(platform: str, out_root: Path = OUT_ROOT) -> Path:
    params = params_mod.load(platform)
    depth = _loop_depth(params)
    stimulus = vectors.tone(params, depth)

    directory = out_root / params.name
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / INIT_FILE
    l1_vectors._write_hex(path, stimulus, params.sample_bits)
    periods = depth // params.if_norm.denominator
    print(f"{platform}: {depth} muestras ({periods} periodos de IF) -> {path}")
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
