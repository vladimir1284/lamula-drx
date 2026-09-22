"""L0 — `drx_timing_engine`: la composición de `drx_prf_batch_seq` +
`drx_trigger_gen` (Z2). No revuelve la corrección interna de ninguno de los
dos -- eso ya lo prueban sus propios L0 -- solo el cableado: que los
NTriggers se arman con CADA `pulse_trig` del secuenciador de lotes, ninguno
menos y ninguno de más.

Oráculo, igual que en los dos L0 que compone: `model/drx_model/timing.py`.
Los ciclos de disparo salen de `radial_trigger_times_cycles`; los ciclos
activos de cada trigger, de `one_shot_active_cycles` aplicado a CADA uno de
esos disparos (D-03).
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
# (delay, width) por canal, deliberadamente pequeños frente a prf_div_low/high
# de _radial_ejemplo() (7 y 5): así ningún trigger se solapa con el disparo
# siguiente y el "último arm gana" de drx_trigger_one_shot.sv nunca entra en
# juego -- lo que aquí se prueba es el cableado, no esa semántica (ya cubierta
# en tb_drx_trigger_gen.py).
TRIGGER_CONFIGS = [(0, 2), (1, 1), (2, 2), (0, 1)]


def _radial_ejemplo() -> timing.RadialBatches:
    low = timing.Batch(prf_div=7, pulse_width_cycles=1, n_pulses=2)
    high = timing.Batch(prf_div=5, pulse_width_cycles=1, n_pulses=2)
    return timing.RadialBatches(low=low, high=high)


async def _reset(dut) -> None:
    dut.rst_n.value = 0
    dut.enable.value = 0
    dut.prf_div_low.value = 1
    dut.pulse_width_low.value = 0
    dut.n_pulses_low.value = 1
    dut.prf_div_high.value = 1
    dut.pulse_width_high.value = 0
    dut.n_pulses_high.value = 1
    for ch in range(N_TRIGGERS):
        dut.trig_delay[ch].value = 0
        dut.trig_width[ch].value = 1
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_los_4_triggers_se_arman_con_cada_pulso_de_prf(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    batches = _radial_ejemplo()
    dut.prf_div_low.value = batches.low.prf_div
    dut.pulse_width_low.value = batches.low.pulse_width_cycles
    dut.n_pulses_low.value = batches.low.n_pulses
    dut.prf_div_high.value = batches.high.prf_div
    dut.pulse_width_high.value = batches.high.pulse_width_cycles
    dut.n_pulses_high.value = batches.high.n_pulses
    for ch, (delay, width) in enumerate(TRIGGER_CONFIGS):
        dut.trig_delay[ch].value = delay
        dut.trig_width[ch].value = width
    dut.enable.value = 1

    n_cycles = batches.dwell_cycles()
    trig_out_samples = []
    pulse_trig_samples = []
    for _ in range(n_cycles):
        await ReadOnly()
        trig_out_samples.append(int(dut.trig_out.value))
        pulse_trig_samples.append(bool(dut.pulse_trig.value))
        await RisingEdge(dut.clk)

    low_times, high_times = timing.radial_trigger_times_cycles(batches, start_cycle=0)
    arm_cycles = sorted(int(c) for c in list(low_times) + list(high_times))

    # El propio motor tiene que producir esos disparos: confirma que la
    # composición no perdió ni desplazó ninguno.
    observed_arms = [c for c in range(n_cycles) if pulse_trig_samples[c]]
    assert observed_arms == arm_cycles, f"{observed_arms} != {arm_cycles}"

    for ch, (delay, width) in enumerate(TRIGGER_CONFIGS):
        expected = set()
        for arm in arm_cycles:
            expected |= set(timing.one_shot_active_cycles(arm, delay, width))
        observed = {c for c in range(n_cycles) if (trig_out_samples[c] >> ch) & 1}
        assert observed == expected, f"canal {ch}: {observed} != {expected}"
