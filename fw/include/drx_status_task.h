/* Tarea de bring-up de Z4.2, ampliada en Z4.5 a status/BITE del contrato.
 *
 * Sondea el mapa de registros de drx_top (STATUS/OVERFLOW/GATE_TRUNCATED/
 * TIMING_STATUS/TRIG_COUNT) sobre UART y limpia los bits sticky que
 * encuentra activos. Desde Z4.5 ademas ACUMULA lo que lee en los contadores
 * del mensaje `status` del contrato y monta la trama con
 * `drx_status_frame.c` -- la misma que saldra por el socket cuando Z4.6 traiga
 * el transporte. Hasta entonces se imprime por UART: montar la trama es lo que
 * de verdad hay que verificar, mandarla es un `write` mas.
 *
 * Los registros sticky son la razon de que esto viva aqui y no en el emisor:
 * son write-1-to-clear, asi que LEERLOS Y LIMPIARLOS es destructivo y solo
 * puede hacerlo un sitio. Si el emisor los leyera por su cuenta, los dos se
 * robarian eventos.
 */
#ifndef DRX_STATUS_TASK_H
#define DRX_STATUS_TASK_H

#include <stdint.h>

#include "drx_control.h"
#include "drx_status_frame.h"

/* Crea la tarea de FreeRTOS. Debe llamarse antes de vTaskStartScheduler();
 * no depende de que lwIP/la red esten arriba. */
void DrxStatusTask_Create(void);

/* Engancha el plano de control del que salen `last_error` y la bandera
 * `config_rejected`. NULL (el valor por defecto) deja los dos a cero. Z4.6 le
 * pasara el que atiende el socket; el bring-up le pasa el suyo. */
void DrxStatusTask_AttachControl(DrxControl *ctl);

/* Instantanea de los contadores del mensaje `status`, tal como los lleva la
 * tarea. Para la autoprueba de arranque y para quien tenga que emitirlo. */
void DrxStatusTask_GetInputs(DrxStatusInputs *out);

#endif /* DRX_STATUS_TASK_H */
