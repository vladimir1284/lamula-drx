"""El plano de control hace lo que dice el contrato, y contesta lo que dice el contrato.

`test_contract_io.py` comprueba el camino de BYTES: que una trama se monta y se
desmonta igual en C y en Python. Esto comprueba el camino de SIGNIFICADO: que un
`test_stimulus_select` que entra por el cable acaba en la acción correcta con
los argumentos correctos, y que lo que vuelve es un `config_ack` con el `seq`
original y el código de error que la acción devolvió.

Lo que más cuesta descubrir de otra forma, y por eso está aquí:

1. **El código de error es el de la acción, no uno inventado por el despacho.**
   Si el plano de control contestara siempre `ok`, todo parecería funcionar y el
   par remoto creería aplicadas configuraciones que se rechazaron.
2. **`seq` vuelve tal cual.** Es lo que empareja respuesta con petición; un
   `seq` perdido deja al emisor esperando para siempre sin ningún error.
3. **Una función que todavía no existe se contesta `unimplemented` (11), no
   `unknown_message` (3).** Son dos diagnósticos distintos para el otro lado:
   uno dice "hablamos versiones distintas", el otro "hablamos la misma y esto
   aún no está".
4. **`afc` no se contesta**, porque no lleva `seq`.

El binario ejercita el MISMO `drx_control.c` que Vitis compila cruzado para el
Cortex-A9.
"""

from __future__ import annotations

import importlib.util
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
GENERATED = ROOT / "contract" / "generated"

#: Bits de la máscara de acciones del arnés, en el orden de su cabecera.
SELECT, CONFIG, AFC = 1, 2, 4
TODAS = SELECT | CONFIG | AFC


