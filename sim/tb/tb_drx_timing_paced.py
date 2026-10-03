"""L0 — el motor de timing paceado por avance de muestra (P-16).

La afirmación que hay que falsar es exactamente una: **pacear cambia la base
de tiempo del motor y nada más**. No "funciona"; que la secuencia de eventos
observada en los ciclos de avance sea LA MISMA que la del motor sin pacear,
disparo a disparo, lote a lote.

Por eso el oráculo aquí no es `model/drx_model/timing.py` sino el propio motor
corriendo sin pacear: el modelo dorado ya cubre la corrección del
secuenciador (`tb_drx_prf_batch_seq.py`), y volver a compararlo contra él no
diría nada sobre el pacing. Lo que falta por probar es la EQUIVALENCIA entre
las dos bases de tiempo, y eso se prueba contra la base de tiempo vieja.

Un patrón de avance irregular (no 1 de cada K fijo) a propósito: el DMA MM2S
de Throttled(DDR) no entrega a cadencia regular, y un hueco periódico podría
esconder un error que dependiera de la alineación entre el hueco y el PRI.
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

# Patrón de avance: 1 = hay muestra este ciclo, 0 = la fuente no entrega.
# Irregular y con una racha larga de ceros, que es el caso que de verdad
# rompería un motor que contara ciclos.
PATRON_AVANCE = [1, 0, 0, 0, 1, 0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0]


def _radial_ejemplo() -> timing.RadialBatches:
    """Mismo radial que `tb_drx_timing_engine.py`: `pulse_width_cycles=200`
    para no caer fuera de la tabla de D-09 y dejar el motor sin correr."""
    low = timing.Batch(prf_div=201, pulse_width_cycles=200, n_pulses=2)
    high = timing.Batch(prf_div=250, pulse_width_cycles=200, n_pulses=2)
    return timing.RadialBatches(low=low, high=high)


async def _reset(dut) -> None:
    dut.rst_n.value = 0
    dut.enable.value = 0
    dut.advance.value = 1
    dut.prf_div_low.value = 1
    dut.pulse_width_low.value = 0
    dut.n_pulses_low.value = 1
    dut.prf_div_high.value = 1
    dut.pulse_width_high.value = 0
    dut.n_pulses_high.value = 1
    dut.bins_low.value = 1
    dut.bins_high.value = 1
    for ch in range(N_TRIGGERS):
        dut.trig_delay[ch].value = 0
        dut.trig_width[ch].value = 1
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


def _configura(dut, batches: timing.RadialBatches) -> None:
    dut.prf_div_low.value = batches.low.prf_div
    dut.pulse_width_low.value = batches.low.pulse_width_cycles
    dut.n_pulses_low.value = batches.low.n_pulses
    dut.prf_div_high.value = batches.high.prf_div
    dut.pulse_width_high.value = batches.high.pulse_width_cycles
    dut.n_pulses_high.value = batches.high.n_pulses
    for ch in range(N_TRIGGERS):
        dut.trig_delay[ch].value = 0
        dut.trig_width[ch].value = 1


async def _traza(dut, n_avances: int, patron: list[int]) -> list[tuple[int, int, int]]:
    """Corre hasta acumular `n_avances` ciclos de avance y devuelve, SOLO en
    esos ciclos, la tupla (pulse_trig, batch_sel, tx_gate).

    Muestrear solo en los avances es la mitad del experimento: en la base de
    tiempo vieja todos los ciclos son avances, así que la traza es la de
    siempre; en la nueva, los ciclos sin avance son tiempo que el motor no
    vive y no deben aparecer en la comparación.
    """
    traza: list[tuple[int, int, int]] = []
    i = 0
    while len(traza) < n_avances:
        avance = patron[i % len(patron)]
        i += 1
        dut.advance.value = avance
        await ReadOnly()
        if avance:
            traza.append(
                (
                    int(dut.pulse_trig.value),
                    int(dut.batch_sel.value),
                    int(dut.tx_gate.value),
                )
            )
        await RisingEdge(dut.clk)
    return traza


@cocotb.test()
async def test_paceado_da_la_misma_traza_que_sin_pacear(dut):
    """El experimento entero. Dos radiales completos en las dos bases de
    tiempo, comparados muestra a muestra."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    batches = _radial_ejemplo()
    # Dos radiales completos: (201*2 + 250*2) * 2 = 1804 avances.
    n_avances = (
        batches.low.prf_div * batches.low.n_pulses
        + batches.high.prf_div * batches.high.n_pulses
    ) * 2

    await _reset(dut)
    _configura(dut, batches)
    dut.enable.value = 1
    await RisingEdge(dut.clk)
    sin_pacear = await _traza(dut, n_avances, [1])

    dut.enable.value = 0
    await _reset(dut)
    _configura(dut, batches)
    dut.enable.value = 1
    await RisingEdge(dut.clk)
    paceado = await _traza(dut, n_avances, PATRON_AVANCE)

    assert paceado == sin_pacear, (
        "la traza paceada diverge de la de ciclos en el avance "
        f"{next(k for k, (a, b) in enumerate(zip(paceado, sin_pacear, strict=True)) if a != b)}"
    )


@cocotb.test()
async def test_pulse_trig_dura_un_solo_ciclo_aunque_el_motor_este_parado(dut):
    """La trampa concreta que este diseño tuvo que esquivar.

    `pulse_trig` es combinacional sobre `pri_cnt == 0`. Si el `advance` solo
    gateara los `always_ff`, `pri_cnt` se quedaría en 0 durante todos los
    ciclos sin avance y `pulse_trig` saldría ANCHO -- y lo consumen
    `ray_start` (D-14) y el contador TRIG_COUNT, que contarían varias veces el
    mismo pulso de PRF. Aquí se para el motor justo encima de un disparo.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)
    _configura(dut, _radial_ejemplo())
    dut.advance.value = 0
    dut.enable.value = 1

    # Con el motor armado y parado, `pri_cnt` vale 0 (el estado de reset), que
    # es justo la condición de disparo. Diez ciclos sin avance: ni uno solo
    # puede dar `pulse_trig`.
    altos_parado = 0
    for _ in range(10):
        await ReadOnly()
        altos_parado += int(dut.pulse_trig.value)
        await RisingEdge(dut.clk)
    assert altos_parado == 0, f"{altos_parado} pulsos con el motor parado"

    # Un único ciclo de avance sobre `pri_cnt == 0`: exactamente un pulso.
    dut.advance.value = 1
    await ReadOnly()
    assert int(dut.pulse_trig.value) == 1, "el avance no produjo el disparo"
    await RisingEdge(dut.clk)
    dut.advance.value = 0
    altos_despues = 0
    for _ in range(10):
        await ReadOnly()
        altos_despues += int(dut.pulse_trig.value)
        await RisingEdge(dut.clk)
    assert altos_despues == 0, f"el disparo se repitió {altos_despues} veces"
