"""L0 — `drx_range_gate`.

`BINS_FINE`/`BINS_COARSE` los pasa el runner pequeños (8 y 4, ver
`sim/tests/test_l0_range_gate.py`) para poder correr muchos rayos sin simular
los 3689/1844 reales — mismo motivo que `DIV` en `tb_drx_heartbeat.py`. 8 se
eligió a propósito potencia de dos: es el caso que rompía una primera versión
de este módulo, que confundía el CONTEO de bins con el ÍNDICE máximo y no
cabía en `$clog2(8) = 3` bits (ver el comentario de `last_idx` en el RTL).

El módulo no tiene un oráculo de valores propio — no hace aritmética, solo
reordena en el tiempo — así que el criterio de corrección es estructural: la
secuencia de `(i, q)` que sale, en orden, tiene que ser exactamente la que
entró, con `m_last` cayendo en la muestra `bins-1` de cada rayo. Eso es
literalmente `model/drx_model/gating.py::tlast_mask` trasladado a hardware.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from drx_model.params import load

PARAMS = load("zedboard")
CLK_PERIOD_PS = round(1e12 / PARAMS.fs_hz)  # clock-const-ok: conversión de unidades s->ps

BINS_FINE = 8
BINS_COARSE = 4


async def _reset(dut) -> None:
    dut.rst_n.value = 0
    dut.s_valid.value = 0
    dut.s_i.value = 0
    dut.s_q.value = 0
    dut.mode_coarse.value = 0
    dut.m_ready.value = 1
    dut.clear.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def _feed_and_collect(
    dut, n_samples: int, mode_coarse: bool, ready_sequence=None, write_period: int = 1
):
    """Envía `n_samples` muestras crecientes y recoge lo que sale por `m_*`.

    `ready_sequence`, si se da, es un iterable de valores de `m_ready` que se
    aplica ciclo a ciclo (se recicla si se agota) — así se puede meter
    intermitencia sin parar el ritmo de entrada.

    `write_period` espacia las muestras de entrada cada N ciclos en vez de
    mandarlas pegadas. Hace falta para probar backpressure de verdad: el único
    margen que da el ping-pong es UN rayo completo, así que un lector con
    algún hueco de `m_ready=0` solo se sostiene si, en promedio, drena al menos
    tan rápido como entra — y a una muestra por ciclo (el caso de los otros
    tests, fieles al hand-shake sin `s_ready` de `drx_ddc_top`) eso exige
    `m_ready=1` casi siempre. `drx_ddc_top` real entrega una muestra cada R1/R2
    ciclos de `FS_HZ` (208/416, muy por encima de 1), así que espaciar aquí no
    es relajar el test: es el caso realista.
    """
    dut.mode_coarse.value = 1 if mode_coarse else 0

    sent = []
    received = []

    def next_ready(i: int) -> int:
        if ready_sequence is None:
            return 1
        return ready_sequence[i % len(ready_sequence)]

    def _sample() -> None:
        # Se muestrea el par valid/ready TAL COMO ESTÁ, antes de tocar ninguna
        # entrada para el ciclo siguiente: es el valor estable de este ciclo,
        # el que de verdad decide si hay transferencia en el próximo flanco.
        # Muestrear después de `await RisingEdge` en vez de antes lee el
        # `m_valid` YA actualizado por ese flanco (combinacional sobre un
        # registro que acaba de cambiar) contra un `m_ready` que en la
        # siguiente iteración todavía no se ha vuelto a fijar — un
        # desfase de un ciclo entre los dos lados del hand-shake.
        if int(dut.m_valid.value) and int(dut.m_ready.value):
            i_val = int(dut.m_i.value.signed_integer)
            q_val = int(dut.m_q.value.signed_integer)
            received.append((i_val, q_val, bool(dut.m_last.value)))

    cycle = 0
    for n in range(n_samples):
        for _ in range(write_period - 1):
            _sample()
            dut.s_valid.value = 0
            dut.m_ready.value = next_ready(cycle)
            cycle += 1
            await RisingEdge(dut.clk)

        _sample()

        i_val = n
        q_val = n + 1000
        dut.s_valid.value = 1
        dut.s_i.value = i_val
        dut.s_q.value = q_val
        dut.m_ready.value = next_ready(cycle)
        cycle += 1

        await RisingEdge(dut.clk)
        sent.append((i_val, q_val))

    # Deja de meter estímulo pero sigue dando ciclos de reloj para que el
    # lado de lectura drene lo que ya está completo en el banco pendiente.
    dut.s_valid.value = 0
    for _ in range(n_samples + 16):
        _sample()
        dut.m_ready.value = next_ready(cycle)
        cycle += 1
        await RisingEdge(dut.clk)
    _sample()

    return sent, received


@cocotb.test()
async def test_orden_y_tlast_modo_fino(dut):
    """En modo fino, `m_last` cae cada `BINS_FINE` muestras y el orden se conserva."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    n_rays = 5
    sent, received = await _feed_and_collect(dut, BINS_FINE * n_rays, mode_coarse=False)

    assert len(received) == len(sent), f"se perdieron muestras: {len(received)} de {len(sent)}"
    assert [(i, q) for i, q, _ in received] == sent, "el orden de (i, q) no coincide con lo enviado"

    last_flags = [last for _, _, last in received]
    expected_last = [(idx % BINS_FINE) == (BINS_FINE - 1) for idx in range(len(sent))]
    assert last_flags == expected_last, "m_last no cae en la muestra bins-1 de cada rayo"


