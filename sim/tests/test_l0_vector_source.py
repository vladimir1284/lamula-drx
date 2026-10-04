"""Entrada de pytest para `vector_source` — ver `sim/tb/tb_vector_source.py`.

El toplevel elaborado es el shim `vector_source_tb_dut` (`sim/tb_sv/`), no
`vector_source` directamente — ver la cabecera del shim.

`DEPTH` se baja a 8: el valor de producción es `VECTOR_BRAM_DEPTH` (8192
muestras por canal) y recorrerlo entero para ver un `last` costaría otros
tantos ciclos por caso sin probar nada que 8 no pruebe. Con DEPTH = 8,
`AddrBits` son 3 bits en vez de los 13 del mapa de registros real, y los
tests escriben el banco entero en ocho ciclos.

`INIT_FILE` se deja vacío a propósito: desde v11 el contenido se CARGA en cada
caso por la ventana `vec_addr`/`vec_data`, así que ningún test depende de lo
que `$readmemh` hubiera dejado. El contenido precargado en el bitstream se
comprueba en placa, midiendo el espectro del rayo contra el modelo dorado.
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
