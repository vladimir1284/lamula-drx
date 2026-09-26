"""L0 — `drx_ray_packer` (Z4.0, fases.md#z4), vía el shim
`sim/tb_sv/drx_ray_packer_tb_dut.sv` (ver su cabecera: la VPI de Verilator no
indexa arrays SIN empaquetar en un puerto de TOP, así que el DUT real de este
test es el shim, que solo reempaqueta puerto a puerto).

El módulo no tiene oráculo propio -- no hace aritmética, solo entrelaza en el
tiempo lo que ya entró -- así que el criterio de corrección es estructural:
por cada muestra donde los N_CH canales están `valid` a la vez, el stream de
salida tiene que traer, en orden (canal 0, 1, ..., N_CH-1), exactamente los
(i, q) que entraron ese ciclo, con `m_last` en alto SOLO en el último beat
(canal N_CH-1) de la muestra en la que TODOS los `s_last` de entrada estaban
altos a la vez.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from drx_model.params import load

PARAMS = load("zedboard")
CLK_PERIOD_PS = round(1e12 / PARAMS.fs_hz)  # clock-const-ok: conversión de unidades s->ps

N_CH = 3
IQ_BITS = 16
MASK1 = (1 << N_CH) - 1
IQ_MASK = (1 << IQ_BITS) - 1


def _pack_channels(values: list[int]) -> int:
    """Empaqueta N_CH valores de IQ_BITS bits, canal 0 en el grupo bajo — ver
    la cabecera del shim sobre el convenio de orden."""
    word = 0
    for c, v in enumerate(values):
        word |= (v & IQ_MASK) << (c * IQ_BITS)
    return word


def _pack_bits(flags: list[bool]) -> int:
    word = 0
    for c, f in enumerate(flags):
        if f:
            word |= 1 << c
    return word


def _split_word(word: int) -> tuple[int, int]:
    """`m_data` es `{cap_i, cap_q}` -- deshace el empaquetado, con signo."""
    i_raw = (word >> IQ_BITS) & IQ_MASK
    q_raw = word & IQ_MASK
    if i_raw >= (1 << (IQ_BITS - 1)):
        i_raw -= 1 << IQ_BITS
    if q_raw >= (1 << (IQ_BITS - 1)):
        q_raw -= 1 << IQ_BITS
    return i_raw, q_raw


async def _reset(dut) -> None:
    dut.rst_n.value = 0
    dut.s_valid.value = 0
    dut.s_i.value = 0
    dut.s_q.value = 0
    dut.s_last.value = 0
    dut.m_ready.value = 1
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def _drive_and_collect(dut, samples: list[list[tuple[int, int, bool]]], ready_sequence=None):
    """`samples[n][c] = (i, q, last)` -- una muestra por ciclo, un (i,q,last) por canal.

    Cuando los N_CH `s_valid` están altos a la vez (siempre, en este test --
    ver la cabecera del módulo sobre por qué no hace falta desincronizarlos
    para cubrir el contrato real), el empaquetador captura y sirve N_CH beats
    de salida antes de aceptar la siguiente muestra -- así que el estímulo de
    entrada se mantiene fijo hasta que `s_ready` confirma la captura.
    """
    received: list[tuple[int, int, bool]] = []

    def next_ready(i: int) -> int:
        if ready_sequence is None:
            return 1
        return ready_sequence[i % len(ready_sequence)]

    cycle = 0
    for sample in samples:
        i_vals = [s[0] for s in sample]
        q_vals = [s[1] for s in sample]
        last_vals = [s[2] for s in sample]

        dut.s_valid.value = MASK1
        dut.s_i.value = _pack_channels(i_vals)
        dut.s_q.value = _pack_channels(q_vals)
        dut.s_last.value = _pack_bits(last_vals)

        # Mantiene el estímulo estable hasta que `s_ready` confirma la
        # captura -- puede tardar varios ciclos si `m_ready` no está siempre
        # alto (todavía sirviendo la muestra anterior).
        captured = False
        while not captured:
            dut.m_ready.value = next_ready(cycle)
            if int(dut.m_valid.value) and int(dut.m_ready.value):
                word = int(dut.m_data.value)
                i_out, q_out = _split_word(word)
                received.append((i_out, q_out, bool(dut.m_last.value)))
            captured = int(dut.s_ready.value) == MASK1
            cycle += 1
            await RisingEdge(dut.clk)

        dut.s_valid.value = 0

        # Drena los N_CH-1 beats restantes de esta muestra antes de pasar a
        # la siguiente -- si no, el estímulo de la próxima muestra podría
        # capturarse mezclado con datos todavía en vuelo del anterior.
        while int(dut.m_valid.value):
            dut.m_ready.value = next_ready(cycle)
            if int(dut.m_valid.value) and int(dut.m_ready.value):
                word = int(dut.m_data.value)
                i_out, q_out = _split_word(word)
                received.append((i_out, q_out, bool(dut.m_last.value)))
            cycle += 1
            await RisingEdge(dut.clk)

    return received


@cocotb.test()
async def test_orden_entrelazado_y_tlast_por_muestra(dut):
    """Orden canal 0..N_CH-1 y `m_last` solo en el último beat del último rayo."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    bin_count = 4
    n_rays = 3
    n_samples = bin_count * n_rays

    samples = []
    expected: list[tuple[int, int, bool]] = []
    for n in range(n_samples):
        ray_last = (n % bin_count) == (bin_count - 1)
        sample = []
        for c in range(N_CH):
            i_val = 100 * c + n
            q_val = 1000 + 100 * c + n
            sample.append((i_val, q_val, ray_last))
            expected.append((i_val, q_val, ray_last and (c == N_CH - 1)))
        samples.append(sample)

    received = await _drive_and_collect(dut, samples)

    assert len(received) == len(expected), (
        f"beats recibidos {len(received)} != esperados {len(expected)}"
    )
    assert received == expected, "orden entrelazado o TLAST no coincide con lo esperado"


@cocotb.test()
async def test_ray_last_requiere_los_n_ch_a_la_vez(dut):
    """Si un solo canal no marca `s_last`, la muestra entera NO cierra rayo."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    # Canal 1 nunca marca `last`: ningún beat de esta muestra debe salir con
    # m_last en alto, ni siquiera el del canal N_CH-1.
    sample = [(1, 2, True), (3, 4, False), (5, 6, True)]
    received = await _drive_and_collect(dut, [sample])

    assert len(received) == N_CH
    assert not any(last for _, _, last in received), "m_last no debe depender de un solo canal"


@cocotb.test()
async def test_backpressure_intermitente_no_pierde_ni_reordena(dut):
    """`m_ready` intermitente retrasa los beats de salida, no los pierde ni reordena."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    random.seed(0)
    ready_sequence = [random.choice([0, 1, 1]) for _ in range(23)]

    bin_count = 5
    n_rays = 3
    n_samples = bin_count * n_rays

    samples = []
    expected: list[tuple[int, int, bool]] = []
    for n in range(n_samples):
        ray_last = (n % bin_count) == (bin_count - 1)
        sample = []
        for c in range(N_CH):
            i_val = 7 * c + n
            q_val = 2000 + 7 * c + n
            sample.append((i_val, q_val, ray_last))
            expected.append((i_val, q_val, ray_last and (c == N_CH - 1)))
        samples.append(sample)

    received = await _drive_and_collect(dut, samples, ready_sequence=ready_sequence)

    assert len(received) == len(expected), (
        f"se perdieron/duplicaron beats bajo backpressure: {len(received)} de {len(expected)}"
    )
    assert received == expected
