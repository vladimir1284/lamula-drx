/* GENERADO por tools/gen_params.py a partir de config/params.toml. NO EDITAR A MANO.
 * Cambia config/params.toml y vuelve a generar; el CI comprueba que coinciden.
 *
 * Fuente única de verdad temporal (D-02). Ningún otro fichero de fw/ puede
 * contener una constante de frecuencia.
 */

#ifndef DRX_PARAMS_H
#define DRX_PARAMS_H

#define DRX_SCHEMA_VERSION 1
#define DRX_PARAMS_SHA256 "87a45203b7be6d20563172607bbb9464e8aef1f2b20411c665117d12841944e1"

#define DRX_FS_HZ_ZEDBOARD 62500000LL
#define DRX_IF_HZ_ZEDBOARD 15000000LL
#define DRX_FS_HZ_ZU9 250000000LL
#define DRX_IF_HZ_ZU9 60000000LL

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
#define DRX_IF_NORM_NUM 6
#define DRX_IF_NORM_DEN 25
#define DRX_NCO_PHASE_INC 1030792151LL

#define DRX_R1 208
#define DRX_R2 416
#define DRX_BINS_MODE_FINE 3689
#define DRX_BINS_MODE_COARSE 1844

#define DRX_N_RX_CH 4
#define DRX_N_TX_BURST_CH 1
#define DRX_N_TRIGGERS 4

#define DRX_SAMPLE_BITS 16
#define DRX_IQ_BITS 16
#define DRX_NCO_PHASE_BITS 32
#define DRX_NCO_OUT_BITS 16

#define DRX_PRF_DIV_MIN 208333
#define DRX_PRF_DIV_MAX 1250000
#define DRX_N_PULSE_WIDTHS 3
#define DRX_PULSE_WIDTH_CYCLES { 200, 415, 825 }

/* Descomposición de la cadena de diezmado. */
#define DRX_CIC_STAGES 5
#define DRX_CIC_RATE 52
#define DRX_CIC_DIFF_DELAY 1
#define DRX_FIR_DECIM 4
#define DRX_FIR_TAPS 63
#define DRX_COARSE_EXTRA_DECIM 2

/* Anchos derivados de Hogenauer y de la ganancia de continua de cada FIR,
 * calculados por model/drx_model/chain.py (ver tools/gen_params.py). */
#define DRX_CIC_GAIN 380204032LL
#define DRX_CIC_GROWTH_BITS 29
#define DRX_CIC_REGISTER_BITS 45
#define DRX_FIR_COEFF_BITS 18
#define DRX_FIR_DC_GAIN 552725LL
#define DRX_FIR_GROWTH_BITS 20
#define DRX_HALFBAND_COEFF_BITS 18
#define DRX_HALFBAND_DC_GAIN 328067LL
#define DRX_HALFBAND_GROWTH_BITS 19

/* Ajuste de ganancia fina (Z1: escalado a fondo de escala), ver
 * model/drx_model/chain.py::Ddc._residual_gain y rtl/generated/drx_params_pkg.sv. */
#define DRX_GAIN_TRIM_BITS 18
#define DRX_FINE_GAIN_COEFF 43890LL
#define DRX_FINE_GAIN_FRAC_BITS 14
#define DRX_COARSE_GAIN_COEFF 35070LL
#define DRX_COARSE_GAIN_FRAC_BITS 13

#endif /* DRX_PARAMS_H */