def _py_module():
    spec = importlib.util.spec_from_file_location(
        "drx_dsp_v0_1", GENERATED / "drx_dsp_v0_1.py"
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def control_bin() -> Path:
    if shutil.which("make") is None or shutil.which("gcc") is None:
        pytest.skip("hacen falta make y gcc")
    build = subprocess.run(
        ["make", "-s", "check", "BUILD_DIR=../build/fw-control"],
        cwd=ROOT / "fw",
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, build.stdout + build.stderr
    return ROOT / "build" / "fw-control" / "drx_control_selftest"


def _frame(module, msg_type: int, body: bytes) -> bytes:
    header = module.Header(
        magic=module.MAGIC,
        version_major=module.VERSION_MAJOR,
        version_minor=module.VERSION_MINOR,
        msg_type=msg_type,
        flags=0,
        payload_len=len(body),
    )
    return header.pack() + body


def _run(control_bin: Path, wire: bytes, mask: int = TODAS) -> dict:
    result = subprocess.run(
        [str(control_bin), str(mask)],
        input=wire.hex(),
        capture_output=True,
        text=True,
        check=True,
    )
    acciones = []
    resumen: dict[str, int] = {}
    respuestas = b""
    for line in result.stdout.splitlines():
        if line.startswith("accion "):
            partes = line.split()
            acciones.append(
                {"nombre": partes[1], **{k: int(v) for k, v in (p.split("=") for p in partes[2:])}}
            )
        elif line.startswith("respuestas="):
            respuestas = bytes.fromhex(line.split("=", 1)[1])
        else:
            for part in line.split():
                clave, valor = part.split("=", 1)
                resumen[clave] = int(valor, 0)
    return {"acciones": acciones, "respuestas": respuestas, **resumen}


def _acks(module, blob: bytes) -> list:
    """Desmonta la ristra de respuestas como `config_ack` encadenados."""
    out = []
    off = 0
    while off < len(blob):
        header = module.Header.unpack(blob[off : off + module.Header.SIZE])
        assert header.magic == module.MAGIC
        assert header.msg_type == module.MsgType.CONFIG_ACK
        body = blob[off + module.Header.SIZE : off + module.Header.SIZE + header.payload_len]
        out.append(module.ConfigAck.unpack(body))
        off += module.Header.SIZE + header.payload_len
    return out


def test_test_stimulus_select_llega_a_la_accion_con_sus_argumentos(control_bin):
    module = _py_module()
    msg = module.TestStimulusSelect(seq=0xABCD1234, vector_id=5, pad0=0, repeat=3)
    salida = _run(control_bin, _frame(module, module.MsgType.TEST_STIMULUS_SELECT, msg.pack()))

    assert salida["acciones"] == [
        {"nombre": "select_stimulus", "vector_id": 5, "repeat": 3}
    ]
    (ack,) = _acks(module, salida["respuestas"])
    assert ack.seq == 0xABCD1234, "el `seq` no volvió tal cual"
    assert ack.error == module.Error.OK


def test_el_codigo_de_error_que_vuelve_es_el_de_la_accion(control_bin):
    """El vector 99 no existe en ningún catálogo; la acción lo rechaza."""
    module = _py_module()
    msg = module.TestStimulusSelect(seq=7, vector_id=99, pad0=0, repeat=1)
    salida = _run(control_bin, _frame(module, module.MsgType.TEST_STIMULUS_SELECT, msg.pack()))

    (ack,) = _acks(module, salida["respuestas"])
    assert ack.seq == 7
    assert ack.error == module.Error.VECTOR_UNKNOWN, (
        "el despacho tapó el código de la acción"
    )


def test_una_funcion_que_no_existe_se_contesta_unimplemented(control_bin):
    """Y no `unknown_message`, que querría decir otra cosa.

    Es el caso de `config` y `afc` en Z4.3: el firmware entiende los dos, pero
    aplicarlos es Z4.4 y Z4.5.
    """
    module = _py_module()
    config = module.Config(seq=42, prf_div=767198, range_bins=3687)
    salida = _run(
        control_bin,
        _frame(module, module.MsgType.CONFIG, config.pack()),
        mask=SELECT,  # sin apply_config
    )

    assert salida["acciones"] == [], "se invocó una acción que no existe"
    (ack,) = _acks(module, salida["respuestas"])
    assert ack.seq == 42
    assert ack.error == module.Error.UNIMPLEMENTED
    assert ack.error != module.Error.UNKNOWN_MESSAGE


def test_afc_no_se_contesta_porque_no_lleva_seq(control_bin):
    module = _py_module()
    afc = module.Afc(nco_phase_inc=0x1122334455667788, apply_at_seq=9, pad0=0)
    salida = _run(control_bin, _frame(module, module.MsgType.AFC, afc.pack()))

    assert salida["acciones"] == [{"nombre": "apply_afc", "apply_at_seq": 9}]
    assert salida["respuestas"] == b"", "`afc` no tiene `seq` al que responder"
    assert salida["replied"] == 0


def test_una_rafaga_mezclada_se_despacha_en_orden(control_bin):
    """Tres mensajes distintos en el mismo empujón, y dos respuestas.

    El orden importa: si el despacho reordenara, un `config` que llega después
    de un `test_stimulus_select` podría aplicarse antes, y el estado final
    dependería de la implementación en vez del cable.
    """
    module = _py_module()
    stim = module.TestStimulusSelect(seq=1, vector_id=0, pad0=0, repeat=0)
    afc = module.Afc(nco_phase_inc=1, apply_at_seq=2, pad0=0)
    config = module.Config(seq=3, prf_div=208333, range_bins=1000)

    wire = (
        _frame(module, module.MsgType.TEST_STIMULUS_SELECT, stim.pack())
        + _frame(module, module.MsgType.AFC, afc.pack())
        + _frame(module, module.MsgType.CONFIG, config.pack())
    )
    salida = _run(control_bin, wire)

    assert [a["nombre"] for a in salida["acciones"]] == [
        "select_stimulus",
        "apply_afc",
        "apply_config",
    ]
    assert salida["handled"] == 3
    acks = _acks(module, salida["respuestas"])
    assert [a.seq for a in acks] == [1, 3], "`afc` no se contesta; los otros dos sí"
    assert salida["send_fails"] == 0
