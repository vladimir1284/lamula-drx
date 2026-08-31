"""Runner de simulación de doble backend.

D-05 pide **un único runner** por encima de dos simuladores: Verilator para las
unidades del RTL custom (L0) y xsim para la integración con IP de Xilinx (L1),
porque los cores del DDC son cajas negras que Verilator no puede elaborar.

Estado real del doble backend
-----------------------------
Verilator funciona. **xsim no está soportado por cocotb** y nunca lo ha estado —
ese es el hallazgo P-09. La decisión tomada el 30 de agosto de 2026 es que L1 no
pasa por cocotb: se escribe en SystemVerilog nativo (`sim/tb_sv/`), el oráculo
del modelo dorado cruza por fichero (`tools/gen_l1_vectors.py`) y lo lanza
`tcl/sim_l1.tcl` sobre xsim. Este runner se queda siendo el de L0.

El backend L1 sigue declarado aquí, y falla con un mensaje que apunta al flujo
correcto en vez de estar ausente en silencio.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass, field
from pathlib import Path

from cocotb.runner import get_runner

ROOT = Path(__file__).resolve().parents[1]
FILELIST = ROOT / "rtl" / "filelist.f"
WAIVERS = ROOT / "sim" / "verilator_waivers.vlt"
TB_DIR = ROOT / "sim" / "tb"
BUILD_ROOT = ROOT / "build" / "sim"

# cocotb propaga al simulador el `sys.path` del proceso padre, así que los
# testbenches tienen que estar en él antes de lanzar. pytest lo hace por
# configuración; esto cubre el uso directo del runner desde un script.
for _path in (TB_DIR, ROOT / "model"):
    if str(_path) not in sys.path:
        sys.path.insert(0, str(_path))

#: Nivel L0 del plan de testing: unidades del RTL custom.
L0 = "verilator"
#: Nivel L1: integración con IP de Xilinx. No corre por aquí — ver P-09.
L1 = "xsim"


class BackendNotAvailable(RuntimeError):
    """El backend está en el plan pero no se puede ejecutar todavía."""


def rtl_sources() -> list[Path]:
    """Fuentes del RTL, leídas de la lista única `rtl/filelist.f`."""
    lines = FILELIST.read_text().splitlines()
    return [
        ROOT / line.strip()
        for line in lines
        if line.strip() and not line.lstrip().startswith("#")
    ]


@dataclass
class SimJob:
    """Una elaboración más una ejecución, independiente del backend."""

    hdl_toplevel: str
    test_module: str
    parameters: dict[str, object] = field(default_factory=dict)
    backend: str = L0
    waves: bool = False
    #: Fuentes que no están en `rtl/filelist.f` porque no son RTL: los módulos
    #: de testbench de `sim/tb_sv/`. La lista del RTL es única (D-07) y esto no
    #: la contamina.
    extra_sources: list[Path] = field(default_factory=list)
    #: Plusargs para la ejecución. El arnés de L1 se configura así, con el mismo
    #: formato en Verilator y en xsim.
    plusargs: list[str] = field(default_factory=list)

    @property
    def build_dir(self) -> Path:
        return BUILD_ROOT / self.backend / self.hdl_toplevel

    def _build_args(self) -> list[str]:
        if self.backend == L0:
            # -Wall más waivers con razón escrita: el lint del RTL corre en cada
            # simulación, no solo en el gate de lint.
            return ["--timing", "-Wall", str(WAIVERS)]
        return []

    def run(self) -> Path:
        if self.backend == L1:
            raise BackendNotAvailable(
                "El backend xsim no está soportado por cocotb 1.9.2 (runners: "
                "icarus, questa, ghdl, nvc, riviera, verilator, xcelium). "
                "Ver P-09 en docs/alcance/pendientes.md: L1 no pasa por cocotb. "
                "Se lanza con `tcl/sim_l1.tcl` sobre testbenches nativos de "
                "sim/tb_sv/, con los vectores de tools/gen_l1_vectors.py."
            )
        if self.backend != L0:
            raise BackendNotAvailable(f"backend desconocido: {self.backend!r}")

        runner = get_runner(self.backend)
        runner.build(
            sources=rtl_sources() + list(self.extra_sources),
            hdl_toplevel=self.hdl_toplevel,
            parameters=self.parameters,
            build_args=self._build_args(),
            build_dir=self.build_dir,
            always=True,
        )
        return runner.test(
            hdl_toplevel=self.hdl_toplevel,
            test_module=self.test_module,
            parameters=self.parameters,
            build_dir=self.build_dir,
            # Los artefactos de cocotb caen en el directorio de build, no en
            # `sim/tb/`: son salida, no fuente.
            test_dir=self.build_dir,
            waves=self.waves,
            plusargs=list(self.plusargs),
        )


def run(hdl_toplevel: str, test_module: str, **kwargs) -> Path:
    """Atajo: `run("drx_top", "tb_drx_top", parameters={...})`."""
    return SimJob(hdl_toplevel=hdl_toplevel, test_module=test_module, **kwargs).run()
