#!/usr/bin/env python3
"""Cliente DSP de mentira: conecta al DRx y habla el contrato de verdad (Z4.6).

Qué contesta, y por qué hacía falta. Hasta Z4.5 el contrato se ejercitaba de
dos maneras, las dos a medias: el framer en C se contrastaba contra este mismo
esquema **en el host**, sin cable de por medio, y en placa se le empujaban
tramas sintéticas que el propio firmware se fabricaba (`drx_control_boot.c`,
`DrxAfcApp_SelfTest`). Nadie había puesto nunca un socket. Esto es la otra
punta del cable, y es lo que convierte a Z4.6 en el cierre de ZM4.

**No reimplementa el contrato.** Todo lo que empaqueta o desempaqueta sale de
`contract/generated/drx_dsp_v0_1.py`, generado del mismo esquema del que sale
el C del DRx. Escribir aquí un `struct.pack` a mano sería construir un segundo
contrato que coincide con el primero por casualidad, y el día que divergieran
este programa diría que todo va bien.

El DRx ESCUCHA y nosotros conectamos (D-16); el puerto sale del esquema
(`TCP_PORT`), no de un número escrito aquí.

    tools/mock_dsp.py --host 192.168.1.10 --seconds 10
    tools/mock_dsp.py --afc 1025629931
    tools/mock_dsp.py --stimulus tono_sobre_escala --seconds 5

Sin argumentos de bajada solo escucha y mide, que ya sirve para ver si los
rayos llegan, si llegan seguidos y a qué ritmo.
"""

from __future__ import annotations

import argparse
import importlib.util
import socket
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GENERATED = ROOT / "contract" / "generated" / "drx_dsp_v0_1.py"


def _contrato():
    """El módulo generado, cargado por ruta.

    Por ruta y no por `import` normal porque `contract/generated/` no es un
    paquete y no tiene por qué estar en `sys.path`: lo que importa es que sea
    EXACTAMENTE el fichero que `tools/gen_contract.py` escribió.
    """
    spec = importlib.util.spec_from_file_location("drx_dsp_v0_1", GENERATED)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


C = _contrato()


class Framer:
    """Reensamblado incremental, el espejo de `DrxParser` del lado del DRx.

    TCP entrega un flujo de bytes: un `recv` puede traer medio mensaje, tres
    mensajes y medio, o un byte. Suponer que trae uno entero es el error
    clásico, y aquí se nota enseguida porque un rayo son ~44 kB y nunca cabe
    en un segmento.
    """

    def __init__(self) -> None:
        self._buf = bytearray()

    def push(self, data: bytes):
        """Añade bytes y devuelve los mensajes completos que hayan salido."""
        self._buf.extend(data)
        salida = []
        while True:
            if len(self._buf) < C.Header.SIZE:
                return salida
            header = C.Header.unpack(bytes(self._buf[: C.Header.SIZE]))
            if header.magic != C.MAGIC:
                raise ValueError(
                    f"magic {header.magic:#010x}, se esperaba {C.MAGIC:#010x}: "
                    "el flujo no es de este contrato o se perdió la sincronía"
                )
            total = C.Header.SIZE + header.payload_len
            if len(self._buf) < total:
                return salida
            cuerpo = bytes(self._buf[C.Header.SIZE : total])
            del self._buf[:total]
            salida.append((header, cuerpo))


def _encode(msg_type: int, cuerpo: bytes) -> bytes:
    header = C.Header(
        magic=C.MAGIC,
        version_major=C.VERSION_MAJOR,
        version_minor=C.VERSION_MINOR,
        msg_type=msg_type,
        flags=0,
        payload_len=len(cuerpo),
    )
    return header.pack() + cuerpo


def _nombre(clase, valor: int) -> str:
    for nombre, v in vars(clase).items():
        if not nombre.startswith("_") and v == valor:
            return nombre.lower()
    return f"? ({valor})"


def _bite(flags: int) -> str:
    if flags == 0:
        return "limpio"
    puestos = [
        nombre.lower()
        for nombre, v in vars(C.BiteFlag).items()
        if not nombre.startswith("_") and isinstance(v, int) and flags & v
    ]
    return "+".join(puestos) if puestos else f"{flags:#x}"


