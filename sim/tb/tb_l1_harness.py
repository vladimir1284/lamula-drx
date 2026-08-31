"""L0 — auto-prueba del arnés de L1.

No prueba el DDC: prueba el lector de `.hex` y el comparador bit a bit que la
suite L1 va a usar cuando exista Vivado. Un comparador que no compara da verde
con cualquier DUT, así que aquí se comprueba lo contrario de lo habitual: que
**sabe fallar**, y en la muestra exacta.

Los ficheros que lee son los que genera `tools/gen_l1_vectors.py` desde el
modelo dorado, así que este test también es el gate de que ese formato es
legible por un simulador y no solo por Python.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from drx_model.params import load

PARAMS = load("zedboard")
CLK_PERIOD_PS = round(1e12 / PARAMS.fs_hz)  # clock-const-ok: conversión de unidades s->ps

#: Margen de ciclos sobre el número de muestras: el arnés entrega una por ciclo.
MARGIN_CYCLES = 32


async def _reset(dut) -> None:
    dut.rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def _run_until_done(dut, limit: int) -> None:
    for _ in range(limit):
        await RisingEdge(dut.clk)
        if int(dut.done.value):
            return
    raise AssertionError(f"el arnés no terminó en {limit} ciclos")


@cocotb.test()
async def test_arnes(dut):
    """Compara los vectores del modelo contra sí mismos y contra sí mismos con un bit cambiado.

    Qué caso corre lo decide el plusarg `+corrupt_index`, que pone el runner:
    sin él se espera cero discrepancias, con él exactamente una.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    # Los `initial` que leen los plusargs y los ficheros ya han corrido: leer
    # `count` antes del primer flanco daría cero y el test pasaría en falso.
    count = int(dut.u_checker.count.value)
    assert count > 0, "el comparador no cargó ninguna muestra esperada"

    await _run_until_done(dut, count + MARGIN_CYCLES)

    checked = int(dut.checked.value)
    mismatches = int(dut.mismatches.value)
    corrupt_index = int(dut.corrupt_index.value.signed_integer)

    assert checked == count, f"se compararon {checked} muestras de {count}"

    if corrupt_index < 0:
        assert mismatches == 0, (
            f"{mismatches} discrepancias sobre vectores idénticos: el arnés está "
            "corrompiendo datos que no debería tocar"
        )
    else:
        assert mismatches == 1, (
            f"se corrompió una muestra y el comparador reportó {mismatches}: "
            "un comparador que no ve un bit cambiado no vale como oráculo de L1"
        )
