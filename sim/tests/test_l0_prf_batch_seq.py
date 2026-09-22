"""Entrada de pytest para `drx_prf_batch_seq` — ver `sim/tb/tb_drx_prf_batch_seq.py`."""

from runner import L0, SimJob


def test_l0_prf_batch_seq_verilator():
    SimJob(
        hdl_toplevel="drx_prf_batch_seq",
        test_module="tb_drx_prf_batch_seq",
        backend=L0,
    ).run()
