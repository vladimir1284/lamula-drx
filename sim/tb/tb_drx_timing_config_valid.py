"""L0 — `drx_timing_config_valid`: los 3 checks de D-09 completo (Z2).

Oráculo: `model/drx_model/timing.py::batch_config_valid` (D-03) -- puro
combinacional, así que cada vector se comprueba en el mismo ciclo, sin
esperar ningún flanco.

`PRF_DIV_MIN_RANGE` la fija `sim/tests/test_l0_timing_config_valid.py` al
elaborar el DUT (parámetro `PrfDivMinRange`) -- un entero pequeño arbitrario,
no `PARAMS.prf_div_min_low/high` reales, para que el sweep no tenga que barrer
`prf_div` hasta cientos de miles (mismo motivo que BINS_FINE/BINS_COARSE en
`tb_drx_range_gate.py`). Tiene que coincidir aquí y en ese fichero.

Sweep, no una lista de casos elegidos a mano: los 3 anchos de la tabla de
`config/params.toml` (uno de ellos deliberadamente fuera de tabla) contra
varios `prf_div` a ambos lados del punto en que el ancho deja de caber en su
propio PRI, y a ambos lados de `PRF_DIV_MIN_RANGE`.
"""

from __future__ import annotations

import cocotb
from cocotb.triggers import Timer
from drx_model import timing
from drx_model.params import load

PARAMS = load("zedboard")

PRF_DIV_MIN_RANGE = 500  # debe coincidir con el parámetro PrfDivMinRange del DUT

PULSE_WIDTHS = list(timing.pulse_width_table(PARAMS)) + [201]  # 201: fuera de tabla a propósito


@cocotb.test()
async def test_config_valid_coincide_bit_a_bit_con_el_modelo_dorado(dut):
    prf_divs = set()
    for pulse_width in PULSE_WIDTHS:
        for prf_div in (1, pulse_width - 1, pulse_width, pulse_width + 1, pulse_width * 2):
            if prf_div >= 1:
                prf_divs.add(prf_div)
    # Puntos explícitos alrededor del piso de rango: el sweep de arriba, atado
    # a los anchos de pulso, no cruza necesariamente PRF_DIV_MIN_RANGE.
    prf_divs |= {PRF_DIV_MIN_RANGE - 1, PRF_DIV_MIN_RANGE, PRF_DIV_MIN_RANGE + 1}

    for pulse_width in PULSE_WIDTHS:
        for prf_div in sorted(prf_divs):
            dut.prf_div.value = prf_div
            dut.pulse_width.value = pulse_width
            await Timer(1, units="ns")  # asentamiento combinacional, sin reloj en este DUT

            expected = timing.batch_config_valid(
                PARAMS,
                prf_div=prf_div,
                pulse_width_cycles=pulse_width,
                prf_div_min_range=PRF_DIV_MIN_RANGE,
            )
            observed = bool(dut.valid.value)
            assert observed == expected, (
                f"prf_div={prf_div} pulse_width={pulse_width}: RTL={observed} != modelo={expected}"
            )
