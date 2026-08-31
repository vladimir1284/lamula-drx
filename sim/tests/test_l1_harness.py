"""Entrada de pytest para la auto-prueba del arnés de L1.

Genera los vectores del modelo en un directorio temporal y corre el arnés dos
veces sobre ellos: limpio y con un bit cambiado. Corre sobre Verilator, sin
Vivado: es la parte de P-09 que sí se puede verificar hoy.
"""

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from drx_model import l1_vectors, vectors  # noqa: E402
from drx_model import params as params_mod  # noqa: E402
from runner import L0, SimJob  # noqa: E402

TB_SV = ROOT / "sim" / "tb_sv"
SOURCES = [
    TB_SV / "drx_l1_file_source.sv",
    TB_SV / "drx_l1_checker.sv",
    TB_SV / "tb_l1_harness.sv",
]

#: Corto a propósito: aquí se prueba el arnés, no la cadena. Los vectores largos
#: son de `tools/gen_l1_vectors.py`, que es lo que consume la suite L1 real.
N_SAMPLES = 4096


@pytest.fixture(scope="module")
def caso(tmp_path_factory) -> dict:
    params = params_mod.load("zedboard")
    out_root = tmp_path_factory.mktemp("l1-vectors")
    case = l1_vectors.export_case(
        params=params,
        name="arnes",
        stimulus=vectors.tone(params, N_SAMPLES),
        out_root=out_root,
    )
    # Releer por el camino público valida de paso el manifiesto y los SHA-256.
    l1_vectors.load_manifest(case.directory)
    return {"directory": case.directory, "manifest": case.manifest}


def _plusargs(caso: dict, corrupt_index: int | None) -> list[str]:
    directory = caso["directory"]
    manifest = caso["manifest"]
    args = [
        f"+expected_i_path={directory / l1_vectors.EXPECTED_I_FILE}",
        f"+expected_q_path={directory / l1_vectors.EXPECTED_Q_FILE}",
        f"+expected_count={manifest['n_expected']}",
        f"+settling={manifest['settling_out_samples']}",
    ]
    if corrupt_index is not None:
        args.append(f"+corrupt_index={corrupt_index}")
    return args


@pytest.mark.parametrize("corrupt_index", [None, 3])
def test_arnes_l1(caso, corrupt_index):
    """Sin corrupción tiene que dar verde; con un bit cambiado, rojo."""
    SimJob(
        hdl_toplevel="tb_l1_harness",
        test_module="tb_l1_harness",
        backend=L0,
        extra_sources=SOURCES,
        plusargs=_plusargs(caso, corrupt_index),
    ).run()
