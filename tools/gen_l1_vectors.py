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

import numpy as np

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


#: Parámetros de las degradaciones inyectadas, iguales a los que ya usan los
#: tests del modelo dorado (model/tests/test_chain.py,
#: model/tests/test_gating_y_vectores.py) para que L1 caracterice exactamente
#: lo que L0 ya caracteriza, contra la IP real en vez de contra el modelo solo.
_RUIDO_SNR_DB = 10.0
_OFFSET_DC_DBFS = -12.0
_DESBALANCE_GANANCIA_DB = 1.0
_DESBALANCE_FASE_DEG = 3.0
_SOBRE_ESCALA_DBFS = 6.0


def _cases(
    params: params_mod.Params, n_samples: int = N_SAMPLES
) -> dict[str, object]:
    """Los casos de L1, por nombre.

    El conjunto es deliberadamente pequeño: L1 no es la suite funcional —esa es
    L0 y el modelo— sino la prueba de que la IP real de Xilinx da el mismo bit
    que el modelo. Cada caso ataca una parte distinta de la aritmética.

    `n_samples` es parámetro desde Z4.3 (1-oct-2026) y no una constante: esta
    MISMA lista, en este MISMO orden, es el catálogo de estímulos que el
    firmware carga por AXI DMA MM2S (`tools/gen_stimulus_catalog.py`), y el
    contrato la nombra en la enumeración `stimulus_vector` (v0.5). Lo que
    cambia entre un uso y otro es solo la longitud: L1 necesita 65536 muestras
    para alcanzar régimen permanente en modo grueso, y el catálogo de la placa
    necesita un bucle corto. Duplicar la lista para cambiar un número habría
    sido la forma segura de que las dos copias divergieran sin que nadie se
    enterase; `contract/tests/test_contract.py` comprueba que no diverge del
    esquema.
    """
    N_SAMPLES = n_samples  # noqa: N806 -- sombra deliberada, ver el docstring
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
        # Degradaciones del frontal analógico (D9, registro delta de
        # portabilidad): desde Z1 el DDC tiene que caracterizarse bajo estas
        # condiciones contra la IP real, no solo contra el modelo. Cada una
        # parte de un tono ya cubierto arriba y le añade una sola degradación,
        # para no mezclar dos efectos en la misma comparación bit a bit.
        "tono_con_ruido": vectors.add_noise(
            vectors.tone(params, N_SAMPLES),
            snr_db=_RUIDO_SNR_DB,
            params=params,
            seed=SEED,
        ),
        "tono_con_offset_dc": vectors.add_dc_offset(
            vectors.tone(params, N_SAMPLES, dbfs=-6.0),
            dbfs=_OFFSET_DC_DBFS,
            params=params,
        ),
        # Desbalance I/Q de un frontal en cuadratura, aplicado en banda base
        # antes de subir a IF (ver el docstring de vectors.modulated_tone).
        # freq_norm=0.001 de desplazamiento en banda base, para quedar dentro
        # de la banda de paso de la cadena de diezmado — el mismo desplazamiento
        # que ya usa "tono_desplazado", no el 0,01 del test de vectors.py (ese
        # prueba solo la función, no la cadena: 0,01 cae fuera de la banda de
        # paso y el DDC lo deja en cero, verificado antes de fijar este valor).
        "tono_desbalanceado": vectors.modulated_tone(
            params,
            N_SAMPLES,
            baseband_norm=0.001,
            gain_imbalance_db=_DESBALANCE_GANANCIA_DB,
            phase_imbalance_deg=_DESBALANCE_FASE_DEG,
        ),
        # Entrada sobre-escala: el ADC real satura, no envuelve. Ejercita el
        # reporte de overflow de principio a fin de la cadena, no solo en
        # `fixed.saturate` (ya cubierto en model/tests).
        "tono_sobre_escala": vectors.tone(params, N_SAMPLES, dbfs=_SOBRE_ESCALA_DBFS),
    }


#: Desplazamiento de frecuencia del caso de AFC, en frecuencia normalizada. Es
#: deliberadamente grande comparado con `tono_desplazado` (0,001): lo que se
#: comprueba aquí no es la respuesta del filtro sino que el NCO de verdad mezcla
#: con la palabra de fase NUEVA, y un desplazamiento pequeño se confundiría con
#: el residuo de cuantización que D-12 ya acepta.
_AFC_FREQ_OFFSET = 0.01

#: Muestra del NCO a partir de la cual el modelo usa el incremento nuevo.
#:
#: HIPÓTESIS, no medida todavía (2-oct-2026): el testbench escribe NCO_PINC
#: nada más soltar el reset, `drx_ddc_top` retiene la escritura hasta que su
#: estirador de reset suelta la IP, y el core tarda `Latency` = 9 ciclos en dar
#: su primera salida -- así que la configuración debería estar aplicada antes de
#: la muestra 0. Si la primera corrida de este caso falla, el camino es medir el
#: desfase real barriendo `k` CONTRA LA MISMA salida del RTL (una sola
#: simulación, barrido offline en Python), exactamente como se calibró
#: `NCO_LUT_OFFSET_K` en `tcl/gen_ip.tcl`. No se ajusta el modelo para que pase:
#: se mide el hardware y se escribe el número medido aquí.
_AFC_RETUNE_AT = 0


def _afc_case(
    params: params_mod.Params, n_samples: int = N_SAMPLES
) -> tuple[np.ndarray, tuple[int, int]]:
    """Estímulo y retune del caso de actuación AFC (Z4.5).

    El tono está a `if_norm + _AFC_FREQ_OFFSET` y la palabra de fase es la de
    ESE tono, así que la salida vuelve a caer en continua. Esa redundancia es a
    propósito: la comparación bit a bit contra el modelo es el gate, pero "el
    pico tiene que estar en continua" es una comprobación que también se puede
    hacer en placa con `tools/dump_ray.py`, sin oráculo de por medio.

    Vive FUERA de `_cases` a propósito: esa lista es también el catálogo de
    estímulos que el firmware carga por DMA y que el contrato nombra en la
    enumeración `stimulus_vector`, y añadir un caso ahí cambiaría las dos cosas.
    """
    freq = float(params.if_norm) + _AFC_FREQ_OFFSET
    stimulus = vectors.tone(params, n_samples, freq_norm=freq)
    pinc = round(freq * (1 << int(params.invariant["nco_phase_bits"])))
    return stimulus, (_AFC_RETUNE_AT, int(pinc))


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
        stimulus, retune = _afc_case(params)
        out.append(
            l1_vectors.export_case(
                params=params,
                name=f"afc_retune__{mode}",
                stimulus=stimulus,
                out_root=out_root,
                mode=mode,
                nco_retune=retune,
            )
        )
    return out


def check(platform: str, out_root: Path = OUT_ROOT) -> list[str]:
    """Devuelve los problemas encontrados; lista vacía significa al día."""
    problems: list[str] = []
    params = params_mod.load(platform)
    for mode in (chain.MODE_FINE, chain.MODE_COARSE):
        for name in list(_cases(params)) + ["afc_retune"]:
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
