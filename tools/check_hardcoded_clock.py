#!/usr/bin/env python3
"""Gate de CI: ninguna constante de reloj fuera del paquete de parámetros.

D-02 y `AGENTS.md`: `FS_HZ` es la única fuente de verdad temporal, y ninguna
frecuencia literal puede aparecer en `rtl/`, `fw/`, `sim/`, `model/`, `tcl/` ni
`contract/`. **La build falla si aparece.** No es un lint cosmético: es la única
defensa contra que la deuda de portabilidad se acumule en silencio. Un solo
`100_000_000` suelto convierte la migración a ZU9 en una auditoría manual.

Qué se marca
------------
Cualquier literal DECIMAL con valor >= 1e6, en notación normal o científica:
`100_000_000`, `100e6`, `250000000`, `1.0e9`.

Qué NO se marca, y por qué
--------------------------
* Literales hexadecimales y binarios: un valor de reloj no se escribe en hex, y
  las máscaras y los números mágicos del contrato sí.
* Los ficheros generados desde `config/params.toml`: son el paquete de
  parámetros, que es exactamente donde estos números deben vivir.
* Líneas con el marcador explícito `clock-const-ok: <razón>`. El marcador exige
  una razón escrita; una constante física o un conteo de muestras la tienen, un
  reloj no.
* Los comentarios. El gate mira código, no prosa: documentar que en ZedBoard son
  100e6 ciclos por segundo es exactamente lo que se quiere que la gente escriba.

Uso:
    python3 tools/check_hardcoded_clock.py [rutas...]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SCAN_DIRS = ("rtl", "fw", "sim", "model", "tcl", "contract")
SUFFIXES = {".sv", ".svh", ".v", ".vh", ".c", ".h", ".py", ".tcl", ".xdc", ".rs", ".mk"}

#: Ficheros generados desde el paquete de parámetros: son la excepción legítima.
EXCLUDED = {
    "rtl/generated",
    "fw/include/drx_params.h",
    "contract/generated",
    "tcl/generated",
}

THRESHOLD = 1_000_000

MARKER = "clock-const-ok:"

#: Literal decimal, con separadores `_` opcionales y exponente opcional. Se exige
#: que no venga precedido de `0x`/`0b` ni de un carácter de identificador.
NUMBER = re.compile(
    r"(?<![\w.$'])(?<!0[xXbB])(\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)(?![\w.])"
)


def _rel(path: Path) -> str:
    """Ruta relativa al repo, o absoluta si el fichero vive fuera de él."""
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def _excluded(path: Path) -> bool:
    rel = _rel(path)
    return any(rel == item or rel.startswith(item + "/") for item in EXCLUDED)


def _value(token: str) -> float | None:
    try:
        return float(token.replace("_", ""))
    except ValueError:
        return None


def strip_comments(lines: list[str]) -> list[str]:
    """Vacía los comentarios conservando el número de línea.

    Cubre `//`, `#` y bloques `/* ... */`, que es todo lo que aparece en los
    lenguajes que este gate escanea. No pretende ser un analizador léxico: si
    corta de más dentro de una cadena, el peor caso es no marcar un número que de
    todas formas no sería un reloj.
    """
    out: list[str] = []
    in_block = False
    for line in lines:
        result = []
        i = 0
        while i < len(line):
            two = line[i : i + 2]
            if in_block:
                if two == "*/":
                    in_block = False
                    i += 2
                    continue
                i += 1
                continue
            if two == "/*":
                in_block = True
                i += 2
                continue
            if two == "//" or line[i] == "#":
                break
            result.append(line[i])
            i += 1
        out.append("".join(result))
    return out


def scan_file(path: Path) -> list[tuple[int, str, str]]:
    hits: list[tuple[int, str, str]] = []
    raw = path.read_text(errors="replace").splitlines()
    for lineno, (line, code) in enumerate(zip(raw, strip_comments(raw), strict=True), 1):
        if MARKER in line:
            continue
        for match in NUMBER.finditer(code):
            value = _value(match.group(1))
            if value is not None and value >= THRESHOLD:
                hits.append((lineno, match.group(1), line.strip()))
    return hits


def iter_files(targets: list[Path]):
    for target in targets:
        if target.is_file():
            candidates = [target]
        else:
            candidates = sorted(target.rglob("*"))
        for path in candidates:
            if path.is_file() and path.suffix in SUFFIXES and not _excluded(path):
                yield path


def main(argv: list[str]) -> int:
    targets = [Path(a).resolve() for a in argv[1:]] or [ROOT / d for d in SCAN_DIRS]
    targets = [t for t in targets if t.exists()]

    failures = 0
    for path in iter_files(targets):
        for lineno, token, line in scan_file(path):
            rel = _rel(path)
            print(f"{rel}:{lineno}: constante de reloj hardcodeada: {token}")
            print(f"    {line}")
            failures += 1

    if failures:
        print(
            f"\n{failures} constante(s) sospechosa(s). Deriva el valor de `FS_HZ` "
            f"desde el paquete de parámetros, o si de verdad no es un reloj añade "
            f"`{MARKER} <razón>` en la línea.",
            file=sys.stderr,
        )
        return 1

    print("sin constantes de reloj hardcodeadas")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
