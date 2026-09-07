"""NCO: acumulador de fase con truncamiento, como el DDS Compiler.

Reproduce el modo de **truncamiento de fase** del DDS Compiler de Xilinx: el
acumulador tiene `phase_bits`, la LUT se direcciona con los `lut_addr_bits` más
significativos, y la salida se cuantiza a `out_bits`. El error de truncamiento de
fase produce espurios en un sitio concreto y determinista, y el modelo tiene que
producirlos en el mismo sitio que la IP o la comparación bit a bit no cierra.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from drx_model import fixed
from drx_model.params import Params


@dataclass(frozen=True)
class Nco:
    """NCO cuantizado.

    `phase_inc` es el incremento por muestra sobre `phase_bits`. Es INVARIANTE
    entre ZedBoard y ZU9 (D-02): la frecuencia normalizada es la misma, así que
    la palabra de fase es la misma. Ese es el punto entero de la dilatación.
    """

    phase_bits: int
    phase_inc: int
    out_bits: int
    lut_addr_bits: int = 16

    @classmethod
    def from_params(cls, params: Params, lut_addr_bits: int = 16) -> Nco:
        return cls(
            phase_bits=int(params.invariant["nco_phase_bits"]),
            phase_inc=params.nco_phase_inc,
            out_bits=int(params.invariant["nco_out_bits"]),
            lut_addr_bits=lut_addr_bits,
        )

    def phase(self, n: int, initial: int = 0) -> np.ndarray:
        """Fase del acumulador para `n` muestras, envuelta a `phase_bits`."""
        mask = (1 << self.phase_bits) - 1
        steps = initial + self.phase_inc * np.arange(n, dtype=np.int64)
        return (steps & mask).astype(np.int64)

    def lut(self) -> tuple[np.ndarray, np.ndarray]:
        """Tablas de coseno y seno cuantizadas a `out_bits`.

        Pico en el máximo estándar de complemento a dos (`fixed.limits()`),
        `2**(out_bits-1) - 1` -- confirmado exacto contra la IP real: la
        medición documentada en `tcl/gen_ip.tcl` (`LUT[656] = (32702, 2059)`,
        búsqueda inversa contra el arranque real del Phase Generator) solo
        sale con este pico, no con `2**(out_bits-1) - 2` (el target de
        `Amplitude_Mode {Full_Range}` de pg141 -- probado y descartado en
        P-10: da (32701, 2059), mal por 1 en el coseno).
        """
        size = 1 << self.lut_addr_bits
        _, high = fixed.limits(self.out_bits)
        angle = 2.0 * np.pi * np.arange(size) / size
        cos_lut = np.round(high * np.cos(angle)).astype(np.int64)
        sin_lut = np.round(high * np.sin(angle)).astype(np.int64)
        return cos_lut, sin_lut

    def generate(self, n: int, initial: int = 0) -> tuple[np.ndarray, np.ndarray]:
        """`(cos, sin)` cuantizados, con truncamiento de fase a la LUT."""
        shift = self.phase_bits - self.lut_addr_bits
        if shift < 0:
            raise ValueError("lut_addr_bits no puede superar phase_bits")
        addr = self.phase(n, initial) >> shift
        cos_lut, sin_lut = self.lut()
        return cos_lut[addr], sin_lut[addr]
