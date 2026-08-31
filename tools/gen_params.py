#!/usr/bin/env python3
"""Genera los paquetes de parámetros de `rtl/` y `fw/` a partir de config/params.toml.

Uso:
    python3 tools/gen_params.py            # regenera los ficheros
    python3 tools/gen_params.py --check    # falla si están desactualizados (gate de CI)

No hay marcas de tiempo en la salida: la generación es determinista, byte a byte,
para que el `BOOT.BIN` también pueda serlo.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "model"))

from drx_model.params import PARAMS_TOML, Params, load_all  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SV_OUT = ROOT / "rtl" / "generated" / "drx_params_pkg.sv"
H_OUT = ROOT / "fw" / "include" / "drx_params.h"
TCL_OUT = ROOT / "tcl" / "generated" / "drx_params.tcl"

BANNER = (
    "GENERADO por tools/gen_params.py a partir de config/params.toml. NO EDITAR A MANO.\n"
    "Cambia config/params.toml y vuelve a generar; el CI comprueba que coinciden."
)


def _toml_sha256() -> str:
    return hashlib.sha256(PARAMS_TOML.read_bytes()).hexdigest()


def _sv_platform_block(p: Params) -> str:
    return f"""
  // --- {p.name}: {p.board} ---
  localparam longint FS_HZ_{p.name.upper()} = {p.fs_hz};
  localparam longint IF_HZ_{p.name.upper()} = {p.if_hz};"""


def render_sv(platforms: dict[str, Params], sel: Params) -> str:
    inv = sel.invariant
    ch = sel.chain
    widths = "  localparam int " + ";\n  localparam int ".join(
        [
            f"SAMPLE_BITS = {inv['sample_bits']}",
            f"IQ_BITS = {inv['iq_bits']}",
            f"NCO_PHASE_BITS = {inv['nco_phase_bits']}",
            f"NCO_OUT_BITS = {inv['nco_out_bits']}",
        ]
    ) + ";"
    pw = ", ".join(str(v) for v in inv["pulse_width_cycles"])
    per_platform = "".join(_sv_platform_block(p) for p in platforms.values())
    return f"""// {BANNER.splitlines()[0]}
// {BANNER.splitlines()[1]}
//
// Fuente única de verdad temporal (D-02). Ningún otro fichero de rtl/ puede
// contener una constante de frecuencia: el gate `tools/check_hardcoded_clock.py`
// falla la build si aparece.

`ifndef DRX_PARAMS_PKG_SV
`define DRX_PARAMS_PKG_SV

package drx_params_pkg;

  localparam int SCHEMA_VERSION = {sel.schema_version};
  localparam string PARAMS_SHA256 = "{_toml_sha256()}";

  // -------------------------------------------------------------------------
  // Plataforma seleccionada. Se sobreescribe en la línea de comandos de síntesis
  // con -generic o redefiniendo DRX_PLATFORM_* ; el valor por defecto es la
  // plataforma de desarrollo.
  // -------------------------------------------------------------------------
`ifdef DRX_PLATFORM_ZU9
  localparam longint FS_HZ = FS_HZ_ZU9;
  localparam longint IF_HZ = IF_HZ_ZU9;
  localparam string  PLATFORM = "zu9";
`else
  localparam longint FS_HZ = FS_HZ_ZEDBOARD;
  localparam longint IF_HZ = IF_HZ_ZEDBOARD;
  localparam string  PLATFORM = "zedboard";
`endif
{per_platform}

  // -------------------------------------------------------------------------
  // Invariantes de dilatación: idénticos en las dos plataformas.
  // -------------------------------------------------------------------------
  localparam int IF_NORM_NUM = {inv['if_norm_num']};
  localparam int IF_NORM_DEN = {inv['if_norm_den']};

  // Incremento de fase del NCO: round(IF_NORM * 2**NCO_PHASE_BITS). Invariante,
  // que es justamente el punto de D-02.
  localparam longint NCO_PHASE_INC = {sel.nco_phase_inc};

  localparam int R1 = {inv['r1']};
  localparam int R2 = {inv['r2']};
  localparam int BINS_MODE_FINE = {inv['bins_mode_fine']};
  localparam int BINS_MODE_COARSE = {inv['bins_mode_coarse']};

  localparam int N_RX_CH = {inv['n_rx_ch']};
  localparam int N_TX_BURST_CH = {inv['n_tx_burst_ch']};
  localparam int N_TRIGGERS = {inv['n_triggers']};

{widths}

  localparam int PRF_DIV_MIN = {inv['prf_div_min']};
  localparam int PRF_DIV_MAX = {inv['prf_div_max']};
  localparam int PULSE_WIDTH_CYCLES [0:{len(inv['pulse_width_cycles']) - 1}] = '{{{pw}}};

  // -------------------------------------------------------------------------
  // Descomposición de la cadena de diezmado (Z1 es dueña de estos valores).
  // -------------------------------------------------------------------------
  localparam int CIC_STAGES = {ch['cic_stages']};
  localparam int CIC_RATE = {ch['cic_rate']};
  localparam int CIC_DIFF_DELAY = {ch['cic_diff_delay']};
  localparam int FIR_DECIM = {ch['fir_decim']};
  localparam int FIR_TAPS = {ch['fir_taps']};
  localparam int COARSE_EXTRA_DECIM = {ch['coarse_extra_decim']};

endpackage : drx_params_pkg

`endif  // DRX_PARAMS_PKG_SV
"""


def render_h(platforms: dict[str, Params], sel: Params) -> str:
    inv = sel.invariant
    ch = sel.chain
    per_platform = "".join(
        f"\n#define DRX_FS_HZ_{p.name.upper()} {p.fs_hz}LL"
        f"\n#define DRX_IF_HZ_{p.name.upper()} {p.if_hz}LL"
        for p in platforms.values()
    )
    pw = ", ".join(str(v) for v in inv["pulse_width_cycles"])
    return f"""/* {BANNER.splitlines()[0]}
 * {BANNER.splitlines()[1]}
 *
 * Fuente única de verdad temporal (D-02). Ningún otro fichero de fw/ puede
 * contener una constante de frecuencia.
 */

