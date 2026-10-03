"""Entrada de pytest para `drx_debug_probe` — ver `sim/tb/tb_drx_debug_probe.py`."""

from runner import L0, SimJob


def test_l0_debug_probe_verilator():
    SimJob(
        hdl_toplevel="drx_debug_probe",
        test_module="tb_drx_debug_probe",
        # 2**4 ciclos en vez de 2**22: la lógica del umbral es la misma y el
        # test cabe en milisegundos. Ver la cabecera del testbench.
        parameters={"STALL_LOG2": 4},
        backend=L0,
    ).run()
