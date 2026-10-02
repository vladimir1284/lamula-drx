"""La actuación AFC aplica la palabra de fase CUANDO toca (Z4.5).

Lo que se verifica aquí no es la escritura al registro —eso es un puntero a
función y se mide en placa— sino las tres decisiones que el firmware toma solo:

1. `apply_at_seq` se respeta. La corrección se aplica entre rayos, nunca dentro
   de uno: el salto de palabra de fase no conserva la fase del acumulador, así
   que aplicarlo a mitad de rayo dejaría ese rayo con dos frecuencias de mezcla.
2. Una `nco_phase_inc` que no cabe en los 32 bits del acumulador se RECHAZA, no
   se trunca. Truncar convertiría una corrección equivocada en una frecuencia de
   mezcla equivocada sin ningún síntoma hasta que alguien mirara el espectro.
3. El contador de rayos envuelve en 2^32 y la comparación lo aguanta.

El binario ejercita el MISMO `drx_afc.c` que Vitis compila cruzado para el
Cortex-A9.
"""

from __future__ import annotations

import importlib.util
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
GENERATED = ROOT / "contract" / "generated"

sys.path.insert(0, str(ROOT / "model"))

from drx_model.params import load  # noqa: E402

#: El arnés de C usa DRX_NCO_PHASE_INC; aquí se lee de la misma fuente (el
#: modelo dorado) en vez de clavar el número, que cambia con `fs`.
PARAMS = load("zedboard")


def _py_module():
    spec = importlib.util.spec_from_file_location(
        "drx_dsp_v0_1", GENERATED / "drx_dsp_v0_1.py"
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def salida() -> dict[str, str]:
    if shutil.which("make") is None or shutil.which("gcc") is None:
        pytest.skip("hacen falta make y gcc")
    build = subprocess.run(
        ["make", "-s", "check", "BUILD_DIR=../build/fw-afc"],
        cwd=ROOT / "fw",
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, build.stdout + build.stderr
    binario = ROOT / "build" / "fw-afc" / "drx_afc_selftest"
    result = subprocess.run([str(binario)], capture_output=True, text=True, check=True)
    return dict(line.split("=", 1) for line in result.stdout.splitlines())


def test_apply_at_seq_cero_se_aplica_ya(salida):
    module = _py_module()

    assert int(salida["inmediato_error"]) == module.Error.OK
    assert int(salida["inmediato_escrituras"]) == 1
    assert int(salida["inmediato_pinc"]) == 0x12345678


def test_apply_at_seq_futuro_espera_a_su_rayo(salida):
    module = _py_module()

    assert int(salida["aplazado_error"]) == module.Error.OK
    assert int(salida["aplazado_escrituras_tras_submit"]) == 0, (
        "una corrección con apply_at_seq futuro no se escribe al llegar"
    )
    assert int(salida["aplazado_ray3"]) == 0
    assert int(salida["aplazado_ray4"]) == 0
    assert int(salida["aplazado_ray5"]) == 1, "se aplica en el rayo pedido, no antes"
    assert int(salida["aplazado_escrituras"]) == 1
    assert int(salida["aplazado_pinc"]) == 0xAABBCCDD

    assert int(salida["aplazado_ray6"]) == 0, "y no se repite en los rayos siguientes"
    assert int(salida["aplazado_escrituras_final"]) == 1


def test_una_palabra_de_fase_que_no_cabe_se_rechaza_sin_truncar(salida):
    module = _py_module()

    assert int(salida["rango_error"]) == module.Error.AFC_OUT_OF_RANGE
    assert int(salida["rango_escrituras"]) == 0
    assert int(salida["rango_rechazadas"]) == 1
    assert int(salida["rango_last_pinc"]) == PARAMS.nco_phase_inc, (
        "el NCO se queda donde estaba; 0x100000000 truncado a 32 bits sería 0"
    )


def test_el_contador_de_rayos_puede_envolver(salida):
    module = _py_module()

    assert int(salida["envuelve_error"]) == module.Error.OK
    assert int(salida["envuelve_escrituras_tras_submit"]) == 0, (
        "con `>=` plano 0xFFFFFFFF >= 1 y la corrección caería en el rayo "
        "equivocado"
    )
    assert int(salida["envuelve_ray0"]) == 0
    assert int(salida["envuelve_ray1"]) == 1
    assert int(salida["envuelve_pinc"]) == 0x00FF00FF


def test_una_correccion_nueva_sustituye_a_la_que_esperaba(salida):
    assert int(salida["sustituye_ray10"]) == 1
    assert int(salida["sustituye_pinc"]) == 0x22222222
    assert int(salida["sustituye_escrituras"]) == 1, (
        "solo se aplica la última: aplicar las dos gastaría un salto de más"
    )
    assert int(salida["sustituye_aplazadas"]) == 2
