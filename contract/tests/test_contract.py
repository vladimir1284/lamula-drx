"""Tests de contrato DRx↔DSP.

La pregunta que responden es una sola: **¿producen los mismos bytes las dos
implementaciones generadas?** Un contrato con dos lados que no coinciden en el
layout es peor que no tener contrato, porque el desacuerdo aparece en campo.

Lo que se comprueba:
  1. Los ficheros generados están al día respecto del esquema.
  2. El C compila con los `_Static_assert` de layout activos: si el compilador
     mete relleno, no compila.
  3. Un programa en C rellena cada mensaje con valores conocidos y vuelca los
     bytes; la implementación de Python monta lo mismo y los bytes coinciden.

Lo que NO se comprueba todavía, y hay que decirlo: **la implementación de Rust no
se compila aquí** porque no hay toolchain de Rust en este repositorio. El lado DSP
tiene que añadir su propio test de layout contra `drx_dsp_v0_1.rs`. Sí se
comprueba que las constantes de tamaño de Rust coinciden con las de C y Python,
que es lo que atrapa un error de codegen.
"""

from __future__ import annotations

import importlib.util
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / "contract" / "schema" / "drx_dsp_v0_1.toml"
GENERATED = ROOT / "contract" / "generated"

WIDTH = {"u8": 1, "u16": 2, "u32": 4, "u64": 8, "i8": 1, "i16": 2, "i32": 4, "i64": 8}


def _schema() -> dict:
    with SCHEMA.open("rb") as handle:
        return tomllib.load(handle)


def _py_module():
    spec = importlib.util.spec_from_file_location(
        "drx_dsp_v0_1", GENERATED / "drx_dsp_v0_1.py"
    )
    module = importlib.util.module_from_spec(spec)
    # `dataclasses` resuelve anotaciones vía sys.modules, así que el módulo tiene
    # que estar registrado antes de ejecutarlo.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _sample_value(index: int, type_name: str) -> int:
    """Valor determinista por posición, recortado al ancho del campo."""
    return (0x0102030405060708 * (index + 1)) & ((1 << (8 * WIDTH[type_name])) - 1)


def _structs() -> list[tuple[str, list[dict]]]:
    schema = _schema()
    out = [("header", schema["header"]["fields"])]
    out += [(m["name"], m["fields"]) for m in schema["message"]]
    return out


def test_los_ficheros_generados_estan_al_dia():
    result = subprocess.run(
        [sys.executable, "tools/gen_contract.py", "--check"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_los_tres_lados_declaran_el_mismo_tamano():
    module = _py_module()
    rust = (GENERATED / "drx_dsp_v0_1.rs").read_text()
    header_c = (GENERATED / "drx_dsp_v0_1.h").read_text()

    for name, fields in _structs():
        expected = sum(WIDTH[f["type"]] for f in fields)
        py_class = getattr(module, "".join(p.capitalize() for p in name.split("_")))
        assert py_class.SIZE == expected, f"Python discrepa en {name}"

        rust_const = re.search(rf"pub const {name.upper()}_SIZE: usize = (\d+);", rust)
        assert rust_const, f"Rust no declara el tamaño de {name}"
        assert int(rust_const.group(1)) == expected, f"Rust discrepa en {name}"

        assert (
            f"_Static_assert(sizeof(drx_dsp_{name}_t) == {expected}," in header_c
        ), f"C no asevera el tamaño de {name}"


@pytest.mark.skipif(shutil.which("gcc") is None, reason="hace falta gcc")
def test_c_y_python_producen_los_mismos_bytes(tmp_path):
    module = _py_module()
    structs = _structs()

    lines = [
        "#include <stdio.h>",
        '#include "drx_dsp_v0_1.h"',
        "",
        "int main(void) {",
    ]
    for name, fields in structs:
        lines.append(f"  drx_dsp_{name}_t {name} = {{")
        for index, field in enumerate(fields):
            value = _sample_value(index, field["type"])
            suffix = "ULL" if WIDTH[field["type"]] == 8 else "u"
            lines.append(f"    .{field['name']} = {value}{suffix},")
        lines.append("  };")
        lines.append(f"  const unsigned char *p_{name} = (const unsigned char *)&{name};")
        lines.append(f"  for (unsigned i = 0; i < sizeof({name}); i++)")
        lines.append(f'    printf("%02x", p_{name}[i]);')
        lines.append('  printf("\\n");')
    lines += ["  return 0;", "}", ""]

    source = tmp_path / "dump.c"
    source.write_text("\n".join(lines))
    binary = tmp_path / "dump"

    compile_result = subprocess.run(
        [
            "gcc",
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            f"-I{GENERATED}",
            str(source),
            "-o",
            str(binary),
        ],
        capture_output=True,
        text=True,
    )
    assert compile_result.returncode == 0, compile_result.stderr

    run_result = subprocess.run([str(binary)], capture_output=True, text=True, check=True)
    c_dumps = run_result.stdout.split()
    assert len(c_dumps) == len(structs)

    for (name, fields), c_hex in zip(structs, c_dumps, strict=True):
        py_class = getattr(module, "".join(p.capitalize() for p in name.split("_")))
        instance = py_class(
            **{
                field["name"]: _sample_value(index, field["type"])
                for index, field in enumerate(fields)
            }
        )
        assert instance.pack().hex() == c_hex, f"C y Python no coinciden en {name}"


def test_ida_y_vuelta_en_python():
    module = _py_module()
    for name, fields in _structs():
        py_class = getattr(module, "".join(p.capitalize() for p in name.split("_")))
        instance = py_class(
            **{
                field["name"]: _sample_value(index, field["type"])
                for index, field in enumerate(fields)
            }
        )
        assert py_class.unpack(instance.pack()) == instance


def test_el_codigo_de_error_de_d09_existe():
    """D-09: rechazar PRF × rango ilegal con un código definido en el contrato."""
    module = _py_module()
    assert module.Error.PRF_RANGE_ILLEGAL == 1
    assert module.Error.OK == 0


def test_los_tipos_de_mensaje_son_unicos():
    ids = [m["type_id"] for m in _schema()["message"]]
    assert len(ids) == len(set(ids))
    assert 0 not in ids, "0 se reserva para detectar un byte de tipo sin inicializar"
