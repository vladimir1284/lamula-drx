"""Punto fijo: cada modo de redondeo y de desbordamiento, por separado.

Elegir truncamiento donde la IP redondea es un error de un LSB que solo aparece
como una discrepancia bit a bit tres semanas después. Se prueban aquí.
"""

import numpy as np
import pytest
from drx_model import fixed


def test_limites_con_signo():
    assert fixed.limits(16) == (-32768, 32767)
    assert fixed.limits(2) == (-2, 1)
    with pytest.raises(ValueError):
        fixed.limits(1)


def test_wrap_es_complemento_a_dos():
    assert list(fixed.wrap(np.array([32767, 32768, -32769, 65536]), 16)) == [
        32767,
        -32768,
        32767,
        0,
    ]


def test_saturate_marca_overflow_por_muestra():
    values, overflow = fixed.saturate(np.array([0, 40000, -40000]), 16)
    assert list(values) == [0, 32767, -32768]
    assert list(overflow) == [False, True, True]


def test_redondeo_es_medio_hacia_arriba():
    """Modo «Round half up» de la IP de Xilinx: el empate sube."""
    assert list(fixed.shift_round(np.array([3, 4, 5, 6, -3, -4, -5]), 1)) == [
        2,
        2,
        3,
        3,
        -1,
        -2,
        -2,
    ]


def test_truncamiento_va_hacia_menos_infinito():
    """`>>>` en RTL: -1 >> 1 es -1, no 0. Se distingue de shift_round a propósito."""
    assert list(fixed.shift_truncate(np.array([3, 4, 5, -1, -3]), 1)) == [1, 2, 2, -1, -2]
    assert list(fixed.shift_round(np.array([-1]), 1)) == [0]


def test_quantize_satura_lo_que_se_sale():
    out = fixed.quantize(np.array([0.0, 1.0, 2.0, -2.0]), 16)
    assert list(out) == [0, 32767, 32767, -32768]


def test_growth_bits():
    assert fixed.growth_bits(1.0) == 0
    assert fixed.growth_bits(2.0) == 1
    assert fixed.growth_bits(3.0) == 2


def test_gain_trim_reproduce_la_ganancia_no_potencia_de_dos():
    """`growth_bits` solo puede quitar potencias de dos; esto quita cualquier cosa."""
    gain = 2.678822641803  # residuo real de la cadena en modo fino, ver chain.py
    coeff, frac_bits = fixed.gain_trim(gain, bits=18)
    values = np.array([1, -1, 1000, -1000, 32767, -32768])
    out = fixed.shift_round(values * coeff, frac_bits)
    expected = np.round(values * gain)
    # Un LSB de tolerancia: es exactamente el redondeo de punto fijo que
    # `gain_trim` existe para modelar, no un error.
    assert np.abs(out - expected).max() <= 1


def test_gain_trim_usa_toda_la_precision_sin_saturar():
    coeff, frac_bits = fixed.gain_trim(1.0, bits=18)
    low, high = fixed.limits(18)
    assert low <= coeff <= high
    # Ganancia unidad exacta: el coeficiente tiene que reproducir la entrada.
    values = np.array([0, 1, -1, 32767, -32768])
    assert list(fixed.shift_round(values * coeff, frac_bits)) == list(values)


def test_gain_trim_rechaza_lo_que_no_cabe():
    with pytest.raises(ValueError, match="no cabe"):
        fixed.gain_trim(1000.0, bits=4)
    with pytest.raises(ValueError, match="positiva"):
        fixed.gain_trim(0.0, bits=18)
    with pytest.raises(ValueError, match="positiva"):
        fixed.gain_trim(-1.0, bits=18)
