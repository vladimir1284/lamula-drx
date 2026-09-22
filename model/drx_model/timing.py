"""Motor de timing de Z2: secuenciador de 2 lotes de PRF/ancho de pulso por radial.

Modelo dorado de [D-13](../../docs/alcance/decisiones.md#d-13) (Batch mode de NEXRAD): cada
radial se transmite como un lote de PRF baja (vigilancia, rango largo) seguido de un lote de
PRF alta (Doppler, rango corto), en bucle continuo durante el barrido. Son exactamente 2 lotes
-- por eso `RadialBatches` tiene los campos `low`/`high` en vez de una lista de N, para que el
"2" de D-13 sea parte del tipo y no una convención que un test pueda dejar de cubrir.

El validador PRF x rango de D-09 se aplica lote por lote (D-13): el rango no ambiguo del lote
bajo y el del lote alto son distintos por diseño, así que un único par PRF/rango no basta.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from drx_model.params import C_M_S, Params


class PrfRangeIllegal(ValueError):
    """Combinación PRF x rango ilegal (D-09). Corresponde a `error.prf_range_illegal` (valor 1)
    en el contrato DRx<->DSP."""


class PulseWidthInvalid(ValueError):
    """Ancho de pulso fuera de la tabla de `config/params.toml`. Corresponde a
    `error.pulse_width_invalid` (valor 6) en el contrato DRx<->DSP."""


@dataclass(frozen=True)
class Batch:
    """Un lote: valores de REGISTRO, idénticos en las dos plataformas (como `prf_div` y
    `pulse_width_cycles` en `params.toml`) -- lo que se dilata es la PRF de pared, no esto."""

    prf_div: int
    pulse_width_cycles: int
    n_pulses: int

    def __post_init__(self) -> None:
        if self.prf_div < 1:
            raise ValueError("prf_div tiene que ser >= 1")
        if self.pulse_width_cycles < 1:
            raise ValueError("pulse_width_cycles tiene que ser >= 1")
        if self.n_pulses < 1:
            raise ValueError("n_pulses tiene que ser >= 1")
        if self.pulse_width_cycles >= self.prf_div:
            raise ValueError(
                f"ancho de pulso ({self.pulse_width_cycles} ciclos) >= periodo de PRF "
                f"({self.prf_div} ciclos): el pulso no cabe en su propio PRI"
            )

    def prf_hz(self, params: Params) -> float:
        return params.prf_hz(self.prf_div)

    def dwell_cycles(self) -> int:
        """Ciclos de `fs` que ocupa el lote entero: `n_pulses` PRIs completos."""
        return self.n_pulses * self.prf_div


@dataclass(frozen=True)
class RadialBatches:
    """Los 2 lotes de un radial (D-13): exactamente `low` + `high`, nunca una tabla de N."""

    low: Batch
    high: Batch

    def dwell_cycles(self) -> int:
        return self.low.dwell_cycles() + self.high.dwell_cycles()

    def dwell_s(self, params: Params) -> float:
        return self.dwell_cycles() / params.fs_hz


def pulse_width_table(params: Params) -> tuple[int, ...]:
    """Anchos de pulso admitidos, en ciclos de `fs` (idéntico en las dos plataformas)."""
    return tuple(int(c) for c in params.invariant["pulse_width_cycles"])


def unambiguous_range_m(params: Params, prf_div: int) -> float:
    """Rango no ambiguo = c / (2*PRF) (D-09)."""
    return C_M_S / (2.0 * params.prf_hz(prf_div))


def validate_pulse_width(params: Params, batch: Batch) -> None:
    """El ancho de pulso del lote tiene que ser uno de los tres de la tabla, no un valor
    arbitrario -- el registro real selecciona por índice, no por ciclo crudo."""
    table = pulse_width_table(params)
    if batch.pulse_width_cycles not in table:
        raise PulseWidthInvalid(
            f"{batch.pulse_width_cycles} ciclos no está en la tabla de anchos de pulso {table}"
        )


def validate_batch(params: Params, batch: Batch, r_max_required_m: float) -> None:
    """Validador PRF x rango de D-09, aplicado a UN lote.

    D-13: el lote bajo y el lote alto tienen rango no ambiguo distinto por diseño, así que
    este validador se llama una vez por lote, nunca una vez por configuración completa.
    """
    r_unambiguous = unambiguous_range_m(params, batch.prf_div)
    if r_unambiguous < r_max_required_m:
        raise PrfRangeIllegal(
            f"PRF={batch.prf_hz(params):.1f} Hz da rango no ambiguo "
            f"{r_unambiguous / 1000:.1f} km < {r_max_required_m / 1000:.1f} km requeridos"
        )


def validate_radial(
    params: Params,
    batches: RadialBatches,
    r_max_required_low_m: float,
    r_max_required_high_m: float,
) -> None:
    """D-09 aplicado a los 2 lotes por separado (D-13).

    Los dos umbrales son distintos a propósito: el lote bajo es el de vigilancia/reflectividad
    (rango largo exigido) y el lote alto es el de Doppler (rango corto, Nyquist de velocidad
    exigido en su lugar) -- no tiene sentido exigirle al lote alto el mismo rango que al bajo.
    """
    validate_batch(params, batches.low, r_max_required_low_m)
    validate_batch(params, batches.high, r_max_required_high_m)
    validate_pulse_width(params, batches.low)
    validate_pulse_width(params, batches.high)


def trigger_times_cycles(batch: Batch, start_cycle: int = 0) -> np.ndarray:
    """Instantes de disparo del lote (flanco de subida del pulso), en ciclos de `fs` desde
    `start_cycle`."""
    return start_cycle + np.arange(batch.n_pulses, dtype=np.int64) * batch.prf_div


def radial_trigger_times_cycles(
    batches: RadialBatches, start_cycle: int = 0
) -> tuple[np.ndarray, np.ndarray]:
    """Triggers del lote bajo y del lote alto de un radial, en ciclos de `fs`.

    El lote alto empieza justo cuando termina el lote bajo: D-13 exige secuenciado autónomo en
    fabric, sin hueco de por medio y sin que el RCP intervenga a esta cadencia.
    """
    low_triggers = trigger_times_cycles(batches.low, start_cycle)
    high_start = start_cycle + batches.low.dwell_cycles()
    high_triggers = trigger_times_cycles(batches.high, high_start)
    return low_triggers, high_triggers


def sweep_trigger_times_cycles(
    batches: RadialBatches, n_radiales: int, start_cycle: int = 0
) -> tuple[np.ndarray, np.ndarray]:
    """La misma pareja de lotes repetida `n_radiales` veces, en bucle continuo (D-13: "durante
    los 360° de esa elevación"), sin hueco entre un radial y el siguiente.

    Sirve para verificar que el periodo del secuenciador es exacto a lo largo de un barrido
    completo -- la instrumentación de jitter de Z2 mide justo esto en fabric.
    """
    if n_radiales < 1:
        raise ValueError("n_radiales tiene que ser >= 1")
    dwell = batches.dwell_cycles()
    low_all = []
    high_all = []
    for radial in range(n_radiales):
        low, high = radial_trigger_times_cycles(batches, start_cycle + radial * dwell)
        low_all.append(low)
        high_all.append(high)
    return np.concatenate(low_all), np.concatenate(high_all)


def one_shot_active_cycles(arm_cycle: int, delay: int, width: int) -> range:
    """Ciclos en los que UN trigger genérico (Z2: "generador de 4 triggers configurables
    con retardo y ancho independientes") está activo, contados en ciclos de `fs`.

    Un evento de arme en `arm_cycle` (p. ej. `pulse_trig` del secuenciador de lotes: cada
    pulso vuelve a armar los 4) produce un pulso que arranca `delay` ciclos después y dura
    `width` ciclos: activo en ``[arm_cycle + delay + 1, arm_cycle + delay + width]``. El +1
    es la latencia de un registro entre el arme y la salida -- igual que `tx_gate` en
    `drx_prf_batch_seq.sv` -- no una demora de más que el hardware real no tenga: es la
    latencia mínima de cualquier salida registrada de un `arm` que también llega por
    registro.
    """
    if delay < 0:
        raise ValueError("delay tiene que ser >= 0")
    if width < 1:
        raise ValueError("width tiene que ser >= 1")
    start = arm_cycle + delay + 1
    return range(start, start + width)
