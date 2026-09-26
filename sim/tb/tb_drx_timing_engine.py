"""L0 — `drx_timing_engine`: la composición de `drx_prf_batch_seq` +
`drx_trigger_gen` + `drx_timing_config_valid` x2 (Z2). No revuelve la
corrección interna de ninguno -- eso ya lo prueban sus propios L0 -- solo el
cableado.

Dos builds distintos, ver `sim/tests/test_l0_timing_engine.py`:

- `PrfDivMinRangeLow/High` overrideados a 1 (sin piso): los dos primeros
  tests, que confirman que los NTriggers se arman con CADA `pulse_trig` del
  secuenciador de lotes (ninguno menos y ninguno de más) y que un lote
  inválido por D-09 autocontenido congela el motor. Usan `prf_div_low/high`
  pequeños a propósito -- con el piso real activo, esos valores ya serían
  inválidos por D-09 completo y no probarían el cableado que dicen probar.
- Sin override (los reales de producción, PRF_DIV_MIN_LOW/HIGH y
  BinsMaxLow/High = BINS_MODE_FINE): `test_pisos_reales_de_produccion_gatean_enable`
  y `test_techo_real_de_bins_gatea_enable` (D-15), solo checks combinacionales
  alrededor de la frontera -- un dwell completo a esa escala sería
  impracticable en L0.

Oráculo, igual que en los L0 que compone: `model/drx_model/timing.py`. Los
ciclos de disparo salen de `radial_trigger_times_cycles`; los ciclos activos
de cada trigger, de `one_shot_active_cycles` aplicado a CADA uno de esos
disparos (D-03).
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
# de _radial_ejemplo(): así ningún trigger se solapa con el disparo siguiente
# y el "último arm gana" de drx_trigger_one_shot.sv nunca entra en juego -- lo
# que aquí se prueba es el cableado, no esa semántica (ya cubierta en
# tb_drx_trigger_gen.py).
TRIGGER_CONFIGS = [(0, 2), (1, 1), (2, 2), (0, 1)]


def _radial_ejemplo() -> timing.RadialBatches:
    """`pulse_width_cycles=200` en los dos lotes a propósito, no un valor
    pequeño arbitrario como en otros L0 de Z2 (`tb_drx_prf_batch_seq.py`,
    `tb_drx_trigger_gen.py`): desde que `drx_timing_engine` gatea `enable`
    contra D-09 autocontenido (checks de `drx_timing_config_valid.sv`), un
    ancho fuera de la tabla de `config/params.toml` dejaría el motor entero
    sin correr y esta prueba no probaría el cableado que dice probar."""
    low = timing.Batch(prf_div=201, pulse_width_cycles=200, n_pulses=2)
    high = timing.Batch(prf_div=250, pulse_width_cycles=200, n_pulses=2)
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
    # D-15: bins_low/high por defecto en 1 -- válido con cualquier BinsMax de
    # este fichero (nunca overrideado a menos de 3689, el real de producción),
    # así que las pruebas que no ejercitan D-15 en sí no lo necesitan tocar.
    dut.bins_low.value = 1
    dut.bins_high.value = 1
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


@cocotb.test()
async def test_lote_invalido_deja_el_secuenciador_sin_correr(dut):
    """D-09 (checks autocontenidos): un `pulse_width` que no cabe en su propio
    PRI deja el lote inválido -- `config_invalid_*` sube y el motor entero se
    queda congelado (ningún `pulse_trig`/`trig_out`), igual que con `enable`
    en bajo, sin importar que `enable` esté en alto."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    # pulse_width_low=200 no cabe en un PRI de prf_div_low=7 (D-09 autocontenido);
    # el lote alto usa valores legales (tabla + cabe en su PRI) a propósito,
    # para aislar que es EL LOTE BAJO el que gatea el motor entero, no que
    # ambos sean ilegales por casualidad.
    dut.prf_div_low.value = 7
    dut.pulse_width_low.value = 200
    dut.n_pulses_low.value = 2
    dut.prf_div_high.value = 201
    dut.pulse_width_high.value = 200
    dut.n_pulses_high.value = 2
    dut.enable.value = 1
    await ReadOnly()
    assert bool(dut.config_invalid_low.value), "config_invalid_low no subió con un lote ilegal"
    assert not bool(dut.config_invalid_high.value), "el lote alto era legal, no debería marcarse"

    for _ in range(20):
        await RisingEdge(dut.clk)
        await ReadOnly()
        assert not bool(dut.pulse_trig.value), "el motor disparó con un lote inválido"
        assert int(dut.trig_out.value) == 0, "los triggers se armaron con un lote inválido"


