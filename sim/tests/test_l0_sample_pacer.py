"""Entrada de pytest para `drx_sample_pacer` — ver `sim/tb/tb_drx_sample_pacer.py`."""

from runner import L0, SimJob


def test_l0_sample_pacer_verilator():
    SimJob(
        hdl_toplevel="drx_sample_pacer",
        test_module="tb_drx_sample_pacer",
        parameters={"N_CH": 3},
        backend=L0,
    ).run()
