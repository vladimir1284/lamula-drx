"""Aritmética de punto fijo bit-exacta.

El modelo dorado es el oráculo (D-03), y un oráculo que redondea distinto que el
RTL no sirve para nada. Todo aquí trabaja sobre enteros: nada de coma flotante en
el camino de datos. La coma flotante solo aparece en el generador de vectores,
antes de cuantizar a la entrada, y en el análisis.

Convenio de nombres: `bits` es siempre el ancho TOTAL con signo, en complemento
a dos, igual que se declara en el RTL (`logic signed [bits-1:0]`).
"""

from __future__ import annotations

import numpy as np

ArrayLike = np.ndarray


def limits(bits: int) -> tuple[int, int]:
    """Rango representable con signo en complemento a dos."""
    if bits < 2:
        raise ValueError(f"ancho con signo inválido: {bits}")
    return -(1 << (bits - 1)), (1 << (bits - 1)) - 1


def wrap(values: ArrayLike, bits: int) -> np.ndarray:
    """Envuelve módulo 2**bits, como hace un registro que desborda.

    Es el comportamiento correcto para los integradores del CIC: el desbordamiento
    intermedio es intencionado y se cancela en los peines, siempre que el ancho
    sea suficiente. Donde el desbordamiento NO es intencionado va `saturate`.
    """
    modulus = 1 << bits
    out = np.asarray(values, dtype=np.int64) & (modulus - 1)
    return np.where(out >= (modulus >> 1), out - modulus, out).astype(np.int64)


def saturate(values: ArrayLike, bits: int) -> tuple[np.ndarray, np.ndarray]:
    """Satura al rango de `bits` y devuelve `(valores, banderas_de_overflow)`.

    La bandera es por muestra: el DDC tiene que reportar overflow, no esconderlo
    (ver la suite de aceptación, caso de entrada sobre-escala).
    """
    low, high = limits(bits)
    values = np.asarray(values, dtype=np.int64)
    overflow = (values < low) | (values > high)
    return np.clip(values, low, high).astype(np.int64), overflow


def shift_round(values: ArrayLike, shift: int) -> np.ndarray:
    """Desplaza a la derecha `shift` bits con redondeo al más cercano.

    Empate hacia +infinito, que es el modo «Round half up» de la IP de Xilinx.
    Con `shift <= 0` desplaza a la izquierda sin redondeo.
    """
    values = np.asarray(values, dtype=np.int64)
    if shift <= 0:
        return (values << -shift).astype(np.int64)
    return ((values + (1 << (shift - 1))) >> shift).astype(np.int64)


def shift_truncate(values: ArrayLike, shift: int) -> np.ndarray:
    """Desplaza a la derecha `shift` bits truncando hacia -infinito.

    Es lo que hace un `>>>` en el RTL y lo que hace la IP en modo «Truncation».
    Se distingue de `shift_round` a propósito: elegir mal el modo es exactamente
    la clase de bug de un LSB que este modelo existe para atrapar.
    """
    values = np.asarray(values, dtype=np.int64)
    if shift <= 0:
        return (values << -shift).astype(np.int64)
    return (values >> shift).astype(np.int64)


def quantize(values: ArrayLike, bits: int, full_scale: float = 1.0) -> np.ndarray:
    """Cuantiza una señal real de coma flotante a un entero con signo de `bits`.

    `full_scale` es el valor de coma flotante que corresponde al fondo de escala
    positivo. Lo que se salga satura, igual que satura un ADC real.
    """
    _, high = limits(bits)
    scaled = np.round(np.asarray(values, dtype=np.float64) / full_scale * high)
    out, _ = saturate(scaled, bits)
    return out


def growth_bits(gain: float) -> int:
    """Bits de crecimiento necesarios para una ganancia lineal dada."""
    if gain <= 0:
        raise ValueError("la ganancia tiene que ser positiva")
    return int(np.ceil(np.log2(gain)))
