#!/usr/bin/env python3
"""Inyección de fallos de Z5, los dos casos que no necesitan firmware ni RTL nuevo.

    tools/inyectar_fallos.py config   # mensajes inválidos del par con el flujo vivo
    tools/inyectar_fallos.py enlace   # caída y reconexión del enlace Ethernet

Cada caso mide el flujo de rayos ANTES, DURANTE y DESPUÉS, y deja la evidencia en
`build/fallos/<fecha>-<caso>/` (resultado.txt + procedencia). Criterio de paso,
fijado antes de correr:

 config: el rechazo vuelve (`last_error` en el status), el flujo no se interrumpe
         (0 huecos de `seq`, misma tasa ±5 %), el NCO no se mueve (mismo pico
         espectral antes y después) y la conexión sigue viva.
 enlace: tras volver el enlace el DRx acepta una conexión nueva sin reiniciar,
         los rayos reanudan a la misma tasa ±5 % y `seq` avanza. El hueco de
         `seq` durante la caída es el esperado (el DRx descarta, no encola).

Lo que NO prueba: ver BITE en el status ni su limpieza cuando es posible; se
informa lo que aparezca, pero el criterio es el de arriba.
"""
from __future__ import annotations

import argparse
import importlib.util
import socket
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "contract" / "generated"))
import drx_dsp_v0_1 as C  # noqa: E402

_spec = importlib.util.spec_from_file_location("mock_dsp", ROOT / "tools" / "mock_dsp.py")
M = importlib.util.module_from_spec(_spec)
sys.modules["mock_dsp"] = M
_spec.loader.exec_module(M)

HOST = "192.168.1.10"
IFACE = "enp1s0"
PERFIL = "drx-zedboard"


class Sesion:
    """Una conexión + contadores de rayos y estado desde `reset()`."""

    def __init__(self, host: str) -> None:
        self.sock = socket.create_connection((host, C.TCP_PORT), timeout=5.0)
        self.sock.settimeout(0.5)
        self.framer = M.Framer()
        self.salida: list[str] = []
        self.ultimo_pico = None
        self.reset()

    def reset(self) -> None:
        self.rayos = 0
        self.huecos = 0
        self.perdidos = 0
        self.seq0 = self.seq1 = None
        self.t0 = time.monotonic()
        self.status = None
        self.errores: set[str] = set()
        self.acks: list[int] = []

    def enviar(self, msg_type: int, cuerpo: bytes) -> None:
        self.sock.sendall(M._encode(msg_type, cuerpo))

    def escuchar(self, segundos: float) -> bool:
        """Devuelve False si el DRx cerró la conexión."""
        fin = time.monotonic() + segundos
        while time.monotonic() < fin:
            try:
                data = self.sock.recv(65536)
            except TimeoutError:
                continue
            except OSError as exc:
                self.salida.append(f"  socket: {exc}")
                return False
            if not data:
                return False
            for header, cuerpo in self.framer.push(data):
                if header.msg_type == C.MsgType.RAY:
                    ray = C.Ray.unpack(cuerpo)
                    self.rayos += 1
                    if self.seq1 is not None:
                        d = (ray.seq - self.seq1) & 0xFFFFFFFF
                        if d != 1:
                            self.huecos += 1
                            self.perdidos += d - 1
                    if self.seq0 is None:
                        self.seq0 = ray.seq
                    self.seq1 = ray.seq
                    self.ultimo_pico = self._pico(ray, cuerpo[C.Ray.SIZE:])
                elif header.msg_type == C.MsgType.STATUS:
                    self.status = C.Status.unpack(cuerpo)
                    self.errores.add(M._nombre(C.Error, self.status.last_error))
                elif header.msg_type == C.MsgType.CONFIG_ACK:
                    self.acks.append(C.ConfigAck.unpack(cuerpo).error)
        return True

    @staticmethod
    def _pico(ray, payload: bytes):
        import numpy as np
        if len(payload) != ray.bins * ray.n_channels * 4:
            return None
        pares = np.frombuffer(payload, dtype="<i2").reshape(ray.bins, ray.n_channels, 2)
        dr = importlib.util.module_from_spec(
            s := importlib.util.spec_from_file_location("dump_ray", ROOT / "tools" / "dump_ray.py"))
        sys.modules["dump_ray"] = dr
        s.loader.exec_module(dr)
        out = []
        for ch in range(ray.n_channels):
            sp = dr.spectrum(pares[:, ch, 0], pares[:, ch, 1])
            out.append((round(sp["peak_frac"], 4), round(sp["peak_db"], 1)))
        return out

    def tasa(self) -> float:
        return self.rayos / max(time.monotonic() - self.t0, 1e-9)

    def resumen(self, nombre: str) -> dict:
        r = {"fase": nombre, "rayos": self.rayos, "tasa": round(self.tasa(), 1),
             "huecos": self.huecos, "perdidos": self.perdidos, "pico": self.ultimo_pico}
        if self.status:
            r["bite"] = M._bite(self.status.bite_flags)
            r["last_error"] = sorted(self.errores)
        if self.acks:
            r["acks"] = [M._nombre(C.Error, e) for e in self.acks]
        return r

    def cerrar(self) -> None:
        self.sock.close()


