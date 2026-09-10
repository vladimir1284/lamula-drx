"""Entrada de pytest para `drx_range_gate` — ver `sim/tb/tb_drx_range_gate.py`."""

from runner import L0, SimJob


def test_l0_range_gate_verilator():
    SimJob(
        hdl_toplevel="drx_range_gate",
        test_module="tb_drx_range_gate",
        parameters={"BINS_FINE": 8, "BINS_COARSE": 4},
        backend=L0,
    ).run()
