/* Implementacion de fw/include/drx_control_boot.h. */
#include "drx_control_boot.h"

#include "drx_afc_app.h"
#include "drx_contract_io.h"
#include "drx_control.h"
#include "drx_params.h"
#include "drx_ray.h"
#include "drx_ray_frame.h"
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

/* Una configuracion CLARAMENTE distinta de la de bring-up, para que "los
 * registros cambiaron" signifique algo.
 *
 * La primera version de esta funcion usaba PRF_DIV_MIN_LOW, que es justo el
 * valor que la configuracion de bring-up ya deja escrito: la comprobacion
 * pasaba sin demostrar nada, y se vio en la primera corrida en placa
 * ("PRF_DIV_LOW 767198 -> 767198"). Los valores de aqui no son PRI alineados a
 * R1 a proposito -- este ejercicio prueba el camino del mensaje, no la calidad
 * de la configuracion, y DrxTiming_Start() deja la buena al terminar. */
static void boot_config(drx_dsp_config_t *out)
{
    memset(out, 0, sizeof(*out));

    out->seq = DRX_BOOT_SEQ;
    out->prf_div_low = 800000u;  /* clock-const-ok: divisor de PRF, no una frecuencia */
    out->prf_div_high = 300000u; /* clock-const-ok: divisor de PRF, no una frecuencia */
    out->range_bins_low = 3000u;
    out->range_bins_high = 1200u;
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
        .apply_afc = DrxAfcApp_Apply, /* Z4.5: ya existe; antes se contestaba `unimplemented` */
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

/* Buffer de salida de la trama de un rayo. Se dimensiona al rayo mas grande
 * que el bitstream puede producir, igual que los descriptores del S2MM. */
static uint8_t g_ray_frame[DRX_RAY_MAX_BINS * DRX_RAY_N_CH * 4u + 64u];

bool DrxControlBoot_RaySelfTest(void)
{
    DrxRayHeader header;
    const uint32_t *iq = NULL;
    uint32_t n_words = 0u;

    if (!DrxRay_GetLast(&header, &iq, &n_words)) {
        xil_printf("drx_control: sin rayo que enmarcar\r\n");
        return false;
    }

    DrxTimingConfig base;
    DrxTiming_DefaultConfig(&base);

    uint8_t mask = 0u;
    for (unsigned i = 0u; i < (unsigned)DRX_N_CH_TOP; i++) {
        mask = (uint8_t)(mask | (1u << i));
    }

    DrxRayContext ctx = {
        .prf_div_low = base.prf_div_low,
        .prf_div_high = base.prf_div_high,
        /* Indices, no ciclos: DrxTimingConfig guarda el ancho en ciclos porque
         * es lo que el registro quiere, y el contrato quiere la posicion en la
         * tabla. La configuracion de bring-up usa el ultimo para el lote bajo
         * y el primero para el alto (ver drx_timing_cfg.c). */
        .pulse_width_idx_low = (uint8_t)(DRX_N_PULSE_WIDTHS - 1u),
        .pulse_width_idx_high = 0u,
        .pulse_mode = 0u,
        .channel_mask = mask,
        .azel_valid = false, /* P-02: no hay encoders SSI todavia */
        .azimuth_raw = 0u,
        .elevation_raw = 0u,
        /* Sin reloj de pared: el instante se deriva del contador de disparos y
         * de FS_HZ. Es monotono y exacto en ciclos, que es lo que el DSP
         * necesita para ordenar rayos; atarlo a una hora real es otro trabajo. */
        .timestamp_ns = ((uint64_t)header.trig_count * 1000000000ull) /
                        (uint64_t)DRX_FS_HZ, /* clock-const-ok: ns/s, conversion de unidades */
        .first_after_config = false,
        .ddc_overflow = DrxReg_ReadOverflow() != 0u,
        .truncated = DrxReg_Read(DRX_REG_GATE_TRUNCATED_OFFSET) != 0u,
    };

    size_t len = DrxRayFrame_Encode(g_ray_frame, sizeof(g_ray_frame), &header,
                                    &ctx, iq, n_words);
    size_t esperado = DrxRayFrame_Size(header.bin_count, header.n_ch);

    if (len == 0u || len != esperado) {
        xil_printf("drx_control: la trama del rayo salio %lu B, se esperaban %lu\r\n",
                   (unsigned long)len, (unsigned long)esperado);
        return false;
    }

    xil_printf("drx_control: trama `ray` de %lu B lista (bins=%lu n_ch=%lu)\r\n",
               (unsigned long)len, (unsigned long)header.bin_count,
               (unsigned long)header.n_ch);
    return true;
}