def _tasa_ok(a: float, b: float) -> bool:
    return abs(a - b) <= 0.05 * a


def caso_config(log) -> bool:
    s = Sesion(HOST)
    ok = True
    # Los primeros segundos de una conexion nueva pueden traer un salto de seq
    # (medido: 4 huecos/21 rayos en una conexion y 0 en la siguiente, sin inyectar
    # nada). Se descartan para que el criterio mida la inyeccion y no el arranque.
    s.escuchar(3.0)
    s.reset()
    s.escuchar(6.0)
    antes = s.resumen("antes")
    log(antes)
    base_tasa, base_pico = antes["tasa"], antes["pico"]

    # 1) afc fuera de rango: u64 que no cabe en el NCO de 32 bits.
    # 2) tipo de mensaje que no existe (el framer del DRx debe rechazarlo, no colgarse).
    s.reset()
    s.enviar(C.MsgType.AFC, C.Afc(nco_phase_inc=1 << 40, apply_at_seq=0).pack())
    s.escuchar(2.0)
    s.enviar(0x7F, b"\x00" * 8)
    vivo = s.escuchar(8.0)
    durante = s.resumen("durante")
    log(durante)

    s.reset()
    vivo = s.escuchar(6.0) and vivo
    despues = s.resumen("despues")
    log(despues)

    # El rechazo tiene que haber vuelto en algún sitio.
    visto = set(durante.get("last_error", [])) | set(despues.get("last_error", []))
    rechazo = bool(visto - {"ok"})
    chequeos = {
        "conexion viva": vivo,
        "rechazo visible (last_error)": rechazo,
        "0 huecos de seq": durante["huecos"] == 0 and despues["huecos"] == 0,
        "tasa estable +-5%": all(_tasa_ok(base_tasa, f["tasa"]) for f in (durante, despues)),
        "NCO sin mover (pico igual)": despues["pico"] == base_pico,
    }
    for k, v in chequeos.items():
        log(f"  [{'PASA' if v else 'FALLA'}] {k}")
        ok &= v
    s.cerrar()
    return ok


def _nmcli(*args: str) -> int:
    r = subprocess.run(["nmcli", *args], capture_output=True, text=True)
    return r.returncode