def _espectro(ray, payload: bytes) -> None:
    """Pico por canal del rayo recibido, en fracción de la tasa diezmada.

    Reusa la medida de `tools/dump_ray.py` en vez de escribir otra FFT: lo que
    se compara contra el modelo dorado tiene que medirse igual, o la
    comparación mide la diferencia entre las dos medidas.
    """
    import numpy as np

    spec = importlib.util.spec_from_file_location("dump_ray", ROOT / "tools" / "dump_ray.py")
    dump_ray = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = dump_ray
    spec.loader.exec_module(dump_ray)

    esperado = ray.bins * ray.n_channels * 4
    if len(payload) != esperado:
        print(f"carga útil de {len(payload)} B, se esperaban {esperado}")
        return

    # El contrato entrega pares (I,Q) de int16, canal más rápido que bin.
    pares = np.frombuffer(payload, dtype="<i2").reshape(ray.bins, ray.n_channels, 2)
    print(f"espectro del rayo seq={ray.seq} (bins={ray.bins}):")
    for ch in range(ray.n_channels):
        s = dump_ray.spectrum(pares[:, ch, 0], pares[:, ch, 1])
        print(f"  canal {ch}: pico en bin {s['peak_bin']:+d} "
              f"({s['peak_frac']:+.5f} de fs_dec), {s['peak_db']:.2f} dBFS, "
              f"potencia {s['power_db']:.2f} dBFS")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="192.168.1.10", help="IP del DRx")
    parser.add_argument("--port", type=int, default=C.TCP_PORT,
                        help=f"puerto del DRx (por defecto {C.TCP_PORT}, del esquema)")
    parser.add_argument("--seconds", type=float, default=5.0,
                        help="cuánto escuchar antes de resumir")
    parser.add_argument("--afc", type=lambda v: int(v, 0), default=None,
                        help="manda un `afc` con esta palabra de fase")
    parser.add_argument("--apply-at", type=int, default=0,
                        help="`apply_at_seq` del `afc` (0 = ya)")
    parser.add_argument("--stimulus", default=None,
                        help="manda un `test_stimulus_select` con este vector")
    parser.add_argument("--repeat", type=int, default=0,
                        help="`repeat` del `test_stimulus_select` (0 = en bucle)")
    parser.add_argument("--quiet", action="store_true",
                        help="solo el resumen, sin una línea por mensaje")
    parser.add_argument("--spectrum", action="store_true",
                        help="mide el espectro del último rayo recibido. Es lo "
                             "que cierra el lazo de un `afc` SIN JTAG: la "
                             "corrección entra por el socket y su efecto se ve "
                             "en los datos que salen por el mismo socket")
    args = parser.parse_args(argv)

    print(f"contrato v{C.VERSION_MAJOR}.{C.VERSION_MINOR}, "
          f"conectando a {args.host}:{args.port}")
    try:
        sock = socket.create_connection((args.host, args.port), timeout=5.0)
    except OSError as exc:
        print(f"no se pudo conectar: {exc}")
        return 1

    with sock:
        sock.settimeout(1.0)
        if args.afc is not None:
            cuerpo = C.Afc(nco_phase_inc=args.afc, apply_at_seq=args.apply_at).pack()
            sock.sendall(_encode(C.MsgType.AFC, cuerpo))
            print(f"-> afc nco_phase_inc={args.afc} apply_at_seq={args.apply_at}")
        if args.stimulus is not None:
            vector = getattr(C.StimulusVector, args.stimulus.upper(), None)
            if vector is None:
                disponibles = sorted(
                    n.lower() for n, v in vars(C.StimulusVector).items()
                    if not n.startswith("_") and isinstance(v, int)
                )
                print(f"vector desconocido: {args.stimulus}. Hay {disponibles}")
                return 2
            cuerpo = C.TestStimulusSelect(vector_id=vector, repeat=args.repeat).pack()
            sock.sendall(_encode(C.MsgType.TEST_STIMULUS_SELECT, cuerpo))
            print(f"-> test_stimulus_select {args.stimulus} repeat={args.repeat}")

        framer = Framer()
        ultimo_iq = None
        cuenta = {}
        bytes_totales = 0
        # Contadores, no la lista de rayos: a 223 rayos/s una corrida de 72 h
        # son ~58 M de objetos y ~8 GB de RSS (medido: ~110 MB/h).
        n_rayos = 0
        huecos = 0
        ultimo_seq = None
        t0 = time.monotonic()
        while time.monotonic() - t0 < args.seconds:
            try:
                data = sock.recv(65536)
            except TimeoutError:
                continue
            if not data:
                print("el DRx cerró la conexión")
                break
            bytes_totales += len(data)
            for header, cuerpo in framer.push(data):
                tipo = _nombre(C.MsgType, header.msg_type)
                cuenta[tipo] = cuenta.get(tipo, 0) + 1
                if header.msg_type == C.MsgType.RAY:
                    ray = C.Ray.unpack(cuerpo)
                    n_rayos += 1
                    # Un hueco en `seq` es un rayo que el DRx descartó o que la red
                    # perdió. Con TCP lo segundo no pasa en silencio, así que un
                    # hueco aquí apunta a `sink_drops` del lado del DRx -- ver D-16
                    # sobre la contrapresión.
                    if ultimo_seq is not None and (ray.seq - ultimo_seq) & 0xFFFFFFFF != 1:
                        huecos += 1
                    ultimo_seq = ray.seq
                    if args.spectrum:
                        ultimo_iq = (ray, cuerpo[C.Ray.SIZE :])
                    if not args.quiet and n_rayos <= 3:
                        print(f"<- ray seq={ray.seq} trig={ray.trigger_count} "
                              f"bins={ray.bins} n_ch={ray.n_channels} "
                              f"flags={ray.ray_flags:#x} payload={header.payload_len}B")
                elif header.msg_type == C.MsgType.STATUS:
                    st = C.Status.unpack(cuerpo)
                    if not args.quiet:
                        print(f"<- status bite={_bite(st.bite_flags)} "
                              f"uptime={st.uptime_s}s last_error="
                              f"{_nombre(C.Error, st.last_error)}")
                elif header.msg_type == C.MsgType.CONFIG_ACK:
                    ack = C.ConfigAck.unpack(cuerpo)
                    print(f"<- config_ack seq={ack.seq} "
                          f"error={_nombre(C.Error, ack.error)}")
                elif not args.quiet:
                    print(f"<- {tipo} payload={header.payload_len}B")

        transcurrido = time.monotonic() - t0

    print()
    print(f"{transcurrido:.1f} s, {bytes_totales / 1e6:.2f} MB "
          f"({bytes_totales * 8 / transcurrido / 1e6:.1f} Mbps)")
    print(f"mensajes: {cuenta or 'ninguno'}")
    if args.spectrum and ultimo_iq is not None:
        _espectro(*ultimo_iq)
    if n_rayos:
        print(f"rayos: {n_rayos} ({n_rayos / transcurrido:.1f}/s)")
        print(f"huecos de seq: {huecos}")
        return 0 if huecos == 0 else 3
    print("NO llegó ningún rayo")
    return 4


if __name__ == "__main__":
    raise SystemExit(main())
