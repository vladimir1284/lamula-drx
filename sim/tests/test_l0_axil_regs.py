"""Entrada de pytest para `drx_axil_regs` — ver `sim/tb/tb_drx_axil_regs.py`."""

from runner import L0, SimJob


def test_l0_axil_regs_verilator():
    SimJob(
        hdl_toplevel="drx_axil_regs",
        test_module="tb_drx_axil_regs",
        parameters={"N_CH": 3},
        backend=L0,
    ).run()
