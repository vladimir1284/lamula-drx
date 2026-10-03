#!/usr/bin/env python3
"""Barre el catálogo de estímulos contra rayos reales y lo compara con el modelo.

Es la medida que [P-16](../docs/alcance/pendientes.md#p-16) bloqueaba y que
le falta a ZM4: hasta hoy el catálogo de ocho vectores de Z4.3 se podía
seleccionar en caliente, pero con el motor de timing en marcha no salía ni un
rayo, así que nunca se comparó un rayo real de cada vector contra
`model/drx_model`.

QUÉ NO REIMPLEMENTA, que es casi todo:

- El contrato y el reensamblado salen de `tools/mock_dsp.py`, cargado por
  ruta. Un segundo framer sería un segundo contrato que coincide con el
  primero por casualidad.
- La medida espectral y el oráculo salen de `tools/dump_ray.py`
  (`spectrum`, `model_channel`) con sus tolerancias. Si esto midiera distinto
  que el camino de JTAG, las dos medidas discreparían entre sí y no sabríamos
  cuál creer.

Lo propio de este programa es el BUCLE y el CRITERIO: cuándo un rayo
pertenece ya al vector nuevo, y qué cuenta como coincidir.

CUÁNDO EL RAYO ES DEL VECTOR NUEVO. No hay forma de preguntárselo al rayo:
`DrxRayContext` tiene un campo `first_after_config` pero el firmware lo deja
siempre en false (`fw/src/app/drx_ray_ctx.c`), así que no se puede usar. El
criterio aquí es temporal y explícito: tras el `config_ack` se DESCARTAN los
rayos durante `--settle` segundos y recién entonces se captura. Es la parte
más floja de la medida y conviene saberlo; si alguna vez un vector da un
falso fallo intermitente, el primer sospechoso es este número y no el DDC.
Lo correcto sería que el firmware pusiera `first_after_config`.

ENSAYO EN SECO. Con `--sin-seleccion` no manda nada: captura un rayo del flujo
que ya esté saliendo y lo compara contra el vector que se le diga. Sirve para
probar el bucle, la comparación y el criterio de PASS/FAIL sin depender de que
el modo DDR funcione -- que es justo lo que separa "el conductor está mal" de
"P-16 está mal" cuando por fin se corran los dos juntos.

    tools/sweep_catalogo.py --sin-seleccion --vector tono_if
    tools/sweep_catalogo.py
    tools/sweep_catalogo.py --solo tono_if,tono_sobre_escala --settle 3

Códigos de salida: 0 todo coincide, 1 algún vector discrepa, 2 uso incorrecto,
4 no llegó ningún rayo.
"""

from __future__ import annotations

import argparse
import importlib.util
import socket
import sys
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def _por_ruta(nombre: str, ruta: Path):
    spec = importlib.util.spec_from_file_location(nombre, ruta)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


MOCK = _por_ruta("mock_dsp", ROOT / "tools" / "mock_dsp.py")
DUMP = _por_ruta("dump_ray", ROOT / "tools" / "dump_ray.py")
C = MOCK.C


def catalogo() -> list[tuple[str, int]]:
    """Los vectores del esquema, en el orden del catálogo. Del contrato
    generado, no de una lista escrita aquí: el catálogo puede CRECER dentro
    del mismo `version_major` y una copia a mano se quedaría corta sin avisar."""
    pares = [
        (nombre.lower(), valor)
        for nombre, valor in vars(C.StimulusVector).items()
        if not nombre.startswith("_") and isinstance(valor, int)
    ]
    return sorted(pares, key=lambda par: par[1])


def canales_del_rayo(ray, payload: bytes) -> list[dict]:
    """Espectro medido de cada canal. Mismo desempaquetado que `mock_dsp`."""
    esperado = ray.bins * ray.n_channels * 4
    if len(payload) != esperado:
        raise ValueError(f"carga útil de {len(payload)} B, se esperaban {esperado}")
    pares = np.frombuffer(payload, dtype="<i2").reshape(ray.bins, ray.n_channels, 2)
    return [
        DUMP.spectrum(pares[:, ch, 0], pares[:, ch, 1])
        for ch in range(ray.n_channels)
    ]


