"""L0 — `drx_prf_batch_seq`, el secuenciador de 2 lotes de PRF/ancho de pulso de Z2 (D-13).

Oráculo: `model/drx_model/timing.py`. Nada de esto reimplementa la aritmética de
PRI a mano -- los tiempos de disparo esperados salen de
`timing.sweep_trigger_times_cycles`, el mismo generador que ya tiene sus propios
tests en `model/tests/test_timing.py` (D-03: el modelo dorado es el oráculo).

Cadencia de muestreo: `pulse_trig` es puramente combinacional sobre un contador
que ya vale 0 nada más salir de reset/armar (para que el primer pulso caiga en
el ciclo 0, igual que `start_cycle=0` en el modelo, sin latencia de más). Por
eso el "ciclo 0" existe como un nivel estable de un periodo de reloj ENTERO
-- no un glitch de una transición -- pero cae ANTES del primer `RisingEdge`
que se espera tras armar. `await ReadOnly()` antes de cada lectura, sin
esperar antes ningún flanco en la primera vuelta, es lo que lo hace visible:
resuelve el asentamiento combinacional del instante actual, haya habido o no
un flanco de por medio, así que el mismo bucle sirve para el ciclo 0 y para
todos los siguientes.
"""

from __future__ import annotations

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge
from drx_model import timing
from drx_model.params import load

PARAMS = load("zedboard")
CLK_PERIOD_PS = round(1e12 / PARAMS.fs_hz)  # clock-const-ok: conversión de unidades s->ps


async def _reset(dut) -> None:
    dut.rst_n.value = 0
    dut.enable.value = 0
    dut.prf_div_low.value = 1
    dut.pulse_width_low.value = 0
    dut.n_pulses_low.value = 1
    dut.prf_div_high.value = 1
    dut.pulse_width_high.value = 0
    dut.n_pulses_high.value = 1
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


def _apply_batches(dut, batches: timing.RadialBatches) -> None:
    dut.prf_div_low.value = batches.low.prf_div
    dut.pulse_width_low.value = batches.low.pulse_width_cycles
    dut.n_pulses_low.value = batches.low.n_pulses
    dut.prf_div_high.value = batches.high.prf_div
    dut.pulse_width_high.value = batches.high.pulse_width_cycles
    dut.n_pulses_high.value = batches.high.n_pulses


async def _run(dut, n_cycles: int) -> list[dict]:
    """Corre `n_cycles` ciclos desde que `enable` ya está en alto y devuelve, por
    ciclo, un dict con las señales de salida -- una entrada por ciclo, no solo
    en los disparos, para poder comprobar también `tx_gate` fuera de los `trig`.
    """
    samples = []
    for cycle in range(n_cycles):
        await ReadOnly()
        samples.append(
            {
                "cycle": cycle,
                "trig": bool(dut.pulse_trig.value),
                "batch_sel": int(dut.batch_sel.value),
                "tx_gate": bool(dut.tx_gate.value),
                "radial_done": bool(dut.radial_done.value),
            }
        )
        await RisingEdge(dut.clk)
    return samples


def _radial_ejemplo() -> timing.RadialBatches:
    """Divisores pequeños a propósito, mismo motivo que `DIV` en
    `tb_drx_heartbeat.py`: un lote NEXRAD real dura milisegundos de `fs` real,
    no unas pocas decenas de ciclos simulables."""
    low = timing.Batch(prf_div=7, pulse_width_cycles=2, n_pulses=3)
    high = timing.Batch(prf_div=4, pulse_width_cycles=1, n_pulses=5)
    return timing.RadialBatches(low=low, high=high)


