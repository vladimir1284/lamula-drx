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

from drx_model import chain as chain_mod  # noqa: E402
from drx_model import fixed  # noqa: E402
from drx_model.params import PARAMS_TOML, Params, load_all  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SV_OUT = ROOT / "rtl" / "generated" / "drx_params_pkg.sv"
H_OUT = ROOT / "fw" / "include" / "drx_params.h"
TCL_OUT = ROOT / "tcl" / "generated" / "drx_params.tcl"

# `tcl/gen_ip.tcl` es quien genera de verdad este paquete, con los anchos de
# TDATA reales que reporta la IP de Xilinx ya configurada (ver el aviso de
# cabecera de ese script: no salen de una fórmula de taps/coeficientes).
# `gen_params.py` solo escribe un valor de arranque —y nunca lo pisa si ya
# existe— para que `rtl/drx_ddc_top.sv` tenga algo que importar y
# `make lint-hdl`/`make lint-hdl-tb` no rompan en un checkout limpio, antes de
# que nadie haya corrido Vivado: Verilator exige resolver todo `import` de
# paquete aunque el módulo que lo hace no se elabore desde ningún top (a
# diferencia de una instancia de módulo no usada, que si no se elabora no
# hace falta que resuelva). Los números de este valor de arranque no los usa
# ningún cálculo real hasta entonces.
DDC_IP_PKG_OUT = ROOT / "rtl" / "generated" / "drx_ddc_ip_pkg.sv"

BANNER = (
    "GENERADO por tools/gen_params.py a partir de config/params.toml. NO EDITAR A MANO.\n"
    "Cambia config/params.toml y vuelve a generar; el CI comprueba que coinciden."
)


def _toml_sha256() -> str:
    return hashlib.sha256(PARAMS_TOML.read_bytes()).hexdigest()


def _chain_derived(sel: Params) -> dict:
    """Constantes de ancho derivadas de la cadena, vía el propio modelo dorado.

    `Ddc.__post_init__` construye `cic`/`fir`/`halfband` sin importar el modo,
    así que una sola instancia basta. Se calculan aquí (no en SV/Tcl) para que
    RTL y modelo lean el mismo número en vez de que el RTL reimplemente
    `ceil(N*log2(RM))` con `$clog2` y arriesgue divergir de `fixed.growth_bits`.
    """
    ddc = chain_mod.Ddc(params=sel, mode=chain_mod.MODE_FINE)
    cic_growth = ddc.cic.growth_bits
    fir_growth = fixed.growth_bits(abs(ddc.fir.dc_gain))
    hb_growth = fixed.growth_bits(abs(ddc.halfband.dc_gain))
    # El ajuste de ganancia fina (Z1: escalado a fondo de escala) tiene un
    # residuo distinto por modo, porque el modo grueso suma una etapa de
    # redondeo más (la semibanda) — ver Ddc._residual_gain. Cada Ddc calcula
    # el suyo en __post_init__; se leen aquí en vez de reimplementar
    # fixed.gain_trim, por la misma razón que el resto de esta función.
    ddc_coarse = chain_mod.Ddc(params=sel, mode=chain_mod.MODE_COARSE)
    return {
        "cic_gain": ddc.cic.gain,
        "cic_growth_bits": cic_growth,
        "cic_register_bits": sel.sample_bits + cic_growth,
        "fir_coeff_bits": ddc.fir.coeff_bits,
        "fir_dc_gain": ddc.fir.dc_gain,
        "fir_growth_bits": fir_growth,
        "halfband_coeff_bits": ddc.halfband.coeff_bits,
        "halfband_dc_gain": ddc.halfband.dc_gain,
        "halfband_growth_bits": hb_growth,
        "gain_trim_bits": chain_mod.GAIN_TRIM_BITS,
        "fine_gain_coeff": ddc._gain_coeff,
        "fine_gain_frac_bits": ddc._gain_frac_bits,
        "coarse_gain_coeff": ddc_coarse._gain_coeff,
        "coarse_gain_frac_bits": ddc_coarse._gain_frac_bits,
    }


