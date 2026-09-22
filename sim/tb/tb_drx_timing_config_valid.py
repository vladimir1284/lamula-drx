"""L0 — `drx_timing_config_valid`: los 2 checks AUTOCONTENIDOS de D-09 (Z2).

Oráculo: `model/drx_model/timing.py::batch_config_valid` (D-03) -- puro
combinacional, así que cada vector se comprueba en el mismo ciclo, sin
esperar ningún flanco.

Sweep, no una lista de casos elegidos a mano: los 3 anchos de la tabla de
`config/params.toml` (uno de ellos deliberadamente fuera de tabla) contra
varios `prf_div` a ambos lados del punto en que el ancho deja de caber en su
propio PRI.
"""

from __future__ import annotations

import cocotb
from cocotb.triggers import Timer
from drx_model import timing
from drx_model.params import load

PARAMS = load("zedboard")

PULSE_WIDTHS = list(timing.pulse_width_table(PARAMS)) + [201]  # 201: fuera de tabla a propósito


@cocotb.test()
async def test_config_valid_coincide_bit_a_bit_con_el_modelo_dorado(dut):
    for pulse_width in PULSE_WIDTHS:
        for prf_div in (1, pulse_width - 1, pulse_width, pulse_width + 1, pulse_width * 2):
            if prf_div < 1:
                continue
            dut.prf_div.value = prf_div
            dut.pulse_width.value = pulse_width
            await Timer(1, units="ns")  # asentamiento combinacional, sin reloj en este DUT

            expected = timing.batch_config_valid(
                PARAMS, prf_div=prf_div, pulse_width_cycles=pulse_width
            )
            observed = bool(dut.valid.value)
            assert observed == expected, (
                f"prf_div={prf_div} pulse_width={pulse_width}: RTL={observed} != modelo={expected}"
            )
