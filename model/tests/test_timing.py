"""Motor de timing de Z2: secuenciador de 2 lotes de PRF/ancho de pulso por radial (D-13)."""

import numpy as np
import pytest
from drx_model import timing
from drx_model.params import load

PARAMS = load("zedboard")

# 318/1014 Hz "de pared" son los valores de ejemplo que trajo D-13; los expresamos como
# divisores de registro sobre PARAMS.fs_hz para no hardcodear una fs concreta aquí.
PRF_DIV_LOW = round(PARAMS.fs_hz / 318.0)
PRF_DIV_HIGH = round(PARAMS.fs_hz / 1014.0)


def _radial_ejemplo() -> timing.RadialBatches:
    low = timing.Batch(prf_div=PRF_DIV_LOW, pulse_width_cycles=200, n_pulses=5)
    high = timing.Batch(prf_div=PRF_DIV_HIGH, pulse_width_cycles=200, n_pulses=30)
    return timing.RadialBatches(low=low, high=high)


def test_un_lote_rechaza_ancho_de_pulso_mayor_que_su_propio_pri():
    with pytest.raises(ValueError):
        timing.Batch(prf_div=100, pulse_width_cycles=200, n_pulses=5)


def test_un_lote_rechaza_conteos_no_positivos():
    with pytest.raises(ValueError):
        timing.Batch(prf_div=1000, pulse_width_cycles=200, n_pulses=0)
    with pytest.raises(ValueError):
        timing.Batch(prf_div=0, pulse_width_cycles=200, n_pulses=5)


def test_batch_config_valid_acepta_ancho_en_tabla_que_cabe_en_el_pri():
    assert timing.batch_config_valid(
        PARAMS, prf_div=1000, pulse_width_cycles=200, prf_div_min_range=1
    )


def test_batch_config_valid_rechaza_ancho_fuera_de_tabla():
    assert not timing.batch_config_valid(
        PARAMS, prf_div=1000, pulse_width_cycles=201, prf_div_min_range=1
    )


def test_batch_config_valid_rechaza_ancho_que_no_cabe_en_el_pri():
    # 200 SÍ está en la tabla, pero no cabe en un PRI de 100 ciclos.
    assert not timing.batch_config_valid(
        PARAMS, prf_div=100, pulse_width_cycles=200, prf_div_min_range=1
    )


def test_batch_config_valid_no_levanta_excepcion_nunca():
    """A diferencia de `Batch`/`validate_batch`: es un oráculo booleano para
    comparar bit a bit contra RTL, no un validador que rechaza construcción."""
    assert (
        timing.batch_config_valid(PARAMS, prf_div=0, pulse_width_cycles=0, prf_div_min_range=1)
        is False
    )


def test_batch_config_valid_rechaza_prf_div_bajo_el_piso_de_rango():
    """El tercer check de D-09 (el corazón real, no solo los autocontenidos):
    un `pulse_width` legal y que cabe en su PRI igual se rechaza si `prf_div`
    no llega al piso de rango exigido."""
    assert not timing.batch_config_valid(
        PARAMS, prf_div=499, pulse_width_cycles=200, prf_div_min_range=500
    )
    assert timing.batch_config_valid(
        PARAMS, prf_div=500, pulse_width_cycles=200, prf_div_min_range=500
    )


def test_batch_config_valid_con_los_pisos_reales_de_produccion():
    """`PARAMS.prf_div_min_low/high` son los umbrales que de verdad usa
    `drx_timing_engine.sv` por defecto (460 km / 115 km WSR-88D-NEXRAD). El
    caso 1200 Hz es el mismo que ya documenta D-09 como físicamente imposible
    para el lote de vigilancia -- confirma que el piso bajo sí rechaza en la
    práctica. El piso alto, con los límites de PRF ya congelados
    (PRF_DIV_MIN/MAX), no rechaza nada -- ver el comentario de
    `config/params.toml` junto a `prf_div_min_high`.

    `prf_div_min` es el valor de REGISTRO invariante para 1200 Hz a 250 MHz
    (ZU9) -- no `round(PARAMS.fs_hz / 1200.0)`, que en ZedBoard daría un
    `prf_div` distinto (fs dilatada, D-02): mezclarlos compararía el piso
    invariante contra un `prf_div` de otra escala.
    """
    div_1200hz = PARAMS.invariant["prf_div_min"]
    assert not timing.batch_config_valid(
        PARAMS,
        prf_div=div_1200hz,
        pulse_width_cycles=200,
        prf_div_min_range=PARAMS.prf_div_min_low,
    )
    assert timing.batch_config_valid(
        PARAMS,
        prf_div=div_1200hz,
        pulse_width_cycles=200,
        prf_div_min_range=PARAMS.prf_div_min_high,
    )


def test_radial_batches_solo_admite_low_y_high():
    """El punto de D-13: el tipo mismo fija "2 lotes", no una lista de N."""
    fields = {f for f in timing.RadialBatches.__dataclass_fields__}
    assert fields == {"low", "high"}


def test_rango_no_ambiguo_es_c_entre_2prf():
    """326 Hz -> ~460 km, la misma tabla que trae D-09 en decisiones.md."""
    div_326hz = round(PARAMS.fs_hz / 326.0)
    assert timing.unambiguous_range_m(PARAMS, div_326hz) == pytest.approx(460_000, rel=2e-3)


