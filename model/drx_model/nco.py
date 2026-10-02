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


@dataclass(frozen=True)
class NcoTaylor:
    """NCO con `Noise_Shaping {Taylor_Series_Corrected}` del DDS Compiler.

    A diferencia de `Nco` (modo `None`: fase truncada a `lut_addr_bits` y
    cuantizada contra una tabla fija de ese mismo tamaño), el DDS Compiler con
    Taylor resuelve `lut_addr_bits + delta_bits` bits de fase en vez de solo
    `lut_addr_bits` -- PG141 lo hace con una tabla gruesa más una corrección
    lineal, `sin(θ+Δ) ≈ sin(θ) + Δ·cos(θ)`, contra los bits que de otro modo
    se truncarían.

    Reconstruir esa aritmética interna (tabla + pendiente cuantizada, con su
    propio ancho y redondeo) se intentó y dejó más residuo del necesario --
    ver docs/alcance/pendientes.md#p-11, entrada del 9-sep-2026. La vía que sí
    cierra bien, confirmada contra IP real (`dds_compiler` v6.0, modo
    `SIN_COS_LUT_only`, sonda fuera del árbol, 11-sep-2026, misma referencia):
    tratar la fase como resuelta a `lut_addr_bits + delta_bits` bits sin más,
    y evaluar el seno/coseno continuo a esa resolución -- exactamente lo que
    hace `generate()` aquí. `delta_bits=9` es el valor confirmado contra la
    IP real para la configuración de este proyecto (`Output_Width` 16 y 18):
    el mismo core con `Noise_Shaping {None}` rechaza más de 16 bits totales de
    fase, y con Taylor acepta hasta 25 -- 16 + 9, no 16 + 16 como asumía sin
    comprobar el intento del 9-sep.

    NO es bit-exacto. El residuo contra la IP real, medido en el círculo
    completo de fase (6106 muestras dispersas, ambos anchos de salida), es de
    hasta ±2 LSB en el 25-55 % de las muestras según canal y ancho -- la misma
    escala de "el core calcula con un algoritmo propio que no coincide LSB a
    LSB" que P-10 ya documentó y aceptó para el modo `None`, no un límite
    propio de Taylor. `generate()` no es compatible con la comparación bit a
    bit de L1 (D-05) hasta que el proyecto decida aceptar ese mismo residuo
    para el bloque NCO -- ver P-11. Nada de esto está conectado hoy a
    `config/params.toml` ni a `Ddc`/`drx_ddc_top.sv`: es una clase nueva,
    independiente de `Nco`, que no cambia el comportamiento por defecto.
    """

    phase_bits: int
    phase_inc: int
    out_bits: int
    lut_addr_bits: int = 16
    delta_bits: int = 9
    #: Actuación AFC (Z4.5): a partir de la muestra `retune_at` el acumulador
    #: avanza con `retune_inc` en vez de con `phase_inc`. `None` (el valor por
    #: defecto) deja el NCO exactamente como antes -- esta clase es el oráculo
    #: de D-12 y no puede cambiar de comportamiento por añadir una opción.
    #:
    #: NO hay continuidad de fase en el salto, igual que en el hardware: el
    #: acumulador sigue desde donde estaba con el incremento nuevo. Esa es la
    #: razón de que el índice importe y de que `retune_at` no sea siempre 0 --
    #: el DDS Compiler aplica la configuración unos ciclos después de que se la
    #: escriban, y el modelo tiene que reproducir ese retardo para que la
    #: comparación bit a bit de L1 cierre.
    retune_at: int | None = None
    retune_inc: int | None = None

    @classmethod
    def from_params(
        cls,
        params: Params,
        lut_addr_bits: int = 16,
        delta_bits: int = 9,
        retune_at: int | None = None,
        retune_inc: int | None = None,
    ) -> NcoTaylor:
        return cls(
            phase_bits=int(params.invariant["nco_phase_bits"]),
            phase_inc=params.nco_phase_inc,
            out_bits=int(params.invariant["nco_out_bits"]),
            lut_addr_bits=lut_addr_bits,
            delta_bits=delta_bits,
            retune_at=retune_at,
            retune_inc=retune_inc,
        )

    def phase(self, n: int, initial: int = 0) -> np.ndarray:
        """Fase del acumulador para `n` muestras, envuelta a `phase_bits`."""
        mask = (1 << self.phase_bits) - 1
        idx = np.arange(n, dtype=np.int64)

        if self.retune_at is None:
            steps = initial + self.phase_inc * idx
        else:
            if self.retune_inc is None:
                raise ValueError("retune_at sin retune_inc")
            k = int(self.retune_at)
            antes = np.minimum(idx, k)
            despues = np.maximum(idx - k, 0)
            steps = initial + self.phase_inc * antes + self.retune_inc * despues

        return (steps & mask).astype(np.int64)

    def generate(self, n: int, initial: int = 0) -> tuple[np.ndarray, np.ndarray]:
        """`(cos, sin)` cuantizados, a la resolución que Taylor sí resuelve."""
        used_bits = self.lut_addr_bits + self.delta_bits
        shift = self.phase_bits - used_bits
        if shift < 0:
            raise ValueError("lut_addr_bits + delta_bits no puede superar phase_bits")
        resolved = self.phase(n, initial) >> shift
        angle = 2.0 * np.pi * resolved.astype(np.float64) / (1 << used_bits)
        _, high = fixed.limits(self.out_bits)
        cos = np.round(high * np.cos(angle)).astype(np.int64)
        sin = np.round(high * np.sin(angle)).astype(np.int64)
        return cos, sin
