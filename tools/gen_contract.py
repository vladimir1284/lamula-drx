#!/usr/bin/env python3
"""Codegen del contrato DRx↔DSP.

Una sola fuente (`contract/schema/drx_dsp_v0_1.toml`) genera las tres
implementaciones: C para el lado DRx, Rust para el lado DSP y Python para los
tests de contrato. AGENTS.md: «no escribas las dos implementaciones a mano».

Uso:
    python3 tools/gen_contract.py
    python3 tools/gen_contract.py --check
"""

from __future__ import annotations

import argparse
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "contract" / "schema" / "drx_dsp_v0_1.toml"
OUT_DIR = ROOT / "contract" / "generated"

BANNER_LINES = [
    "GENERADO por tools/gen_contract.py a partir de",
    "contract/schema/drx_dsp_v0_1.toml. NO EDITAR A MANO.",
]

TYPES = {
    "u8": ("uint8_t", "u8", "B", 1),
    "u16": ("uint16_t", "u16", "H", 2),
    "u32": ("uint32_t", "u32", "I", 4),
    "u64": ("uint64_t", "u64", "Q", 8),
    "i8": ("int8_t", "i8", "b", 1),
    "i16": ("int16_t", "i16", "h", 2),
    "i32": ("int32_t", "i32", "i", 4),
    "i64": ("int64_t", "i64", "q", 8),
}


def load_schema() -> dict:
    with SCHEMA.open("rb") as handle:
        return tomllib.load(handle)


def size_of(fields: list[dict]) -> int:
    return sum(TYPES[f["type"]][3] for f in fields)


def struct_format(fields: list[dict]) -> str:
    return "<" + "".join(TYPES[f["type"]][2] for f in fields)


def _c_name(*parts: str) -> str:
    return "_".join(parts)


def render_c(schema: dict) -> str:
    meta = schema["meta"]
    out = [f"/* {line} */" for line in BANNER_LINES]
    out += [
        " *",
        " * Contrato DRx↔DSP v{}.{} — lado DRx.".format(
            meta["version_major"], meta["version_minor"]
        ),
        " *",
        " * Little-endian, empaquetado, sin relleno implícito. Los _Static_assert",
        " * de abajo fallan la compilación si el compilador añade relleno: es el",
        " * único sitio donde un desacuerdo de layout se puede detectar barato.",
        " */",
        "",
        "#ifndef DRX_DSP_V0_1_H",
        "#define DRX_DSP_V0_1_H",
        "",
        "#include <stdint.h>",
        "",
        f"#define DRX_DSP_MAGIC 0x{meta['magic']:08X}u",
        f"#define DRX_DSP_VERSION_MAJOR {meta['version_major']}",
        f"#define DRX_DSP_VERSION_MINOR {meta['version_minor']}",
        f"#define DRX_DSP_TCP_PORT {meta['tcp_port']}u",
        "",
    ]
    # El primer bloque de comentario abre con /* y el resto son continuaciones.
    out[0] = "/* " + BANNER_LINES[0]
    out[1] = " * " + BANNER_LINES[1]

    def emit_struct(name: str, fields: list[dict], doc: str) -> None:
        out.append(f"/* {doc.strip().replace(chr(10), chr(10) + ' * ')} */")
        out.append("typedef struct __attribute__((packed)) {")
        for field in fields:
            ctype = TYPES[field["type"]][0]
            out.append(f"  {ctype} {field['name']};  /* {field['doc']} */")
        out.append(f"}} drx_dsp_{name}_t;")
        out.append(
            f'_Static_assert(sizeof(drx_dsp_{name}_t) == {size_of(fields)}, '
            f'"layout de drx_dsp_{name}_t");'
        )
        out.append("")

    emit_struct("header", schema["header"]["fields"], "Cabecera común a todo mensaje.")

    out.append("/* Tipos de mensaje. */")
    out.append("typedef enum {")
    for message in schema["message"]:
        out.append(
            f"  DRX_DSP_MSG_{message['name'].upper()} = {message['type_id']},"
            f"  /* {message['dir']} */"
        )
    out.append("} drx_dsp_msg_type_t;")
    out.append("")

    for message in schema["message"]:
        emit_struct(message["name"], message["fields"], message["doc"])

    for enum in schema["enum"]:
        out.append(f"/* {enum['doc']} */")
        out.append("typedef enum {")
        for value in enum["values"]:
            out.append(
                f"  {_c_name('DRX_DSP', enum['name'].upper(), value['name'].upper())}"
                f" = {value['value']},  /* {value['doc']} */"
            )
        out.append(f"}} drx_dsp_{enum['name']}_t;")
        out.append("")

    out += ["#endif /* DRX_DSP_V0_1_H */", ""]
    return "\n".join(out)


