"""Entrada de pytest para el pacing del motor (P-16) — ver
`sim/tb/tb_drx_timing_paced.py`."""

from runner import L0, SimJob


def test_l0_timing_paced_verilator():
    # Mismo override de pisos que `test_l0_timing_engine.py` y por la misma
    # razón: este banco prueba la EQUIVALENCIA de las dos bases de tiempo, no
    # D-09, y usa prf_div pequeños para que dos radiales completos quepan en
    # una simulación L0.
    SimJob(
        hdl_toplevel="drx_timing_engine",
        test_module="tb_drx_timing_paced",
        parameters={"PrfDivMinRangeLow": 1, "PrfDivMinRangeHigh": 1},
        backend=L0,
    ).run()
