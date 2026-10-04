/* Instancia unica del AXI DMA (Z4.4).
 *
 * Hoy solo hay un canal, S2MM (camino de rayos, drx_ray.c): el MM2S salio del
 * block design el 4-oct-2026 junto con el modo Throttled(DDR) del estimulo.
 *
 * La instancia compartida se conserva igualmente, y no por simetria:
 * `XAxiDma_CfgInitialize` llama a `XAxiDma_Reset`, que resetea el PERIFERICO
 * entero, no el canal. Con un `XAxiDma` por fichero, el dia que vuelva a
 * haber dos consumidores el segundo en arrancar tiraria abajo el anillo de
 * descriptores del primero, y el sintoma seria que el primero se queda mudo
 * sin ningun error. Es una trampa que ya costo encontrarla una vez.
 */
#ifndef DRX_DMA_H
#define DRX_DMA_H

#include <stdbool.h>

#include "xaxidma.h"

/* Idempotente: la primera llamada inicializa, las siguientes solo confirman.
 * Devuelve false y lo explica por UART si el XSA no declara el DMA, si la
 * inicializacion falla o si el DMA no esta en modo scatter-gather. */
bool DrxDma_Init(void);

/* NULL mientras `DrxDma_Init()` no haya devuelto true. */
XAxiDma *DrxDma_Get(void);

#endif /* DRX_DMA_H */
