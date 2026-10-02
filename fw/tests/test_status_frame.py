"""La trama `status` que monta el firmware es la que dice el esquema (Z4.5).

El mensaje `status` se congeló en Z0 y hasta Z4.5 nadie lo montaba. Lo que este
test protege no es el empaquetado —de eso ya se encarga el codegen— sino el
MAPEO de contadores a banderas de BITE, que es código escrito a mano y el único
sitio donde se decide qué le decimos al DSP que está roto.

El binario ejercita el MISMO `drx_status_frame.c` que Vitis compila cruzado para
el Cortex-A9.
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
        ["make", "-s", "check", "BUILD_DIR=../build/fw-status-frame"],
        cwd=ROOT / "fw",
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, build.stdout + build.stderr
    binario = ROOT / "build" / "fw-status-frame" / "drx_status_frame_selftest"
    result = subprocess.run([str(binario)], capture_output=True, text=True, check=True)
    return dict(line.split("=", 1) for line in result.stdout.splitlines())


def test_la_trama_de_c_es_la_de_python(salida):
    module = _py_module()

    body = module.Status(
        uptime_s=0x01020304,
        bite_flags=int(salida["bite"], 16),
        ssa_underruns=7,
        dma_overruns=0,
        ssi_errors=3,
        ddc_overflows=11,
        last_error=12,
        pad0=0,
        pad1=0,
    ).pack()

    header = module.Header(
        magic=module.MAGIC,
        version_major=module.VERSION_MAJOR,
        version_minor=module.VERSION_MINOR,
        msg_type=module.MsgType.STATUS,
        flags=0,
        payload_len=len(body),
    ).pack()

    assert salida["status"] == (header + body).hex()


def test_las_banderas_de_bite_salen_de_los_contadores(salida):
    """Cada bandera la levanta SU contador, y solo ese.

    `dma_overruns` entra en el arnés a cero a propósito: es la comprobación de
    que el mapeo no está poniendo banderas de más. Y `ssi_timeout` no se levanta
    aunque `ssi_errors` sea distinto de cero -- hoy no hay lectores SSI (Z3) y
    nada puede distinguir un timeout de una trama mala, así que levantar las dos
    con el mismo contador le diría al DSP que sabemos algo que no sabemos.
    """
    module = _py_module()
    bite = int(salida["bite"], 16)

    assert bite & module.BiteFlag.SSA_UNDERRUN
    assert bite & module.BiteFlag.SSI_FRAME_ERROR
    assert bite & module.BiteFlag.CONFIG_REJECTED
    assert bite & module.BiteFlag.LINK_DOWN

    assert not (bite & module.BiteFlag.DMA_OVERRUN), (
        "dma_overruns = 0 no puede levantar su bandera"
    )
    assert not (bite & module.BiteFlag.MMCM_UNLOCKED)
    assert not (bite & module.BiteFlag.SSI_TIMEOUT), (
        "no hay fuente de timeout de SSI hasta Z3"
    )


def test_sin_fallos_no_hay_ninguna_bandera(salida):
    """Un BITE que siempre dice algo no dice nada."""
    assert int(salida["bite_limpio"], 16) == 0
