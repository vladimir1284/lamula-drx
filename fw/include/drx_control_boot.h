/* Ejercicio de arranque del plano de control contra el contrato (Z4.4).
 *
 * El plano de control (drx_control.c) y el framer (drx_contract_io.c) existen
 * desde Z4.3 y se contrastan contra la implementacion de Python generada del
 * mismo esquema, pero eso corre en el HOST. En la placa no habia forma de
 * ejercitarlos: el transporte TCP es Z4.6 y hasta entonces no hay nadie al
 * otro lado del cable.
 *
 * Esto cierra ese hueco sin inventar un transporte: monta una trama `config`
 * de 2 lotes con el mismo codificador que usara el cable, la empuja por el
 * mismo parser, y comprueba que el `config_ack` que sale lleva el `seq`
 * original y que los registros del motor de timing CAMBIARON de verdad. Lo
 * que no cubre es el socket; todo lo demas del camino es el mismo codigo.
 */
#ifndef DRX_CONTROL_BOOT_H
#define DRX_CONTROL_BOOT_H

#include <stdbool.h>

/* Corre el ejercicio y deja el motor con la configuracion de bring-up de
 * DrxTiming_Start(). Devuelve true si las tres comprobaciones pasaron. */
bool DrxControlBoot_SelfTest(void);

#endif /* DRX_CONTROL_BOOT_H */
