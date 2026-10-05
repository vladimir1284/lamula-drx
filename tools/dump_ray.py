#!/usr/bin/env python3
"""Lee un rayo de la DDR de la ZedBoard por JTAG y lo contrasta con el modelo.

Qué contesta, y por qué hacía falta: hasta Z4.3 lo único medible en placa era
que los BYTES del vector de estímulo llegaban a la PL (una pasada del DMA se
completa, y el stream tiene backpressure). Nada decía si el DATO sale bien del
DDC. El A/B contra el vector de +6 dBFS dio `OVERFLOW = 0` en los dos casos y
no discriminó. Z4.4 abre el camino de vuelta, así que por fin se puede mirar.

Cómo:

1. El firmware congela un rayo entero (`DrxRay_Freeze`, ver fw/include/drx_ray.h)
   e imprime por UART su dirección y su longitud. Congelar no es un lujo: sin
   eso el buffer se rearma a los ~18 ms y la lectura por JTAG traería otro rayo,
   o medio de cada uno.
2. Este script lo lee con `mrd -bin -file` y deshace el entrelazado de canales.
3. Lo compara contra `model/drx_model` alimentado con el MISMO vector del
   catálogo, en el dominio de la frecuencia.

Por qué en frecuencia y no muestra a muestra: el rayo empieza en un punto
arbitrario del vector en bucle —`ray_start` viene del motor de timing y no sabe
nada del DMA— y la longitud del bucle (4000 muestras) no es múltiplo del
diezmado (R1 = 208), así que la salida decimada no se repite con un periodo
entero de muestras. No hay un desplazamiento entero que alinee las dos series.
El contenido espectral sí es invariante a dónde empiece el rayo, y es lo que
distingue un vector de otro: frecuencia del pico, su magnitud, y la potencia
total. Eso es exactamente lo que el A/B de OVERFLOW no supo distinguir.

    tools/dump_ray.py --addr 0x00123456 --words 11061 --vector tono_if

Sin `--vector` solo informa de lo medido, que ya sirve para ver si los canales
traen señal y si alguno está mudo.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "model"))
sys.path.insert(0, str(ROOT / "tools"))

import gen_l1_vectors  # noqa: E402
import gen_vector_source_init  # noqa: E402
from drx_model import chain  # noqa: E402
from drx_model import params as params_mod  # noqa: E402

#: Palabras de metadato que `drx_ray_packer` antepone a cada rayo. Tiene que
#: coincidir con `MetaBeats` del RTL y con `DRX_RAY_META_WORDS` del firmware.
META_WORDS = 4
RAY_MAGIC = 0x52590001

#: Margen con el que se comparan pico y potencia. Es holgado a propósito: no
#: mide la aritmética del DDC (eso lo hace L1 contra xsim, bit a bit bajo D-12),
#: mide que lo que llegó a la DDR es ESTE vector y no otro ni ruido.
PEAK_BIN_TOL = 2
PEAK_DB_TOL = 3.0


def read_memory(addr: int, words: int, out: Path) -> np.ndarray:
    """Vuelca `words` palabras de 32 bits desde `addr` con xsct."""
    script = (
        "connect\n"
        'targets -set -filter {name =~ "*Cortex-A9*#0" || name =~ "ARM*#0"}\n'
        f"mrd -bin -file {out} {addr:#010x} {words}\n"
    )
    with tempfile.NamedTemporaryFile("w", suffix=".tcl", delete=False) as handle:
        handle.write(script)
        tcl = Path(handle.name)
    try:
        result = subprocess.run(
            ["xsct", str(tcl)], capture_output=True, text=True, check=False
        )
        if not out.exists() or out.stat().st_size == 0:
            raise SystemExit(
                "xsct no escribió nada. Salida:\n" + result.stdout + result.stderr
            )
    finally:
        tcl.unlink(missing_ok=True)
    raw = out.read_bytes()
    return np.frombuffer(raw[: (len(raw) // 4) * 4], dtype="<u4")


def split_iq(words: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """`m_data` es {I[31:16], Q[15:0]}, los dos con signo."""
    i = (words >> 16).astype(np.int32)
    q = (words & 0xFFFF).astype(np.int32)
    i[i >= 1 << 15] -= 1 << 16
    q[q >= 1 << 15] -= 1 << 16
    return i, q


def parse_header(words: np.ndarray) -> dict:
    if words.size < META_WORDS:
        raise SystemExit("el volcado no llega ni a la cabecera")
    if int(words[0]) != RAY_MAGIC:
        raise SystemExit(
            f"la primera palabra es {int(words[0]):#010x}, no {RAY_MAGIC:#010x}: "
            "el volcado no empieza en un rayo (¿dirección equivocada, o el "
            "buffer no estaba congelado?)"
        )
    flags = int(words[3])
    return {
        "trig_count": int(words[1]),
        "ray_index": int(words[2]),
        "bin_count": flags & 0xFFFF,
        "batch_high": bool((flags >> 16) & 1),
        "mode_coarse": bool((flags >> 17) & 1),
        "n_ch": (flags >> 24) & 0xFF,
    }


#: Cuánto tienen que parecerse el pico y su bin espejo para que el signo deje
#: de ser un criterio. Holgado a propósito: con un espectro simétrico la
#: diferencia real es 0 dB y lo único que la separa de 0 es el ruido de
#: cuantización de la cadena, así que un umbral apretado volvería a hacer el
#: test dependiente de la suerte -- que es justo lo que se está arreglando.
PEAK_MIRROR_TOL_DB = 0.5


def spectrum(i: np.ndarray, q: np.ndarray) -> dict:
    """Pico y potencia de un canal, sin depender de dónde empiece el rayo."""
    iq = i.astype(np.float64) + 1j * q.astype(np.float64)
    n = iq.size
    if n == 0:
        return {"peak_bin": 0, "peak_db": -np.inf, "power_db": -np.inf, "max_abs": 0}

    window = np.hanning(n)
    mag = np.abs(np.fft.fft(iq * window)) / (n / 2.0)
    peak = int(np.argmax(mag))
    # Bin centrado en 0: un pico en continua sale en 0, uno a frecuencia
    # negativa cerca de n, y comparar «bin 1 contra bin n-1» sería un falso
    # fallo sin esto.
    peak_signed = peak if peak <= n // 2 else peak - n
    full_scale = float(1 << 15)
    with np.errstate(divide="ignore"):
        peak_db = 20.0 * np.log10(max(mag[peak], 1e-12) / full_scale)
        power_db = 10.0 * np.log10(max(float(np.mean(np.abs(iq) ** 2)), 1e-12)
                                   / full_scale**2)
    # ¿El pico tiene un gemelo en el bin espejo con la MISMA magnitud? Si lo
    # tiene, qué lado gana lo decide el ruido y `argmax` no es un criterio
    # estable.
    #
    # No es hipotético: `dos_tonos` son dos tonos colocados simétricamente
    # alrededor del IF (`if_norm -+ 0,0008`), así que en banda base el espectro
    # es EXACTAMENTE simétrico -- el modelo da 4657187.1 en +156 y en -156, bit
    # a bit. Medido el 4-oct-2026 en 201 barridos encadenados: el pico sale en
    # -156 en 27 de ellos, un 13 %. El DRx está bien; lo que no servía era
    # comparar el signo.
    mirror_db = -np.inf
    if peak_signed != 0 and abs(peak_signed) != n // 2:
        mirror = (-peak_signed) % n
        with np.errstate(divide="ignore"):
            mirror_db = 20.0 * np.log10(max(mag[mirror], 1e-12) / full_scale)

    return {
        "peak_bin": peak_signed,
        "peak_frac": peak_signed / n,
        "peak_db": peak_db,
        "power_db": power_db,
        "peak_ambiguo": bool(abs(mirror_db - peak_db) < PEAK_MIRROR_TOL_DB),
        "max_abs": int(np.max(np.abs(np.concatenate([i, q])))),
    }


def model_channel(platform: str, vector: str, bins: int, mode_coarse: bool,
                  nco_pinc: int | None = None) -> dict:
    """Lo que el modelo dorado da para ese vector, con la misma longitud.

    `nco_pinc` (Z4.5) es la palabra de fase que el NCO tenga puesta en ese
    momento, si se hizo una actuación AFC. Aquí entra como un retune en la
    muestra 0, y eso NO es una aproximación: el rayo que se congela es muy
    posterior al retune, así que el NCO lleva esa palabra desde mucho antes de
    la primera muestra del rayo. El transitorio del salto no cae dentro de esta
    ventana.
    """
    params = params_mod.load(platform)
    depth = gen_vector_source_init._loop_depth(params)
    cases = gen_l1_vectors._cases(params, depth)
    if vector not in cases:
        raise SystemExit(f"vector desconocido: {vector}. Hay {sorted(cases)}")

    decim = params.invariant["r2" if mode_coarse else "r1"]
    # El firmware reproduce el vector en bucle, así que el estímulo del rayo es
    # el vector repetido. Se pide algo de más para descartar el transitorio de
    # los filtros antes de medir.
    needed = int(bins) * int(decim)
    warmup = int(decim) * 64
    reps = (needed + warmup + depth - 1) // depth
    stimulus = np.tile(np.asarray(cases[vector]), reps)

    retune = None if nco_pinc is None else (0, int(nco_pinc))
    ddc = chain.Ddc(
        params=params, mode="coarse" if mode_coarse else "fine", nco_retune=retune
    )
    out = ddc.process(stimulus)
    i = np.asarray(out.i)[64 : 64 + bins]
    q = np.asarray(out.q)[64 : 64 + bins]
    stats = spectrum(i, q)
    # Si el modelo satura en esta ventana, el hardware tiene que levantar
    # `ddc_overflow` en el rayo, y si no satura no debe levantarlo. Sale de
    # aqui y no de una lista de nombres de vector: el 4-oct-2026 se midio que
    # `tono_sobre_escala` NO satura la salida del DDC -- la entrada esta a
    # +6 dBFS pero el ajuste de ganancia de la cadena deja el pico de salida
    # en 21005 de 32767, 3,9 dB por debajo del fondo-- y una expectativa
    # escrita a mano daba por hecho lo contrario.
    overflow = np.asarray(out.overflow)[64 : 64 + bins]
    stats["overflow"] = bool(np.any(overflow))
    return stats


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--addr", required=True, help="dirección del rayo en DDR (0x...)")
    parser.add_argument("--words", type=int, required=True,
                        help="palabras de 32 bits a leer, cabecera incluida")
    parser.add_argument("--vector", default=None, help="caso del catálogo con el que comparar")
    parser.add_argument("--platform", default="zedboard", choices=["zedboard", "zu9"])
    parser.add_argument(
        "--nco-pinc", type=lambda v: int(v, 0), default=None,
        help="palabra de fase del NCO vigente (registro NCO_PINC, v9) si se "
             "hizo una actuación AFC; sin esto el modelo mezcla al IF nominal "
             "y el pico medido no caerá donde el modelo lo pone",
    )
    parser.add_argument("--out", default=None, help="dónde dejar el binario crudo")
    args = parser.parse_args(argv)

    out = Path(args.out) if args.out else ROOT / "build" / "ray" / "ray.bin"
    out.parent.mkdir(parents=True, exist_ok=True)

    words = read_memory(int(args.addr, 0), args.words, out)
    header = parse_header(words)
    print(
        f"rayo idx={header['ray_index']} trig={header['trig_count']} "
        f"bins={header['bin_count']} n_ch={header['n_ch']} "
        f"lote={'alto' if header['batch_high'] else 'bajo'} "
        f"celda={'gruesa' if header['mode_coarse'] else 'fina'}"
    )

    n_ch = header["n_ch"]
    if n_ch == 0:
        raise SystemExit("la cabecera dice n_ch = 0")

    payload = words[META_WORDS:]
    usable = (payload.size // n_ch) * n_ch
    i_all, q_all = split_iq(payload[:usable])

    medido = []
    for c in range(n_ch):
        stats = spectrum(i_all[c::n_ch], q_all[c::n_ch])
        medido.append(stats)
        print(
            f"  canal {c}: pico en bin {stats['peak_bin']:+d} "
            f"({stats['peak_frac']:+.5f} de fs_dec), {stats['peak_db']:+.2f} dBFS, "
            f"potencia {stats['power_db']:+.2f} dBFS, |max| {stats['max_abs']}"
        )

    if args.vector is None:
        return 0

    esperado = model_channel(args.platform, args.vector, header["bin_count"],
                             header["mode_coarse"], args.nco_pinc)
    print(
        f"modelo ({args.vector}): pico en bin {esperado['peak_bin']:+d} "
        f"({esperado['peak_frac']:+.5f}), {esperado['peak_db']:+.2f} dBFS, "
        f"potencia {esperado['power_db']:+.2f} dBFS"
    )

    fallos = []
    for c, stats in enumerate(medido):
        if abs(stats["peak_bin"] - esperado["peak_bin"]) > PEAK_BIN_TOL:
            fallos.append(
                f"canal {c}: pico en {stats['peak_bin']:+d}, el modelo lo pone en "
                f"{esperado['peak_bin']:+d}"
            )
        if abs(stats["peak_db"] - esperado["peak_db"]) > PEAK_DB_TOL:
            fallos.append(
                f"canal {c}: pico a {stats['peak_db']:+.2f} dBFS, el modelo "
                f"{esperado['peak_db']:+.2f} dBFS"
            )

    if fallos:
        print("DISCREPA:")
        for linea in fallos:
            print(f"  {linea}")
        return 1

    print("coincide con el modelo dentro de la tolerancia")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
