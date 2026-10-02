/* Instancia unica del AXI DMA, compartida por sus dos canales (Z4.4).
 *
 * Existe por un motivo concreto y no por simetria: `XAxiDma_CfgInitialize`
 * llama a `XAxiDma_Reset`, que resetea el PERIFERICO entero, no el canal.
 * Con un `XAxiDma` por fichero, inicializar el camino de rayos (S2MM,
 * drx_ray.c) tiraria abajo el anillo de descriptores que el camino de
 * estimulo (MM2S, drx_stimulus.c) ya tuviera en marcha, y al reves. El
 * sintoma seria que el segundo en arrancar funciona y el primero se queda
 * mudo, sin ningun error.
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