def render_rust(schema: dict) -> str:
    meta = schema["meta"]
    out = [f"// {line}" for line in BANNER_LINES]
    out += [
        "//",
        f"// Contrato DRx↔DSP v{meta['version_major']}.{meta['version_minor']} — lado DSP.",
        "//",
        "// Little-endian, empaquetado. Los `assert!` de tamaño viven en los tests",
        "// del proyecto DSP; aquí van como constantes para que se puedan comprobar.",
        "",
        "#![allow(dead_code)]",
        "",
        f"pub const MAGIC: u32 = 0x{meta['magic']:08X};",
        f"pub const VERSION_MAJOR: u8 = {meta['version_major']};",
        f"pub const VERSION_MINOR: u8 = {meta['version_minor']};",
        f"pub const TCP_PORT: u16 = {meta['tcp_port']};",
        "",
    ]

    def emit_struct(name: str, fields: list[dict], doc: str) -> None:
        for line in doc.strip().splitlines():
            out.append(f"/// {line}")
        out.append("#[repr(C, packed)]")
        out.append("#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]")
        out.append(f"pub struct {to_camel(name)} {{")
        for field in fields:
            out.append(f"    /// {field['doc']}")
            out.append(f"    pub {field['name']}: {TYPES[field['type']][1]},")
        out.append("}")
        out.append(
            f"pub const {name.upper()}_SIZE: usize = {size_of(fields)};"
        )
        out.append("")

    emit_struct("header", schema["header"]["fields"], "Cabecera común a todo mensaje.")

    out.append("/// Tipos de mensaje.")
    out.append("#[repr(u8)]")
    out.append("#[derive(Debug, Clone, Copy, PartialEq, Eq)]")
    out.append("pub enum MsgType {")
    for message in schema["message"]:
        out.append(f"    /// {message['dir']}")
        out.append(f"    {to_camel(message['name'])} = {message['type_id']},")
    out.append("}")
    out.append("")

    for message in schema["message"]:
        emit_struct(message["name"], message["fields"], message["doc"])

    for enum in schema["enum"]:
        for line in enum["doc"].strip().splitlines():
            out.append(f"/// {line}")
        out.append(f"pub mod {enum['name']} {{")
        rust_type = TYPES[enum["type"]][1]
        for value in enum["values"]:
            out.append(f"    /// {value['doc']}")
            out.append(
                f"    pub const {value['name'].upper()}: {rust_type} = {value['value']};"
            )
        out.append("}")
        out.append("")

    return "\n".join(out)


def render_python(schema: dict) -> str:
    meta = schema["meta"]
    out = ['"""' + BANNER_LINES[0] + " " + BANNER_LINES[1]]
    out += [
        "",
        f"Contrato DRx↔DSP v{meta['version_major']}.{meta['version_minor']} — referencia",
        "de los tests de contrato. Es la tercera implementación generada de la misma",
        "fuente: si esta y la de C no producen los mismos bytes, el codegen está mal.",
        '"""',
        "",
        "from __future__ import annotations",
        "",
        "import struct",
        "from dataclasses import dataclass",
        "",
        f"MAGIC = 0x{meta['magic']:08X}",
        f"VERSION_MAJOR = {meta['version_major']}",
        f"VERSION_MINOR = {meta['version_minor']}",
        f"TCP_PORT = {meta['tcp_port']}",
        "",
    ]

    def emit_struct(name: str, fields: list[dict], doc: str) -> None:
        out.append("@dataclass")
        out.append(f"class {to_camel(name)}:")
        out.append(f'    """{doc.strip().splitlines()[0]}"""')
        out.append("")
        out.append(f'    FORMAT = "{struct_format(fields)}"')
        out.append(f"    SIZE = {size_of(fields)}")
        out.append(
            "    FIELDS = ("
            + ", ".join(f'"{field["name"]}"' for field in fields)
            + ",)"
        )
        out.append("")
        for field in fields:
            out.append(f"    {field['name']}: int = 0")
        out.append("")
        out.append("    def pack(self) -> bytes:")
        out.append(
            "        return struct.pack(self.FORMAT, "
            "*(getattr(self, name) for name in self.FIELDS))"
        )
        out.append("")
        out.append("    @classmethod")
        out.append(f"    def unpack(cls, data: bytes) -> \"{to_camel(name)}\":")
        out.append("        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))")
        out.append("")

    emit_struct("header", schema["header"]["fields"], "Cabecera común a todo mensaje.")

    out.append("class MsgType:")
    out.append('    """Tipos de mensaje."""')
    out.append("")
    for message in schema["message"]:
        out.append(f"    {message['name'].upper()} = {message['type_id']}")
    out.append("")

    for message in schema["message"]:
        emit_struct(message["name"], message["fields"], message["doc"])

    for enum in schema["enum"]:
        out.append(f"class {to_camel(enum['name'])}:")
        out.append(f'    """{enum["doc"].strip().splitlines()[0]}"""')
        out.append("")
        for value in enum["values"]:
            out.append(f"    {value['name'].upper()} = {value['value']}")
        out.append("")

    return "\n".join(out)


def to_camel(name: str) -> str:
    return "".join(part.capitalize() for part in name.split("_"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    schema = load_schema()
    outputs = {
        OUT_DIR / "drx_dsp_v0_1.h": render_c(schema),
        OUT_DIR / "drx_dsp_v0_1.rs": render_rust(schema),
        OUT_DIR / "drx_dsp_v0_1.py": render_python(schema),
    }

    if args.check:
        stale = [p for p, text in outputs.items() if not p.exists() or p.read_text() != text]
        for path in stale:
            print(f"DESACTUALIZADO: {path.relative_to(ROOT)}", file=sys.stderr)
        if stale:
            print("Ejecuta: python3 tools/gen_contract.py", file=sys.stderr)
            return 1
        print("contrato generado al día")
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for path, text in outputs.items():
        path.write_text(text)
        print(f"escrito {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
