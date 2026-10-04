"""Lectura del paquete único de parámetros.

`config/params.toml` es la única fuente de verdad temporal del proyecto (D-02).
Este módulo lo lee; no copia ningún valor. Si necesitas un número nuevo, va al
TOML, no aquí.
"""

from __future__ import annotations

import tomllib
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PARAMS_TOML = ROOT / "config" / "params.toml"

#: Velocidad de la luz en el vacío, m/s. Constante física, no un parámetro de
#: plataforma: la celda de rango es R·c/(2·fs).
C_M_S = 299_792_458  # clock-const-ok: constante física, no un reloj


@dataclass(frozen=True)
class Params:
    """Parámetros resueltos para una plataforma concreta."""

    name: str
    schema_version: int
    invariant: dict
    chain: dict
    platform: dict

    # -- plataforma ---------------------------------------------------------
    @property
    def fs_hz(self) -> int:
        return int(self.platform["fs_hz"])

    @property
    def part(self) -> str:
        return str(self.platform["part"])

    @property
    def board(self) -> str:
        return str(self.platform["board"])

    @property
    def is_target(self) -> bool:
        return bool(self.platform["is_target"])

    # -- derivados de fs ----------------------------------------------------
    @property
    def if_norm(self) -> Fraction:
        """IF / fs. Invariante entre plataformas: es el punto de D-02."""
        return Fraction(self.invariant["if_norm_num"], self.invariant["if_norm_den"])

    @property
    def if_hz(self) -> int:
        value = self.if_norm * self.fs_hz
        if value.denominator != 1:
            raise ValueError(
                f"IF no entero en {self.name}: {value}. "
                "Elige fs tal que fs*if_norm caiga en un entero de Hz."
            )
        return int(value)

    def cell_m(self, r: int) -> float:
        """Tamaño de celda de rango para un factor de diezmado `r`, en metros.

        Solo tiene significado físico en la plataforma objetivo: en ZedBoard el
        tiempo está dilatado y este número no es el que ve el radar.
        """
        return r * C_M_S / (2 * self.fs_hz)

    def prf_hz(self, prf_div: int) -> float:
        """PRF de pared. Se dilata con fs; el valor de registro no."""
        return self.fs_hz / prf_div

    # -- invariantes --------------------------------------------------------
    @property
    def nco_phase_inc(self) -> int:
        """round(if_norm * 2**nco_phase_bits). Idéntico en las dos plataformas."""
        bits = self.invariant["nco_phase_bits"]
        num = self.if_norm.numerator << bits
        den = self.if_norm.denominator
        return (num + den // 2) // den

    @property
    def r1(self) -> int:
        return int(self.invariant["r1"])

    @property
    def r2(self) -> int:
        return int(self.invariant["r2"])

    @property
    def prf_div_min_low(self) -> int:
        """D-09: piso de `prf_div` para el rango no ambiguo mínimo del lote
        bajo (460 km, WSR-88D/NEXRAD). Invariante entre plataformas."""
        return int(self.invariant["prf_div_min_low"])

    @property
    def prf_div_min_high(self) -> int:
        """D-09: piso de `prf_div` para el rango no ambiguo mínimo del lote
        alto (115 km, WSR-88D/NEXRAD). No-vinculante hoy, ver params.toml."""
        return int(self.invariant["prf_div_min_high"])

    @property
    def n_rx_ch(self) -> int:
        return int(self.invariant["n_rx_ch"])

    @property
    def n_ch_top(self) -> int:
        """Canales que instancia `rtl/drx_top.sv` (Config A: Tx + H + V)."""
        return int(self.invariant["n_ch_top"])

    @property
    def vector_bram_depth(self) -> int:
        """Capacidad física de cada banco de BRAM de `rtl/vector_source.sv`."""
        return int(self.invariant["vector_bram_depth"])

    @property
    def vector_loop_len(self) -> int:
        """Longitud que se reproduce en bucle; reset de VEC_LEN (mapa v11).

        Múltiplo de `if_norm.denominator` por construcción — `tools/gen_params.py`
        lo comprueba —, para que el tono cierre un número entero de periodos y no
        haya salto de fase al envolver.
        """
        return int(self.invariant["vector_loop_len"])

    @property
    def sample_bits(self) -> int:
        return int(self.invariant["sample_bits"])

    @property
    def iq_bits(self) -> int:
        return int(self.invariant["iq_bits"])


def _raw() -> dict:
    with PARAMS_TOML.open("rb") as handle:
        return tomllib.load(handle)


def load_all() -> dict[str, Params]:
    """Todas las plataformas declaradas, en el orden del fichero."""
    raw = _raw()
    return {
        name: Params(
            name=name,
            schema_version=int(raw["schema_version"]),
            invariant=raw["invariant"],
            chain=raw["chain"],
            platform=platform,
        )
        for name, platform in raw["platform"].items()
    }


def load(platform: str = "zedboard") -> Params:
    """Parámetros de una plataforma. Por defecto la de desarrollo."""
    platforms = load_all()
    if platform not in platforms:
        raise KeyError(f"plataforma desconocida: {platform!r}; hay {sorted(platforms)}")
    return platforms[platform]