def compara(ray, medido: list[dict], vector: str, platform: str) -> list[str]:
    """Devuelve `(fallos, esperado)`. Lista de fallos vacía = coincide.

    Mismas dos tolerancias que `dump_ray.py` y por la misma razón: el residuo
    de cuantización que D-12 acepta mueve el pico unos pocos bins y unas
    décimas de dB, y comparar bit a bit aquí sería exigir más que en L1.
    """
    esperado = DUMP.model_channel(
        platform, vector, int(ray.bins), bool(ray.cell_mode)
    )
    fallos = []
    for c, stats in enumerate(medido):
        if abs(stats["peak_bin"] - esperado["peak_bin"]) > DUMP.PEAK_BIN_TOL:
            fallos.append(
                f"canal {c}: pico en bin {stats['peak_bin']:+d}, el modelo lo "
                f"pone en {esperado['peak_bin']:+d}"
            )
        if abs(stats["peak_db"] - esperado["peak_db"]) > DUMP.PEAK_DB_TOL:
            fallos.append(
                f"canal {c}: pico a {stats['peak_db']:+.2f} dBFS, el modelo "
                f"{esperado['peak_db']:+.2f} dBFS"
            )

    # `tono_sobre_escala` existe para ejercitar el reporte de overflow de punta
    # a punta (ver tools/gen_l1_vectors.py). Que el pico coincida no prueba
    # eso: la bandera tiene que llegar, y NO debe llegar con los demás.
    hubo_overflow = bool(ray.ray_flags & C.RayFlag.DDC_OVERFLOW)
    if vector == "tono_sobre_escala" and not hubo_overflow:
        fallos.append("ray_flags sin ddc_overflow en el vector de sobre-escala")
    if vector != "tono_sobre_escala" and hubo_overflow:
        fallos.append(f"ray_flags con ddc_overflow inesperado en {vector}")
    return fallos, esperado


def captura_rayo(sock, framer, descartar_s: float, timeout_s: float):
    """Descarta rayos `descartar_s` segundos y devuelve el siguiente entero.

    Devuelve `(ray, payload)` o `None` si no llegó ninguno a tiempo. Los
    mensajes que no son `ray` se ignoran aquí a propósito: el `config_ack` ya
    se consumió antes y un `status` por el medio no dice nada del dato.
    """
    t0 = time.monotonic()
    while True:
        transcurrido = time.monotonic() - t0
        if transcurrido > descartar_s + timeout_s:
            return None
        try:
            data = sock.recv(65536)
        except TimeoutError:
            continue
        if not data:
            return None
        for header, cuerpo in framer.push(data):
            if header.msg_type != C.MsgType.RAY:
                continue
            if time.monotonic() - t0 < descartar_s:
                continue
            ray = C.Ray.unpack(cuerpo)
            return ray, cuerpo[C.Ray.SIZE :]


