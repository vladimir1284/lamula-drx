"""Entrada de pytest para `vector_source` — ver `sim/tb/tb_vector_source.py`.

El toplevel elaborado es el shim `vector_source_tb_dut` (`sim/tb_sv/`), no
`vector_source` directamente — ver la cabecera del shim.

`DEPTH` se baja a 8: el valor de producción son 4000 muestras por canal, y
recorrerlas enteras para ver un `last` de BRAM-loop costaría 4000 ciclos por
caso sin probar nada que 8 no pruebe. `INIT_FILE` se deja vacío a propósito —
ninguno de los casos compara el CONTENIDO de la BRAM, que es lo que cubre L1
contra la IP real.
"""

from pathlib import Path

from runner import L0, SimJob

TB_SV_DIR = Path(__file__).resolve().parents[1] / "tb_sv"


def test_l0_vector_source_verilator():
    SimJob(
        hdl_toplevel="vector_source_tb_dut",
        test_module="tb_vector_source",
        parameters={"N_CH": 3, "DEPTH": 8},
        backend=L0,
        extra_sources=[TB_SV_DIR / "vector_source_tb_dut.sv"],
    ).run()
