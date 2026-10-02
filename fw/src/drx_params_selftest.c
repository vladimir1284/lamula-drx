/* Auto-comprobación del paquete de parámetros en el lado del firmware.
 *
 * FASE Z0: el firmware real (FreeRTOS, ensamblado de rayos, lwIP) es Z4 y
 * necesita Vitis y un BSP, que aquí no existen. Lo que este programa hace es lo
 * único que Z0 necesita del lado del PS: demostrar que `fw/` consume el MISMO
 * paquete de parámetros que `rtl/`, `sim/` y `model/`, y fallar si deja de
 * hacerlo.
 *
 * Compila para el host, así que el gate de CI corre sin toolchain cruzada. Vuelca
 * los valores en `clave=valor` para que el test de Python los contraste contra
 * config/params.toml: así el desfase entre el TOML y la cabecera generada se
 * detecta en las dos direcciones.
 */

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#include "drx_params.h"
#include "drx_dsp_v0_1.h"

static int failures = 0;

static void check(int condition, const char *what) {
  if (!condition) {
    fprintf(stderr, "FALLO: %s\n", what);
    failures++;
  }
}

int main(void) {
  /* Invariantes que tienen que cumplirse sin mirar el TOML. */
  check(DRX_R2 == DRX_R1 * DRX_COARSE_EXTRA_DECIM,
        "R2 tiene que ser R1 por la etapa extra del modo grueso");
  check(DRX_R1 == DRX_CIC_RATE * DRX_FIR_DECIM,
        "R1 tiene que ser la descomposicion CIC x FIR");
  check(DRX_IF_HZ * DRX_IF_NORM_DEN == DRX_FS_HZ * DRX_IF_NORM_NUM,
        "el IF no cae en el IF normalizado declarado");
  check(DRX_PRF_DIV_MIN < DRX_PRF_DIV_MAX, "el rango de divisores de PRF esta invertido");
  check(DRX_SAMPLE_BITS > 0 && DRX_IQ_BITS > 0, "anchos de dato no positivos");
  check(DRX_NCO_PHASE_BITS >= 32, "la palabra de fase del NCO se quedo corta");

  /* El contrato tiene que estar generado y ser coherente con el firmware. */
  check(DRX_DSP_VERSION_MAJOR == 0 && DRX_DSP_VERSION_MINOR == 5,
        "version del contrato DRx<->DSP inesperada");
  check(sizeof(drx_dsp_ray_t) > 0, "la cabecera de rayo no tiene campos");

  /* Volcado para el contraste desde Python. */
  printf("fs_hz=%" PRId64 "\n", (int64_t)DRX_FS_HZ);
  printf("if_hz=%" PRId64 "\n", (int64_t)DRX_IF_HZ);
  printf("nco_phase_inc=%" PRId64 "\n", (int64_t)DRX_NCO_PHASE_INC);
  printf("r1=%d\n", DRX_R1);
  printf("r2=%d\n", DRX_R2);
  printf("bins_mode_fine=%d\n", DRX_BINS_MODE_FINE);
  printf("bins_mode_coarse=%d\n", DRX_BINS_MODE_COARSE);
  printf("n_rx_ch=%d\n", DRX_N_RX_CH);
  printf("sample_bits=%d\n", DRX_SAMPLE_BITS);
  printf("iq_bits=%d\n", DRX_IQ_BITS);
  printf("cic_stages=%d\n", DRX_CIC_STAGES);
  printf("cic_rate=%d\n", DRX_CIC_RATE);
  printf("fir_decim=%d\n", DRX_FIR_DECIM);
  printf("fir_taps=%d\n", DRX_FIR_TAPS);
  printf("platform=%s\n", DRX_PLATFORM_NAME);
  printf("params_sha256=%s\n", DRX_PARAMS_SHA256);

  if (failures) {
    fprintf(stderr, "%d comprobacion(es) fallida(s)\n", failures);
    return EXIT_FAILURE;
  }
  return EXIT_SUCCESS;
}