@cocotb.test()
async def test_pisos_reales_de_produccion_gatean_enable(dut):
    """Sin override de parámetros (ver `test_l0_timing_engine_pisos_reales_de_
    produccion_verilator`): `PrfDivMinRangeLow`/`PrfDivMinRangeHigh` toman su
    valor por defecto, PRF_DIV_MIN_LOW/HIGH del paquete de parámetros -- los
    mismos que usa `drx_top.sv` en producción (460 km / 115 km WSR-88D-NEXRAD,
    D-09). Solo checks combinacionales alrededor de la frontera: un dwell
    completo con `prf_div` de ~767198 ciclos/lote sería impracticable en L0 y
    ya no probaría nada que `tb_drx_timing_config_valid.py` no pruebe bit a
    bit a ese nivel -- esto solo confirma que `drx_timing_engine` propaga el
    piso real hasta el gateo de `enable`."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    below_floor = PARAMS.prf_div_min_low - 1
    at_floor = PARAMS.prf_div_min_low

    dut.pulse_width_low.value = 200
    dut.n_pulses_low.value = 1
    dut.prf_div_high.value = PARAMS.prf_div_min_high  # muy por encima del piso alto, legal
    dut.pulse_width_high.value = 200
    dut.n_pulses_high.value = 1
    dut.enable.value = 1

    dut.prf_div_low.value = below_floor
    await ReadOnly()
    assert bool(dut.config_invalid_low.value), (
        f"prf_div_low={below_floor}, justo bajo el piso real de 460 km, debería ser inválido"
    )
    assert not bool(dut.config_invalid_high.value)

    await RisingEdge(dut.clk)
    dut.prf_div_low.value = at_floor
    await ReadOnly()
    assert not bool(dut.config_invalid_low.value), (
        f"prf_div_low={at_floor}, el piso real de 460 km exacto, debería ser válido"
    )


@cocotb.test()
async def test_techo_real_de_bins_gatea_enable(dut):
    """D-15, mismo build que el test anterior (sin override -- BinsMaxLow/High
    por defecto son BINS_MODE_FINE, el techo físico real de BRAM). Solo
    confirma que `drx_timing_engine` propaga ese techo hasta el gateo de
    `enable` -- el barrido bit a bit del check en sí ya lo hace
    `tb_drx_timing_config_valid.py`."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    bins_max = PARAMS.invariant["bins_mode_fine"]

    dut.prf_div_low.value = PARAMS.prf_div_min_low  # legal, justo el piso real
    dut.pulse_width_low.value = 200
    dut.n_pulses_low.value = 1
    dut.prf_div_high.value = PARAMS.prf_div_min_high
    dut.pulse_width_high.value = 200
    dut.n_pulses_high.value = 1
    dut.enable.value = 1

    dut.bins_low.value = bins_max + 1
    await ReadOnly()
    assert bool(dut.config_invalid_low.value), (
        f"bins_low={bins_max + 1}, justo sobre el techo físico real, debería ser inválido"
    )

    await RisingEdge(dut.clk)
    dut.bins_low.value = bins_max
    await ReadOnly()
    assert not bool(dut.config_invalid_low.value), (
        f"bins_low={bins_max}, el techo físico real exacto, debería ser válido"
    )