def espera_ack(sock, framer, timeout_s: float):
    """El `config_ack` del `test_stimulus_select`, o None si no llega.

    Se espera ANTES de medir y no en paralelo: si el DRx rechaza el vector
    (`vector_unknown`, `unimplemented`), medir el rayo siguiente mediría el
    vector VIEJO y el barrido daría un PASS que no significa nada.
    """
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout_s:
        try:
            data = sock.recv(65536)
        except TimeoutError:
            continue
        if not data:
            return None
        for header, cuerpo in framer.push(data):
            if header.msg_type == C.MsgType.CONFIG_ACK:
                return C.ConfigAck.unpack(cuerpo)
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--host", default="192.168.1.10")
    parser.add_argument("--port", type=int, default=C.TCP_PORT)
    parser.add_argument("--platform", default="zedboard")
    parser.add_argument("--solo", default=None,
                        help="lista separada por comas de vectores a barrer")
    # Los dos valores por defecto están puestos para el caso LENTO, que es el
    # que importa. En BRAM-loop llegan 223 rayos/s y cualquier número sirve; en
    # Throttled(DDR) paceado un rayo del lote bajo tarda ~1,9 s, y no por el
    # pacing: un rayo de 3689 bins necesita 3689*R1 = 767 312 muestras, o sea
    # 192 pasadas del bucle de 4000, y entre pasada y pasada hay el hueco de
    # DRX_STIMULUS_POLL_MS (10 ms) que tarda la tarea en reencolar el DMA. Con
    # `--settle 2` se descartaría UN rayo y el margen sería demasiado justo.
    parser.add_argument("--settle", type=float, default=5.0,
                        help="segundos de rayos descartados tras el config_ack")
    parser.add_argument("--timeout", type=float, default=25.0,
                        help="espera máxima por un rayo o un config_ack")
    parser.add_argument("--repeat", type=int, default=0,
                        help="`repeat` del test_stimulus_select. 0 = en bucle, "
                             "que es lo que quiere un barrido: el vector tiene "
                             "que seguir sonando mientras se captura. Un valor "
                             "finito hace que el firmware vuelva solo a "
                             "BRAM-loop al acabar las pasadas, util para probar "
                             "el camino de ida y vuelta sin dejar la placa en "
                             "modo DDR")
    parser.add_argument("--id-crudo", type=int, default=None,
                        help="manda este vector_id tal cual, aunque no esté en "
                             "el catálogo. Es la única forma de ejercitar el "
                             "camino de rechazo (`vector_unknown`) de punta a "
                             "punta, que si no nunca se ejecuta")
    parser.add_argument("--sin-seleccion", action="store_true",
                        help="no manda test_stimulus_select: mide el flujo que "
                             "ya sale y lo compara con --vector. El ensayo en "
                             "seco del conductor")
    parser.add_argument("--vector", default="tono_if",
                        help="con --sin-seleccion, contra qué vector comparar")
    args = parser.parse_args(argv)

    if args.id_crudo is not None:
        objetivos = [(f"id_crudo_{args.id_crudo}", args.id_crudo)]
    elif args.sin_seleccion:
        objetivos = [(args.vector, None)]
    else:
        objetivos = catalogo()
        if args.solo:
            pedidos = [v.strip() for v in args.solo.split(",") if v.strip()]
            conocidos = dict(objetivos)
            desconocidos = [v for v in pedidos if v not in conocidos]
            if desconocidos:
                print(f"vectores desconocidos: {desconocidos}. "
                      f"Hay {sorted(conocidos)}")
                return 2
            objetivos = [(v, conocidos[v]) for v in pedidos]

    print(f"contrato v{C.VERSION_MAJOR}.{C.VERSION_MINOR}, "
          f"conectando a {args.host}:{args.port}")
    try:
        sock = socket.create_connection((args.host, args.port), timeout=5.0)
    except OSError as exc:
        print(f"no se pudo conectar: {exc}")
        return 1

    resultados: list[tuple[str, str, list[str]]] = []
    sin_rayo = 0
    with sock:
        sock.settimeout(1.0)
        framer = MOCK.Framer()
        for nombre, vector_id in objetivos:
            print(f"\n--- {nombre} ---")
            if vector_id is not None:
                cuerpo = C.TestStimulusSelect(vector_id=vector_id, repeat=args.repeat).pack()
                sock.sendall(MOCK._encode(C.MsgType.TEST_STIMULUS_SELECT, cuerpo))
                print(f"-> test_stimulus_select {nombre} (id {vector_id}) repeat={args.repeat}")
                ack = espera_ack(sock, framer, args.timeout)
                if ack is None:
                    resultados.append((nombre, "SIN ACK", []))
                    print("   no llegó config_ack")
                    continue
                error = MOCK._nombre(C.Error, ack.error)
                print(f"<- config_ack error={error}")
                if ack.error != C.Error.OK:
                    resultados.append((nombre, f"RECHAZADO ({error})", []))
                    continue

            capturado = captura_rayo(sock, framer, args.settle, args.timeout)
            if capturado is None:
                sin_rayo += 1
                resultados.append((nombre, "SIN RAYO", []))
                print(f"   no llegó ningún rayo en {args.settle + args.timeout:.0f} s")
                continue

            ray, payload = capturado
            try:
                medido = canales_del_rayo(ray, payload)
            except ValueError as exc:
                resultados.append((nombre, f"RAYO MALFORMADO ({exc})", []))
                print(f"   {exc}")
                continue

            print(f"<- ray seq={ray.seq} bins={ray.bins} n_ch={ray.n_channels} "
                  f"cell_mode={ray.cell_mode} flags={ray.ray_flags:#x}")
            for c, s in enumerate(medido):
                print(f"   canal {c}: pico {s['peak_bin']:+d} "
                      f"({s['peak_frac']:+.5f} de fs_dec), {s['peak_db']:+.2f} dBFS")
            fallos, esperado = compara(ray, medido, nombre, args.platform)
            print(f"   modelo: pico {esperado['peak_bin']:+d} "
                  f"({esperado['peak_frac']:+.5f}), {esperado['peak_db']:+.2f} dBFS")
            if fallos:
                resultados.append((nombre, "DISCREPA", fallos))
                for linea in fallos:
                    print(f"   {linea}")
            else:
                resultados.append((nombre, "coincide", []))
                print("   coincide con el modelo")

    print("\n=== resumen ===")
    for nombre, veredicto, _ in resultados:
        print(f"{nombre:24s} {veredicto}")
    malos = [r for r in resultados if r[1] != "coincide"]
    print(f"{len(resultados) - len(malos)}/{len(resultados)} coinciden con el modelo")
    if sin_rayo == len(resultados):
        return 4
    return 1 if malos else 0


if __name__ == "__main__":
    raise SystemExit(main())