@cocotb.test()
async def test_orden_y_tlast_modo_grueso(dut):
    """Mismo criterio que en fino, con `BINS_COARSE`."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    n_rays = 6
    sent, received = await _feed_and_collect(dut, BINS_COARSE * n_rays, mode_coarse=True)

    assert len(received) == len(sent), f"se perdieron muestras: {len(received)} de {len(sent)}"
    assert [(i, q) for i, q, _ in received] == sent
    last_flags = [last for _, _, last in received]
    expected_last = [(idx % BINS_COARSE) == (BINS_COARSE - 1) for idx in range(len(sent))]
    assert last_flags == expected_last


@cocotb.test()
async def test_backpressure_intermitente_no_pierde_muestras(dut):
    """`m_ready` intermitente no debe perder ni reordenar muestras, solo retrasarlas."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    random.seed(0)
    # Duty de listo ~75 % frente a una entrada espaciada cada 2 ciclos (duty
    # de escritura 50 %): el lector drena de sobra en promedio, con huecos
    # cortos que el ping-pong absorbe sin acercarse al margen de un rayo.
    ready_sequence = [random.choice([0, 1, 1, 1]) for _ in range(37)]

    n_rays = 4
    sent, received = await _feed_and_collect(
        dut, BINS_FINE * n_rays, mode_coarse=False, ready_sequence=ready_sequence, write_period=2
    )

    assert len(received) == len(sent), (
        f"se perdieron muestras bajo backpressure: {len(received)} de {len(sent)}"
    )
    assert [(i, q) for i, q, _ in received] == sent


@cocotb.test()
async def test_overrun_se_dispara_si_el_lector_no_vacia_a_tiempo(dut):
    """Sin `m_ready`, al tercer rayo completo un banco se pisa sin haberse vaciado nunca: `overrun`.

    Con solo dos bancos, el primero en pisarse sin leer es el que ya se había
    llenado una vez (banco 0, rayo 1) cuando le vuelve a tocar turno de
    escritura (rayo 3) — el rayo 2 llena el banco 1 por primera vez y no
    dispara nada todavía.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    dut.mode_coarse.value = 0
    dut.m_ready.value = 0

    assert int(dut.overrun.value) == 0, "overrun arranca en alto sin haber corrido nada"

    async def _run_one_ray() -> None:
        for n in range(BINS_FINE):
            dut.s_valid.value = 1
            dut.s_i.value = n
            dut.s_q.value = n
            await RisingEdge(dut.clk)
        dut.s_valid.value = 0
        await RisingEdge(dut.clk)

    await _run_one_ray()
    assert int(dut.overrun.value) == 0, "overrun no debería dispararse tras un solo rayo"

    await _run_one_ray()
    assert int(dut.overrun.value) == 0, (
        "overrun no debería dispararse tras el segundo rayo (banco distinto)"
    )

    await _run_one_ray()
    assert int(dut.overrun.value) == 1, "overrun no se disparó al reusar un banco nunca leído"


@cocotb.test()
async def test_clear_limpia_overrun_y_permite_un_segundo_disparo(dut):
    """`clear` (mapa de registros AXI-Lite) borra `overrun`, y un overrun
    genuino posterior se vuelve a ver — sin esto, `overrun` es sticky para
    siempre y firmware nunca podría rearmarlo (ver la cabecera del RTL).
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    dut.mode_coarse.value = 0
    dut.m_ready.value = 0

    async def _run_one_ray() -> None:
        for n in range(BINS_FINE):
            dut.s_valid.value = 1
            dut.s_i.value = n
            dut.s_q.value = n
            await RisingEdge(dut.clk)
        dut.s_valid.value = 0
        await RisingEdge(dut.clk)

    for _ in range(3):
        await _run_one_ray()
    assert int(dut.overrun.value) == 1, "precondición: overrun disparado tras el tercer rayo"

    # Se sondea en vez de asumir un ciclo exacto: un valor recién escrito
    # desde la corrutina justo al reanudar tras un `await RisingEdge` puede
    # tardar un flanco extra en verse desde el lado de cocotb/Verilator —
    # mismo tipo de desfase de un ciclo que ya documenta `_sample()` más
    # arriba para valid/ready, aquí sobre una entrada en vez de un handshake.
    dut.clear.value = 1
    for _ in range(4):
        await RisingEdge(dut.clk)
        if int(dut.overrun.value) == 0:
            break
    else:
        raise AssertionError("clear no limpió overrun en un margen razonable de ciclos")
    dut.clear.value = 0

    # Bancos ya sucios de la secuencia anterior (ninguno se ha vaciado nunca,
    # `m_ready` sigue en 0): el siguiente rayo que reutilice un banco pendiente
    # dispara un overrun NUEVO, y clear ya lo había limpiado — confirma que de
    # verdad se rearmó, no que se quedó en 0 por casualidad.
    await _run_one_ray()
    assert int(dut.overrun.value) == 1, (
        "overrun no se volvió a disparar tras limpiarlo con clear: no se rearmó"
    )

    # Un overrun genuino el mismo ciclo que `clear` tiene que ganar: no se
    # puede perder un fallo real por una carrera con la limpieza de firmware.
    dut.clear.value = 1
    for n in range(BINS_FINE):
        dut.s_valid.value = 1
        dut.s_i.value = n
        dut.s_q.value = n
        await RisingEdge(dut.clk)
    dut.s_valid.value = 0
    dut.clear.value = 0
    # Mismo ciclo de asentamiento que ya usa `_run_one_ray()` antes de que su
    # llamador lea `overrun` — sin él, la lectura cae justo en el flanco en que
    # `s_valid`/`clear` todavía se están soltando.
    await RisingEdge(dut.clk)
    assert int(dut.overrun.value) == 1, "el set debe ganar sobre un clear concurrente"
