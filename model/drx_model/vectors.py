"""Generador de vectores de estímulo.

Produce la entrada real de IF ya cuantizada a `sample_bits`, que es lo que
consumen por igual el modelo dorado y el `vector_source` del RTL. Como `FS_HZ`
dilata todo por igual (D-02), un vector generado con los parámetros de ZedBoard y
otro con los de ZU9 son la MISMA secuencia de enteros siempre que la frecuencia
se pida normalizada; por eso todas las funciones de aquí trabajan en frecuencia
normalizada a `fs` y no en Hz.

Degradaciones
-------------
Desde Z1 el generador inyecta a propósito lo que va a traer el frontal real:
ruido, offset de continua, desbalance I/Q y entrada sobre-escala. No es realismo
decorativo: es para que el DDC esté caracterizado bajo esas condiciones antes de
que exista el frontal, y para que el modelo también las modele.

Determinismo: toda función que use aleatoriedad exige una semilla. Un oráculo que
cambia entre ejecuciones no es un oráculo.
"""

from __future__ import annotations

import numpy as np

from drx_model import fixed
from drx_model.params import Params


def _amplitude(dbfs: float) -> float:
    """Amplitud lineal relativa al fondo de escala a partir de dBFS."""
    if dbfs > 0:
        # Permitido a propósito: la suite de aceptación tiene un caso sobre-escala.
        pass
    return 10.0 ** (dbfs / 20.0)


def tone(
    params: Params,
    n: int,
    freq_norm: float | None = None,
    dbfs: float = -3.0,
    phase: float = 0.0,
) -> np.ndarray:
    """Tono puro real. `freq_norm` por defecto es el IF normalizado (0,24)."""
    if freq_norm is None:
        freq_norm = float(params.if_norm)
    t = np.arange(n, dtype=np.float64)
    signal = _amplitude(dbfs) * np.cos(2.0 * np.pi * freq_norm * t + phase)
    return fixed.quantize(signal, params.sample_bits)


def two_tone(
    params: Params,
    n: int,
    freq_norm_a: float,
    freq_norm_b: float,
    dbfs: float = -9.0,
) -> np.ndarray:
    """Dos tonos de igual amplitud: rechazo de imagen e intermodulación."""
    t = np.arange(n, dtype=np.float64)
    amp = _amplitude(dbfs)
    signal = amp * (
        np.cos(2.0 * np.pi * freq_norm_a * t) + np.cos(2.0 * np.pi * freq_norm_b * t)
    )
    return fixed.quantize(signal, params.sample_bits)


def chirp(
    params: Params,
    n: int,
    f_start_norm: float = 0.0,
    f_stop_norm: float = 0.5,
    dbfs: float = -6.0,
) -> np.ndarray:
    """Barrido lineal por la zona de Nyquist, bordes y punto de aliasing incluidos."""
    t = np.arange(n, dtype=np.float64)
    rate = (f_stop_norm - f_start_norm) / max(n - 1, 1)
    phase = 2.0 * np.pi * (f_start_norm * t + 0.5 * rate * t * t)
    return fixed.quantize(_amplitude(dbfs) * np.cos(phase), params.sample_bits)


def impulse(params: Params, n: int, position: int = 0, dbfs: float = 0.0) -> np.ndarray:
    """Impulso unitario: respuesta al impulso de la cadena completa."""
    signal = np.zeros(n, dtype=np.float64)
    signal[position] = _amplitude(dbfs)
    return fixed.quantize(signal, params.sample_bits)


def step(params: Params, n: int, position: int = 0, dbfs: float = -3.0) -> np.ndarray:
    """Escalón: respuesta al escalón de la cadena completa."""
    signal = np.zeros(n, dtype=np.float64)
    signal[position:] = _amplitude(dbfs)
    return fixed.quantize(signal, params.sample_bits)


def modulated_tone(
    params: Params,
    n: int,
    baseband_norm: float,
    dbfs: float = -6.0,
    gain_imbalance_db: float = 0.0,
    phase_imbalance_deg: float = 0.0,
) -> np.ndarray:
    """Tono de banda base subido al IF, con desbalance I/Q opcional.

    El desbalance se aplica en banda base ANTES de subir al IF, que es donde lo
    introduce un frontal en cuadratura. Con muestreo de IF real el desbalance no
    lo mete el ADC: entra por delante, y así es como hay que inyectarlo.
    """
    t = np.arange(n, dtype=np.float64)
    gain = 10.0 ** (gain_imbalance_db / 20.0)
    phi = np.deg2rad(phase_imbalance_deg)
    i = np.cos(2.0 * np.pi * baseband_norm * t)
    q = gain * np.sin(2.0 * np.pi * baseband_norm * t + phi)
    if_norm = float(params.if_norm)
    signal = _amplitude(dbfs) * (
        i * np.cos(2.0 * np.pi * if_norm * t) - q * np.sin(2.0 * np.pi * if_norm * t)
    )
    return fixed.quantize(signal, params.sample_bits)


def add_noise(x: np.ndarray, snr_db: float, params: Params, seed: int) -> np.ndarray:
    """Ruido gaussiano al SNR pedido, medido contra la potencia de `x`."""
    x = np.asarray(x, dtype=np.int64)
    signal_power = float(np.mean(x.astype(np.float64) ** 2))
    if signal_power == 0.0:
        raise ValueError("no se puede fijar un SNR sobre una señal de potencia cero")
    noise_power = signal_power / (10.0 ** (snr_db / 10.0))
    rng = np.random.default_rng(seed)
    noise = rng.normal(0.0, np.sqrt(noise_power), size=x.size)
    out, _ = fixed.saturate(np.round(x + noise), params.sample_bits)
    return out


def add_dc_offset(x: np.ndarray, dbfs: float, params: Params) -> np.ndarray:
    """Offset de continua, en dBFS. El DDC tiene que rechazarlo, no atragantarse."""
    _, high = fixed.limits(params.sample_bits)
    offset = round(_amplitude(dbfs) * high)
    out, _ = fixed.saturate(np.asarray(x, dtype=np.int64) + offset, params.sample_bits)
    return out