def _sv_platform_block(p: Params) -> str:
    return f"""
  // --- {p.name}: {p.board} ---
  localparam longint FS_HZ_{p.name.upper()} = {p.fs_hz};
  localparam longint IF_HZ_{p.name.upper()} = {p.if_hz};"""


def render_sv(platforms: dict[str, Params], sel: Params, derived: dict) -> str:
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
  localparam int N_CH_TOP = {inv['n_ch_top']};
  localparam int N_TX_BURST_CH = {inv['n_tx_burst_ch']};
  localparam int N_TRIGGERS = {inv['n_triggers']};

{widths}

  localparam int PRF_DIV_MIN = {inv['prf_div_min']};
  localparam int PRF_DIV_MAX = {inv['prf_div_max']};

  // D-09: piso de PRF_DIV por lote para el rango no ambiguo mínimo exigido
  // (460 km / 115 km WSR-88D-NEXRAD, ver el comentario de config/params.toml).
  localparam int PRF_DIV_MIN_LOW = {inv['prf_div_min_low']};
  localparam int PRF_DIV_MIN_HIGH = {inv['prf_div_min_high']};

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

  // Anchos derivados de Hogenauer y de la ganancia de continua de cada FIR,
  // calculados por `model/drx_model/chain.py`: Z1 los consume en
  // `drx_round_sat` para que el punto de recorte de cada etapa sea el mismo
  // número que usa el oráculo, no una copia a mano de la fórmula.
  localparam longint CIC_GAIN = {derived['cic_gain']};
  localparam int CIC_GROWTH_BITS = {derived['cic_growth_bits']};
  localparam int CIC_REGISTER_BITS = {derived['cic_register_bits']};
  localparam int FIR_COEFF_BITS = {derived['fir_coeff_bits']};
  localparam longint FIR_DC_GAIN = {derived['fir_dc_gain']};
  localparam int FIR_GROWTH_BITS = {derived['fir_growth_bits']};
  localparam int HALFBAND_COEFF_BITS = {derived['halfband_coeff_bits']};
  localparam longint HALFBAND_DC_GAIN = {derived['halfband_dc_gain']};
  localparam int HALFBAND_GROWTH_BITS = {derived['halfband_growth_bits']};

  // Ajuste de ganancia fina (Z1: escalado a fondo de escala), un residuo
  // distinto por modo — ver model/drx_model/chain.py::Ddc._residual_gain.
  // Un único multiplicador de coeficiente constante por rama deshace lo que
  // CIC_GROWTH_BITS/FIR_GROWTH_BITS(/HALFBAND_GROWTH_BITS) dejan a medias.
  localparam int GAIN_TRIM_BITS = {derived['gain_trim_bits']};
  localparam longint FINE_GAIN_COEFF = {derived['fine_gain_coeff']};
  localparam int FINE_GAIN_FRAC_BITS = {derived['fine_gain_frac_bits']};
  localparam longint COARSE_GAIN_COEFF = {derived['coarse_gain_coeff']};
  localparam int COARSE_GAIN_FRAC_BITS = {derived['coarse_gain_frac_bits']};

endpackage : drx_params_pkg