def test_el_lote_bajo_tiene_mas_rango_no_ambiguo_que_el_alto():
    """Ese es el punto entero de Batch mode: vigilancia (rango largo) + Doppler (Nyquist bueno)."""
    batches = _radial_ejemplo()
    r_low = timing.unambiguous_range_m(PARAMS, batches.low.prf_div)
    r_high = timing.unambiguous_range_m(PARAMS, batches.high.prf_div)
    assert r_low > r_high


def test_validate_batch_rechaza_rango_no_ambiguo_insuficiente():
    """1200 Hz a 460 km es exactamente el caso imposible que documenta D-09."""
    batch_1200hz = timing.Batch(
        prf_div=round(PARAMS.fs_hz / 1200.0), pulse_width_cycles=200, n_pulses=5
    )
    with pytest.raises(timing.PrfRangeIllegal):
        timing.validate_batch(PARAMS, batch_1200hz, r_max_required_m=460_000)


def test_validate_batch_acepta_una_combinacion_legal():
    """El requisito se pide un poco por debajo de los 459,8 km reales de 326 Hz a propósito:
    `prf_div` es un entero redondeado, así que el rango exacto nunca cae en 460,000 km clavado."""
    batch_326hz = timing.Batch(
        prf_div=round(PARAMS.fs_hz / 326.0), pulse_width_cycles=200, n_pulses=5
    )
    timing.validate_batch(PARAMS, batch_326hz, r_max_required_m=459_000)  # no debe lanzar


def test_validate_radial_aplica_d09_a_cada_lote_por_separado():
    """El lote alto de Doppler nunca cumpliría el umbral de rango del lote bajo -- por eso D-13
    exige dos llamadas, no una."""
    batches = _radial_ejemplo()
    r_low_required = timing.unambiguous_range_m(PARAMS, batches.low.prf_div) - 1.0
    r_high_required = timing.unambiguous_range_m(PARAMS, batches.high.prf_div) - 1.0

    timing.validate_radial(PARAMS, batches, r_low_required, r_high_required)  # no debe lanzar

    with pytest.raises(timing.PrfRangeIllegal):
        # el umbral del lote bajo aplicado como si fuera el del lote alto: tiene que fallar,
        # porque son rangos no ambiguos distintos por diseño.
        timing.validate_radial(PARAMS, batches, r_low_required, r_low_required)


def test_validate_pulse_width_rechaza_un_ancho_fuera_de_tabla():
    batch = timing.Batch(prf_div=100_000, pulse_width_cycles=201, n_pulses=5)
    with pytest.raises(timing.PulseWidthInvalid):
        timing.validate_pulse_width(PARAMS, batch)


def test_validate_pulse_width_acepta_los_tres_de_la_tabla():
    for width in timing.pulse_width_table(PARAMS):
        batch = timing.Batch(prf_div=100_000, pulse_width_cycles=width, n_pulses=5)
        timing.validate_pulse_width(PARAMS, batch)  # no debe lanzar


def test_los_triggers_de_un_lote_estan_espaciados_por_prf_div():
    batch = timing.Batch(prf_div=1000, pulse_width_cycles=200, n_pulses=4)
    times = timing.trigger_times_cycles(batch, start_cycle=50)
    assert list(times) == [50, 1050, 2050, 3050]


def test_el_lote_alto_empieza_justo_cuando_termina_el_lote_bajo():
    """D-13: secuenciado autónomo en fabric, sin hueco entre lotes."""
    low = timing.Batch(prf_div=1000, pulse_width_cycles=200, n_pulses=3)
    high = timing.Batch(prf_div=100, pulse_width_cycles=50, n_pulses=5)
    batches = timing.RadialBatches(low=low, high=high)

    low_times, high_times = timing.radial_trigger_times_cycles(batches, start_cycle=0)

    assert list(low_times) == [0, 1000, 2000]
    assert high_times[0] == low.dwell_cycles()  # 3000: ni un ciclo antes ni un ciclo después
    assert list(high_times) == [3000, 3100, 3200, 3300, 3400]


def test_el_barrido_completo_no_deja_hueco_entre_radiales():
    """El bucle continuo de D-13 ("durante los 360°") no puede perder ni ganar ciclos en la
    frontera de un radial: el siguiente lote bajo empieza justo donde acaba el lote alto
    anterior."""
    batches = _radial_ejemplo()
    low_all, high_all = timing.sweep_trigger_times_cycles(batches, n_radiales=3)

    dwell = batches.dwell_cycles()
    assert low_all[0] == 0
    assert low_all[batches.low.n_pulses] == dwell  # primer trigger bajo del segundo radial
    assert low_all[2 * batches.low.n_pulses] == 2 * dwell

    # ningún trigger, de ningún lote, cae fuera de su radial.
    all_times = np.sort(np.concatenate([low_all, high_all]))
    assert all_times[-1] < 3 * dwell


def test_sweep_rechaza_cero_radiales():
    with pytest.raises(ValueError):
        timing.sweep_trigger_times_cycles(_radial_ejemplo(), n_radiales=0)


def test_one_shot_arranca_un_ciclo_despues_del_arme_mas_el_retardo():
    assert list(timing.one_shot_active_cycles(arm_cycle=100, delay=0, width=3)) == [101, 102, 103]
    assert list(timing.one_shot_active_cycles(arm_cycle=100, delay=5, width=3)) == [106, 107, 108]


def test_one_shot_rechaza_retardo_negativo_o_ancho_no_positivo():
    with pytest.raises(ValueError):
        timing.one_shot_active_cycles(arm_cycle=0, delay=-1, width=1)
    with pytest.raises(ValueError):
        timing.one_shot_active_cycles(arm_cycle=0, delay=0, width=0)
