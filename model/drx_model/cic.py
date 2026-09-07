"""CIC diezmador de Hogenauer, bit-exacto.

N integradores a `fs`, diezmado por R, N peines a `fs/R`, retardo diferencial M.
La aritmética es en complemento a dos con **desbordamiento intencionado** en los
integradores: es correcto siempre que el ancho de registro sea el de Hogenauer, y
reproducirlo es obligatorio porque el CIC Compiler de Xilinx hace exactamente eso.
Un modelo que usara precisión infinita daría otro resultado en los transitorios.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from drx_model import fixed


@dataclass(frozen=True)
class Cic:
    """CIC diezmador."""

    stages: int  # N
    rate: int  # R
    diff_delay: int = 1  # M
    in_bits: int = 16

    def __post_init__(self) -> None:
        if self.stages < 1 or self.rate < 1 or self.diff_delay < 1:
            raise ValueError("N, R y M tienen que ser >= 1")
        if self.register_bits > 63:
            raise ValueError(
                f"el ancho de registro del CIC ({self.register_bits} bits) no cabe "
                "en int64; el modelo tendría que pasar a enteros de Python"
            )

    @property
    def gain(self) -> int:
        """Ganancia en continua: (R·M)^N."""
        return (self.rate * self.diff_delay) ** self.stages

    @property
    def growth_bits(self) -> int:
        """Bits de crecimiento: ceil(N·log2(R·M))."""
        return math.ceil(self.stages * math.log2(self.rate * self.diff_delay))

    @property
    def register_bits(self) -> int:
        """Ancho de registro de Hogenauer: B_in + crecimiento."""
        return self.in_bits + self.growth_bits

    @property
    def pipeline_fill(self) -> int:
        """Muestras de relleno de tubería antes del primer resultado representativo.

        El CIC Compiler de Xilinx es una tubería real de N integradores + N
        peines, con latencia de silicio entre que entra una muestra y que su
        efecto llega al último peine — `process()`, en cambio, calculaba con
        latencia cero (recursión matemática instantánea). Medido contra la IP
        real en Z1 (xsim, caso `tono_if__fine`, cadena ya con el desfase de
        fase del NCO corregido): `rate - 1` muestras de relleno reproducen el
        transitorio real bit a bit, con el único residuo del artefacto de
        amplitud del NCO ya conocido (~1 LSB, ver `nco.py`).
        """
        return self.rate - 1

    def process(self, x: np.ndarray) -> np.ndarray:
        """Filtra y diezma. Devuelve enteros a `register_bits`, sin escalar.

        El escalado a la salida lo decide la cadena, no el CIC: dónde se recorta
        la ganancia (R·M)^N es una elección de arquitectura y tiene que ser
        visible, no implícita.
        """
        bits = self.register_bits
        fill = np.zeros(self.pipeline_fill, dtype=np.int64)
        acc = np.concatenate([fill, np.asarray(x, dtype=np.int64)])

        # Integradores. `cumsum` sobre int64 envuelve módulo 2**64, y como
        # 2**bits divide a 2**64, los `bits` bits bajos son los correctos: es la
        # misma aritmética que el registro del hardware.
        for _ in range(self.stages):
            acc = fixed.wrap(np.cumsum(acc), bits)

        # Diezmado.
        acc = acc[self.rate - 1 :: self.rate]

        # Peines.
        delay = self.diff_delay
        for _ in range(self.stages):
            delayed = np.concatenate([np.zeros(delay, dtype=np.int64), acc[:-delay]])
            acc = fixed.wrap(acc - delayed, bits)

        return acc

    def response(self, freqs: np.ndarray) -> np.ndarray:
        """Respuesta en amplitud normalizada, en frecuencia normalizada a fs.

        Se usa para diseñar el compensador de droop y para asertar la plantilla
        de banda de paso; no está en el camino de datos.
        """
        f = np.asarray(freqs, dtype=np.float64)
        rm = self.rate * self.diff_delay
        # |H(f)| = |sin(pi·f·R·M) / sin(pi·f)|^N. Se escribe con np.sinc para que
        # f = 0 no sea un caso especial: sin(pi·x) = pi·x·sinc(x), y el factor
        # R·M que queda es justamente la ganancia por etapa.
        h = (rm * np.sinc(f * rm) / np.sinc(f)) ** self.stages
        return np.abs(h) / self.gain