@cocotb.test()
async def test_los_disparos_coinciden_bit_a_bit_con_el_modelo_dorado(dut):
    """`pulse_trig`/`batch_sel` del RTL, ciclo a ciclo, contra
    `timing.sweep_trigger_times_cycles` -- ningún valor esperado se calcula a
    mano aquí."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    batches = _radial_ejemplo()
    n_radiales = 3
    _apply_batches(dut, batches)
    dut.enable.value = 1

    dwell = batches.dwell_cycles()
    samples = await _run(dut, n_cycles=n_radiales * dwell)

    low_times, high_times = timing.sweep_trigger_times_cycles(batches, n_radiales=n_radiales)
    expected = sorted(
        [(int(c), 0) for c in low_times] + [(int(c), 1) for c in high_times]
    )

    observed = [(s["cycle"], s["batch_sel"]) for s in samples if s["trig"]]
    assert observed == expected, f"disparos != modelo: {observed} != {expected}"


@cocotb.test()
async def test_radial_done_marca_el_arranque_de_cada_radial_menos_el_primero(dut):
    """`radial_done` es el propio secuenciador anunciando que cerró el lote alto
    y empieza uno nuevo -- no puede dispararse en el primer radial (D-13: nunca
    hubo un lote alto anterior que cerrar)."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    batches = _radial_ejemplo()
    n_radiales = 3
    _apply_batches(dut, batches)
    dut.enable.value = 1

    dwell = batches.dwell_cycles()
    samples = await _run(dut, n_cycles=n_radiales * dwell)

    done_cycles = [s["cycle"] for s in samples if s["radial_done"]]
    expected = [k * dwell for k in range(1, n_radiales)]
    assert done_cycles == expected, f"{done_cycles} != {expected}"

    # Coincide con el primer disparo (lote bajo) de cada radial nuevo, nunca con
    # el del lote alto.
    for cycle in done_cycles:
        matching = [s for s in samples if s["cycle"] == cycle]
        assert matching[0]["trig"] and matching[0]["batch_sel"] == 0


@cocotb.test()
async def test_tx_gate_dura_el_ancho_de_pulso_del_lote_activo(dut):
    """El ancho de `tx_gate` es el de REGISTRO del lote que disparó, no una
    constante global -- el punto entero de que D-13 pida ancho por lote."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    batches = _radial_ejemplo()
    _apply_batches(dut, batches)
    dut.enable.value = 1

    dwell = batches.dwell_cycles()
    samples = await _run(dut, n_cycles=dwell)  # un radial completo: lote bajo + lote alto

    def _gate_cycles_after(trig_cycle: int, width: int) -> list[int]:
        lo, hi = trig_cycle, trig_cycle + width
        return [s["cycle"] for s in samples if s["tx_gate"] and lo < s["cycle"] <= hi]

    # Primer disparo del lote bajo: cycle 0.
    low_gate_cycles = _gate_cycles_after(0, batches.low.pulse_width_cycles)
    assert low_gate_cycles == list(range(1, batches.low.pulse_width_cycles + 1)), low_gate_cycles

    # Primer disparo del lote alto: cycle == batches.low.dwell_cycles().
    high_trig_cycle = batches.low.dwell_cycles()
    high_gate_cycles = _gate_cycles_after(high_trig_cycle, batches.high.pulse_width_cycles)
    high_width = batches.high.pulse_width_cycles
    expected_high = list(range(high_trig_cycle + 1, high_trig_cycle + high_width + 1))
    assert high_gate_cycles == expected_high, high_gate_cycles


@cocotb.test()
async def test_disabled_no_avanza(dut):
    """Con `enable` en bajo el secuenciador no dispara nunca -- es la garantía
    que necesita firmware para poder escribir los registros de configuración
    sin carreras contra un lote en curso (ver la cabecera del RTL)."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    batches = _radial_ejemplo()
    _apply_batches(dut, batches)
    # enable se queda en 0, puesto por _reset().

    samples = await _run(dut, n_cycles=3 * batches.dwell_cycles())
    assert not any(s["trig"] for s in samples), "disparó estando deshabilitado"
    assert not any(s["tx_gate"] for s in samples), "abrió tx_gate estando deshabilitado"
