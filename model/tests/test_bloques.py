"""NCO, CIC y FIR por separado, antes de encadenarlos."""

import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest
from drx_model import fir as fir_mod
from drx_model.cic import Cic
from drx_model.nco import Nco
from drx_model.params import load

ROOT = Path(__file__).resolve().parents[2]
PARAMS = load("zedboard")


# --- NCO -------------------------------------------------------------------


def test_nco_emite_en_la_frecuencia_normalizada_del_if():
    nco = Nco.from_params(PARAMS)
    n = 8192
    cos_w, sin_w = nco.generate(n)
    spectrum = np.abs(np.fft.rfft(cos_w.astype(np.float64) - np.mean(cos_w)))
    peak_norm = np.argmax(spectrum) / n
    assert peak_norm == pytest.approx(float(PARAMS.if_norm), abs=1.0 / n)
    assert sin_w.size == n


def test_nco_respeta_el_fondo_de_escala():
    nco = Nco.from_params(PARAMS)
    cos_w, sin_w = nco.generate(4096)
    high = (1 << (nco.out_bits - 1)) - 1
    for wave in (cos_w, sin_w):
        assert wave.max() <= high
        assert wave.min() >= -high


def test_el_acumulador_de_fase_envuelve():
    nco = Nco.from_params(PARAMS)
    phase = nco.phase(10_000)
    assert phase.min() >= 0
    assert phase.max() < (1 << nco.phase_bits)
    assert np.any(np.diff(phase) < 0), "la fase nunca envolvió: revisa el incremento"


def test_el_nco_es_determinista():
    nco = Nco.from_params(PARAMS)
    assert np.array_equal(nco.generate(1024)[0], nco.generate(1024)[0])


# --- CIC -------------------------------------------------------------------


def _cic() -> Cic:
    chain = PARAMS.chain
    return Cic(
        stages=int(chain["cic_stages"]),
        rate=int(chain["cic_rate"]),
        diff_delay=int(chain["cic_diff_delay"]),
        in_bits=PARAMS.sample_bits,
    )


def test_ganancia_en_continua_del_cic():
    """(R·M)^N exacta: cualquier otra cosa es un error de escalado."""
    cic = _cic()
    steady = cic.process(np.full(cic.rate * 20, 1, dtype=np.int64))
    assert steady[-1] == cic.gain == cic.rate**cic.stages


def test_ancho_de_registro_de_hogenauer():
    cic = _cic()
    assert cic.growth_bits == 29  # ceil(5·log2(52))
    assert cic.register_bits == PARAMS.sample_bits + 29


def test_el_cic_diezma_por_r():
    cic = _cic()
    out = cic.process(np.zeros(cic.rate * 37, dtype=np.int64))
    assert out.size == 37


def test_el_cic_rechaza_un_ancho_que_no_cabe_en_int64():
    with pytest.raises(ValueError, match="int64"):
        Cic(stages=8, rate=1024, in_bits=32)


def test_la_respuesta_del_cic_cae_monotona_en_la_banda_de_paso():
    cic = _cic()
    freqs = np.linspace(0.0, 0.5 / cic.rate, 64)
    response = cic.response(freqs)
    assert response[0] == pytest.approx(1.0)
    assert np.all(np.diff(response) <= 1e-12)


# --- FIR -------------------------------------------------------------------


def test_los_coeficientes_congelados_estan_al_dia():
    result = subprocess.run(
        [sys.executable, "tools/gen_coeffs.py", "--check"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_el_fir_tiene_los_taps_del_paquete_de_parametros():
    coeffs = fir_mod.load_coeffs("droop_decim_fir")
    assert coeffs.size == PARAMS.chain["fir_taps"]
    assert np.array_equal(coeffs, coeffs[::-1]), "el FIR tiene que ser de fase lineal"


def test_el_fir_compensa_el_droop_del_cic():
    """La cascada CIC+FIR es más plana en banda de paso que el CIC solo.

    Es la razón de existir del compensador; si esto falla, el diseño de
    tools/gen_coeffs.py se rompió.
    """
    cic = _cic()
    fir = fir_mod.Fir(coeffs=fir_mod.load_coeffs("droop_decim_fir"), decim=4)
    freqs = np.linspace(0.0, 0.06, 128)  # normalizado a la entrada del FIR
    cic_only = cic.response(freqs / cic.rate)
    cascade = cic_only * fir.response(freqs)
    cascade /= cascade[0]
    assert np.max(np.abs(cascade - 1.0)) < np.max(np.abs(cic_only - 1.0))
    assert np.max(np.abs(cascade - 1.0)) < 0.02  # rizado < 2 % en banda de paso


def test_el_fir_atenua_lo_que_pliega_sobre_la_banda_de_paso():
    """Lo que importa no es Nyquist/4 sino lo que pliega ENCIMA de la banda útil.

    Con diezmado ÷4 y banda de paso hasta 0,09, la primera frecuencia que pliega
    sobre la señal es 0,25 - 0,09 = 0,16.
    """
    fir = fir_mod.Fir(coeffs=fir_mod.load_coeffs("droop_decim_fir"), decim=4)
    alias_band = fir.response(np.linspace(0.16, 0.5, 512))
    assert 20 * np.log10(np.max(alias_band)) < -50


def test_el_semibanda_diezma_por_dos():
    fir = fir_mod.Fir(coeffs=fir_mod.load_coeffs("halfband_decim2"), decim=2)
    assert fir.process(np.zeros(100, dtype=np.int64)).size == 50


def test_el_semibanda_atenua_lo_que_pliega():
    """Con diezmado ÷2 y banda de paso hasta 0,15, pliega a partir de 0,35."""
    fir = fir_mod.Fir(coeffs=fir_mod.load_coeffs("halfband_decim2"), decim=2)
    alias_band = fir.response(np.linspace(0.35, 0.5, 256))
    assert 20 * np.log10(np.max(alias_band)) < -60
    passband = fir.response(np.linspace(0.0, 0.15, 128))
    assert passband.max() - passband.min() < 0.15


def test_faltan_coeficientes_da_un_error_util():
    with pytest.raises(FileNotFoundError, match="gen_coeffs"):
        fir_mod.load_coeffs("no_existe")
