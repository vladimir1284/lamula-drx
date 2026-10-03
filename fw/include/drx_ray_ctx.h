/* Lo que un rayo no sabe de si mismo, en un solo sitio (Z4.6).
 *
 * `DrxRayFrame_Encode` necesita un `DrxRayContext`: la configuracion de timing
 * vigente, la mascara de canales, el instante y las banderas de diagnostico.
 * Nada de eso esta en el rayo que sale del DMA.
 *
 * Vive aparte porque hay DOS productores de tramas `ray` --la autoprueba de
 * arranque (`drx_control_boot.c`) y el transporte (`drx_transport.c`)-- y el
 * contenido tiene detalles que no se adivinan: el contrato quiere el INDICE
 * del ancho de pulso y `DrxTimingConfig` guarda CICLOS, y el instante se
 * deriva de `trig_count` y `DRX_FS_HZ` porque no hay reloj de pared. Con dos
 * copias, la que se usa menos se queda vieja sin que nada lo diga.
 */
#ifndef DRX_RAY_CTX_H
#define DRX_RAY_CTX_H

#include "drx_ray.h"
#include "drx_ray_frame.h"

/* Rellena `out` para el rayo que describe `header`. Lee los registros de
 * diagnostico (OVERFLOW, GATE_TRUNCATED), asi que necesita hardware. */
void DrxRayCtx_Fill(DrxRayContext *out, const DrxRayHeader *header);

#endif /* DRX_RAY_CTX_H */
