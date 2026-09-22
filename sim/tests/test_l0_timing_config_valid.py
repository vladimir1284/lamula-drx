"""Entrada de pytest para `drx_timing_config_valid` — ver
`sim/tb/tb_drx_timing_config_valid.py`."""

from runner import L0, SimJob


def test_l0_timing_config_valid_verilator():
    SimJob(
        hdl_toplevel="drx_timing_config_valid",
        test_module="tb_drx_timing_config_valid",
        backend=L0,
    ).run()
