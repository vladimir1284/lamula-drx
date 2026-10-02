/* Plano de control: qué hace el DRx con cada mensaje que le llega (Z4.3).
 *
 * Es el consumidor de `drx_contract_io.h`. La division del trabajo entre los
 * dos es deliberada: el framer sabe de BYTES (donde empieza y acaba un mensaje,
 * si la cabecera cuadra) y este sabe de SIGNIFICADO (que hacer con un
 * `test_stimulus_select`, con que contestar). Ninguno de los dos sabe de
 * sockets.
 *
 * Y, como el framer, este fichero NO depende de Xilinx ni de FreeRTOS: las
 * acciones entran por una tabla de punteros (`DrxControlOps`). El firmware le
 * pasa las de verdad; `fw/tests/test_control.py` le pasa unas falsas y
 * comprueba el despacho y las respuestas contra la implementacion de Python
 * del contrato, sin placa de por medio. Si alguien mete aqui un `Xil_Out32`,
 * esa comprobacion desaparece.
 */
#ifndef DRX_CONTROL_H
#define DRX_CONTROL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "drx_contract_io.h"

/* Acciones que el plano de control necesita del resto del firmware. Un puntero
 * a NULL significa "esta funcion todavia no existe en este receptor", y el
 * mensaje correspondiente se contesta con `unimplemented` -- que es distinto de
 * `unknown_message`: el par remoto sabe que hablan la misma version y que la
 * funcion aun no esta. */
typedef struct {
    /* Devuelve el codigo del contrato con el que contestar. */
    drx_dsp_error_t (*select_stimulus)(uint8_t vector_id, uint16_t repeat,
                                       void *user);
    drx_dsp_error_t (*apply_config)(const drx_dsp_config_t *config, void *user);
    drx_dsp_error_t (*apply_afc)(const drx_dsp_afc_t *afc, void *user);
    void *user;
} DrxControlOps;

/* Entrega un marco de respuesta ya formado. Devuelve los bytes aceptados; el
 * plano de control cuenta como fallo cualquier cosa distinta de `len`. En el
 * firmware esto escribe en el socket TCP; en los tests, en un buffer. */
typedef size_t (*DrxControlSend)(const uint8_t *frame, size_t len, void *user);

typedef struct {
    DrxControlOps ops;
    DrxControlSend send;
    void *send_user;
    uint32_t handled;    /* mensajes despachados */
    uint32_t replied;    /* respuestas entregadas */
    uint32_t send_fails; /* respuestas que el transporte no acepto entera */
} DrxControl;

void DrxControl_Init(DrxControl *ctl, const DrxControlOps *ops,
                     DrxControlSend send, void *send_user);

/* Callback para DrxParser_Push: `user` tiene que ser el DrxControl.
 *
 * Contesta SIEMPRE que el mensaje lleve `seq` -- `config` y
 * `test_stimulus_select` lo llevan, y el esquema dice que los dos se responden
 * con `config_ack`. `afc` no lo lleva y no se contesta: es una correccion que
 * se aplica o no, y el DSP se entera por el flujo de rayos. */
void DrxControl_OnMessage(const drx_dsp_header_t *header, const uint8_t *body,
                          uint32_t body_len, void *user);

#endif /* DRX_CONTROL_H */
