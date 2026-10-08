/* Implementacion de fw/include/drx_ray_ctx.h. Extraido de drx_control_boot.c
 * en Z4.6, cuando el transporte paso a ser un segundo productor de tramas. */
#include "drx_ray_ctx.h"

#include "drx_params.h"
#include "drx_regs.h"
#include "drx_regs_hw.h"
#include "drx_timing_cfg.h"

#include <string.h>

void DrxRayCtx_Fill(DrxRayContext *out, const DrxRayHeader *header)
{
    if (out == NULL || header == NULL) {
        return;
    }
    memset(out, 0, sizeof(*out));

    DrxTimingRayMeta meta;
    DrxTiming_GetRayMeta(&meta);

    out->prf_div_low = meta.prf_div_low;
    out->prf_div_high = meta.prf_div_high;
    out->pulse_width_idx_low = meta.pulse_width_idx_low;
    out->pulse_width_idx_high = meta.pulse_width_idx_high;
    out->pulse_mode = 0u;
    out->channel_mask = meta.channel_mask;
    out->azel_valid = false; /* P-02: no hay encoders SSI todavia */
    out->azimuth_raw = 0u;
    out->elevation_raw = 0u;
    /* Sin reloj de pared: el instante se deriva del contador de disparos y de
     * FS_HZ. Es monotono y exacto en ciclos, que es lo que el DSP necesita
     * para ordenar rayos; atarlo a una hora real es otro trabajo. */
    out->timestamp_ns = ((uint64_t)header->trig_count * 1000000000ull) /
                        (uint64_t)DRX_FS_HZ; /* clock-const-ok: ns/s, conversion de unidades */
    out->first_after_config = meta.first_after_config;
    out->ddc_overflow = DrxReg_ReadOverflow() != 0u;
    out->truncated = DrxReg_Read(DRX_REG_GATE_TRUNCATED_OFFSET) != 0u;
}
