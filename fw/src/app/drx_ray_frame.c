/* Implementacion de fw/include/drx_ray_frame.h. Sin Xilinx ni FreeRTOS: se
 * compila igual para el host (fw/Makefile) y para el Cortex-A9 (tcl/gen_bsp.tcl).
 */
#include "drx_ray_frame.h"

#include "drx_contract_io.h"

#include <string.h>

size_t DrxRayFrame_Size(uint32_t bins, uint32_t n_ch)
{
    return sizeof(drx_dsp_header_t) + sizeof(drx_dsp_ray_t) +
           (size_t)bins * (size_t)n_ch * 4u;
}

size_t DrxRayFrame_Encode(uint8_t *out, size_t cap, const DrxRayHeader *header,
                          const DrxRayContext *ctx, const uint32_t *iq,
                          uint32_t n_words)
{
    if (out == NULL || header == NULL || ctx == NULL || iq == NULL) {
        return 0u;
    }
    if (header->n_ch == 0u || header->bin_count == 0u) {
        return 0u;
    }
    if (n_words != (uint32_t)header->bin_count * (uint32_t)header->n_ch) {
        /* Se comprueba en vez de confiarse: un rayo corto codificado con el
         * `bins` de su cabecera produce una trama cuyo `payload_len` no cuadra
         * con lo que lleva, y eso desincroniza al lector en el mensaje
         * SIGUIENTE, no en este. */
        return 0u;
    }

    size_t payload_len = (size_t)n_words * 4u;
    size_t total = sizeof(drx_dsp_header_t) + sizeof(drx_dsp_ray_t) + payload_len;

    if (cap < total) {
        return 0u;
    }

    uint8_t flags = 0u;
    if (!ctx->azel_valid) flags |= (uint8_t)DRX_DSP_RAY_FLAG_AZEL_INVALID;
    if (ctx->ddc_overflow) flags |= (uint8_t)DRX_DSP_RAY_FLAG_DDC_OVERFLOW;
    if (ctx->truncated) flags |= (uint8_t)DRX_DSP_RAY_FLAG_TRUNCATED;
    if (ctx->first_after_config) flags |= (uint8_t)DRX_DSP_RAY_FLAG_FIRST_AFTER_CONFIG;
    if (header->batch_high) flags |= (uint8_t)DRX_DSP_RAY_FLAG_BATCH_HIGH;

    drx_dsp_ray_t body;
    memset(&body, 0, sizeof(body));

    body.seq = header->ray_index;
    body.timestamp_ns = ctx->timestamp_ns;
    body.trigger_count = header->trig_count;
    body.azimuth_raw = ctx->azel_valid ? ctx->azimuth_raw : 0u;
    body.elevation_raw = ctx->azel_valid ? ctx->elevation_raw : 0u;
    body.prf_div = header->batch_high ? ctx->prf_div_high : ctx->prf_div_low;
    body.bins = header->bin_count;
    body.pulse_width_idx = header->batch_high ? ctx->pulse_width_idx_high
                                              : ctx->pulse_width_idx_low;
    body.pulse_mode = ctx->pulse_mode;
    body.cell_mode = header->mode_coarse ? 1u : 0u;
    body.n_channels = header->n_ch;
    body.channel_mask = ctx->channel_mask;
    body.ray_flags = flags;

    /* La carga util se copia cruda y se le da la vuelta DESPUES, en el propio
     * buffer de salida: la DDR trae {I[31:16], Q[15:0]} -- en memoria
     * Q_lo Q_hi I_lo I_hi -- y el contrato pide el par en orden I,Q. Hacerlo
     * asi evita un buffer intermedio del tamano de un rayo entero (44 KiB en
     * modo fino) y evita pasarle a memcpy un origen y un destino que serian la
     * misma direccion. */
    size_t written = DrxFrame_Encode(out, cap, DRX_DSP_MSG_RAY, &body,
                                     sizeof(body), iq, payload_len);
    if (written != total) {
        return 0u;
    }

    uint8_t *payload = &out[sizeof(drx_dsp_header_t) + sizeof(drx_dsp_ray_t)];
    for (uint32_t w = 0; w < n_words; w++) {
        uint8_t *word = &payload[w * 4u];
        uint8_t q_lo = word[0];
        uint8_t q_hi = word[1];

        word[0] = word[2];
        word[1] = word[3];
        word[2] = q_lo;
        word[3] = q_hi;
    }

    return written;
}
