"""Entrada de pytest para `drx_timing_engine` — ver `sim/tb/tb_drx_timing_engine.py`."""

from runner import L0, SimJob


def test_l0_timing_engine_verilator():
    SimJob(
        hdl_toplevel="drx_timing_engine",
        test_module="tb_drx_timing_engine",
        backend=L0,
    ).run()
