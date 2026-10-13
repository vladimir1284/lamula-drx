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
from collections import Counter
from datetime import datetime
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
    parser.add_argument("--esperar", default=None, metavar="PRF:BINS,...",
                        help="pares prf_div:bins permitidos en las cabeceras, p.ej. "
                             "208416:1002,767312:3689. Cualquier rayo con otro par "
                             "(o con TRUNCATED) da código 5: un soak sobre una config "
                             "que nadie eligió no vale como evidencia")
    parser.add_argument("--estricto", action="store_true",
                        help="modo soak: terminar antes de --seconds (el DRx cerró el "
                             "socket) o pasar --stall s sin rayos da código 5, en vez "
                             "de parecer una corrida corta pero limpia")
    parser.add_argument("--stall", type=float, default=10.0,
                        help="con --estricto, segundos sin rayos que cuentan como parada")
    args = parser.parse_args(argv)

    esperados = None
    if args.esperar is not None:
        esperados = {tuple(int(x) for x in par.split(":")) for par in args.esperar.split(",")}

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
        # Evidencia de config: el soak de 72 h de oct-2026 corrio sobre una config
        # que nadie registro. Se cuenta cada combinacion distinta que pasa y se
        # guarda la cabecera del primer y del ultimo rayo.
        rayos_perdidos = 0
        truncados = 0
        configs = Counter()
        primero = ultimo = None
        cerrado_por_drx = False
        paradas = 0
        en_parada = False
        t0 = time.monotonic()
        t_ultimo_rayo = t0
        while time.monotonic() - t0 < args.seconds:
            # Vigilante de paradas: sin esto una placa colgada deja al cliente
            # esperando en silencio hasta el final de un soak de 72 h.
            if args.estricto and not en_parada and time.monotonic() - t_ultimo_rayo > args.stall:
                en_parada = True
                paradas += 1
                print(f"{datetime.now().isoformat(timespec='seconds')} "
                      f"sin rayos desde hace {args.stall:.0f} s (último seq={ultimo_seq})",
                      flush=True)
            try:
                data = sock.recv(65536)
            except TimeoutError:
                continue
            if not data:
                print(f"{datetime.now().isoformat(timespec='seconds')} el DRx cerró la conexión")
                cerrado_por_drx = True
                break
            bytes_totales += len(data)
            for header, cuerpo in framer.push(data):
                tipo = _nombre(C.MsgType, header.msg_type)
                cuenta[tipo] = cuenta.get(tipo, 0) + 1
                if header.msg_type == C.MsgType.RAY:
                    ray = C.Ray.unpack(cuerpo)
                    n_rayos += 1
                    if en_parada:
                        print(f"{datetime.now().isoformat(timespec='seconds')} "
                              f"rayos de nuevo tras {time.monotonic() - t_ultimo_rayo:.1f} s",
                              flush=True)
                        en_parada = False
                    t_ultimo_rayo = time.monotonic()
                    # Un hueco en `seq` es un rayo que el DRx descartó o que la red
                    # perdió. Con TCP lo segundo no pasa en silencio, así que un
                    # hueco aquí apunta a `sink_drops` del lado del DRx -- ver D-16
                    # sobre la contrapresión.
                    if ultimo_seq is not None and (ray.seq - ultimo_seq) & 0xFFFFFFFF != 1:
                        huecos += 1
                        perdidos = ((ray.seq - ultimo_seq) & 0xFFFFFFFF) - 1
                        rayos_perdidos += perdidos
                        # Hora de pared: sin ella un hueco no se puede cruzar con
                        # nada (uart, carga del host, otros procesos).
                        print(f"{datetime.now().isoformat(timespec='seconds')} "
                              f"hueco seq {ultimo_seq}->{ray.seq} ({perdidos} perdidos)",
                              flush=True)
                    ultimo_seq = ray.seq
                    if ray.ray_flags & C.RayFlag.TRUNCATED:
                        truncados += 1
                    batch_high = bool(ray.ray_flags & C.RayFlag.BATCH_HIGH)
                    configs[(ray.prf_div, ray.bins, ray.pulse_width_idx, ray.pulse_mode,
                             ray.cell_mode, ray.n_channels, batch_high)] += 1
                    if primero is None:
                        primero = ray
                    ultimo = ray
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
        print(f"huecos de seq: {huecos} ({rayos_perdidos} rayos perdidos)")
        print(f"rayos con TRUNCATED: {truncados}")
        for nombre, r in (("primer", primero), ("ultimo", ultimo)):
            print(f"cabecera {nombre} rayo: seq={r.seq} prf_div={r.prf_div} bins={r.bins} "
                  f"pulse_width_idx={r.pulse_width_idx} pulse_mode={r.pulse_mode} "
                  f"cell_mode={r.cell_mode} n_ch={r.n_channels} flags={r.ray_flags:#x}")
        print("configs vistas (prf_div, bins, pw_idx, pulse_mode, cell_mode, n_ch, batch_high):")
        for k, v in configs.most_common():
            print(f"  {k}: {v}")

        problemas = []
        if esperados is not None:
            fuera = {k: v for k, v in configs.items() if (k[0], k[1]) not in esperados}
            if fuera:
                problemas.append(f"cabeceras fuera de lo esperado {sorted(esperados)}: {fuera}")
        if truncados and esperados is not None:
            problemas.append(f"{truncados} rayos con TRUNCATED")
        if args.estricto:
            if cerrado_por_drx or transcurrido < args.seconds - 2.0:
                problemas.append(f"terminó a los {transcurrido:.0f} s de {args.seconds:.0f} s pedidos")
            if paradas:
                problemas.append(f"{paradas} paradas de más de {args.stall:.0f} s sin rayos")
        for p in problemas:
            print(f"PROBLEMA: {p}")
        if huecos:
            return 3
        return 5 if problemas else 0
    print("NO llegó ningún rayo")
    return 4


if __name__ == "__main__":
    raise SystemExit(main())
