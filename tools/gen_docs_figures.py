#!/usr/bin/env python3
"""Genera las figuras de la documentación a partir del modelo dorado.

Las figuras del sitio NO se dibujan a mano ni se capturan de pantalla: salen del
mismo modelo que sirve de oráculo, así que si el modelo cambia y alguien no
regenera, la documentación y el código discrepan de forma visible.

    python3 tools/gen_docs_figures.py

No hay gate de CI sobre estos SVG: matplotlib no garantiza salida byte a byte
entre versiones, y un gate que falla por el número de decimales de un path SVG
enseña a la gente a ignorar los gates. Lo que sí está en CI son los tests que
comprueban numéricamente lo que las figuras enseñan (rizado de banda de paso,
atenuación en la banda que pliega, ganancia del CIC).

Estilo: fondo transparente y ejes en gris medio, para que las figuras se lean
igual en el tema claro y en el oscuro del sitio.
"""

from __future__ import annotations

import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

# El texto se queda como texto en el SVG en vez de convertirse en trazados: los
# ficheros bajan de ~50 kB a ~10 kB y el texto se puede seleccionar y buscar.
plt.rcParams["svg.fonttype"] = "none"

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "model"))

from drx_model import fir as fir_mod  # noqa: E402
from drx_model import vectors  # noqa: E402
from drx_model.chain import MODE_FINE, Ddc  # noqa: E402
from drx_model.cic import Cic  # noqa: E402
from drx_model.nco import Nco  # noqa: E402
from drx_model.params import load  # noqa: E402

OUT = ROOT / "docs" / "assets"
INK = "#6b7280"  # gris medio: legible sobre blanco y sobre slate
ACCENT = ("#7c3aed", "#0891b2", "#dc2626", "#059669")


def _style(ax, xlabel: str, ylabel: str, title: str) -> None:
    ax.set_xlabel(xlabel, color=INK, fontsize=9)
    ax.set_ylabel(ylabel, color=INK, fontsize=9)
    ax.set_title(title, color=INK, fontsize=10)
    ax.tick_params(colors=INK, labelsize=8)
    for spine in ax.spines.values():
        spine.set_color(INK)
    ax.grid(True, color=INK, alpha=0.20, linewidth=0.6)


