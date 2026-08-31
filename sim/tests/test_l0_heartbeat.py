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


def test_l1_no_pasa_por_cocotb():
    """El backend L1 de este runner falla explícito y apunta al flujo correcto.

    P-09 está decidido: L1 es SystemVerilog nativo sobre xsim y se lanza con
    `tcl/sim_l1.tcl`, no desde aquí. Este test fija esa decisión en el código
    para que nadie vuelva a intentar `backend=L1` y se quede pensando que es un
    fallo de instalación.
    """
    job = SimJob(hdl_toplevel="drx_top", test_module="tb_drx_heartbeat", backend=L1)
    with pytest.raises(BackendNotAvailable, match="P-09"):
        job.run()
