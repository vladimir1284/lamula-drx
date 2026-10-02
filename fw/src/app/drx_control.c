/* Implementacion de fw/include/drx_control.h.
 *
 * Sin dependencias de Xilinx ni de FreeRTOS: se compila tambien para el host
 * (fw/Makefile) y ahi lo ejercita fw/tests/test_control.py contra la
 * implementacion de Python del contrato. Ver la cabecera.
 */
#include "drx_control.h"

#include <string.h>

void DrxControl_Init(DrxControl *ctl, const DrxControlOps *ops,
                     DrxControlSend send, void *send_user)
{
    memset(ctl, 0, sizeof(*ctl));
    ctl->ops = *ops;
    ctl->send = send;
    ctl->send_user = send_user;
}

static void reply_config_ack(DrxControl *ctl, uint32_t seq, drx_dsp_error_t error)
{
    /* Cabecera + el struct mas grande que este fichero llega a emitir. Local y
     * no estatico: este callback corre desde la tarea que empuja los bytes del
     * socket, y un buffer compartido seria un dato en comun entre dos tareas
     * sin ningun candado. Son 20 bytes de pila. */
    uint8_t frame[DRX_FRAME_HEADER_SIZE + sizeof(drx_dsp_config_ack_t)];
    drx_dsp_config_ack_t ack;

    memset(&ack, 0, sizeof(ack));
    ack.seq = seq;
    ack.error = (uint8_t)error;

    size_t n = DrxFrame_Encode(frame, sizeof(frame), DRX_DSP_MSG_CONFIG_ACK, &ack,
                               sizeof(ack), NULL, 0);
    if (n == 0u || ctl->send == NULL) {
        ctl->send_fails++;
        return;
    }
    if (ctl->send(frame, n, ctl->send_user) != n) {
        ctl->send_fails++;
        return;
    }
    ctl->replied++;
}

void DrxControl_OnMessage(const drx_dsp_header_t *header, const uint8_t *body,
                          uint32_t body_len, void *user)
{
    DrxControl *ctl = (DrxControl *)user;

    ctl->handled++;

    switch (header->msg_type) {
    case DRX_DSP_MSG_TEST_STIMULUS_SELECT: {
        drx_dsp_test_stimulus_select_t msg;

        /* `body_len` ya lo valido el framer contra el tamano del struct, asi
         * que esto no puede quedarse corto. Se comprueba igual: una copia de
         * mas bytes de los que hay es el tipo de fallo que no se ve hasta que
         * corrompe otra cosa. */
        if (body_len < sizeof(msg)) {
            reply_config_ack(ctl, 0u, DRX_DSP_ERROR_BAD_LENGTH);
            return;
        }
        memcpy(&msg, body, sizeof(msg));

        drx_dsp_error_t error =
            (ctl->ops.select_stimulus == NULL)
                ? DRX_DSP_ERROR_UNIMPLEMENTED
                : ctl->ops.select_stimulus(msg.vector_id, msg.repeat, ctl->ops.user);
        reply_config_ack(ctl, msg.seq, error);
        return;
    }

    case DRX_DSP_MSG_CONFIG: {
        drx_dsp_config_t msg;

        if (body_len < sizeof(msg)) {
            reply_config_ack(ctl, 0u, DRX_DSP_ERROR_BAD_LENGTH);
            return;
        }
        memcpy(&msg, body, sizeof(msg));

        drx_dsp_error_t error = (ctl->ops.apply_config == NULL)
                                    ? DRX_DSP_ERROR_UNIMPLEMENTED
                                    : ctl->ops.apply_config(&msg, ctl->ops.user);
        reply_config_ack(ctl, msg.seq, error);
        return;
    }

    case DRX_DSP_MSG_AFC: {
        drx_dsp_afc_t msg;

        if (body_len < sizeof(msg)) {
            return; /* `afc` no lleva `seq`: no hay a que contestar */
        }
        memcpy(&msg, body, sizeof(msg));

        if (ctl->ops.apply_afc != NULL) {
            (void)ctl->ops.apply_afc(&msg, ctl->ops.user);
        }
        return;
    }

    default:
        /* El framer no entrega tipos que no sean "down" y conocidos, asi que
         * llegar aqui significaria que las dos tablas se desincronizaron. No
         * se contesta: no hay `seq` del que fiarse. */
        return;
    }
}
