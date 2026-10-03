"""El reensamblado del cliente DSP de mentira aguanta cualquier troceado (Z4.6).

Es la única lógica que `tools/mock_dsp.py` añade por su cuenta: todo lo demás
—formatos, tipos, enumeraciones— sale de `contract/generated/drx_dsp_v0_1.py`,
así que no hay nada que verificar ahí que no verifiquen ya los tests del
contrato.

Lo que sí hay que verificar es el troceado. TCP entrega un FLUJO: un `recv`
puede traer medio mensaje, tres y medio, o un byte. Suponer que trae uno entero
es el error clásico, y con rayos de ~44 kB no es una posibilidad teórica —
nunca caben en un segmento. El caso de un byte por `recv` es el peor y el que
más rápido lo saca a la luz.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


def _carga(nombre: str, ruta: Path):
    spec = importlib.util.spec_from_file_location(nombre, ruta)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


C = _carga("drx_dsp_v0_1", ROOT / "contract" / "generated" / "drx_dsp_v0_1.py")
MOCK = _carga("mock_dsp", ROOT / "tools" / "mock_dsp.py")


def _trama(msg_type: int, cuerpo: bytes) -> bytes:
    return MOCK._encode(msg_type, cuerpo)


def _status(uptime: int = 7) -> bytes:
    return _trama(C.MsgType.STATUS, C.Status(uptime_s=uptime).pack())


def _ray(seq: int, bins: int = 4, n_ch: int = 3) -> bytes:
    cuerpo = C.Ray(seq=seq, bins=bins, n_channels=n_ch).pack()
    # La carga útil no se interpreta aquí; lo que importa es su longitud, que
    # es lo que el reensamblado usa para saber dónde acaba el mensaje.
    return _trama(C.MsgType.RAY, cuerpo + bytes(bins * n_ch * 4))


def test_un_mensaje_entero_sale_entero():
    framer = MOCK.Framer()
    salida = framer.push(_status(42))

    assert len(salida) == 1
    header, cuerpo = salida[0]
    assert header.msg_type == C.MsgType.STATUS
    assert C.Status.unpack(cuerpo).uptime_s == 42


def test_varios_mensajes_en_un_solo_recv():
    framer = MOCK.Framer()
    flujo = _status(1) + _ray(10) + _status(2)

    salida = framer.push(flujo)

    assert [h.msg_type for h, _ in salida] == [
        C.MsgType.STATUS, C.MsgType.RAY, C.MsgType.STATUS
    ]
    assert C.Ray.unpack(salida[1][1]).seq == 10


@pytest.mark.parametrize("trozo", [1, 2, 7, 13, 64, 1460])
def test_un_rayo_troceado_se_reensambla(trozo):
    """1460 es un MSS típico; 1 es el peor caso y el que rompe lo ingenuo."""
    framer = MOCK.Framer()
    flujo = _ray(99, bins=64, n_ch=3)

    recogidos = []
    for i in range(0, len(flujo), trozo):
        recogidos.extend(framer.push(flujo[i : i + trozo]))

    assert len(recogidos) == 1, f"con trozos de {trozo} B salieron {len(recogidos)}"
    header, cuerpo = recogidos[0]
    assert header.msg_type == C.MsgType.RAY
    assert header.payload_len == len(cuerpo)
    assert C.Ray.unpack(cuerpo).seq == 99


def test_una_cabecera_partida_no_adelanta_nada():
    """Con menos de 12 bytes no se puede ni mirar el `magic`."""
    framer = MOCK.Framer()
    flujo = _status()

    assert framer.push(flujo[:5]) == []
    assert framer.push(flujo[5:11]) == []
    assert len(framer.push(flujo[11:])) == 1


def test_un_magic_malo_se_denuncia_y_no_se_traga():
    """Resincronizar por las bravas escondería el problema: si el `magic` no
    cuadra, o el flujo no es de este contrato o ya se perdió la sincronía, y
    seguir leyendo desde un sitio arbitrario inventa mensajes."""
    framer = MOCK.Framer()
    malo = bytearray(_status())
    malo[0] ^= 0xFF

    with pytest.raises(ValueError, match="magic"):
        framer.push(bytes(malo))
