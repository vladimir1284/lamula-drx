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
