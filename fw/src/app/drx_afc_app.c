/* Implementacion de fw/include/drx_afc_app.h. */
#include "drx_afc_app.h"

#include "drx_afc.h"
#include "drx_contract_io.h"
#include "drx_control.h"
#include "drx_params.h"
#include "drx_ray.h"
#include "drx_regs_hw.h"
#include "drx_status_task.h"

#include "xil_printf.h"

static DrxAfc g_afc;

static void escribe_pinc(uint32_t pinc, void *user)
{
    (void)user;
    DrxReg_WriteNcoPinc(pinc);
}

void DrxAfcApp_Init(void)
{
    DrxAfc_Init(&g_afc, escribe_pinc, NULL, DrxReg_ReadNcoPinc());
}

drx_dsp_error_t DrxAfcApp_Apply(const drx_dsp_afc_t *afc, void *user)
{
    (void)user;
    /* El `ray_index` del ultimo rayo entregado es lo que `apply_at_seq`
     * compara. Se lee aqui y no se guarda: el plano de control corre en otra
     * tarea que el ensamblado de rayos, y un valor copiado se queda viejo. */
    return DrxAfc_Submit(&g_afc, afc, DrxRay_LastIndex());
}

void DrxAfcApp_OnRay(uint32_t ray_index)
{
    (void)DrxAfc_OnRay(&g_afc, ray_index);
}

uint32_t DrxAfcApp_LastPinc(void)
{
    return DrxAfc_LastPinc(&g_afc);
}

/* --- autoprueba de arranque ------------------------------------------------
 *
 * Manda el mensaje por el PARSER, no llamando a `DrxAfcApp_Apply` a pelo: lo
 * que interesa comprobar en placa es el camino entero -- bytes -> cabecera ->
 * despacho -> registro -> canal S_AXIS_CONFIG del DDS Compiler -- que es por
 * donde entrara el `afc` del DSP de verdad.
 *
 * Lo que esto NO prueba: que el NCO mezcle de verdad a la frecuencia nueva. Eso
 * se ve en el espectro de un rayo (`tools/dump_ray.py`), no en un registro. */
static DrxControl g_ctl;
static DrxParser g_parser;
static uint8_t g_parse_buf[64];

static size_t descarta(const uint8_t *frame, size_t len, void *user)
{
    (void)frame;
    (void)user;
    return len; /* `afc` no se contesta; nada que entregar */
}

static bool empuja_afc(uint64_t pinc, uint32_t apply_at_seq)
{
    drx_dsp_afc_t msg = {0};
    uint8_t wire[64];

    msg.nco_phase_inc = pinc;
    msg.apply_at_seq = apply_at_seq;

    size_t len = DrxFrame_Encode(wire, sizeof(wire), DRX_DSP_MSG_AFC, &msg,
                                 sizeof(msg), NULL, 0u);
    if (len == 0u) {
        return false;
    }
    return DrxParser_Push(&g_parser, wire, len, DrxControl_OnMessage, &g_ctl) == len;
}

bool DrxAfcApp_SelfTest(void)
{
    DrxControlOps ops = {
        .select_stimulus = NULL,
        .apply_config = NULL,
        .apply_afc = DrxAfcApp_Apply,
        .user = NULL,
    };

    DrxControl_Init(&g_ctl, &ops, descarta, NULL);
    DrxParser_Init(&g_parser, g_parse_buf, sizeof(g_parse_buf));

    const uint32_t original = DrxReg_ReadNcoPinc();
    /* Un desplazamiento claramente visible y claramente dentro de rango. No es
     * una frecuencia: es una palabra de fase, y lo unico que importa aqui es
     * que no se parezca a la de partida. */
    const uint32_t retune = original + 0x00200000u;

    bool ok = true;

    if (!empuja_afc(retune, 0u)) {
        xil_printf("drx_afc: el parser no acepto la trama `afc`\r\n");
        return false;
    }

    uint32_t leido = DrxReg_ReadNcoPinc();
    if (leido != retune) {
        xil_printf("drx_afc: NCO_PINC quedo en %lu, se pidio %lu\r\n",
                   (unsigned long)leido, (unsigned long)retune);
        ok = false;
    }

    /* Fuera de rango: tiene que dejar el registro donde estaba. */
    if (!empuja_afc(0x100000000ull, 0u)) {
        xil_printf("drx_afc: el parser no acepto la trama fuera de rango\r\n");
        ok = false;
    }
    if (DrxReg_ReadNcoPinc() != retune) {
        xil_printf("drx_afc: una palabra fuera de rango movio NCO_PINC\r\n");
        ok = false;
    }

    /* Y se deja el NCO donde estaba: el resto de las medidas de arranque dan
     * por buena la frecuencia de mezcla nominal. */
    DrxReg_WriteNcoPinc(original);
    if (DrxReg_ReadNcoPinc() != original) {
        xil_printf("drx_afc: no se pudo restaurar NCO_PINC\r\n");
        ok = false;
    }

    /* El rechazo por rango acaba de dejar `last_error` puesto en este plano de
     * control. Engancharlo aqui es lo que hace que ese codigo salga en la linea
     * de `status` de la tarea de diagnostico en vez de morir en una variable
     * local -- es el camino que Z4.6 usara con el control del socket. */
    DrxStatusTask_AttachControl(&g_ctl);

    xil_printf("drx_afc: actuacion AFC %s (NCO_PINC %lu -> %lu -> %lu)\r\n",
               ok ? "OK" : "FALLO", (unsigned long)original,
               (unsigned long)retune, (unsigned long)DrxReg_ReadNcoPinc());
    return ok;
}

/* --- A/B espectral del retune ----------------------------------------------
 *
 * Ver la cabecera para por que los dos lados salen del mismo arranque.
 */
#include "FreeRTOS.h"
#include "task.h"

bool DrxAfcApp_RetuneAB(uint32_t pinc, uint32_t hold_ms)
{
    const uint32_t original = DrxReg_ReadNcoPinc();

    xil_printf("drx_afc: A/B del retune -- lado A (NCO_PINC %lu) congelado, "
               "%lu ms para leerlo por JTAG\r\n",
               (unsigned long)original, (unsigned long)hold_ms);
    vTaskDelay(pdMS_TO_TICKS(hold_ms));

    DrxRay_Thaw();
    DrxReg_WriteNcoPinc(pinc);
    if (DrxReg_ReadNcoPinc() != pinc) {
        xil_printf("drx_afc: A/B abortado, NCO_PINC no acepto %lu\r\n",
                   (unsigned long)pinc);
        return false;
    }

    /* El anillo tiene que dar la vuelta entera antes de congelar: un buffer a
     * medio escribir cuando se solto el `Thaw` lleva muestras de las dos
     * palabras de fase, y ese rayo no es ni A ni B. */
    vTaskDelay(pdMS_TO_TICKS(500));

    if (!DrxRay_Freeze()) {
        xil_printf("drx_afc: A/B abortado, no se pudo congelar el lado B\r\n");
        return false;
    }
    vTaskDelay(pdMS_TO_TICKS(100));

    xil_printf("drx_afc: A/B del retune -- lado B (NCO_PINC %lu)\r\n",
               (unsigned long)pinc);
    DrxRay_DumpLast(0u);
    return true;
}