`endif  // DRX_PARAMS_PKG_SV
"""


def render_h(platforms: dict[str, Params], sel: Params, derived: dict) -> str:
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
#define DRX_N_CH_TOP {inv['n_ch_top']}
#define DRX_N_TX_BURST_CH {inv['n_tx_burst_ch']}
#define DRX_N_TRIGGERS {inv['n_triggers']}

#define DRX_SAMPLE_BITS {inv['sample_bits']}
#define DRX_IQ_BITS {inv['iq_bits']}
#define DRX_NCO_PHASE_BITS {inv['nco_phase_bits']}
#define DRX_NCO_OUT_BITS {inv['nco_out_bits']}

#define DRX_PRF_DIV_MIN {inv['prf_div_min']}
#define DRX_PRF_DIV_MAX {inv['prf_div_max']}

/* D-09: piso de PRF_DIV por lote para el rango no ambiguo minimo exigido
 * (460 km / 115 km WSR-88D-NEXRAD, ver el comentario de config/params.toml). */
#define DRX_PRF_DIV_MIN_LOW {inv['prf_div_min_low']}
#define DRX_PRF_DIV_MIN_HIGH {inv['prf_div_min_high']}

#define DRX_N_PULSE_WIDTHS {len(inv['pulse_width_cycles'])}
#define DRX_PULSE_WIDTH_CYCLES {{ {pw} }}

/* Descomposición de la cadena de diezmado. */
#define DRX_CIC_STAGES {ch['cic_stages']}
#define DRX_CIC_RATE {ch['cic_rate']}
#define DRX_CIC_DIFF_DELAY {ch['cic_diff_delay']}
#define DRX_FIR_DECIM {ch['fir_decim']}
#define DRX_FIR_TAPS {ch['fir_taps']}
#define DRX_COARSE_EXTRA_DECIM {ch['coarse_extra_decim']}

/* Anchos derivados de Hogenauer y de la ganancia de continua de cada FIR,
 * calculados por model/drx_model/chain.py (ver tools/gen_params.py). */
#define DRX_CIC_GAIN {derived['cic_gain']}LL
#define DRX_CIC_GROWTH_BITS {derived['cic_growth_bits']}
#define DRX_CIC_REGISTER_BITS {derived['cic_register_bits']}
#define DRX_FIR_COEFF_BITS {derived['fir_coeff_bits']}
#define DRX_FIR_DC_GAIN {derived['fir_dc_gain']}LL
#define DRX_FIR_GROWTH_BITS {derived['fir_growth_bits']}
#define DRX_HALFBAND_COEFF_BITS {derived['halfband_coeff_bits']}
#define DRX_HALFBAND_DC_GAIN {derived['halfband_dc_gain']}LL
#define DRX_HALFBAND_GROWTH_BITS {derived['halfband_growth_bits']}

/* Ajuste de ganancia fina (Z1: escalado a fondo de escala), ver
 * model/drx_model/chain.py::Ddc._residual_gain y rtl/generated/drx_params_pkg.sv. */
#define DRX_GAIN_TRIM_BITS {derived['gain_trim_bits']}
#define DRX_FINE_GAIN_COEFF {derived['fine_gain_coeff']}LL
#define DRX_FINE_GAIN_FRAC_BITS {derived['fine_gain_frac_bits']}
#define DRX_COARSE_GAIN_COEFF {derived['coarse_gain_coeff']}LL
#define DRX_COARSE_GAIN_FRAC_BITS {derived['coarse_gain_frac_bits']}

#endif /* DRX_PARAMS_H */
"""


def render_tcl(platforms: dict[str, Params], sel: Params, derived: dict) -> str:
    inv = sel.invariant
    ch = sel.chain
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
        "  # Invariantes de dilatación y de la cadena de diezmado (D-02): idénticos",
        "  # en las dos plataformas, y de aquí los toma tcl/gen_ip.tcl para",
        "  # configurar la IP del DDC sin repetir un número a mano.",
        f"  variable NCO_PHASE_BITS {inv['nco_phase_bits']}",
        f"  variable NCO_OUT_BITS {inv['nco_out_bits']}",
        f"  variable NCO_PHASE_INC {sel.nco_phase_inc}",
        f"  variable SAMPLE_BITS {inv['sample_bits']}",
        f"  variable IQ_BITS {inv['iq_bits']}",
        f"  variable CIC_STAGES {ch['cic_stages']}",
        f"  variable CIC_RATE {ch['cic_rate']}",
        f"  variable CIC_DIFF_DELAY {ch['cic_diff_delay']}",
        f"  variable FIR_DECIM {ch['fir_decim']}",
        f"  variable FIR_TAPS {ch['fir_taps']}",
        f"  variable COARSE_EXTRA_DECIM {ch['coarse_extra_decim']}",
        "",
        "  # Anchos derivados (Hogenauer, ganancia de continua de cada FIR),",
        "  # calculados por model/drx_model/chain.py: mismo número que consume",
        "  # rtl/generated/drx_params_pkg.sv, para tcl/gen_ip.tcl.",
        f"  variable CIC_GAIN {derived['cic_gain']}",
        f"  variable CIC_GROWTH_BITS {derived['cic_growth_bits']}",
        f"  variable CIC_REGISTER_BITS {derived['cic_register_bits']}",
        f"  variable FIR_COEFF_BITS {derived['fir_coeff_bits']}",
        f"  variable FIR_DC_GAIN {derived['fir_dc_gain']}",
        f"  variable FIR_GROWTH_BITS {derived['fir_growth_bits']}",
        f"  variable HALFBAND_COEFF_BITS {derived['halfband_coeff_bits']}",
        f"  variable HALFBAND_DC_GAIN {derived['halfband_dc_gain']}",
        f"  variable HALFBAND_GROWTH_BITS {derived['halfband_growth_bits']}",
        "",
        "  # Ajuste de ganancia fina (Z1: escalado a fondo de escala), ver",
        "  # model/drx_model/chain.py::Ddc._residual_gain.",
        f"  variable GAIN_TRIM_BITS {derived['gain_trim_bits']}",
        f"  variable FINE_GAIN_COEFF {derived['fine_gain_coeff']}",
        f"  variable FINE_GAIN_FRAC_BITS {derived['fine_gain_frac_bits']}",
        f"  variable COARSE_GAIN_COEFF {derived['coarse_gain_coeff']}",
        f"  variable COARSE_GAIN_FRAC_BITS {derived['coarse_gain_frac_bits']}",
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


def render_ddc_ip_placeholder(derived: dict) -> str:
    """Valor de arranque de `rtl/generated/drx_ddc_ip_pkg.sv`.

    Solo se escribe si el fichero no existe (ver `DDC_IP_PKG_OUT`): en cuanto
    alguien corre `tcl/gen_ip.tcl` contra Vivado, ese script lo sustituye por
    los anchos reales y esta función deja de intervenir.
    """
    sample_bits = derived["cic_register_bits"] - derived["cic_growth_bits"]
    fir_out_bits = sample_bits + derived["fir_coeff_bits"] + derived["fir_growth_bits"]
    return f"""// VALOR DE ARRANQUE — `tcl/gen_ip.tcl` lo sustituye por los anchos reales en
// cuanto corre contra Vivado (ver el aviso de esa cabecera). Estos números
// son una cota razonable, no una medida: no los usa ningún cálculo real
// mientras `drx_ddc_top.sv` no se elabore desde un top real.

`ifndef DRX_DDC_IP_PKG_SV
`define DRX_DDC_IP_PKG_SV

package drx_ddc_ip_pkg;

  localparam int DDS_TDATA_BITS = 32;
  localparam int CIC_IN_BITS = {sample_bits};
  localparam int CIC_TDATA_BITS = {derived['cic_register_bits']};
  localparam int FIR_DROOP_IN_BITS = {sample_bits};
  localparam int FIR_DROOP_TDATA_BITS = {fir_out_bits};
  localparam int FIR_HALFBAND_IN_BITS = {sample_bits};
  localparam int FIR_HALFBAND_TDATA_BITS = {fir_out_bits};

endpackage : drx_ddc_ip_pkg

`endif  // DRX_DDC_IP_PKG_SV
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="no escribe; falla si hay desfase")
    args = ap.parse_args()

    platforms = load_all()
    sel = platforms["zedboard"]
    derived = _chain_derived(sel)
    outputs = {
        SV_OUT: render_sv(platforms, sel, derived),
        H_OUT: render_h(platforms, sel, derived),
        TCL_OUT: render_tcl(platforms, sel, derived),
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

    if not args.check and not DDC_IP_PKG_OUT.exists():
        DDC_IP_PKG_OUT.parent.mkdir(parents=True, exist_ok=True)
        DDC_IP_PKG_OUT.write_text(render_ddc_ip_placeholder(derived))
        rel = DDC_IP_PKG_OUT.relative_to(ROOT)
        print(f"escrito {rel} (valor de arranque; tcl/gen_ip.tcl lo sustituye)")

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
