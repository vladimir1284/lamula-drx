"""El framer en C del DRx y la implementación generada de Python tienen que coincidir.

`contract/tests/test_contract.py` ya comprueba que los **structs** generados por
los tres lados tienen el mismo layout. Eso no es suficiente desde Z4.3: lo que
viaja por el cable no es un struct, es una trama —cabecera común + cuerpo + carga
variable— y la lógica que la monta y la desmonta (`fw/src/app/drx_contract_io.c`)
sí está escrita a mano. Un error ahí produce tramas que parsean y desincronizan
al lector en el mensaje siguiente, que es el fallo más caro de diagnosticar que
tiene este formato.

Qué se comprueba:
  1. Las tramas que el C emite son byte a byte las que Python monta del mismo
     esquema, incluido un `ray` con carga variable (el único mensaje cuyo
     `payload_len` no es el tamaño de su struct).
  2. El C se niega a emitir una trama mal formada en vez de emitirla.
  3. El parser recupera los mismos mensajes tanto de un empujón como byte a
     byte — el caso que de verdad ocurre en TCP y el que una implementación
     ingenua pasa por alto.
  4. Cada fallo de validación para el flujo con el estado correcto, y se traduce
     al código de error del contrato que corresponde.

El binario que se ejercita compila el MISMO `drx_contract_io.c` que Vitis
compila cruzado para el Cortex-A9, no una copia.
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

#: Los mismos números fijos que `fw/src/drx_contract_io_selftest.c`. Distintos
#: entre campos a propósito: con ceros, intercambiar dos campos del mismo ancho
#: no se notaría.
SAMPLE_SEQ = 0x11223344
SAMPLE_ERROR = 7
SAMPLE_UPTIME = 0x0A0B0C0D

#: Estados de `DrxFrameStatus`, en el orden del enum de drx_contract_io.h.
OK, NEED_MORE, BAD_MAGIC, BAD_VERSION, BAD_FLAGS, BAD_LENGTH, UNKNOWN_TYPE, TOO_LARGE = range(8)


def _py_module():
    spec = importlib.util.spec_from_file_location(
        "drx_dsp_v0_1", GENERATED / "drx_dsp_v0_1.py"
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def contract_io() -> Path:
    if shutil.which("make") is None or shutil.which("gcc") is None:
        pytest.skip("hacen falta make y gcc")
    build = subprocess.run(
        ["make", "-s", "check", "BUILD_DIR=../build/fw-contract-io"],
        cwd=ROOT / "fw",
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, build.stdout + build.stderr
    return ROOT / "build" / "fw-contract-io" / "drx_contract_io_selftest"


@pytest.fixture(scope="module")
def encoded(contract_io) -> dict[str, str]:
    result = subprocess.run(
        [str(contract_io), "encode"], capture_output=True, text=True, check=True
    )
    return dict(line.split("=", 1) for line in result.stdout.splitlines())


def _frame(module, msg_type: int, body: bytes, payload: bytes = b"") -> bytes:
    """La trama tal como la define el esquema, montada desde el lado de Python."""
    header = module.Header(
        magic=module.MAGIC,
        version_major=module.VERSION_MAJOR,
        version_minor=module.VERSION_MINOR,
        msg_type=msg_type,
        flags=0,
        payload_len=len(body) + len(payload),
    )
    return header.pack() + body + payload


def _parse(contract_io: Path, wire: bytes, chunk: int = 0) -> dict:
    result = subprocess.run(
        [str(contract_io), "parse", str(chunk)],
        input=wire.hex(),
        capture_output=True,
        text=True,
        check=True,
    )
    mensajes = []
    resumen: dict[str, int] = {}
    for line in result.stdout.splitlines():
        if line.startswith("msg "):
            campos = dict(part.split("=", 1) for part in line[4:].split())
            mensajes.append({k: int(v, 0) for k, v in campos.items()})
        else:
            for part in line.split():
                clave, valor = part.split("=", 1)
                resumen[clave] = int(valor, 0)
    return {"mensajes": mensajes, **resumen}


def test_las_tramas_de_c_son_las_de_python(encoded):
    """Byte a byte, incluido el `ray` con carga variable."""
    module = _py_module()

    ack = module.ConfigAck(seq=SAMPLE_SEQ, error=SAMPLE_ERROR, pad0=0, pad1=0)
    assert encoded["config_ack"] == _frame(
        module, module.MsgType.CONFIG_ACK, ack.pack()
    ).hex()

    status = module.Status(
        uptime_s=SAMPLE_UPTIME,
        bite_flags=0x40,
        ssa_underruns=1,
        dma_overruns=2,
        ssi_errors=3,
        ddc_overflows=4,
        last_error=5,
        pad0=0,
        pad1=0,
    )
    assert encoded["status"] == _frame(
        module, module.MsgType.STATUS, status.pack()
    ).hex()


def test_el_ray_cuenta_su_carga_variable_en_payload_len(encoded):
    """El único mensaje donde las dos lecturas de `payload_len` difieren.

    Un lector con la lectura equivocada consume 36 bytes de menos por rayo y se
    desincroniza en el segundo mensaje, no en el primero — por eso vale la pena
    fijarlo con un caso propio y no solo con la comparación de bytes.
    """
    module = _py_module()
    import struct

    ray = module.Ray(
        seq=SAMPLE_SEQ,
        timestamp_ns=0x0102030405060708,
        trigger_count=0x99,
        bins=2,
        n_channels=1,
        channel_mask=module.Channel.RX_0,
    )
    iq = struct.pack("<4h", 1, -1, 2, -2)
    esperado = _frame(module, module.MsgType.RAY, ray.pack(), iq)
    assert encoded["ray"] == esperado.hex()

    cabecera = module.Header.unpack(bytes.fromhex(encoded["ray"]))
    assert cabecera.payload_len == module.Ray.SIZE + len(iq)
    assert cabecera.payload_len != len(iq), "payload_len volvió a la lectura ambigua"


def test_el_emisor_se_niega_a_emitir_tramas_mal_formadas(encoded):
    """Devolver 0 y no escribir nada, en vez de emitir algo que el otro lado parsea."""
    assert encoded["rechaza_body_corto"] == "0"
    assert encoded["rechaza_tipo_desconocido"] == "0"
    assert encoded["rechaza_carga_en_mensaje_fijo"] == "0"
    assert encoded["rechaza_buffer_corto"] == "0"


def _tres_mensajes_down(module) -> bytes:
    config = module.Config(seq=1, prf_div_low=767198, range_bins_low=3687, cell_mode=0)
    afc = module.Afc(nco_phase_inc=0x0102030405060708, apply_at_seq=2, pad0=0)
    stim = module.TestStimulusSelect(seq=3, vector_id=5, pad0=0, repeat=0)
    return (
        _frame(module, module.MsgType.CONFIG, config.pack())
        + _frame(module, module.MsgType.AFC, afc.pack())
        + _frame(module, module.MsgType.TEST_STIMULUS_SELECT, stim.pack())
    )


@pytest.mark.parametrize("chunk", [0, 1, 7, 12, 13])
def test_el_parser_da_lo_mismo_venga_como_venga_partido(contract_io, chunk):
    """TCP parte los mensajes donde quiere; el resultado no puede depender de eso.

    Los tamaños elegidos no son arbitrarios: 1 es el peor caso, 12 es
    exactamente la cabecera común y 13 la cruza por un byte — los dos puntos
    donde una máquina de estados mal escrita se equivoca.
    """
    module = _py_module()
    salida = _parse(contract_io, _tres_mensajes_down(module), chunk)

    assert salida["accepted"] == 3
    assert salida["rejected"] == 0
    assert salida["status"] == OK
    assert [m["type"] for m in salida["mensajes"]] == [
        module.MsgType.CONFIG,
        module.MsgType.AFC,
        module.MsgType.TEST_STIMULUS_SELECT,
    ]
    assert [m["payload_len"] for m in salida["mensajes"]] == [
        module.Config.SIZE,
        module.Afc.SIZE,
        module.TestStimulusSelect.SIZE,
    ]
    # Lo que el arnés imprime como `seq` es en realidad el primer u32 del
    # cuerpo. Para `config` y `test_stimulus_select` eso ES `seq`; para `afc`
    # NO —su primer campo es `nco_phase_inc`, de 64 bits— así que ahí toca la
    # mitad baja de esa palabra. Comprobarlo así, y no suponiendo que los tres
    # empiezan igual, es lo que hace que este test detecte un cuerpo desplazado
    # un campo en vez de taparlo.
    assert [m["seq"] for m in salida["mensajes"]] == [1, 0x05060708, 3]


def test_un_mensaje_incompleto_espera_mas_sin_entregar_nada(contract_io):
    """Media trama no es una trama: ni se entrega ni se descarta."""
    module = _py_module()
    entera = _tres_mensajes_down(module)
    salida = _parse(contract_io, entera[: len(entera) - 1])

    assert salida["accepted"] == 2, "los dos primeros sí estaban completos"
    assert salida["rejected"] == 0
    assert salida["status"] == NEED_MORE


@pytest.mark.parametrize(
    "mutacion,estado_esperado,codigo_esperado",
    [
        ("magic", BAD_MAGIC, 0),
        ("version_major", BAD_VERSION, 2),
        ("flags", BAD_FLAGS, 4),
        ("payload_len", BAD_LENGTH, 4),
        ("msg_type_up", UNKNOWN_TYPE, 3),
        ("msg_type_desconocido", UNKNOWN_TYPE, 3),
    ],
)
def test_cada_fallo_de_validacion_para_el_flujo_con_su_estado(
    contract_io, mutacion, estado_esperado, codigo_esperado
):
    """Y se traduce al código del contrato que corresponde, o a ninguno.

    `magic` mal no es contestable: el flujo entero no es de este contrato y lo
    que procede es cerrar, no mandar un `config_ack` por un canal que a lo mejor
    ni siquiera lo entiende. Por eso su código esperado es 0 (`ok`) y no un
    error inventado.
    """
    module = _py_module()
    config = module.Config(seq=1, prf_div_low=767198, range_bins_low=3687)
    wire = bytearray(_frame(module, module.MsgType.CONFIG, config.pack()))

    if mutacion == "magic":
        wire[0] ^= 0xFF
    elif mutacion == "version_major":
        wire[4] = 9
    elif mutacion == "flags":
        wire[7] = 1
    elif mutacion == "payload_len":
        wire[8] = module.Config.SIZE + 1
    elif mutacion == "msg_type_up":
        wire[6] = module.MsgType.STATUS
    elif mutacion == "msg_type_desconocido":
        wire[6] = 99

    salida = _parse(contract_io, bytes(wire))
    assert salida["accepted"] == 0
    assert salida["rejected"] == 1
    assert salida["status"] == estado_esperado
    assert salida["error_code"] == codigo_esperado
    # El parser se para: no consume el cuerpo de una trama que ya rechazó.
    assert salida["consumed"] == module.Header.SIZE


def test_el_parser_no_sigue_leyendo_tras_una_cabecera_invalida(contract_io):
    """Tras perder el punto de sincronización, seguir solo produce basura creíble.

    Es una decisión, no una limitación: saltarse la trama mala exigiría adivinar
    dónde empieza la siguiente, y un acierto por casualidad entregaría un mensaje
    inventado al plano de control.
    """
    module = _py_module()
    config = module.Config(seq=1, prf_div_low=767198, range_bins_low=3687)
    mala = bytearray(_frame(module, module.MsgType.CONFIG, config.pack()))
    mala[0] ^= 0xFF
    buena = _frame(module, module.MsgType.CONFIG, config.pack())

    salida = _parse(contract_io, bytes(mala) + buena)
    assert salida["accepted"] == 0, "entregó un mensaje tras perder la sincronización"
    assert salida["status"] == BAD_MAGIC
