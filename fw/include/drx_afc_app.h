/* Pegamento entre `drx_afc.c` (logica pura, sin Xilinx) y el hardware (Z4.5).
 *
 * Mismo reparto que `drx_regs.h` / `drx_regs_hw.h`: lo que se puede probar en
 * el host vive en `drx_afc.c` y se ejercita con `fw/tests/test_afc.py`; lo que
 * necesita una placa -- escribir NCO_PINC por AXI-Lite -- vive aqui.
 *
 * Es un singleton a proposito: hay UN NCO por canal pero una sola palabra de
 * fase para todos (los N_CH ven el mismo IF), asi que no hay nada que
 * parametrizar y un estado global evita pasar un puntero por media docena de
 * capas hasta la interrupcion del S2MM.
 */
#ifndef DRX_AFC_APP_H
#define DRX_AFC_APP_H

#include <stdbool.h>
#include <stdint.h>

#include "drx_dsp_v0_1.h"

/* Una vez, al arrancar. Lee el valor actual de NCO_PINC como punto de partida
 * en vez de dar por supuesto el de reset: si alguien ya lo movio (una sesion de
 * JTAG, por ejemplo), lo que diga `DrxAfcApp_LastPinc` sigue siendo cierto. */
void DrxAfcApp_Init(void);

/* Despacho del mensaje `afc` del contrato. Encaja con `DrxControlOps.apply_afc`. */
drx_dsp_error_t DrxAfcApp_Apply(const drx_dsp_afc_t *afc, void *user);

/* Una vez por rayo entregado, con su `ray_index`. Aplica la correccion que
 * estuviera esperando su rayo. */
void DrxAfcApp_OnRay(uint32_t ray_index);

uint32_t DrxAfcApp_LastPinc(void);

/* Autoprueba de arranque, contra hardware real: manda un `afc` sintetico por el
 * mismo camino por el que entrara el del DSP y comprueba que NCO_PINC cambia,
 * que una palabra fuera de rango NO lo cambia, y deja el registro como estaba.
 * Imprime el resultado por UART. */
bool DrxAfcApp_SelfTest(void);

/* A/B espectral del retune, en placa (Z4.5). `DrxAfcApp_SelfTest` prueba que
 * NCO_PINC cambia; esto prueba que el NCO MEZCLA a la frecuencia nueva, que es
 * otra pregunta y solo se contesta mirando el espectro de un rayo.
 *
 * Secuencia: espera `hold_ms` con el rayo nominal todavia congelado --ese es el
 * lado A, y el hueco existe para que `tools/dump_ray.py` lo lea por JTAG antes
 * de que el buffer vuelva al anillo--, descongela, escribe `pinc`, deja pasar
 * rayos con la palabra nueva y congela otro, que es el lado B. Imprime la
 * direccion de los dos y deja el NCO retuneado: restaurarlo aqui no cambiaria
 * el buffer ya congelado y solo serviria para confundir la lectura.
 *
 * Los dos lados salen del MISMO arranque a proposito. Medirlos en arranques
 * distintos obligaria a dar por supuesto que nada mas cambio entre los dos.
 *
 * Devuelve false si no se pudo congelar el segundo rayo. */
bool DrxAfcApp_RetuneAB(uint32_t pinc, uint32_t hold_ms);

#endif /* DRX_AFC_APP_H */
