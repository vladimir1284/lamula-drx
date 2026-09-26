"""Entrada de pytest para `drx_ray_packer` — ver `sim/tb/tb_drx_ray_packer.py`.

El toplevel elaborado es el shim `drx_ray_packer_tb_dut` (`sim/tb_sv/`), no
`drx_ray_packer` directamente — ver la cabecera del shim.
"""

from pathlib import Path

from runner import L0, SimJob

TB_SV_DIR = Path(__file__).resolve().parents[1] / "tb_sv"


def test_l0_ray_packer_verilator():
    SimJob(
        hdl_toplevel="drx_ray_packer_tb_dut",
        test_module="tb_drx_ray_packer",
        parameters={"N_CH": 3},
        backend=L0,
        extra_sources=[TB_SV_DIR / "drx_ray_packer_tb_dut.sv"],
    ).run()
