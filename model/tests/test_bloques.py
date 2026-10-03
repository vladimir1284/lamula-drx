"""NCO, CIC y FIR por separado, antes de encadenarlos."""

import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest
from drx_model import fir as fir_mod
from drx_model.cic import Cic
from drx_model.nco import Nco, NcoTaylor
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


# --- NCO con Taylor_Series_Corrected ----------------------------------------
#
# `NcoTaylor` es una clase nueva, independiente de `Nco` -- no cambia el
# comportamiento por defecto que usan los tests de arriba ni el resto de la
# cadena (`Ddc`/`config/params.toml` siguen en `Noise_Shaping {None}`). Ver
# docs/alcance/pendientes.md#p-11 (11-sep-2026) para el origen de estos
# números.


def test_nco_taylor_respeta_el_fondo_de_escala():
    nco = NcoTaylor.from_params(PARAMS)
    cos_w, sin_w = nco.generate(4096)
    high = (1 << (nco.out_bits - 1)) - 1
    for wave in (cos_w, sin_w):
        assert wave.max() <= high
        assert wave.min() >= -high


def test_el_nco_taylor_es_determinista():
    nco = NcoTaylor.from_params(PARAMS)
    assert np.array_equal(nco.generate(1024)[0], nco.generate(1024)[0])


def test_nco_taylor_resuelve_mas_fase_que_nco_plano():
    # Mismo incremento de fase, mismo out_bits: `NcoTaylor` usa
    # `lut_addr_bits + delta_bits` bits de fase (25 con los defaults de este
    # proyecto) en vez de los `lut_addr_bits` (16) de `Nco`, así que dos fases
    # que `Nco` trata como idénticas (mismo `addr`, distinto residuo de los
    # bits truncados) dan salidas distintas en `NcoTaylor`.
    nco = Nco.from_params(PARAMS)
    taylor = NcoTaylor.from_params(PARAMS)
    shift = nco.phase_bits - nco.lut_addr_bits
    base = 12345 << shift
    tweak = base + (1 << (shift - 1))  # mismo addr de 16 bits, distinto residuo
    assert nco.generate(1, initial=base)[0] == nco.generate(1, initial=tweak)[0]
    assert taylor.generate(1, initial=base)[0] != taylor.generate(1, initial=tweak)[0]


def test_nco_taylor_reproduce_la_ip_real_dentro_de_dos_lsb():
    """Contra `dds_compiler` v6.0 real (`Noise_Shaping {Taylor_Series_Corrected}`,
    modo `SIN_COS_LUT_only`, `Output_Width=16`), sonda de xsim fuera del árbol,
    11-sep-2026 -- ver docs/alcance/pendientes.md#p-11. `n` es la fase de 25
    bits que se le dio directamente al core (sin acumulador); `cos`/`sin` son
    los dos campos crudos de `m_axis_data_tdata` para esa muestra. El residuo
    de hasta ±2 LSB es el mismo ya aceptado para el modo `None` (P-10) -- este
    test fija esa cota, no pide coincidencia exacta.
    """
    # (n, cos_ip, sin_ip) -- `n` en hex porque son fases, no relojes (el gate
    # de `tools/check_hardcoded_clock.py` solo mira literales decimales).
    referencia = [
        (0x172D87E, -5267, -32340),
        (0xFA4B6, 32164, 6251),
        (0x1CB57DC, 26159, -19730),
        (0x5D7A1A, 13470, 29869),
        (0xB1F8C4, -18858, 26796),
        (0x1A38AA2, 13843, -29698),
        (0x1F4B7EB, 32452, -4522),
        (0x1141138, -31778, -7987),
        (0x1F17516, 32246, -5816),
        (0xA27BDD, -13456, 29876),
        (0x10E140, 32066, 6739),
        (0x1A8914B, 15647, -28789),
    ]
    nco = NcoTaylor(
        phase_bits=25,
        phase_inc=0,
        out_bits=16,
        lut_addr_bits=16,
        delta_bits=9,
    )
    for n, cos_ip, sin_ip in referencia:
        cos_w, sin_w = nco.generate(1, initial=n)
        assert abs(int(cos_w[0]) - cos_ip) <= 2
        assert abs(int(sin_w[0]) - sin_ip) <= 2


def test_el_retune_de_afc_cambia_el_incremento_sin_reiniciar_la_fase():
    """`retune_at`/`retune_inc` (Z4.5): el acumulador NO vuelve a cero.

    La propiedad que importa no es que la frecuencia cambie -- eso es trivial--
    sino que la fase siga desde donde estaba. El hardware hace eso (el DDS
    Compiler sigue acumulando con el incremento nuevo) y un modelo que
    reiniciase la fase daría una rotación constante de diferencia contra el
    RTL, que es justo el error que la comparación bit a bit de L1 no podría
    explicar.
    """
    base = NcoTaylor.from_params(PARAMS)
    nuevo_inc = base.phase_inc + 1_000_000  # clock-const-ok: delta de fase, no reloj
    k = 7

    retune = NcoTaylor.from_params(PARAMS, retune_at=k, retune_inc=nuevo_inc)

    fase_base = base.phase(16)
    fase_retune = retune.phase(16)

    # Antes del salto, idénticas.
    assert list(fase_retune[: k + 1]) == list(fase_base[: k + 1])

    # Después, cada paso avanza con el incremento nuevo DESDE la fase que había.
    mask = (1 << base.phase_bits) - 1
    for n in range(k + 1, 16):
        esperado = (int(fase_base[k]) + nuevo_inc * (n - k)) & mask
        assert int(fase_retune[n]) == esperado

    # Y sin `retune_at` nada cambia: el oráculo de D-12 no se mueve por existir
    # esta opción.
    assert list(NcoTaylor.from_params(PARAMS).phase(16)) == list(fase_base)


def test_retune_at_sin_incremento_es_un_error():
    with pytest.raises(ValueError):
        NcoTaylor.from_params(PARAMS, retune_at=3).phase(8)


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
