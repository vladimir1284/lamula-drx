"""Entrada de pytest para la suite L0.

pytest construye y lanza; los `@cocotb.test()` viven en `sim/tb/`. El runner es
el mismo para todos los niveles — ver `sim/runner.py`.
"""

import pytest
from runner import L0, L1, BackendNotAvailable, SimJob


def test_l0_heartbeat_verilator():
    SimJob(
        hdl_toplevel="drx_heartbeat",
        test_module="tb_drx_heartbeat",
        parameters={"DIV": 5},
        backend=L0,
    ).run()


def test_l1_declara_su_bloqueo():
    """L1 no está mudo: falla con la razón y con el hallazgo que lo bloquea.

    Si algún día este test empieza a fallar es porque P-09 se resolvió, y
    entonces hay que borrarlo y escribir la suite L1 de verdad.
    """
    job = SimJob(hdl_toplevel="drx_top", test_module="tb_drx_heartbeat", backend=L1)
    with pytest.raises(BackendNotAvailable, match="P-09"):
        job.run()
