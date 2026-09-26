"""Entrada de pytest para `drx_range_gate` — ver `sim/tb/tb_drx_range_gate.py`."""

from runner import L0, SimJob


def test_l0_range_gate_verilator():
    # BINS_MAX cubre el techo de los dos BINS_FINE/BINS_COARSE que barre
    # tb_drx_range_gate.py (D-15: ya no son dos "modos", son dos puntos del
    # sweep de `bin_count`, así que basta un solo parámetro de profundidad).
    SimJob(
        hdl_toplevel="drx_range_gate",
        test_module="tb_drx_range_gate",
        parameters={"BINS_MAX": 8},
        backend=L0,
    ).run()
