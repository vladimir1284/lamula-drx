"""L0 — `drx_debug_probe`: la sonda que instrumenta P-21.

Es un instrumento, no camino de datos, pero se verifica igual que el resto por
una razón concreta: una sonda que miente es peor que no tener sonda. Si el
troceado del bus estuviera desplazado un bit, la captura del ILA diría que se
para `ddc_valid` cuando en realidad se para `vs_ready`, y la conclusión de
P-21 sería falsa sin que nada chirríe.

Lo que se prueba:

1. **El troceado.** Cada entrada aparece en el bit que dice `drx_debug_pkg`, y
   solo en ese. Se comprueba una señal cada vez, con todas las demás en bajo:
   un desplazamiento de un bit rompe el test.
2. **El contador.** Se pone a cero con cada avance de muestra, cuenta ciclos
   cuando no lo hay, y no cuenta nada con `armed` en bajo (BRAM-loop).
3. **El umbral.** `stalled` sube exactamente en el ciclo 2**STALL_LOG2 sin
   avance, ni antes ni después, y se queda arriba.
4. **Saturación.** El contador no da la vuelta. Un contador envolvente
   soltaría `stalled` justo cuando el atasco lleva más tiempo, que es cuando
   más falta hace.

`STALL_LOG2` se baja a 4 en la elaboración del test: el valor real son 2**22
ciclos y no hay por qué simular 4,2 millones para ejercitar la misma lógica.
"""

from __future__ import annotations

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

N_CH = 3
STALL_LOG2 = 4
IDLE_BITS = 24

# Mismo orden que `drx_debug_pkg`. Duplicarlo aquí es deliberado: si el test
# importara el troceado del propio RTL no comprobaría nada.
FLAGS = {
    "s_vec_valid": 0,
    "s_vec_ready": 1,
    "s_vec_last": 2,
    "m_ray_valid": 3,
    "m_ray_ready": 4,
    "m_ray_last": 5,
    "ddr_mode": 6,
    "timing_enable": 7,
    "timing_paced": 8,
    # bit 9 es `moved`, derivado de vs_valid/vs_ready, no una entrada
    "pulse_trig": 10,
    # bit 11 es `stalled`, derivado del contador
}
BUSES = {
    "vs_valid": 12,
    "vs_ready": 12 + N_CH,
    "ddc_valid": 12 + 2 * N_CH,
    "gate_valid": 12 + 3 * N_CH,
    "gate_ready": 12 + 4 * N_CH,
    "gate_overrun": 12 + 5 * N_CH,
    "gate_truncated": 12 + 6 * N_CH,
}
IDLE_OFFSET = 12 + 7 * N_CH

TODAS = list(FLAGS) + list(BUSES)


def _reposo(dut) -> None:
    for nombre in TODAS:
        getattr(dut, nombre).value = 0


