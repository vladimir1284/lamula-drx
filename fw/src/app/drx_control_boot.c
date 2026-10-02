/* Implementacion de fw/include/drx_control_boot.h. */
#include "drx_control_boot.h"

#include "drx_contract_io.h"
#include "drx_control.h"
#include "drx_params.h"
#include "drx_regs.h"
#include "drx_regs_hw.h"
#include "drx_stimulus.h"
#include "drx_timing_cfg.h"

#include "xil_printf.h"

#include <string.h>

#define DRX_BOOT_SEQ 0xC0FFEE01u

/* Buffer del parser: la trama mas grande que este ejercicio empuja es un
 * `config`, asi que basta la cabecera comun mas el cuerpo mas grande que el
 * DRx puede recibir. */
static uint8_t g_parse_buf[128];
static uint8_t g_reply[128];
static size_t g_reply_len;

static size_t boot_send(const uint8_t *frame, size_t len, void *user)
{
    (void)user;

    if (len > sizeof(g_reply)) {
        return 0u;
    }
    memcpy(g_reply, frame, len);
    g_reply_len = len;
    return len;
}

static drx_dsp_error_t boot_apply_config(const drx_dsp_config_t *config, void *user)
{
    (void)user;
    return DrxTiming_Apply(config);
}

static drx_dsp_error_t boot_select_stimulus(uint8_t vector_id, uint16_t repeat, void *user)
{
    (void)user;
    return DrxStimulus_Select(vector_id, repeat);
}

/* Una configuracion distinta de la de bring-up, para que "los registros
 * cambiaron" signifique algo. Sigue siendo valida bajo D-09: mismo lote bajo
 * en el piso de rango no ambiguo, lote alto con la mitad de pulsos. */
static void boot_config(drx_dsp_config_t *out)
{
    memset(out, 0, sizeof(*out));

    out->seq = DRX_BOOT_SEQ;
    out->prf_div_low = (uint32_t)DRX_PRF_DIV_MIN_LOW;
    out->prf_div_high = (uint32_t)DRX_PRF_DIV_MIN;
    out->range_bins_low = (uint16_t)((uint32_t)DRX_PRF_DIV_MIN_LOW / (uint32_t)DRX_R1 - 2u);
    out->range_bins_high = (uint16_t)((uint32_t)DRX_PRF_DIV_MIN / (uint32_t)DRX_R1 - 2u);
    out->n_pulses_low = 8u;
    out->n_pulses_high = 24u;
    out->pulse_width_idx_low = (uint8_t)(DRX_N_PULSE_WIDTHS - 1u);
    out->pulse_width_idx_high = 0u;
    out->cell_mode = 0u;
    out->scan_mode = 1u; /* batch cut, que es lo que D-13 secuencia */

    /* Tantos canales como instancia el bitstream, empezando por el burst de
     * transmision: `DrxTiming_Apply` exige que la cardinalidad case. */
    uint8_t mask = 0u;
    for (unsigned i = 0u; i < (unsigned)DRX_N_CH_TOP; i++) {
        mask = (uint8_t)(mask | (1u << i));
    }
    out->channel_mask = mask;

    for (unsigned i = 0u; i < DRX_N_TRIGGERS; i++) {
        uint32_t width = 64u;
        uint32_t delay = 32u * i;

        switch (i) {
        case 0: out->trigger_delay_0 = delay; out->trigger_width_0 = width; break;
        case 1: out->trigger_delay_1 = delay; out->trigger_width_1 = width; break;
        case 2: out->trigger_delay_2 = delay; out->trigger_width_2 = width; break;
        default: out->trigger_delay_3 = delay; out->trigger_width_3 = width; break;
        }
    }
}

bool DrxControlBoot_SelfTest(void)
{
    DrxControlOps ops = {
        .select_stimulus = boot_select_stimulus,
        .apply_config = boot_apply_config,
        .apply_afc = NULL, /* Z4.5: se contesta `unimplemented`, no `unknown_message` */
        .user = NULL,
    };
    DrxControl control;
    DrxParser parser;
    drx_dsp_config_t config;
    uint8_t wire[128];

    DrxControl_Init(&control, &ops, boot_send, NULL);
    DrxParser_Init(&parser, g_parse_buf, sizeof(g_parse_buf));
    g_reply_len = 0u;

    boot_config(&config);

    size_t len = DrxFrame_Encode(wire, sizeof(wire), DRX_DSP_MSG_CONFIG,
                                 &config, sizeof(config), NULL, 0u);
    if (len == 0u) {
        xil_printf("drx_control: no se pudo codificar el config de prueba\r\n");
        return false;
    }

    uint32_t prf_antes = DrxReg_Read(DRX_REG_PRF_DIV_LOW_OFFSET);
    size_t consumed = DrxParser_Push(&parser, wire, len, DrxControl_OnMessage, &control);

    bool ok = true;

    if (consumed != len || parser.accepted != 1u) {
        xil_printf("drx_control: el parser consumio %lu de %lu (status=%d)\r\n",
                   (unsigned long)consumed, (unsigned long)len, (int)parser.status);
        ok = false;
    }

    /* La respuesta se desmonta con el mismo parser de cabecera que usa el
     * lector: comprobar solo `g_reply_len` diria que algo salio, no que salio
     * un `config_ack` con el `seq` correcto. */
    if (g_reply_len < sizeof(drx_dsp_header_t) + sizeof(drx_dsp_config_ack_t)) {
        xil_printf("drx_control: respuesta corta (%lu B)\r\n", (unsigned long)g_reply_len);
        ok = false;
    } else {
        drx_dsp_header_t header;
        drx_dsp_config_ack_t ack;

        memcpy(&header, g_reply, sizeof(header));
        memcpy(&ack, &g_reply[sizeof(header)], sizeof(ack));

        if (header.msg_type != DRX_DSP_MSG_CONFIG_ACK || ack.seq != DRX_BOOT_SEQ) {
            xil_printf("drx_control: ack inesperado (tipo=%lu seq=0x%08lx)\r\n",
                       (unsigned long)header.msg_type, (unsigned long)ack.seq);
            ok = false;
        }
        if (ack.error != DRX_DSP_ERROR_OK) {
            xil_printf("drx_control: el config de prueba se rechazo (error=%lu)\r\n",
                       (unsigned long)ack.error);
            ok = false;
        }
    }

    uint32_t prf_despues = DrxReg_Read(DRX_REG_PRF_DIV_LOW_OFFSET);
    if (prf_despues != config.prf_div_low) {
        xil_printf("drx_control: PRF_DIV_LOW quedo en %lu, se pidio %lu\r\n",
                   (unsigned long)prf_despues, (unsigned long)config.prf_div_low);
        ok = false;
    }

    xil_printf("drx_control: config por contrato %s (PRF_DIV_LOW %lu -> %lu)\r\n",
               ok ? "OK" : "FALLO", (unsigned long)prf_antes,
               (unsigned long)prf_despues);

    /* Deja el motor en la configuracion de bring-up: es la que el resto de las
     * medidas de esta sesion dan por buena. */
    DrxTimingConfig base;
    DrxTiming_DefaultConfig(&base);
    DrxReg_TimingDisable();
    DrxReg_WriteTimingConfig(&base);
    DrxReg_ClearTimingStatus(DrxReg_ReadTimingStatus());
    DrxReg_TimingEnable();

    return ok;
}