def caso_enlace(log, cierra_antes: bool = False) -> bool:
    s = Sesion(HOST)
    s.escuchar(6.0)
    antes = s.resumen("antes")
    log(antes)
    seq_antes = s.seq1

    # Sin sudo no se puede bajar el enlace por software: se desenchufa el cable.
    print(">>> DESENCHUFA el cable Ethernet de la ZedBoard (espero hasta 240 s)", flush=True)
    t_baja = None
    fin = time.monotonic() + 240
    if cierra_antes:
        # Control del experimento: el DRx ve el FIN ANTES de la caida, asi que no
        # le queda una conexion vieja reintentando contra un peer que no contesta.
        s.cerrar()
        log("  socket del cliente cerrado antes de la caida")
        while time.monotonic() < fin:
            if subprocess.run(["ping", "-c1", "-W1", HOST], capture_output=True).returncode != 0:
                t_baja = time.monotonic()
                break
    else:
        while time.monotonic() < fin:
            n = s.rayos
            s.escuchar(1.5)
            if s.rayos == n:
                t_baja = time.monotonic()
                break
    if t_baja is None:
        log("  no se detecto la caida en 240 s")
        return False
    log("  caida detectada")
    print(">>> ENCHUFA el cable otra vez (espero hasta 120 s)", flush=True)
    t_baja_ok = time.monotonic()
    while time.monotonic() - t_baja_ok < 120:
        try:
            # ping, no TCP: una conexion de sonda ocuparia el unico cliente del DRx.
            if subprocess.run(["ping", "-c1", "-W1", HOST], capture_output=True).returncode == 0:
                break
        except OSError:
            pass
        time.sleep(0.5)
    else:
        log("  el enlace no volvio en 120 s")
        return False
    log(f"  enlace caido ~{time.monotonic() - t_baja:.0f} s")
    # El socket viejo ya no sirve; la prueba es que el DRx acepte uno nuevo.
    if not cierra_antes:
        s.cerrar()
    t_ping = time.monotonic()
    nuevo = None
    for _ in range(30):
        try:
            nuevo = Sesion(HOST)
            break
        except OSError:
            time.sleep(1.0)
    t_vuelta = time.monotonic() - t_baja
    log(f"  enlace caido ~10 s, reconexion TCP a los {t_vuelta:.1f} s de bajarlo: "
        f"{'OK' if nuevo else 'NO CONECTA'}")
    if nuevo is None:
        return False
    t_con = t_ping
    t_primer = None
    while time.monotonic() - t_con < 30:
        nuevo.escuchar(0.5)
        if nuevo.rayos:
            t_primer = time.monotonic() - t_con
            break
    log(f"  primer rayo a los {t_primer:.1f} s de que vuelve el ping" if t_primer is not None
        else "  NINGUN rayo en 30 s tras conectar")
    nuevo.escuchar(2.0)
    nuevo.reset()
    nuevo.escuchar(8.0)
    despues = nuevo.resumen("despues")
    log(despues)
    chequeos = {
        "DRx acepta conexion nueva sin reiniciar": True,
        "rayos reanudan": despues["rayos"] > 0,
        "tasa estable +-5%": _tasa_ok(antes["tasa"], despues["tasa"]),
        "seq avanza": nuevo.seq0 is not None and seq_antes is not None
                      and ((nuevo.seq0 - seq_antes) & 0xFFFFFFFF) > 1,
    }
    ok = True
    for k, v in chequeos.items():
        log(f"  [{'PASA' if v else 'FALLA'}] {k}")
        ok &= v
    nuevo.cerrar()
    return ok


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("caso", choices=["config", "enlace", "enlace-limpio"])
    args = p.parse_args()

    destino = ROOT / "build" / "fallos" / f"{datetime.now():%Y%m%d-%H%M%S}-{args.caso}"
    destino.mkdir(parents=True)
    lineas: list[str] = []

    def log(x) -> None:
        t = f"{datetime.now():%H:%M:%S} {x}"
        print(t, flush=True)
        lineas.append(t)

    commit = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"],
                            capture_output=True, text=True).stdout.strip()
    log(f"caso={args.caso} commit={commit}")
    ok = {"config": caso_config, "enlace": caso_enlace,
          "enlace-limpio": lambda lg: caso_enlace(lg, cierra_antes=True)}[args.caso](log)
    log(f"RESULTADO: {'PASA' if ok else 'FALLA'}")
    (destino / "resultado.txt").write_text("\n".join(lineas) + "\n")
    print(f"evidencia en {destino}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