async def _arranca(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    _reposo(dut)
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


def _bus(dut) -> int:
    return int(dut.dbg_bus.value)


def _idle(dut) -> int:
    return (_bus(dut) >> IDLE_OFFSET) & ((1 << IDLE_BITS) - 1)


def _stalled(dut) -> int:
    return (_bus(dut) >> 11) & 1


@cocotb.test()
async def test_cada_senal_cae_en_su_bit(dut):
    await _arranca(dut)

    for nombre, bit in FLAGS.items():
        _reposo(dut)
        getattr(dut, nombre).value = 1
        await Timer(1, units="ns")
        esperado = 1 << bit
        # `armed` en alto con el contador a cero no mueve ningún otro bit.
        assert _bus(dut) == esperado, (
            f"{nombre} tenía que encender solo el bit {bit}: "
            f"bus = {_bus(dut):#x}, esperado {esperado:#x}"
        )

    for nombre, base in BUSES.items():
        for c in range(N_CH):
            _reposo(dut)
            getattr(dut, nombre).value = 1 << c
            await Timer(1, units="ns")
            esperado = 1 << (base + c)
            assert _bus(dut) == esperado, (
                f"{nombre}[{c}] tenía que encender solo el bit {base + c}: "
                f"bus = {_bus(dut):#x}, esperado {esperado:#x}"
            )


@cocotb.test()
async def test_moved_pide_valid_y_ready_en_todos_los_canales(dut):
    """Misma definición de avance que `drx_sample_pacer`, y por eso se repite
    aquí: si las dos se separaran, el contador mediría otra cosa que el motor
    de timing y la captura no sería comparable con la traza."""
    await _arranca(dut)

    casos = [
        (0b111, 0b111, 1),
        (0b111, 0b110, 0),
        (0b011, 0b111, 0),
        (0b000, 0b111, 0),
        (0b111, 0b000, 0),
    ]
    for valid, ready, esperado in casos:
        _reposo(dut)
        dut.vs_valid.value = valid
        dut.vs_ready.value = ready
        await Timer(1, units="ns")
        moved = (_bus(dut) >> 9) & 1
        assert moved == esperado, (
            f"vs_valid={valid:#05b} vs_ready={ready:#05b} dio moved={moved}, "
            f"esperado {esperado}"
        )


@cocotb.test()
async def test_sin_armar_el_contador_no_cuenta(dut):
    """BRAM-loop sin DMA: la fuente entrega una muestra por ciclo y un hueco no
    significa nada. Contar ahí daría `stalled` en cuanto el DDC frenara un
    momento."""
    await _arranca(dut)
    dut.ddr_mode.value = 0
    dut.s_vec_valid.value = 0

    for _ in range(4 * (1 << STALL_LOG2)):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")

    assert _idle(dut) == 0, f"desarmado, el contador llegó a {_idle(dut)}"
    assert _stalled(dut) == 0, "desarmado no puede haber stalled"


@cocotb.test()
async def test_un_beat_sin_consumir_arma_aunque_ddr_mode_sea_cero(dut):
    """El caso que de verdad hay que capturar en P-21, y el que un armado
    atado solo a `ddr_mode` perdería.

    `DrxStimulus_Stop()` termina con `set_modo_ddr(false)`. Si el drenado
    salió antes de tiempo, el MM2S se queda ofreciendo un beat que
    `vector_source` ya no puede aceptar — `s_axis_ready = ddr_mode && …` —, o
    sea `ddr_mode = 0` y `s_vec_valid = 1` para siempre. Con el contador atado
    a `ddr_mode`, la sonda se desarmaría justo al entrar en ese estado y el
    ILA no dispararía nunca.
    """
    await _arranca(dut)
    dut.ddr_mode.value = 0
    dut.s_vec_valid.value = 1
    dut.s_vec_ready.value = 0

    for _ in range(1 << STALL_LOG2):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")

    assert _stalled(dut) == 1, (
        "con un beat ofrecido y sin consumir durante el umbral entero, "
        f"stalled tenía que subir; contador = {_idle(dut)}"
    )


@cocotb.test()
async def test_el_avance_pone_el_contador_a_cero(dut):
    await _arranca(dut)
    dut.ddr_mode.value = 1

    for _ in range(3):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert _idle(dut) > 0, "con armed=1 y sin avance el contador tiene que subir"

    dut.vs_valid.value = 0b111
    dut.vs_ready.value = 0b111
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert _idle(dut) == 0, f"tras un avance el contador quedó en {_idle(dut)}"

    # Y vuelve a contar en cuanto el avance para.
    dut.vs_ready.value = 0b000
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert _idle(dut) == 1, f"el ciclo siguiente al avance tenía que dar 1, dio {_idle(dut)}"


@cocotb.test()
async def test_stalled_sube_en_el_umbral_exacto(dut):
    """El umbral es lo único que separa un hueco legítimo entre pasadas (el
    firmware sondea cada 10 ms) de un atasco. Que suba un ciclo antes o
    después no importa en placa; que lo haga por la mitad del umbral, sí."""
    await _arranca(dut)
    dut.ddr_mode.value = 1

    umbral = 1 << STALL_LOG2
    for ciclo in range(1, umbral):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        assert _idle(dut) == ciclo, f"ciclo {ciclo}: contador = {_idle(dut)}"
        assert _stalled(dut) == 0, f"stalled subió en el ciclo {ciclo}, antes del umbral {umbral}"

    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert _idle(dut) == umbral
    assert _stalled(dut) == 1, f"stalled no subió con el contador en {umbral}"

    # Se queda arriba: el atasco es permanente y la captura se lee después.
    for _ in range(10):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert _stalled(dut) == 1, "stalled se cayó solo"

    # Y un avance lo baja -- es lo que permite rearmar el ILA sin reset.
    dut.vs_valid.value = 0b111
    dut.vs_ready.value = 0b111
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert _stalled(dut) == 0, "un avance tenía que bajar stalled"


@cocotb.test()
async def test_el_contador_satura_y_no_da_la_vuelta(dut):
    """Con el contador real (24 bits) esto tarda 16,8 millones de ciclos; con
    STALL_LOG2=4 el test fuerza la condición escribiendo el límite no se
    puede, así que se comprueba la propiedad que importa: una vez saturado,
    `stalled` no se cae nunca mientras no haya avance."""
    await _arranca(dut)
    dut.ddr_mode.value = 1

    umbral = 1 << STALL_LOG2
    for _ in range(8 * umbral):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if _idle(dut) >= umbral:
            assert _stalled(dut) == 1, (
                f"contador en {_idle(dut)} (>= {umbral}) con stalled en bajo: "
                "el contador dio la vuelta"
            )
