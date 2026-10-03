#!/usr/bin/env python3
"""Codegen del mapa de registros AXI-Lite de `drx_top`.

Una sola fuente (`config/registers.toml`) genera el paquete SV que usa el RTL
(`rtl/drx_axil_regs.sv`) y el header C que usará firmware. AGENTS.md: «nada
generado se edita a mano».

Uso:
    python3 tools/gen_registers.py
    python3 tools/gen_registers.py --check
"""

from __future__ import annotations

import argparse
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "config" / "registers.toml"
SV_OUT = ROOT / "rtl" / "generated" / "drx_regs_pkg.sv"
H_OUT = ROOT / "fw" / "include" / "drx_regs.h"

BANNER_LINES = [
    "GENERADO por tools/gen_registers.py a partir de",
    "config/registers.toml. NO EDITAR A MANO.",
]

NOTE_LINES = [
    "Mapa de registros AXI-Lite de drx_top (Z1). Ver la cabecera de",
    "config/registers.toml para el historial de versiones y",
    "docs/implementacion/registros.md para la descripcion completa.",
]


def load_schema() -> dict:
    with SCHEMA.open("rb") as handle:
        return tomllib.load(handle)


def _sv_name(reg_name: str) -> str:
    return f"REG_{reg_name.upper()}_ADDR"


def _h_name(reg_name: str) -> str:
    return f"DRX_REG_{reg_name.upper()}_OFFSET"


def render_sv(schema: dict) -> str:
    addr_width = schema["addr_width"]
    out = [f"// {line}" for line in BANNER_LINES]
    out += [f"// {line}" for line in NOTE_LINES]
    out += [
        "",
        "`ifndef DRX_REGS_PKG_SV",
        "`define DRX_REGS_PKG_SV",
        "",
        "package drx_regs_pkg;",
        "",
        f"  localparam int REGS_VERSION = {schema['schema_version']};",
        f"  localparam int REGS_ADDR_WIDTH = {addr_width};",
        "",
    ]
    for reg in schema["register"]:
        out.append(
            f"  localparam logic [REGS_ADDR_WIDTH-1:0] {_sv_name(reg['name'])} = "
            f"REGS_ADDR_WIDTH'(32'h{reg['offset']:08X});"
        )
    out += [
        "",
        "endpackage : drx_regs_pkg",
        "",
        "`endif  // DRX_REGS_PKG_SV",
        "",
    ]
    return "\n".join(out)


def render_h(schema: dict) -> str:
    out = ["/* " + BANNER_LINES[0]]
    out += [" * " + line for line in BANNER_LINES[1:]]
    out.append(" *")
    out += [" * " + line for line in NOTE_LINES]
    out.append(" */")
    out += [
        "",
        "#ifndef DRX_REGS_H",
        "#define DRX_REGS_H",
        "",
        f"#define DRX_REGS_VERSION {schema['schema_version']}",
        "",
    ]
    for reg in schema["register"]:
        out.append(f"#define {_h_name(reg['name'])} 0x{reg['offset']:02X}u")
    out += [
        "",
        # Los bits con nombre de CTRL se escriben aqui y no salen del TOML: el
        # esquema describe registros, no campos de bits. Si CTRL llega a tener
        # muchos mas, el sitio donde arreglarlo es el esquema, no esta lista.
        "#define DRX_REG_CTRL_MODE_COARSE_BIT 0u",
        "#define DRX_REG_CTRL_MODE_COARSE_MASK (1u << DRX_REG_CTRL_MODE_COARSE_BIT)",
        "#define DRX_REG_CTRL_VECTOR_SOURCE_DDR_BIT 1u",
        "#define DRX_REG_CTRL_VECTOR_SOURCE_DDR_MASK (1u << DRX_REG_CTRL_VECTOR_SOURCE_DDR_BIT)",
        "#define DRX_REG_TIMING_CTRL_ENABLE_BIT 0u",
        "#define DRX_REG_TIMING_CTRL_ENABLE_MASK (1u << DRX_REG_TIMING_CTRL_ENABLE_BIT)",
        "#define DRX_REG_TIMING_CTRL_PACED_BIT 1u",
        "#define DRX_REG_TIMING_CTRL_PACED_MASK (1u << DRX_REG_TIMING_CTRL_PACED_BIT)",
        "",
        "#endif /* DRX_REGS_H */",
        "",
    ]
    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    schema = load_schema()
    outputs = {
        SV_OUT: render_sv(schema),
        H_OUT: render_h(schema),
    }

    if args.check:
        stale = [p for p, text in outputs.items() if not p.exists() or p.read_text() != text]
        for path in stale:
            print(f"DESACTUALIZADO: {path.relative_to(ROOT)}", file=sys.stderr)
        if stale:
            print("Ejecuta: python3 tools/gen_registers.py", file=sys.stderr)
            return 1
        print("registros generados al día")
        return 0

    for path, text in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print(f"escrito {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