def _save(fig, name: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    # `Date: None` quita la marca de tiempo que matplotlib mete en los metadatos:
    # sin ella, regenerar sin cambiar nada produce un diff.
    fig.savefig(path, transparent=True, bbox_inches="tight", metadata={"Date": None})
    plt.close(fig)
    print(f"escrito {path.relative_to(ROOT)}")


def _db(values: np.ndarray) -> np.ndarray:
    return 20.0 * np.log10(np.maximum(np.asarray(values, dtype=np.float64), 1e-12))


def _cic(params) -> Cic:
    chain = params.chain
    return Cic(
        stages=int(chain["cic_stages"]),
        rate=int(chain["cic_rate"]),
        diff_delay=int(chain["cic_diff_delay"]),
        in_bits=params.sample_bits,
    )


def figure_droop(params) -> None:
    """Droop del CIC, respuesta del FIR y cascada, en la banda de paso."""
    cic = _cic(params)
    fir = fir_mod.Fir(coeffs=fir_mod.load_coeffs("droop_decim_fir"), decim=4)

    freqs = np.linspace(0.0, 0.10, 512)
    cic_resp = cic.response(freqs / cic.rate)
    fir_resp = fir.response(freqs)
    cascade = cic_resp * fir_resp
    cascade = cascade / cascade[0]

    fig, ax = plt.subplots(figsize=(7.0, 3.2))
    ax.plot(freqs, _db(cic_resp), color=ACCENT[0], label="CIC solo (droop)")
    ax.plot(freqs, _db(fir_resp / fir_resp[0]), color=ACCENT[1], label="FIR compensador")
    ax.plot(freqs, _db(cascade), color=ACCENT[2], linewidth=2, label="cascada CIC+FIR")
    ax.axvline(0.09, color=INK, linestyle="--", linewidth=0.8)
    ax.annotate(
        "borde de banda de paso",
        xy=(0.09, -0.9),
        xytext=(0.055, -1.15),
        color=INK,
        fontsize=8,
    )
    ax.set_ylim(-1.4, 0.9)
    _style(
        ax,
        "frecuencia normalizada a la entrada del FIR (fs/52)",
        "dB",
        "El FIR compensa el droop del CIC",
    )
    ax.legend(fontsize=8, framealpha=0.0, labelcolor=INK)
    _save(fig, "cic-droop.svg")


def figure_alias(params) -> None:
    """Respuesta del FIR y la banda que pliega sobre la señal al diezmar por 4."""
    fir = fir_mod.Fir(coeffs=fir_mod.load_coeffs("droop_decim_fir"), decim=4)
    freqs = np.linspace(0.0, 0.5, 2048)
    resp = _db(fir.response(freqs) / fir.response(np.zeros(1))[0])

    alias_start = 0.25 - 0.09
    worst = resp[freqs >= alias_start].max()

    fig, ax = plt.subplots(figsize=(7.0, 3.2))
    ax.plot(freqs, resp, color=ACCENT[0])
    ax.axvspan(alias_start, 0.5, color=ACCENT[2], alpha=0.12)
    ax.axhline(worst, color=ACCENT[2], linestyle="--", linewidth=0.9)
    ax.annotate(
        f"peor caso en la banda que pliega: {worst:.1f} dB",
        xy=(alias_start, worst),
        xytext=(0.20, worst + 8),
        color=INK,
        fontsize=8,
    )
    ax.annotate(
        "pliega sobre la señal\nal diezmar por 4",
        xy=(0.33, -20),
        color=INK,
        fontsize=8,
        ha="center",
    )
    ax.set_ylim(-110, 10)
    _style(
        ax,
        "frecuencia normalizada a la entrada del FIR (fs/52)",
        "dB",
        "Lo que hay que atenuar no es Nyquist/4: es lo que pliega encima",
    )
    _save(fig, "fir-alias.svg")


def figure_nco(params) -> None:
    """Espectro del NCO: el truncamiento de fase deja espurios deterministas."""
    nco = Nco.from_params(params)
    n = 8192
    cos_w, _ = nco.generate(n)
    window = np.hanning(n)
    spectrum = np.abs(np.fft.rfft(cos_w.astype(np.float64) * window))
    spectrum = _db(spectrum / spectrum.max())
    freqs = np.fft.rfftfreq(n)

    fig, ax = plt.subplots(figsize=(7.0, 3.2))
    ax.plot(freqs, spectrum, color=ACCENT[1], linewidth=0.8)
    ax.axvline(float(params.if_norm), color=ACCENT[2], linestyle="--", linewidth=0.9)
    ax.annotate(
        f"IF normalizado = {float(params.if_norm):.2f}",
        xy=(float(params.if_norm), -6),
        xytext=(0.28, -12),
        color=INK,
        fontsize=8,
    )
    ax.set_ylim(-160, 8)
    _style(
        ax,
        "frecuencia normalizada a fs",
        "dBc",
        "Salida del NCO: la portadora y el suelo de espurios de truncamiento",
    )
    _save(fig, "nco-espectro.svg")


def figure_ddc(params) -> None:
    """Un tono en el IF entra; sale en continua a la tasa diezmada."""
    n = 60_000
    x = vectors.tone(params, n, dbfs=-3.0)
    result = Ddc(params=params, mode=MODE_FINE).process(x)

    settled = result.iq[len(result.iq) // 2 :]
    window_in = np.hanning(x.size)
    spec_in = np.abs(np.fft.rfft(x.astype(np.float64) * window_in))
    spec_in = _db(spec_in / spec_in.max())
    freq_in = np.fft.rfftfreq(x.size)

    window_out = np.hanning(settled.size)
    spec_out = np.fft.fftshift(np.abs(np.fft.fft(settled * window_out)))
    spec_out = _db(spec_out / spec_out.max())
    freq_out = np.fft.fftshift(np.fft.fftfreq(settled.size))

    fig, (ax_in, ax_out) = plt.subplots(1, 2, figsize=(7.6, 3.0))
    ax_in.plot(freq_in, spec_in, color=ACCENT[0], linewidth=0.8)
    ax_in.set_ylim(-140, 8)
    _style(ax_in, "frecuencia normalizada a fs", "dBc", "Entrada: IF real")

    ax_out.plot(freq_out, spec_out, color=ACCENT[3], linewidth=0.8)
    ax_out.set_ylim(-140, 8)
    _style(
        ax_out,
        f"frecuencia normalizada a fs/{result.decimation}",
        "dBc",
        "Salida: I/Q compleja en banda base",
    )
    fig.tight_layout()
    _save(fig, "ddc-espectro.svg")


def main() -> int:
    params = load("zedboard")
    figure_droop(params)
    figure_alias(params)
    figure_nco(params)
    figure_ddc(params)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
