"""L0 — testbench del divisor de latido.

Comprueba lo único que Z0 tiene que demostrar en simulación: que el RTL deriva su
temporización de `FS_HZ` y no de una constante escrita a mano. El periodo de
reloj del testbench también sale del paquete de parámetros: si alguien cambia
`fs` en config/params.toml, este banco se mueve con él sin tocar una línea.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from drx_model.params import load

#: Divisor pequeño: el valor real (FS_HZ/2) son 5·10^7 ciclos y no se simula.
DIV = 5

PARAMS = load("zedboard")
#: Periodo de reloj en picosegundos, derivado de FS_HZ. Nada de literales (D-02).
CLK_PERIOD_PS = round(1e12 / PARAMS.fs_hz)  # clock-const-ok: conversión de unidades s->ps


async def _reset(dut) -> None:
    dut.rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_periodo_del_latido(dut):
    """`level` conmuta exactamente cada DIV ciclos."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    previous = int(dut.level.value)
    cycles_between_toggles = []
    count = 0

    for _ in range(DIV * 6 + 2):
        await RisingEdge(dut.clk)
        count += 1
        current = int(dut.level.value)
        if current != previous:
            cycles_between_toggles.append(count)
            count = 0
            previous = current

    assert len(cycles_between_toggles) >= 4, (
        f"se esperaban al menos 4 conmutaciones, hubo {len(cycles_between_toggles)}"
    )
    # La primera cuenta arrastra la salida del reset; el resto tiene que ser exacta.
    assert all(value == DIV for value in cycles_between_toggles[1:]), (
        f"periodo del latido incorrecto: {cycles_between_toggles}"
    )


@cocotb.test()
async def test_reset_asincrono(dut):
    """El reset asíncrono pone `level` a cero sin esperar al reloj."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    # Deja que conmute al menos una vez para que el valor no sea trivialmente 0.
    for _ in range(DIV + 1):
        await RisingEdge(dut.clk)
    assert int(dut.level.value) == 1, "el latido no llegó a conmutar antes del reset"

    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    assert int(dut.level.value) == 0, "el reset no forzó `level` a cero"
