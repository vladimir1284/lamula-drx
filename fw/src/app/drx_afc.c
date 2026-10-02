/* Implementacion de fw/include/drx_afc.h. */
#include "drx_afc.h"

#include <string.h>

/* NCO_PHASE_BITS = 32 (config/params.toml, via rtl/generated/drx_params_pkg.sv
 * y fw/include/drx_params.h). El contrato manda `nco_phase_inc` como u64 a
 * proposito -- la ZU9 podria tener un acumulador mas ancho sin cambiar el
 * esquema-- asi que aqui hay que comprobar el rango, no truncar en silencio:
 * truncar convertiria una correccion de AFC equivocada en una frecuencia de
 * mezcla equivocada, sin ningun sintoma hasta que alguien mirara el espectro. */
#define DRX_AFC_PINC_MAX 0xFFFFFFFFull

static void afc_write(DrxAfc *afc, uint32_t pinc)
{
    afc->last_pinc = pinc;
    afc->applied++;
    if (afc->write != NULL) {
        afc->write(pinc, afc->user);
    }
}

void DrxAfc_Init(DrxAfc *afc, DrxAfc_Write write, void *user, uint32_t reset_pinc)
{
    memset(afc, 0, sizeof(*afc));
    afc->write = write;
    afc->user = user;
    afc->last_pinc = reset_pinc;
}

drx_dsp_error_t DrxAfc_Submit(DrxAfc *afc, const drx_dsp_afc_t *msg,
                              uint32_t current_seq)
{
    if (msg->nco_phase_inc > DRX_AFC_PINC_MAX) {
        afc->rejected++;
        return DRX_DSP_ERROR_AFC_OUT_OF_RANGE;
    }

    uint32_t pinc = (uint32_t)msg->nco_phase_inc;

    /* `apply_at_seq = 0` es "ya" por esquema. Para cualquier otro valor se
     * compara con diferencia CON SIGNO, no con `>=`: `ray_index` envuelve en
     * 2^32 y un `>=` plano dejaria una correccion colgada media eternidad cada
     * vez que el contador diera la vuelta entre el mensaje y su rayo. */
    if (msg->apply_at_seq == 0u ||
        (int32_t)(current_seq - msg->apply_at_seq) >= 0) {
        afc->pending = false;
        afc_write(afc, pinc);
        return DRX_DSP_ERROR_OK;
    }

    /* Una correccion nueva sustituye a la que estuviera esperando: la ultima
     * que manda el DSP es la que vale, y aplicar las dos en orden solo gastaria
     * un salto de frecuencia de mas. */
    afc->pending = true;
    afc->pending_pinc = pinc;
    afc->pending_at_seq = msg->apply_at_seq;
    afc->deferred++;
    return DRX_DSP_ERROR_OK;
}

bool DrxAfc_OnRay(DrxAfc *afc, uint32_t seq)
{
    if (!afc->pending) {
        return false;
    }
    if ((int32_t)(seq - afc->pending_at_seq) < 0) {
        return false;
    }

    afc->pending = false;
    afc_write(afc, afc->pending_pinc);
    return true;
}

uint32_t DrxAfc_LastPinc(const DrxAfc *afc)
{
    return afc->last_pinc;
}
