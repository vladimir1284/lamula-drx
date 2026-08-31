"""Cadena DDC completa, bit-exacta: NCO → mixer → CIC → FIR → escalado.

Este es el oráculo del proyecto (D-03). Toda salida del DDC del RTL se compara
**bit a bit** contra lo que produce esta función. Si discrepan, hay un bug en uno
de los dos — no se ajusta este modelo para que el test pase.

Aviso de fase Z0
----------------
La cadena está modelada contra la configuración *pretendida* de la IP de Xilinx
(DDS/CIC/FIR Compiler), no contra la IP real: en Z0 no hay Vivado ni IP generada.
La correspondencia bit a bit modelo↔IP se establece en Z1, y es ahí donde este
fichero puede necesitar ajustes de redondeo. Hasta entonces el modelo es
autoconsistente y determinista, que es lo que Z0 promete.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from drx_model import fir as fir_mod
from drx_model import fixed
from drx_model.cic import Cic
from drx_model.nco import Nco
from drx_model.params import Params

MODE_FINE = "fine"
MODE_COARSE = "coarse"


@dataclass
class DdcResult:
    """Salida del DDC más lo que hay que reportar sobre ella."""

    i: np.ndarray
    q: np.ndarray
    overflow: np.ndarray
    decimation: int
    mode: str

    @property
    def iq(self) -> np.ndarray:
        """Vista compleja, solo para análisis. El camino de datos es entero."""
        return self.i.astype(np.float64) + 1j * self.q.astype(np.float64)


@dataclass
class Ddc:
    """Cadena de bajada a banda base y diezmado."""

    params: Params
    mode: str = MODE_FINE
    nco: Nco = field(init=False)
    cic: Cic = field(init=False)
    fir: fir_mod.Fir = field(init=False)
    halfband: fir_mod.Fir = field(init=False)

    def __post_init__(self) -> None:
        if self.mode not in (MODE_FINE, MODE_COARSE):
            raise ValueError(f"modo desconocido: {self.mode!r}")
        chain = self.params.chain
        self.nco = Nco.from_params(self.params)
        self.cic = Cic(
            stages=int(chain["cic_stages"]),
            rate=int(chain["cic_rate"]),
            diff_delay=int(chain["cic_diff_delay"]),
            in_bits=self.params.sample_bits,
        )
        self.fir = fir_mod.Fir(
            coeffs=fir_mod.load_coeffs("droop_decim_fir"),
            decim=int(chain["fir_decim"]),
        )
        self.halfband = fir_mod.Fir(
            coeffs=fir_mod.load_coeffs("halfband_decim2"),
            decim=int(chain["coarse_extra_decim"]),
        )

    @property
    def decimation(self) -> int:
        """R total. Tiene que coincidir con R1/R2 del paquete de parámetros."""
        r1 = self.cic.rate * self.fir.decim
        return r1 if self.mode == MODE_FINE else r1 * self.halfband.decim

    def _check_decimation(self) -> None:
        expected = self.params.r1 if self.mode == MODE_FINE else self.params.r2
        if self.decimation != expected:
            raise ValueError(
                f"la descomposición de la cadena da R={self.decimation} pero el "
                f"paquete de parámetros dice {expected}. Uno de los dos está mal; "
                "arregla config/params.toml, no este modelo."
            )

    def mix(self, x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """Bajada a banda base. Devuelve `(i, q)` a `sample_bits`.

        El producto crece a `sample_bits + nco_out_bits` y se vuelve a bajar
        quitando el fondo de escala del NCO, con redondeo al más cercano.
        """
        x = np.asarray(x, dtype=np.int64)
        cos_w, sin_w = self.nco.generate(x.size)
        shift = self.params.invariant["nco_out_bits"] - 1
        i = fixed.shift_round(x * cos_w, shift)
        q = fixed.shift_round(-x * sin_w, shift)
        return i, q

    def _decimate(self, branch: np.ndarray) -> np.ndarray:
        # Nota de escalado: cada punto de recorte quita la ganancia de su etapa
        # redondeando a la potencia de dos superior, así que la cadena tiene una
        # pérdida neta de algunos dB y el modo grueso pierde 6 dB más que el fino.
        # El escalado de ganancia a fondo de escala es trabajo de Z1 («escalado de
        # ganancia y saturación con reporte de overflow»); aquí se deja explícito
        # y medible en vez de escondido en un factor mágico.
        out = self.cic.process(branch)
        # Se quita la ganancia del CIC en un único punto y de forma explícita.
        out = fixed.shift_round(out, self.cic.growth_bits)
        out = self.fir.process(out)
        out = fixed.shift_round(out, fixed.growth_bits(abs(self.fir.dc_gain)))
        if self.mode == MODE_COARSE:
            out = self.halfband.process(out)
            out = fixed.shift_round(out, fixed.growth_bits(abs(self.halfband.dc_gain)))
        return out

    def process(self, x: np.ndarray) -> DdcResult:
        """Cadena completa sobre un vector real de IF ya cuantizado."""
        self._check_decimation()
        i_mixed, q_mixed = self.mix(x)
        i = self._decimate(i_mixed)
        q = self._decimate(q_mixed)
        n = min(i.size, q.size)
        i, q = i[:n], q[:n]
        i_sat, i_ovf = fixed.saturate(i, self.params.iq_bits)
        q_sat, q_ovf = fixed.saturate(q, self.params.iq_bits)
        return DdcResult(
            i=i_sat,
            q=q_sat,
            overflow=i_ovf | q_ovf,
            decimation=self.decimation,
            mode=self.mode,
        )
