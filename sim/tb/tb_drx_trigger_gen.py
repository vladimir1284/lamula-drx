"""L0 — `drx_trigger_gen`, el generador de N_TRIGGERS triggers (retardo+ancho) de Z2.

Oráculo: `model/drx_model/timing.py::one_shot_active_cycles` (D-03) -- ningún
ciclo de actividad esperado se calcula a mano aquí.

Convención de ciclo: "ciclo N" es el N-ésimo estado muestreado por
`_drive_and_sample`, empezando en 0 ANTES del primer `RisingEdge` -- lo mismo
que ya usa `tb_drx_prf_batch_seq.py` (ver su cabecera) y por el mismo motivo:
`trig_out` es la salida de `drx_trigger_one_shot`, registrada, pero `arm` en sí
se decide y se deja estable un ciclo entero ANTES de que la FF lo muestree en
el flanco que cierra ese ciclo, así que fijar `arm` y leer `trig_out` dentro de
la misma iteración (con `await ReadOnly()` de por medio) es consistente ciclo
a ciclo, incluido el primero.
"""

from __future__ import annotations

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge
from drx_model import timing
from drx_model.params import load

PARAMS = load("zedboard")
CLK_PERIOD_PS = round(1e12 / PARAMS.fs_hz)  # clock-const-ok: conversión de unidades s->ps

N_TRIGGERS = 4


async def _reset(dut) -> None:
    dut.rst_n.value = 0
    dut.arm.value = 0
    for ch in range(N_TRIGGERS):
        dut.delay[ch].value = 0
        dut.width[ch].value = 1
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def _drive_and_sample(dut, n_cycles: int, arm_cycles: set[int]) -> list[list[bool]]:
    """Por cada ciclo 0..n_cycles-1: fija `arm` (alto si el ciclo está en
    `arm_cycles`) y muestrea `trig_out` de los N_TRIGGERS canales."""
    samples = []
    for cycle in range(n_cycles):
        dut.arm.value = 1 if cycle in arm_cycles else 0
        await ReadOnly()
        bits = int(dut.trig_out.value)
        samples.append([bool((bits >> ch) & 1) for ch in range(N_TRIGGERS)])
        await RisingEdge(dut.clk)
    return samples


@cocotb.test()
async def test_cada_canal_respeta_su_propio_delay_y_width(dut):
    """Un solo `arm`, 4 canales con retardo/ancho distintos -- cada uno tiene que
    coincidir con `one_shot_active_cycles`, independiente de los otros tres."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    configs = [(0, 3), (2, 1), (5, 4), (1, 2)]  # (delay, width) por canal
    for ch, (delay, width) in enumerate(configs):
        dut.delay[ch].value = delay
        dut.width[ch].value = width

    n_cycles = 20
    samples = await _drive_and_sample(dut, n_cycles, arm_cycles={0})

    for ch, (delay, width) in enumerate(configs):
        expected = set(timing.one_shot_active_cycles(arm_cycle=0, delay=delay, width=width))
        observed = {c for c in range(n_cycles) if samples[c][ch]}
        assert observed == expected, f"canal {ch}: {observed} != {expected}"


@cocotb.test()
async def test_un_arme_nuevo_reinicia_el_canal_last_arm_wins(dut):
    """Un `arm` que llega en medio del retardo o del pulso reinicia el canal desde
    cero -- la semántica que documenta la cabecera de `drx_trigger_one_shot.sv`.
    Con delay=2, un primer arme en el ciclo 0 dispararía recién en el ciclo 3; un
    segundo arme en el ciclo 2 (antes de eso) tiene que ganar y correr el disparo
    a partir de ESE arme, no del primero."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    ch = 0
    dut.delay[ch].value = 2
    dut.width[ch].value = 5

    n_cycles = 15
    samples = await _drive_and_sample(dut, n_cycles, arm_cycles={0, 2})

    expected = set(timing.one_shot_active_cycles(arm_cycle=2, delay=2, width=5))
    observed = {c for c in range(n_cycles) if samples[c][ch]}
    assert observed == expected, f"{observed} != {expected}"


@cocotb.test()
async def test_sin_armar_nunca_dispara(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    for ch in range(N_TRIGGERS):
        dut.delay[ch].value = 0
        dut.width[ch].value = 3

    samples = await _drive_and_sample(dut, 10, arm_cycles=set())
    assert not any(any(sample) for sample in samples), "disparó sin haberse armado nunca"
