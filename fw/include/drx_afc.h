/* Actuacion AFC (Z4.5): aplicar al NCO la palabra de fase que calcula el DSP.
 *
 * Hasta v8 del mapa de registros esto era IMPOSIBLE, y no por falta de
 * firmware: el incremento de fase vivia congelado en la personalizacion de la
 * IP del DDS Compiler (`Phase_Increment {Fixed}`), sin ningun puerto por el que
 * cambiarlo. Z4.5 regenera esa IP con `{Programmable}` y anade el registro
 * NCO_PINC (v9); este fichero es el unico escritor de ese registro.
 *
 * Como `drx_contract_io.c` y `drx_control.c`, NO depende de Xilinx ni de
 * FreeRTOS: la escritura entra por un puntero a funcion. El firmware le pasa la
 * de verdad (`DrxReg_WriteNcoPinc`), `fw/tests/test_afc.py` le pasa una falsa y
 * comprueba la logica de aplazamiento y de rango sin placa de por medio.
 *
 * `apply_at_seq` del mensaje `afc` no es decorativo: la correccion se aplica
 * ENTRE rayos, nunca dentro de uno. El salto de palabra de fase no conserva la
 * fase del acumulador (el DDS Compiler sigue desde donde estaba con el
 * incremento nuevo), asi que aplicarlo a mitad de rayo dejaria ese rayo con dos
 * frecuencias de mezcla. Es el mismo criterio que `mode_coarse` y por el mismo
 * motivo.
 */
#ifndef DRX_AFC_H
#define DRX_AFC_H

#include <stdbool.h>
#include <stdint.h>

#include "drx_dsp_v0_1.h"

/* Escribe la palabra de fase en el hardware. En el firmware esto es
 * `DrxReg_WriteNcoPinc`; en los tests, un buffer. */
typedef void (*DrxAfc_Write)(uint32_t nco_pinc, void *user);

typedef struct {
    DrxAfc_Write write;
    void *user;

    bool pending;            /* hay una correccion esperando su rayo */
    uint32_t pending_pinc;   /* palabra de fase que espera */
    uint32_t pending_at_seq; /* primer `ray_index` en el que aplicarla */

    uint32_t applied;  /* correcciones escritas al NCO */
    uint32_t deferred; /* correcciones que quedaron en espera al llegar */
    uint32_t rejected; /* correcciones descartadas por rango */
    uint32_t last_pinc; /* ultima palabra escrita; valor de reset al arrancar */
} DrxAfc;

/* `reset_pinc` es el valor con el que arranca el registro NCO_PINC
 * (DRX_NCO_PHASE_INC): no se escribe nada al inicializar, solo se recuerda para
 * que `DrxAfc_LastPinc` diga la verdad antes de la primera correccion. */
void DrxAfc_Init(DrxAfc *afc, DrxAfc_Write write, void *user, uint32_t reset_pinc);

/* Procesa un mensaje `afc` recien llegado. `current_seq` es el `ray_index` del
 * ultimo rayo emitido (0 si todavia no hay ninguno).
 *
 * Devuelve el codigo del contrato: `ok` si se aplico o quedo en espera,
 * `afc_out_of_range` si `nco_phase_inc` no cabe en los NCO_PHASE_BITS = 32 bits
 * del acumulador de fase. El mensaje `afc` no lleva `seq` y por tanto no se
 * contesta -- el codigo viaja en `last_error` del mensaje `status`, que es donde
 * el par remoto puede verlo. */
drx_dsp_error_t DrxAfc_Submit(DrxAfc *afc, const drx_dsp_afc_t *msg,
                              uint32_t current_seq);

/* Llamar una vez por rayo emitido, con su `ray_index`. Aplica la correccion en
 * espera en cuanto `seq` alcanza `apply_at_seq`. Devuelve true si escribio. */
bool DrxAfc_OnRay(DrxAfc *afc, uint32_t seq);

uint32_t DrxAfc_LastPinc(const DrxAfc *afc);

#endif /* DRX_AFC_H */
