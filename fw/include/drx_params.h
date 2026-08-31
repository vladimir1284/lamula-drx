/* GENERADO por tools/gen_params.py a partir de config/params.toml. NO EDITAR A MANO.
 * Cambia config/params.toml y vuelve a generar; el CI comprueba que coinciden.
 *
 * Fuente única de verdad temporal (D-02). Ningún otro fichero de fw/ puede
 * contener una constante de frecuencia.
 */

#ifndef DRX_PARAMS_H
#define DRX_PARAMS_H

#define DRX_SCHEMA_VERSION 1
#define DRX_PARAMS_SHA256 "e90ab8bb9c31092b8cab9c74acc55f0c917f5db1e544915f775296748a10b95a"

#define DRX_FS_HZ_ZEDBOARD 100000000LL
#define DRX_IF_HZ_ZEDBOARD 24000000LL
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
#define DRX_N_TX_BURST_CH 2
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

#endif /* DRX_PARAMS_H */
