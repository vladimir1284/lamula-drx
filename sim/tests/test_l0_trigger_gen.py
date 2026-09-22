"""Entrada de pytest para `drx_trigger_gen` — ver `sim/tb/tb_drx_trigger_gen.py`."""

from runner import L0, SimJob


def test_l0_trigger_gen_verilator():
    SimJob(
        hdl_toplevel="drx_trigger_gen",
        test_module="tb_drx_trigger_gen",
        backend=L0,
    ).run()
