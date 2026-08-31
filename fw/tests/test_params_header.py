"""El firmware tiene que leer los MISMOS parámetros que el modelo.

`AGENTS.md`: el paquete de parámetros es único y lo consumen `rtl/`, `fw/`, `sim/`
y `model/`; ninguno de los cuatro define su propia copia. Este test lo comprueba
de verdad: compila la auto-comprobación de C, la ejecuta y contrasta lo que
imprime contra `config/params.toml` leído por Python.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest
from drx_model.params import load

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture(scope="module")
def firmware_values() -> dict[str, str]:
    if shutil.which("make") is None or shutil.which("gcc") is None:
        pytest.skip("hacen falta make y gcc")
    # Directorio propio: el otro test compila para la ZU9 y no pueden compartir
    # artefacto, o uno lee los parámetros de la plataforma del otro.
    build = subprocess.run(
        ["make", "-s", "check", "BUILD_DIR=../build/fw-zedboard"],
        cwd=ROOT / "fw",
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, build.stdout + build.stderr

    binary = ROOT / "build" / "fw-zedboard" / "drx_params_selftest"
    result = subprocess.run([str(binary)], capture_output=True, text=True, check=True)
    return dict(line.split("=", 1) for line in result.stdout.splitlines())


def test_el_firmware_ve_los_mismos_parametros_que_el_modelo(firmware_values):
    params = load("zedboard")
    assert int(firmware_values["fs_hz"]) == params.fs_hz
    assert int(firmware_values["if_hz"]) == params.if_hz
    assert int(firmware_values["nco_phase_inc"]) == params.nco_phase_inc
    assert int(firmware_values["r1"]) == params.r1
    assert int(firmware_values["r2"]) == params.r2
    assert int(firmware_values["sample_bits"]) == params.sample_bits
    assert int(firmware_values["cic_rate"]) == params.chain["cic_rate"]
    assert firmware_values["platform"] == "zedboard"


def test_el_firmware_compila_tambien_para_la_plataforma_objetivo():
    """El firmware de ZU9 tiene que compilar aunque no haya placa (D2 del delta)."""
    result = subprocess.run(
        ["make", "-s", "check", "PLATFORM=zu9", "BUILD_DIR=../build/fw-zu9"],
        cwd=ROOT / "fw",
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr
