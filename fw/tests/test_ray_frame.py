"""La trama `ray` que monta el firmware es la que dice el esquema.

`test_contract_io.py` cubre el framer generico y `test_control.py` el camino de
vuelta del plano de control. Esto cubre el único mensaje con carga útil
variable, que es el que de verdad lleva los datos del radar, y en particular el
detalle que una trama mal montada NO delata al parsear:

**el orden I/Q**. El buffer de la DDR trae palabras de 32 bits
`{I[31:16], Q[15:0]}` —en memoria little-endian, `Q_lo Q_hi I_lo I_hi`— y el
contrato pide los pares en orden I,Q. Copiar la palabra tal cual produce una
trama con `payload_len` correcto, cabecera correcta y todos los bins con I y Q
cambiados. El parser del otro lado no puede verlo: para él son bytes. En el DSP
se vería como un espectro reflejado, sin ninguna pista del origen.

El binario ejercita el MISMO `drx_ray_frame.c` que Vitis compila cruzado para
el Cortex-A9.
"""

from __future__ import annotations

import importlib.util
import shutil
import struct
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
GENERATED = ROOT / "contract" / "generated"

BINS = 3
N_CH = 3


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
        ["make", "-s", "check", "BUILD_DIR=../build/fw-ray-frame"],
        cwd=ROOT / "fw",
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, build.stdout + build.stderr
    binario = ROOT / "build" / "fw-ray-frame" / "drx_ray_frame_selftest"
    result = subprocess.run([str(binario)], capture_output=True, text=True, check=True)
    return dict(line.split("=", 1) for line in result.stdout.splitlines())


def _payload_esperado() -> bytes:
    """Mismos valores que fw/src/drx_ray_frame_selftest.c, en orden I,Q."""
    out = bytearray()
    for bin_idx in range(BINS):
        for ch in range(N_CH):
            i_val = 1000 * bin_idx + ch + 1
            q_val = -(2000 * bin_idx + ch + 1)
            out += struct.pack("<hh", i_val, q_val)
    return bytes(out)


def test_la_trama_de_c_es_la_de_python(salida):
    module = _py_module()
    payload = _payload_esperado()

    body = module.Ray(
        seq=0x55667788,
        timestamp_ns=0x0102030405060708,
        trigger_count=0x11223344,
        azimuth_raw=0,
        elevation_raw=0,
        prf_div=208333,  # lote alto: batch_high está puesto
        bins=BINS,
        pulse_width_idx=0,  # idem
        pulse_mode=1,
        cell_mode=0,
        n_channels=N_CH,
        channel_mask=0x07,
        ray_flags=(
            module.RayFlag.AZEL_INVALID
            | module.RayFlag.FIRST_AFTER_CONFIG
            | module.RayFlag.BATCH_HIGH
        ),
    ).pack()

    header = module.Header(
        magic=module.MAGIC,
        version_major=module.VERSION_MAJOR,
        version_minor=module.VERSION_MINOR,
        msg_type=module.MsgType.RAY,
        flags=0,
        payload_len=len(body) + len(payload),
    ).pack()

    assert salida["ray"] == (header + body + payload).hex()


def test_el_par_viaja_en_orden_i_q_y_no_al_reves(salida):
    """La comprobación que justifica este fichero, aislada.

    Se desmonta la carga útil de la trama de C y se exige que el primer int16
    de cada par sea el I. Con I y Q cambiados, el test de arriba también
    fallaría, pero diría «la trama no coincide» sin decir por qué.
    """
    module = _py_module()
    blob = bytes.fromhex(salida["ray"])
    inicio = module.Header.SIZE + module.Ray.SIZE
    payload = blob[inicio:]

    assert len(payload) == BINS * N_CH * 4

    for bin_idx in range(BINS):
        for ch in range(N_CH):
            off = (bin_idx * N_CH + ch) * 4
            i_val, q_val = struct.unpack_from("<hh", payload, off)
            assert i_val == 1000 * bin_idx + ch + 1, (
                f"bin {bin_idx} canal {ch}: I y Q llegaron cambiados"
            )
            assert q_val == -(2000 * bin_idx + ch + 1)


def test_un_rayo_que_no_cuadra_con_su_cabecera_se_rechaza(salida):
    """Y no se codifica a medias.

    Una trama cuyo `payload_len` declara más bytes de los que lleva no rompe
    ESTE mensaje: rompe el siguiente, porque el lector sigue contando desde
    donde cree que acabó este. Es el fallo más caro de diagnosticar que tiene
    este formato, así que el framer prefiere no emitir nada.
    """
    assert salida["rechaza_n_words"] == "1"
    assert salida["rechaza_buffer_corto"] == "1"