#ifndef DRX_PARAMS_H
#define DRX_PARAMS_H

#define DRX_SCHEMA_VERSION {sel.schema_version}
#define DRX_PARAMS_SHA256 "{_toml_sha256()}"
{per_platform}

/* Plataforma seleccionada en tiempo de compilación. */
#if defined(DRX_PLATFORM_ZU9)
#define DRX_FS_HZ DRX_FS_HZ_ZU9
#define DRX_IF_HZ DRX_IF_HZ_ZU9
#define DRX_PLATFORM_NAME "zu9"
#else
#define DRX_FS_HZ DRX_FS_HZ_ZEDBOARD
#define DRX_IF_HZ DRX_IF_HZ_ZEDBOARD
#define DRX_PLATFORM_NAME "zedboard"
#endif

/* Invariantes de dilatación. */
#define DRX_IF_NORM_NUM {inv['if_norm_num']}
#define DRX_IF_NORM_DEN {inv['if_norm_den']}
#define DRX_NCO_PHASE_INC {sel.nco_phase_inc}LL

#define DRX_R1 {inv['r1']}
#define DRX_R2 {inv['r2']}
#define DRX_BINS_MODE_FINE {inv['bins_mode_fine']}
#define DRX_BINS_MODE_COARSE {inv['bins_mode_coarse']}

#define DRX_N_RX_CH {inv['n_rx_ch']}
#define DRX_N_TX_BURST_CH {inv['n_tx_burst_ch']}
#define DRX_N_TRIGGERS {inv['n_triggers']}

#define DRX_SAMPLE_BITS {inv['sample_bits']}
#define DRX_IQ_BITS {inv['iq_bits']}
#define DRX_NCO_PHASE_BITS {inv['nco_phase_bits']}
#define DRX_NCO_OUT_BITS {inv['nco_out_bits']}

#define DRX_PRF_DIV_MIN {inv['prf_div_min']}
#define DRX_PRF_DIV_MAX {inv['prf_div_max']}
#define DRX_N_PULSE_WIDTHS {len(inv['pulse_width_cycles'])}
#define DRX_PULSE_WIDTH_CYCLES {{ {pw} }}

/* Descomposición de la cadena de diezmado. */
#define DRX_CIC_STAGES {ch['cic_stages']}
#define DRX_CIC_RATE {ch['cic_rate']}
#define DRX_CIC_DIFF_DELAY {ch['cic_diff_delay']}
#define DRX_FIR_DECIM {ch['fir_decim']}
#define DRX_FIR_TAPS {ch['fir_taps']}
#define DRX_COARSE_EXTRA_DECIM {ch['coarse_extra_decim']}

#endif /* DRX_PARAMS_H */
"""


def render_tcl(platforms: dict[str, Params], sel: Params) -> str:
    lines = [
        f"# {BANNER.splitlines()[0]}",
        f"# {BANNER.splitlines()[1]}",
        "#",
        "# El flujo de tcl/ deriva de aquí el periodo de reloj y la pieza. Ningún",
        "# fichero de tcl/ ni ningún XDC puede llevar un periodo literal (D-02).",
        "",
        "namespace eval ::drx {",
        f"  variable SCHEMA_VERSION {sel.schema_version}",
        f"  variable PARAMS_SHA256 {_toml_sha256()}",
        "",
    ]
    for p in platforms.values():
        up = p.name.upper()
        period_ns = 1e9 / p.fs_hz  # clock-const-ok: conversión de unidades Hz->ns
        lines += [
            f"  # {p.name}: {p.board}",
            f"  variable FS_HZ_{up} {p.fs_hz}",
            f"  variable IF_HZ_{up} {p.if_hz}",
            f"  variable CLK_PERIOD_NS_{up} {period_ns:.6f}",
            f"  variable PART_{up} {p.part}",
            "",
        ]
    names = " ".join(platforms)
    lines += [
        f"  variable PLATFORMS [list {names}]",
        "}",
        "",
        "# Resuelve una variable por plataforma: [::drx::get FS_HZ zedboard]",
        "proc ::drx::get {name platform} {",
        "  set var ::drx::${name}_[string toupper $platform]",
        "  if {![info exists $var]} {",
        "    error \"parámetro desconocido: $name para la plataforma $platform\"",
        "  }",
        "  return [set $var]",
        "}",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="no escribe; falla si hay desfase")
    args = ap.parse_args()

    platforms = load_all()
    sel = platforms["zedboard"]
    outputs = {
        SV_OUT: render_sv(platforms, sel),
        H_OUT: render_h(platforms, sel),
        TCL_OUT: render_tcl(platforms, sel),
    }

    stale = []
    for path, text in outputs.items():
        if args.check:
            current = path.read_text() if path.exists() else None
            if current != text:
                stale.append(path)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)

    if args.check:
        if stale:
            for path in stale:
                print(f"DESACTUALIZADO: {path.relative_to(ROOT)}", file=sys.stderr)
            print("Ejecuta: python3 tools/gen_params.py", file=sys.stderr)
            return 1
        print("parámetros generados al día")
        return 0

    for path in outputs:
        print(f"escrito {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
