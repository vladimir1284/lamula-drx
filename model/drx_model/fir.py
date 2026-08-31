"""FIR con coeficientes cuantizados y diezmado entero.

Los coeficientes son los que **realmente se cargan en la IP**: enteros con signo
de `coeff_bits`, congelados en `config/coeffs/` y leídos desde ahí. El modelo no
vuelve a diseñarlos en cada ejecución — si lo hiciera, una actualización de scipy
cambiaría el oráculo por debajo.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np

from drx_model import fixed

COEFF_DIR = Path(__file__).resolve().parents[2] / "config" / "coeffs"


def load_coeffs(name: str) -> np.ndarray:
    """Lee un juego de coeficientes congelado de `config/coeffs/<name>.txt`."""
    path = COEFF_DIR / f"{name}.txt"
    if not path.exists():
        raise FileNotFoundError(
            f"faltan los coeficientes {name!r}; genéralos con "
            "`python3 tools/gen_coeffs.py`"
        )
    values = [
        int(line.split("#", 1)[0])
        for line in path.read_text().splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    return np.asarray(values, dtype=np.int64)


@dataclass(frozen=True)
class Fir:
    """FIR diezmador de aritmética entera."""

    coeffs: np.ndarray
    decim: int = 1
    coeff_bits: int = 18

    @property
    def taps(self) -> int:
        return int(self.coeffs.size)

    @property
    def dc_gain(self) -> int:
        return int(np.sum(self.coeffs))

    def process(self, x: np.ndarray) -> np.ndarray:
        """Convolución entera y diezmado. Salida a precisión completa.

        Se usa `mode="full"` recortado al tamaño de la entrada, es decir el mismo
        arranque en frío que el hardware: las primeras `taps-1` salidas están
        contaminadas por el estado inicial a cero, igual que en la placa.
        """
        x = np.asarray(x, dtype=np.int64)
        acc = np.convolve(x, self.coeffs)[: x.size]
        return acc[self.decim - 1 :: self.decim]

    def response(self, freqs: np.ndarray) -> np.ndarray:
        """Respuesta en amplitud normalizada a la ganancia de continua."""
        f = np.asarray(freqs, dtype=np.float64)
        n = np.arange(self.taps)
        h = np.exp(-2j * np.pi * np.outer(f, n)) @ self.coeffs.astype(np.float64)
        return np.abs(h) / abs(self.dc_gain)


def quantize_coeffs(taps: np.ndarray, coeff_bits: int) -> np.ndarray:
    """Cuantiza coeficientes de coma flotante al entero con signo de la IP.

    Se escala por el mayor coeficiente en valor absoluto para usar todo el rango,
    que es lo que hace el FIR Compiler cuando se le dan coeficientes normalizados.
    """
    taps = np.asarray(taps, dtype=np.float64)
    peak = np.max(np.abs(taps))
    if peak == 0:
        raise ValueError("juego de coeficientes idénticamente nulo")
    _, high = fixed.limits(coeff_bits)
    scaled = np.round(taps / peak * high)
    out, overflow = fixed.saturate(scaled, coeff_bits)
    if overflow.any():
        raise ValueError("la cuantización de coeficientes saturó: revisa el escalado")
    return out
