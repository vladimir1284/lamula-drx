/* Arnes de host para fw/src/app/drx_afc.c.
 *
 * Imprime el resultado de cada paso como `clave=valor`; el test de Python
 * comprueba los valores contra el esquema generado. Lo que de verdad se
 * ejercita aqui no es la escritura (eso es un puntero a funcion) sino CUANDO se
 * escribe: aplazar hasta `apply_at_seq`, no truncar una palabra de fase que no
 * cabe, y no quedarse colgado cuando el contador de rayos envuelve.
 */
#include "drx_afc.h"
#include "drx_params.h"

#include <stdio.h>

static uint32_t g_escrito;
static uint32_t g_escrituras;

static void captura(uint32_t pinc, void *user)
{
    (void)user;
    g_escrito = pinc;
    g_escrituras++;
}

/* El valor de reset de NCO_PINC sale del paquete de parametros generado, no de
 * un literal: `tools/check_hardcoded_clock.py` lo exige y tiene razon -- este
 * numero cambia con `fs`. */
#define RESET_PINC ((uint32_t)DRX_NCO_PHASE_INC)

static void arranca(DrxAfc *afc)
{
    g_escrito = 0u;
    g_escrituras = 0u;
    DrxAfc_Init(afc, captura, NULL, RESET_PINC);
}

int main(void)
{
    DrxAfc afc;
    drx_dsp_afc_t msg = {0};

    /* 1. `apply_at_seq = 0` es "ya". */
    arranca(&afc);
    msg.nco_phase_inc = 0x12345678u;
    msg.apply_at_seq = 0u;
    printf("inmediato_error=%d\n", (int)DrxAfc_Submit(&afc, &msg, 7u));
    printf("inmediato_escrituras=%u\n", g_escrituras);
    printf("inmediato_pinc=%u\n", g_escrito);

    /* 2. Aplazada: no se escribe hasta que el rayo alcanza `apply_at_seq`. */
    arranca(&afc);
    msg.nco_phase_inc = 0xAABBCCDDu;
    msg.apply_at_seq = 5u;
    printf("aplazado_error=%d\n", (int)DrxAfc_Submit(&afc, &msg, 2u));
    printf("aplazado_escrituras_tras_submit=%u\n", g_escrituras);
    printf("aplazado_ray3=%d\n", (int)DrxAfc_OnRay(&afc, 3u));
    printf("aplazado_ray4=%d\n", (int)DrxAfc_OnRay(&afc, 4u));
    printf("aplazado_ray5=%d\n", (int)DrxAfc_OnRay(&afc, 5u));
    printf("aplazado_escrituras=%u\n", g_escrituras);
    printf("aplazado_pinc=%u\n", g_escrito);
    printf("aplazado_ray6=%d\n", (int)DrxAfc_OnRay(&afc, 6u));
    printf("aplazado_escrituras_final=%u\n", g_escrituras);

    /* 3. Fuera de rango: ni se trunca ni se escribe. */
    arranca(&afc);
    msg.nco_phase_inc = 0x100000000ull;
    msg.apply_at_seq = 0u;
    printf("rango_error=%d\n", (int)DrxAfc_Submit(&afc, &msg, 0u));
    printf("rango_escrituras=%u\n", g_escrituras);
    printf("rango_last_pinc=%u\n", DrxAfc_LastPinc(&afc));
    printf("rango_rechazadas=%u\n", afc.rejected);

    /* 4. El contador de rayos envuelve entre el mensaje y su rayo. Con una
     * comparacion `>=` plana esto se aplicaria de inmediato (0xFFFFFFFF >= 1) y
     * la correccion caeria en el rayo equivocado. */
    arranca(&afc);
    msg.nco_phase_inc = 0x00FF00FFu;
    msg.apply_at_seq = 1u;
    printf("envuelve_error=%d\n", (int)DrxAfc_Submit(&afc, &msg, 0xFFFFFFFFu));
    printf("envuelve_escrituras_tras_submit=%u\n", g_escrituras);
    printf("envuelve_ray0=%d\n", (int)DrxAfc_OnRay(&afc, 0u));
    printf("envuelve_ray1=%d\n", (int)DrxAfc_OnRay(&afc, 1u));
    printf("envuelve_pinc=%u\n", g_escrito);

    /* 5. Una correccion nueva sustituye a la que esperaba. */
    arranca(&afc);
    msg.nco_phase_inc = 0x11111111u;
    msg.apply_at_seq = 10u;
    (void)DrxAfc_Submit(&afc, &msg, 0u);
    msg.nco_phase_inc = 0x22222222u;
    msg.apply_at_seq = 10u;
    (void)DrxAfc_Submit(&afc, &msg, 0u);
    printf("sustituye_ray10=%d\n", (int)DrxAfc_OnRay(&afc, 10u));
    printf("sustituye_pinc=%u\n", g_escrito);
    printf("sustituye_escrituras=%u\n", g_escrituras);
    printf("sustituye_aplazadas=%u\n", afc.deferred);

    return 0;
}
