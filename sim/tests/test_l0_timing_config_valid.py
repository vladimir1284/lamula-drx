"""Entrada de pytest para `drx_timing_config_valid` — ver
`sim/tb/tb_drx_timing_config_valid.py`."""

from runner import L0, SimJob


def test_l0_timing_config_valid_verilator():
    # PrfDivMinRange/BinsMax deben coincidir con PRF_DIV_MIN_RANGE/BINS_MAX de
    # tb_drx_timing_config_valid.py -- enteros pequeños arbitrarios, no los
    # reales de producción (ver la cabecera de ese fichero).
    SimJob(
        hdl_toplevel="drx_timing_config_valid",
        test_module="tb_drx_timing_config_valid",
        parameters={"PrfDivMinRange": 500, "BinsMax": 64},
        backend=L0,
    ).run()
