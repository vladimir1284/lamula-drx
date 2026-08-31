"""Enrejado en rango y generador de vectores."""

import numpy as np
import pytest
from drx_model import fixed, gating, vectors
from drx_model.params import load

PARAMS = load("zedboard")


def test_conteo_de_bins_por_modo():
    assert gating.bins_for_mode(PARAMS, "fine") == 3689
    assert gating.bins_for_mode(PARAMS, "coarse") == 1844


def test_los_rayos_completos_no_se_marcan_truncados():
    data = np.arange(30, dtype=np.int64)
    rays = gating.gate(data, data, bins=10)
    assert len(rays) == 3
    assert [ray.bins for ray in rays] == [10, 10, 10]
    assert not any(ray.truncated for ray in rays)


def test_un_rayo_corto_se_marca_en_vez_de_descartarse():
    """Un rayo corto en la placa es un fallo que el BITE tiene que ver."""
    data = np.arange(25, dtype=np.int64)
    rays = gating.gate(data, data, bins=10)
    assert [ray.bins for ray in rays] == [10, 10, 5]
    assert [ray.truncated for ray in rays] == [False, False, True]


def test_tlast_cae_en_la_ultima_muestra_de_cada_rayo():
    mask = gating.tlast_mask(30, bins=10)
    assert list(np.flatnonzero(mask)) == [9, 19, 29]


def test_gating_rechaza_entradas_descuadradas():
    with pytest.raises(ValueError):
        gating.gate(np.zeros(10), np.zeros(9), bins=5)


def test_el_tono_por_defecto_sale_en_el_if():
    n = 4096
    x = vectors.tone(PARAMS, n, dbfs=0.0)
    spectrum = np.abs(np.fft.rfft(x.astype(np.float64)))
    assert np.argmax(spectrum) / n == pytest.approx(float(PARAMS.if_norm), abs=1.0 / n)


def test_la_amplitud_en_dbfs_es_la_pedida():
    _, high = fixed.limits(PARAMS.sample_bits)
    for dbfs in (0.0, -6.0, -20.0):
        peak = np.max(np.abs(vectors.tone(PARAMS, 8192, dbfs=dbfs)))
        assert peak / high == pytest.approx(10 ** (dbfs / 20.0), rel=0.02)


def test_la_entrada_sobre_escala_satura_en_vez_de_envolver():
    """Envolver en vez de saturar convierte un pico en una raya espectral falsa."""
    x = vectors.tone(PARAMS, 4096, dbfs=+6.0)
    low, high = fixed.limits(PARAMS.sample_bits)
    assert x.max() == high
    assert x.min() == low


def test_los_vectores_son_identicos_en_las_dos_plataformas():
    """La consecuencia buscada de D-02: un vector, dos placas."""
    zed = vectors.tone(load("zedboard"), 2048)
    zu9 = vectors.tone(load("zu9"), 2048)
    assert np.array_equal(zed, zu9)


def test_el_desbalance_iq_cambia_la_señal_y_es_determinista():
    clean = vectors.modulated_tone(PARAMS, 4096, baseband_norm=0.01)
    skewed = vectors.modulated_tone(
        PARAMS, 4096, baseband_norm=0.01, gain_imbalance_db=1.0, phase_imbalance_deg=3.0
    )
    assert not np.array_equal(clean, skewed)
    assert np.array_equal(skewed, vectors.modulated_tone(
        PARAMS, 4096, baseband_norm=0.01, gain_imbalance_db=1.0, phase_imbalance_deg=3.0
    ))


def test_el_ruido_exige_semilla():
    with pytest.raises(TypeError):
        vectors.add_noise(vectors.tone(PARAMS, 128), 20.0, PARAMS)
