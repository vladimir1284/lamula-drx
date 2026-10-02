/* Implementacion de fw/include/drx_status_frame.h. Sin Xilinx ni FreeRTOS: se
 * compila igual para el host (fw/Makefile) y para el Cortex-A9 (tcl/gen_bsp.tcl).
 */
#include "drx_status_frame.h"

#include "drx_contract_io.h"

#include <string.h>

uint32_t DrxStatus_BiteFlags(const DrxStatusInputs *in)
{
    uint32_t flags = 0u;

    if (in->ssa_underruns != 0u) flags |= (uint32_t)DRX_DSP_BITE_FLAG_SSA_UNDERRUN;
    if (in->dma_overruns != 0u) flags |= (uint32_t)DRX_DSP_BITE_FLAG_DMA_OVERRUN;
    if (in->ssi_errors != 0u) flags |= (uint32_t)DRX_DSP_BITE_FLAG_SSI_FRAME_ERROR;
    if (in->config_rejects != 0u) flags |= (uint32_t)DRX_DSP_BITE_FLAG_CONFIG_REJECTED;
    if (in->link_down) flags |= (uint32_t)DRX_DSP_BITE_FLAG_LINK_DOWN;
    if (in->mmcm_unlocked) flags |= (uint32_t)DRX_DSP_BITE_FLAG_MMCM_UNLOCKED;

    /* `ssi_timeout` no se levanta aqui a proposito: hoy no hay forma de
     * distinguir un timeout de una trama mala, porque no hay lectores SSI (Z3).
     * Levantar las dos con el mismo contador diria al DSP que sabemos algo que
     * no sabemos. */
    return flags;
}

void DrxStatus_Fill(drx_dsp_status_t *out, const DrxStatusInputs *in)
{
    memset(out, 0, sizeof(*out));

    out->uptime_s = in->uptime_s;
    out->bite_flags = DrxStatus_BiteFlags(in);
    out->ssa_underruns = in->ssa_underruns;
    out->dma_overruns = in->dma_overruns;
    out->ssi_errors = in->ssi_errors;
    out->ddc_overflows = in->ddc_overflows;
    out->last_error = in->last_error;
}

size_t DrxStatus_Encode(uint8_t *out, size_t cap, const DrxStatusInputs *in)
{
    if (out == NULL || in == NULL) {
        return 0u;
    }

    drx_dsp_status_t body;
    DrxStatus_Fill(&body, in);

    return DrxFrame_Encode(out, cap, (uint8_t)DRX_DSP_MSG_STATUS, &body,
                           sizeof(body), NULL, 0u);
}
