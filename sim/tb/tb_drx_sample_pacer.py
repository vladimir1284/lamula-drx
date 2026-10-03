"""L0 — `drx_sample_pacer`: qué cuenta como un avance de muestra (P-16).

Tres líneas de RTL, pero la definición de "un avance" es la decisión entera
del cierre de P-16, así que tiene banco propio. Lo que se prueba:

1. Con `paced` en bajo, `advance` es 1 SIEMPRE, pase lo que pase en el
   handshake. Es la condición que hace que el motor de timing siga siendo el
   de v3..v9 cuando el bit del registro está en su valor de reset.
2. Con `paced` en alto, hace falta `valid && ready` en TODOS los canales. Un
   canal suelto no basta -- si bastara, el motor adelantaría respecto de los
   canales lentos y el desfase no daría ningún error visible, que es la clase
   de fallo que este módulo existe para no tener.
"""

from __future__ import annotations

import itertools

import cocotb
from cocotb.triggers import Timer

N_CH = 3


def _bus(bits: tuple[int, ...]) -> int:
    """`valid`/`ready` son buses empaquetados, no arrays de escalares: cocotb
    no puede indexar los segundos (ver la cabecera del modulo)."""
    return sum(b << c for c, b in enumerate(bits))


def _pon(dut, valid: tuple[int, ...], ready: tuple[int, ...]) -> None:
    dut.valid.value = _bus(valid)
    dut.ready.value = _bus(ready)


@cocotb.test()
async def test_sin_pacear_el_avance_es_siempre_uno(dut):
    dut.paced.value = 0
    for valid in itertools.product([0, 1], repeat=N_CH):
        for ready in itertools.product([0, 1], repeat=N_CH):
            _pon(dut, valid, ready)
            await Timer(1, units="ns")
            assert int(dut.advance.value) == 1, (
                f"paced=0 con valid={valid} ready={ready} dio advance=0"
            )


@cocotb.test()
async def test_paceado_exige_el_conjunto_entero(dut):
    dut.paced.value = 1
    for valid in itertools.product([0, 1], repeat=N_CH):
        for ready in itertools.product([0, 1], repeat=N_CH):
            _pon(dut, valid, ready)
            await Timer(1, units="ns")
            esperado = int(all(valid[c] and ready[c] for c in range(N_CH)))
            assert int(dut.advance.value) == esperado, (
                f"valid={valid} ready={ready}: "
                f"advance={int(dut.advance.value)}, esperado {esperado}"
            )
