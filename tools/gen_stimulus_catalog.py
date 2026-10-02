#!/usr/bin/env python3
"""Genera el catálogo de estímulos que el firmware carga en la PL (Z4.3).

Qué es: los OCHO casos de `tools/gen_l1_vectors.py` —la misma lista, en el
mismo orden, importada de ahí y no copiada— volcados a un `.c` de arrays
`int16_t` que `drx_app` compila dentro de su imagen. El firmware los copia a un
buffer de DDR y se los entrega a `rtl/vector_source.sv` por AXI DMA MM2S, en el
modo Throttled(DDR) que Z4.3 añadió. El par remoto elige cuál con el mensaje
`test_stimulus_select` del contrato (v0.5), cuyo `vector_id` es el índice en
esta misma lista.

Por qué esto y no leerlos de una SD: no hay pila FAT en el firmware y montarla
para ocho vectores de 4000 muestras sería construir un subsistema entero para
mover 64 KiB que caben de sobra en la imagen. Cuando el catálogo necesite ser
grande o cambiable sin recompilar, ese será el momento de la SD.

Distinto de los otros dos generadores de vectores, y conviene no confundirlos:

  * `gen_l1_vectors.py` dimensiona para que una simulación L1 llegue a régimen
    permanente (65536 muestras) y escribe ficheros que lee un testbench.
  * `gen_vector_source_init.py` escribe el `$readmemh` que queda FIJO en el
    bitstream (modo BRAM-loop).
  * este escribe C que viaja en la imagen del firmware y se elige en tiempo de
    ejecución.

La longitud es la misma que la del bucle de BRAM (`MIN_DEPTH` redondeado al
múltiplo de `if_norm.denominator`): el vector se reproduce en bucle rearmando
el DMA, así que tiene que cerrar sin salto de fase exactamente por el mismo
motivo que el de la BRAM.

    python3 tools/gen_stimulus_catalog.py                 # todas las plataformas
    python3 tools/gen_stimulus_catalog.py --platform zedboard

La salida va a `build/fw/stimulus/<plataforma>/`, directorio de build no
versionado: se regenera, no se guarda — igual que `build/l1-vectors/` y
`build/vector-source-init/`. `tools/build_vitis.sh` lo invoca antes de llamar a
`xsct`, y `tcl/gen_bsp.tcl` copia el resultado al proyecto de Vitis.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "model"))
sys.path.insert(0, str(ROOT / "tools"))

import gen_l1_vectors  # noqa: E402
import gen_vector_source_init  # noqa: E402
from drx_model import params as params_mod  # noqa: E402

OUT_ROOT = ROOT / "build" / "fw" / "stimulus"

C_NAME = "drx_stimulus_catalog.c"
H_NAME = "drx_stimulus_catalog.h"

#: Muestras por línea del `.c`. Doce entra de sobra en 100 columnas con valores
#: de hasta seis caracteres, y mantiene el fichero legible en una revisión.
PER_LINE = 12


def _samples(params: params_mod.Params) -> dict[str, np.ndarray]:
    depth = gen_vector_source_init._loop_depth(params)
    return gen_l1_vectors._cases(params, depth)


def _to_int16(values: np.ndarray, sample_bits: int) -> np.ndarray:
    """Recorta a la rejilla del ADC, igual que hace el volcado hexadecimal de L1.

    Los vectores del modelo son enteros ya saturados a `sample_bits` (ver
    `drx_model.vectors`), así que esto no debería recortar nada — se comprueba
    en vez de suponerlo, porque un vector fuera de rango no produciría un error
    sino muestras envueltas, que en la placa se ven como un espectro raro sin
    ninguna pista de dónde viene.
    """
    arr = np.asarray(values).astype(np.int64)
    low = -(1 << (sample_bits - 1))
    high = (1 << (sample_bits - 1)) - 1
    if arr.min() < low or arr.max() > high:
        raise SystemExit(
            f"vector fuera del rango de {sample_bits} bits: "
            f"[{arr.min()}, {arr.max()}] no cabe en [{low}, {high}]"
        )
    return arr.astype(np.int16)


def _render_header(names: list[str], depth: int, platform: str) -> str:
    out = [
        "/* GENERADO por tools/gen_stimulus_catalog.py para la plataforma",
        f" * {platform}. NO EDITAR A MANO: se regenera en cada build de Vitis.",
        " *",
        " * Catalogo v1 de estimulos: los ocho casos de tools/gen_l1_vectors.py,",
        " * en el mismo orden que la enumeracion `stimulus_vector` del contrato",
        " * DRx<->DSP v0.5. El `vector_id` del mensaje `test_stimulus_select` es",
        " * el indice en este array.",
        " */",
        "",
        "#ifndef DRX_STIMULUS_CATALOG_H",
        "#define DRX_STIMULUS_CATALOG_H",
        "",
        "#include <stddef.h>",
        "#include <stdint.h>",
        "",
        f"#define DRX_STIMULUS_COUNT {len(names)}u",
        f"#define DRX_STIMULUS_DEPTH {depth}u",
        "",
        "typedef struct {",
        "    const char *name;",
        "    const int16_t *samples;  /* DRX_STIMULUS_DEPTH muestras, un solo canal */",
        "    size_t count;",
        "} DrxStimulusVector;",
        "",
        "/* Indexado por `vector_id`. Un solo canal por vector: la replicacion a",
        " * los N_CH canales la hace el firmware al montar el buffer de DDR, igual",
        " * que el modo BRAM-loop replica el mismo INIT_FILE en los N_CH bancos. */",
        "extern const DrxStimulusVector kDrxStimulusCatalog[DRX_STIMULUS_COUNT];",
        "",
        "#endif /* DRX_STIMULUS_CATALOG_H */",
        "",
    ]
    return "\n".join(out)


def _render_source(cases: dict[str, np.ndarray], sample_bits: int, platform: str) -> str:
    out = [
        "/* GENERADO por tools/gen_stimulus_catalog.py para la plataforma",
        f" * {platform}. NO EDITAR A MANO. Ver drx_stimulus_catalog.h. */",
        "",
        '#include "drx_stimulus_catalog.h"',
        "",
    ]
    for name, values in cases.items():
        arr = _to_int16(values, sample_bits)
        out.append(f"static const int16_t k_{name}[] = {{")
        for start in range(0, len(arr), PER_LINE):
            chunk = ", ".join(str(int(v)) for v in arr[start : start + PER_LINE])
            out.append(f"    {chunk},")
        out.append("};")
        out.append("")

    out.append("const DrxStimulusVector kDrxStimulusCatalog[DRX_STIMULUS_COUNT] = {")
    for name in cases:
        out.append(
            f'    {{ "{name}", k_{name}, sizeof(k_{name}) / sizeof(k_{name}[0]) }},'
        )
    out.append("};")
    out.append("")
    return "\n".join(out)


def generate(platform: str, out_root: Path = OUT_ROOT) -> Path:
    params = params_mod.load(platform)
    cases = _samples(params)
    depth = gen_vector_source_init._loop_depth(params)

    directory = out_root / params.name
    directory.mkdir(parents=True, exist_ok=True)

    (directory / H_NAME).write_text(
        _render_header(list(cases), depth, params.name), encoding="utf-8"
    )
    (directory / C_NAME).write_text(
        _render_source(cases, params.sample_bits, params.name), encoding="utf-8"
    )

    total = len(cases) * depth * 2
    print(
        f"{platform}: {len(cases)} vectores x {depth} muestras "
        f"({total // 1024} KiB) -> {directory}"
    )
    return directory


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["zedboard", "zu9"], default=None)
    args = parser.parse_args(argv)

    for platform in [args.platform] if args.platform else ["zedboard", "zu9"]:
        generate(platform)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
