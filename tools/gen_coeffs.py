#!/usr/bin/env python3
"""Diseña y congela los coeficientes del FIR de la cadena DDC.

El FIR hace dos cosas a la vez: compensa el droop del CIC en la banda de paso y
antialiasa el diezmado final ÷4. Los coeficientes se **congelan** en
`config/coeffs/` porque son los que se cargan en el FIR Compiler, y porque el
modelo dorado no puede cambiar de resultado si mañana se actualiza scipy.

Uso:
    python3 tools/gen_coeffs.py            # rediseña y escribe
    python3 tools/gen_coeffs.py --check    # falla si el fichero no coincide
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from scipy.signal import firwin2

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "model"))

from drx_model.cic import Cic  # noqa: E402
from drx_model.fir import quantize_coeffs  # noqa: E402
from drx_model.params import load  # noqa: E402

OUT_DIR = ROOT / "config" / "coeffs"
NAME = "droop_decim_fir"
HALFBAND_NAME = "halfband_decim2"

#: Taps del semibanda de la etapa ÷2 del modo grueso. Z1 confirma el número
#: contra el cierre de recursos; el modelo y el RTL leen el mismo fichero.
HALFBAND_TAPS = 23

#: Bordes del semibanda, normalizados a SU frecuencia de entrada (fs/R1). El
#: modo grueso se queda con la mitad del ancho de banda del fino: esa es la
#: contrapartida de la celda del doble de tamaño.
HALFBAND_PASSBAND_EDGE = 0.15
HALFBAND_STOPBAND_EDGE = 0.25

#: Bordes de banda, normalizados a la frecuencia de muestreo de ENTRADA del FIR
#: (es decir fs/R_cic).
#:
#: Lo que hay que atenuar no es «todo lo que pase de Nyquist/4»: es lo que pliega
#: SOBRE la banda de paso al diezmar por 4, es decir a partir de 0,25 - 0,09 =
#: 0,16. Poner el borde de banda eliminada en 0,125 exige una transición que 63
#: taps no dan y deja el alias real en -23 dB; ponerlo en 0,14 deja la banda que
#: pliega por debajo de -58 dB con los mismos taps.
PASSBAND_EDGE = 0.090
STOPBAND_EDGE = 0.140
#: Primera frecuencia que pliega sobre la banda de paso tras el diezmado ÷4.
ALIAS_BAND_START = 0.250 - PASSBAND_EDGE

COEFF_BITS = 18  # ancho de coeficiente del FIR Compiler sobre DSP48


def design(params) -> tuple[np.ndarray, np.ndarray]:
    """Devuelve `(coeficientes_float, coeficientes_enteros)`."""
    chain = params.chain
    cic = Cic(
        stages=int(chain["cic_stages"]),
        rate=int(chain["cic_rate"]),
        diff_delay=int(chain["cic_diff_delay"]),
        in_bits=params.sample_bits,
    )
    taps = int(chain["fir_taps"])

    # Rejilla de diseño en frecuencia normalizada a la entrada del FIR.
    grid = np.linspace(0.0, 0.5, 1024)
    desired = np.zeros_like(grid)

    # Banda de paso: el inverso del droop del CIC. La frecuencia del CIC está
    # normalizada a fs, así que hay que dividir por su factor de diezmado.
    passband = grid <= PASSBAND_EDGE
    droop = cic.response(grid[passband] / cic.rate)
    desired[passband] = droop[0] / droop  # 1 en continua, sube donde el CIC cae

    # Transición: bajada suave hasta el borde de banda eliminada.
    transition = (grid > PASSBAND_EDGE) & (grid < STOPBAND_EDGE)
    if transition.any():
        span = (grid[transition] - PASSBAND_EDGE) / (STOPBAND_EDGE - PASSBAND_EDGE)
        desired[transition] = desired[passband][-1] * (1.0 - span)

    # `firwin2` necesita la rejilla normalizada a Nyquist, no a fs.
    float_taps = firwin2(taps, grid * 2.0, desired, window="hamming")
    return float_taps, quantize_coeffs(float_taps, COEFF_BITS)


def design_halfband() -> tuple[np.ndarray, np.ndarray]:
    """Semibanda de la etapa ÷2 que convierte el modo fino en el modo grueso.

    D-04 mantiene R2 = 2·R1 justamente para que esto sea una etapa añadida y no
    una segunda cadena. Bordes normalizados a la fs de entrada de la etapa.
    """
    grid = np.linspace(0.0, 0.5, 1024)
    desired = np.zeros_like(grid)
    desired[grid <= HALFBAND_PASSBAND_EDGE] = 1.0
    transition = (grid > HALFBAND_PASSBAND_EDGE) & (grid < HALFBAND_STOPBAND_EDGE)
    span = (grid[transition] - HALFBAND_PASSBAND_EDGE) / (
        HALFBAND_STOPBAND_EDGE - HALFBAND_PASSBAND_EDGE
    )
    desired[transition] = 1.0 - span
    float_taps = firwin2(HALFBAND_TAPS, grid * 2.0, desired, window="hamming")
    return float_taps, quantize_coeffs(float_taps, COEFF_BITS)


def render_halfband(float_taps: np.ndarray, int_taps: np.ndarray) -> str:
    lines = [
        "# GENERADO por tools/gen_coeffs.py. NO EDITAR A MANO.",
        "#",
        "# Semibanda de la etapa ÷2 del modo grueso (250 m). Es lo que hace que",
        "# R2 = 2·R1 sea una etapa añadida y no una segunda cadena de diezmado.",
        "#",
        f"# taps={HALFBAND_TAPS} decim=2 coeff_bits={COEFF_BITS}",
        f"# Bandas (norm. a fs/R1): paso<={HALFBAND_PASSBAND_EDGE} "
        f"eliminada>={HALFBAND_STOPBAND_EDGE} alias>={0.5 - HALFBAND_PASSBAND_EDGE:.2f}",
        "# Rizado de banda de paso ~1,2 dB en el borde: aceptable para Z0, lo afina",
        "# Z1 contra el cierre de recursos del FIR Compiler.",
        f"# Ganancia de continua entera: {int(np.sum(int_taps))}",
        "",
    ]
    lines += [str(int(v)) for v in int_taps]
    return "\n".join(lines) + "\n"


def render(params, float_taps: np.ndarray, int_taps: np.ndarray) -> str:
    chain = params.chain
    peak_float = float(np.max(np.abs(float_taps)))
    lines = [
        "# GENERADO por tools/gen_coeffs.py. NO EDITAR A MANO.",
        "#",
        "# FIR compensador de droop del CIC + antialias del diezmado final.",
        "# Estos son los coeficientes que se cargan en el FIR Compiler y los que",
        "# usa el modelo dorado: un solo juego, o el oráculo deja de serlo.",
        "#",
        f"# CIC: N={chain['cic_stages']} R={chain['cic_rate']} M={chain['cic_diff_delay']}",
        f"# FIR: taps={chain['fir_taps']} decim={chain['fir_decim']} coeff_bits={COEFF_BITS}",
        f"# Bandas (norm. a la fs de entrada del FIR): paso<={PASSBAND_EDGE} "
        f"eliminada>={STOPBAND_EDGE} alias>={ALIAS_BAND_START:.3f}",
        f"# Escala de cuantización: pico float={peak_float:.9e}",
        f"# Ganancia de continua entera: {int(np.sum(int_taps))}",
        "",
    ]
    lines += [str(int(v)) for v in int_taps]
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    params = load("zedboard")  # los coeficientes son invariantes de plataforma
    float_taps, int_taps = design(params)
    hb_float, hb_int = design_halfband()
    outputs = {
        OUT_DIR / f"{NAME}.txt": render(params, float_taps, int_taps),
        OUT_DIR / f"{HALFBAND_NAME}.txt": render_halfband(hb_float, hb_int),
    }

    if args.check:
        stale = [p for p, text in outputs.items() if not p.exists() or p.read_text() != text]
        if stale:
            for p in stale:
                print(f"DESACTUALIZADO: {p.relative_to(ROOT)}", file=sys.stderr)
            print("Ejecuta: python3 tools/gen_coeffs.py", file=sys.stderr)
            return 1
        print("coeficientes al día")
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for p, text in outputs.items():
        p.write_text(text)
        print(f"escrito {p.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
