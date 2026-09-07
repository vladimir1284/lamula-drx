"""Exportación de vectores L1: el oráculo cruza a fichero.

Por qué existe
--------------
D-05 daba por hecho que un único runner de cocotb cubría los dos backends,
Verilator para L0 y xsim para L1. cocotb no tiene backend para xsim y nunca lo ha
tenido, y ese es el hallazgo P-09. La salida adoptada es mantener el modelo dorado
como oráculo (D-03 no se toca) y **cruzar la frontera Python↔simulador por
fichero** en vez de por VPI: aquí se escribe el estímulo y la salida esperada, y
el testbench nativo de SystemVerilog los lee con `$readmemh` y compara bit a bit.

Lo que se pierde es el runner único de cocotb en L1. Lo que se gana es no
depender de ninguna licencia nueva y que el mismo par de ficheros valga para
cualquier simulador que aparezca después.

Formato
-------
Un valor por línea, hexadecimal sin prefijo, en complemento a dos con el ancho
declarado en el manifiesto — que es exactamente lo que `$readmemh` espera para un
`logic signed [W-1:0]`. Nada de comentarios ni de cabecera dentro del fichero de
datos: los metadatos van al manifiesto JSON, no mezclados con las muestras.

El manifiesto lleva SHA-256 de cada fichero y la huella del paquete de
parámetros. Un caso cuyo `params_sha256` no coincide con el `config/params.toml`
vigente es un caso caducado, y el testbench tiene que rechazarlo en vez de
comparar contra un oráculo de otra configuración.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from drx_model import chain
from drx_model.params import PARAMS_TOML, Params

#: Nombres de fichero dentro del directorio de un caso. Los conoce también el
#: testbench de SystemVerilog: cambiarlos aquí obliga a cambiarlos allí.
STIMULUS_FILE = "stimulus.hex"
EXPECTED_I_FILE = "expected_i.hex"
EXPECTED_Q_FILE = "expected_q.hex"
MANIFEST_FILE = "manifest.json"


def params_sha256() -> str:
    """Huella del paquete de parámetros del que sale este oráculo."""
    return hashlib.sha256(PARAMS_TOML.read_bytes()).hexdigest()


def to_hex_lines(values: np.ndarray, bits: int) -> list[str]:
    """Enteros con signo a hexadecimal en complemento a dos de ancho fijo.

    Se comprueba el rango en vez de envolver en silencio: un valor que no cabe en
    `bits` significa que el modelo y el ancho declarado no coinciden, y eso es un
    fallo del generador, no un dato que haya que truncar.
    """
    values = np.asarray(values, dtype=np.int64)
    low, high = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    if values.size and (values.min() < low or values.max() > high):
        raise ValueError(
            f"valor fuera del rango de {bits} bits con signo "
            f"[{low}, {high}]: min={values.min()}, max={values.max()}"
        )
    modulus = 1 << bits
    digits = (bits + 3) // 4
    return [f"{int(v) & (modulus - 1):0{digits}x}" for v in values]


def _write_hex(path: Path, values: np.ndarray, bits: int) -> str:
    text = "\n".join(to_hex_lines(values, bits))
    if text:
        text += "\n"
    path.write_text(text, encoding="ascii")
    return hashlib.sha256(path.read_bytes()).hexdigest()


@dataclass(frozen=True)
class L1Case:
    """Un caso exportado: dónde está y qué contiene."""

    name: str
    directory: Path
    manifest: dict

    @property
    def manifest_path(self) -> Path:
        return self.directory / MANIFEST_FILE


def export_case(
    params: Params,
    name: str,
    stimulus: np.ndarray,
    out_root: Path,
    mode: str = chain.MODE_FINE,
) -> L1Case:
    """Corre el modelo sobre `stimulus` y escribe el caso completo.

    `stimulus` tiene que venir ya cuantizado a `sample_bits`, igual que lo
    consume el modelo: la cuantización es parte del oráculo y no se hace aquí.
    """
    ddc = chain.Ddc(params=params, mode=mode)
    result = ddc.process(stimulus)

    directory = out_root / params.name / name
    directory.mkdir(parents=True, exist_ok=True)

    stimulus_sha = _write_hex(
        directory / STIMULUS_FILE, stimulus, params.sample_bits
    )
    expected_i_sha = _write_hex(
        directory / EXPECTED_I_FILE, result.i, params.iq_bits
    )
    expected_q_sha = _write_hex(
        directory / EXPECTED_Q_FILE, result.q, params.iq_bits
    )

    manifest = {
        "schema_version": 1,
        "case": name,
        "platform": params.name,
        "mode": result.mode,
        "params_sha256": params_sha256(),
        "fs_hz": params.fs_hz,
        "decimation": result.decimation,
        "sample_bits": params.sample_bits,
        "iq_bits": params.iq_bits,
        "n_stimulus": int(np.asarray(stimulus).size),
        "n_expected": int(result.i.size),
        # Cuántas muestras de salida están contaminadas por el transitorio de
        # arranque de la cadena. El testbench las compara igual: el RTL arranca
        # con los mismos registros a cero que el modelo, así que el transitorio
        # también es bit a bit. Se declara para que un fallo dentro de esta
        # ventana se pueda leer como «arranque» y no como «aritmética».
        "settling_out_samples": int(np.ceil(_settling_in_samples(ddc) / result.decimation)),
        "overflow_count": int(np.count_nonzero(result.overflow)),
        "files": {
            STIMULUS_FILE: stimulus_sha,
            EXPECTED_I_FILE: expected_i_sha,
            EXPECTED_Q_FILE: expected_q_sha,
        },
    }
    (directory / MANIFEST_FILE).write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="ascii"
    )
    return L1Case(name=name, directory=directory, manifest=manifest)


def _settling_in_samples(ddc: chain.Ddc) -> int:
    """Longitud del transitorio de la cadena, en muestras de ENTRADA.

    CIC: `pipeline_fill` (la tubería real, ver `cic.py`) más `stages *
    diff_delay * rate` (el propio transitorio del filtro). FIR: su longitud,
    referida a la entrada multiplicando por el diezmado que tiene delante.
    """
    cic = ddc.cic.pipeline_fill + ddc.cic.stages * ddc.cic.diff_delay * ddc.cic.rate
    fir = ddc.fir.coeffs.size * ddc.cic.rate
    total = cic + fir
    if ddc.mode == chain.MODE_COARSE:
        total += ddc.halfband.coeffs.size * ddc.cic.rate * ddc.fir.decim
    return int(total)


def load_manifest(directory: Path) -> dict:
    """Lee el manifiesto y comprueba que el caso no ha caducado."""
    manifest = json.loads((directory / MANIFEST_FILE).read_text(encoding="ascii"))
    if manifest.get("params_sha256") != params_sha256():
        raise ValueError(
            f"el caso {directory} se generó con otro config/params.toml. "
            "Regenéralo con tools/gen_l1_vectors.py antes de simular: comparar "
            "contra un oráculo caducado es peor que no comparar."
        )
    for filename, digest in manifest["files"].items():
        actual = hashlib.sha256((directory / filename).read_bytes()).hexdigest()
        if actual != digest:
            raise ValueError(f"{directory / filename} no coincide con su SHA-256")
    return manifest
