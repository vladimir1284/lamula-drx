/* Arnes de host para fw/src/app/drx_ray_frame.c.
 *
 * Imprime en hexadecimal la trama `ray` que el firmware mandaria para un rayo
 * conocido. El test de Python monta la misma con la implementacion generada
 * del mismo esquema y compara byte a byte: si no coinciden, o el codegen esta
 * mal o el firmware esta montando mal la carga util -- y el caso que mas
 * importa ahi es el orden I/Q, que una trama mal montada NO delata al parsear.
 */
#include "drx_ray_frame.h"

#include <stdio.h>
#include <string.h>

#define BINS 3u
#define N_CH 3u

int main(void)
{
    uint32_t iq[BINS * N_CH];

    /* I y Q distintos entre si y distintos por (bin, canal): si el framer
     * cambiara I por Q, o barajara canales, saldria en la comparacion. Los
     * valores negativos entran a proposito -- el error clasico es perder el
     * signo al estrechar a 16 bits. */
    for (uint32_t bin = 0; bin < BINS; bin++) {
        for (uint32_t ch = 0; ch < N_CH; ch++) {
            int16_t i_val = (int16_t)(1000 * (int)bin + (int)ch + 1);
            int16_t q_val = (int16_t)(-(2000 * (int)bin + (int)ch + 1));

            iq[bin * N_CH + ch] =
                ((uint32_t)(uint16_t)i_val << 16) | (uint32_t)(uint16_t)q_val;
        }
    }

    DrxRayHeader header = {
        .trig_count = 0x11223344u,
        .ray_index = 0x55667788u,
        .bin_count = (uint16_t)BINS,
        .n_ch = (uint8_t)N_CH,
        .batch_high = true,
        .mode_coarse = false,
    };
    DrxRayContext ctx = {
        .prf_div_low = 767198u,
        .prf_div_high = 208333u,
        .pulse_width_idx_low = 2u,
        .pulse_width_idx_high = 0u,
        .pulse_mode = 1u,
        .channel_mask = 0x07u,
        .azel_valid = false,
        .azimuth_raw = 0u,
        .elevation_raw = 0u,
        .timestamp_ns = 0x0102030405060708ull,
        .first_after_config = true,
        .ddc_overflow = false,
        .truncated = false,
    };

    uint8_t out[512];
    size_t len = DrxRayFrame_Encode(out, sizeof(out), &header, &ctx, iq,
                                    BINS * N_CH);

    if (len == 0u || len != DrxRayFrame_Size(BINS, N_CH)) {
        printf("len=0\n");
        return 1;
    }

    printf("ray=");
    for (size_t i = 0; i < len; i++) {
        printf("%02x", out[i]);
    }
    printf("\n");

    /* Rechazos: un rayo cuyo n_words no cuadra con su cabecera, y un buffer
     * corto. Los dos tienen que devolver 0 y no una trama a medias. */
    printf("rechaza_n_words=%d\n",
           DrxRayFrame_Encode(out, sizeof(out), &header, &ctx, iq,
                              BINS * N_CH - 1u) == 0u ? 1 : 0);
    printf("rechaza_buffer_corto=%d\n",
           DrxRayFrame_Encode(out, len - 1u, &header, &ctx, iq,
                              BINS * N_CH) == 0u ? 1 : 0);
    return 0;
}
