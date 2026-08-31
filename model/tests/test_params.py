"""El paquete de parámetros es la única fuente de verdad: hay que probarlo como tal."""

import subprocess
import sys
from pathlib import Path

import pytest
from drx_model.params import PARAMS_TOML, load, load_all

ROOT = Path(__file__).resolve().parents[2]


def test_hay_dos_plataformas():
    platforms = load_all()
    assert set(platforms) == {"zedboard", "zu9"}
    assert platforms["zu9"].is_target
    assert not platforms["zedboard"].is_target


def test_if_normalizado_identico_en_las_dos_plataformas():
    """El punto entero de D-02: lo normalizado no se mueve, lo de pared sí."""
    zed, zu9 = load("zedboard"), load("zu9")
    assert zed.if_norm == zu9.if_norm
    assert zed.if_hz != zu9.if_hz
    assert zu9.fs_hz / zed.fs_hz == pytest.approx(2.5)


def test_palabra_de_fase_del_nco_es_invariante():
    """Si esto falla, los vectores dejan de ser comunes a las dos placas."""
    assert load("zedboard").nco_phase_inc == load("zu9").nco_phase_inc


def test_el_if_cae_en_un_entero_de_hz():
    for params in load_all().values():
        assert params.if_hz * params.if_norm.denominator == (
            params.fs_hz * params.if_norm.numerator
        )


def test_la_descomposicion_de_la_cadena_reproduce_r1_y_r2():
    """Gate real: cambiar R1 en el TOML sin tocar la cadena tiene que fallar aquí.

    Es el caso que va a ocurrir cuando se cierre P-08 y R1/R2 pasen a 120/240.
    """
    params = load("zedboard")
    chain = params.chain
    assert chain["cic_rate"] * chain["fir_decim"] == params.r1
    assert params.r2 == params.r1 * chain["coarse_extra_decim"]


def test_tamano_de_celda_en_la_plataforma_objetivo():
    """249,427 m con R2 = 416: el número que P-01 dice que ORPG descarta."""
    zu9 = load("zu9")
    assert zu9.cell_m(zu9.r2) == pytest.approx(249.427, abs=1e-3)
    assert zu9.cell_m(zu9.r1) == pytest.approx(124.714, abs=1e-3)


def test_prf_de_pared_se_dilata_y_el_registro_no():
    zed, zu9 = load("zedboard"), load("zu9")
    div = zu9.invariant["prf_div_min"]
    assert zu9.prf_hz(div) == pytest.approx(1200.0, abs=0.1)
    assert zed.prf_hz(div) == pytest.approx(480.0, abs=0.1)


def test_los_ficheros_generados_estan_al_dia():
    """El mismo gate que corre el CI, para que falle también en local."""
    result = subprocess.run(
        [sys.executable, "tools/gen_params.py", "--check"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_el_toml_no_declara_frecuencias_fuera_de_platform():
    """Una `fs` escondida en [invariant] rompería la dilatación en silencio."""
    text = PARAMS_TOML.read_text()
    invariant_block = text.split("[invariant]", 1)[1].split("[chain]", 1)[0]
    assert "fs_hz" not in invariant_block
