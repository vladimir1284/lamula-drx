"""Entrada de pytest para `drx_timing_engine` — ver `sim/tb/tb_drx_timing_engine.py`."""

from runner import L0, SimJob


def test_l0_timing_engine_verilator():
    # PrfDivMinRangeLow/High por defecto son los reales de producción
    # (767198/191800, D-09) -- overrideados aquí a 1 (sin piso) porque este
    # test prueba el CABLEADO del motor (que los 4 triggers se arman con cada
    # pulso de PRF), no D-09 en sí, y usa prf_div_low/high pequeños a
    # propósito (ver `_radial_ejemplo()` en tb_drx_timing_engine.py) para que
    # la simulación no tenga que recorrer cientos de miles de ciclos.
    SimJob(
        hdl_toplevel="drx_timing_engine",
        test_module="tb_drx_timing_engine",
        parameters={"PrfDivMinRangeLow": 1, "PrfDivMinRangeHigh": 1},
        testcases=[
            "test_los_4_triggers_se_arman_con_cada_pulso_de_prf",
            "test_lote_invalido_deja_el_secuenciador_sin_correr",
        ],
        backend=L0,
    ).run()


def test_l0_timing_engine_pisos_reales_de_produccion_verilator():
    # Sin override: elabora con PrfDivMinRangeLow/High = PRF_DIV_MIN_LOW/HIGH
    # y BinsMaxLow/High = BINS_MODE_FINE, todos del paquete de parámetros --
    # los mismos valores que usa `drx_top.sv` en producción. Ver
    # `test_pisos_reales_de_produccion_gatean_enable`/
    # `test_techo_real_de_bins_gatea_enable` (D-15) en
    # tb_drx_timing_engine.py: solo checks combinacionales, sin recorrer
    # ningún dwell completo (a 767198 ciclos/lote sería impracticable).
    SimJob(
        hdl_toplevel="drx_timing_engine",
        test_module="tb_drx_timing_engine",
        testcases=[
            "test_pisos_reales_de_produccion_gatean_enable",
            "test_techo_real_de_bins_gatea_enable",
        ],
        backend=L0,
    ).run()
