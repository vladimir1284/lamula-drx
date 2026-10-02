/* Mensaje `status` del contrato DRx<->DSP: status y BITE (Z4.5).
 *
 * El esquema congelo este mensaje en Z0 y hasta ahora nadie lo montaba. Aqui se
 * monta, con el MISMO criterio que `drx_ray_frame.c`: el fichero no depende de
 * Xilinx ni de FreeRTOS, se compila tambien para el host y se contrasta byte a
 * byte contra la implementacion de Python generada del mismo esquema
 * (`fw/tests/test_status_frame.py`). Quien sabe de registros es el llamador.
 *
 * Las banderas de BITE salen del catalogo `bite_flag` del esquema, que a su vez
 * sale del plan de testing. NO todas tienen fuente hoy, y eso se dice aqui en
 * vez de rellenarlas con ceros silenciosos:
 *
 *   ssa_underrun     SI  -- `vector_source` en Throttled(DDR) sin datos a tiempo
 *                           lo cuenta el firmware del lado del MM2S.
 *   dma_overrun      SI  -- STATUS(overrun) del range-gate + descriptores S2MM
 *                           fallidos (DrxRayStatus).
 *   ssi_timeout      NO  -- los lectores SSI son Z3; no existen todavia.
 *   ssi_frame_error  NO  -- idem.
 *   mmcm_unlocked    NO  -- el `locked` del MMCM no llega al mapa de registros;
 *                           haria falta un bit nuevo en STATUS. Anotado, no
 *                           inventado: hoy siempre se reporta a cero.
 *   link_down        SI  -- lo sabe lwIP, y el transporte es Z4.6; hasta
 *                           entonces el llamador pasa `false`.
 *   config_rejected  SI  -- cualquier rechazo del plano de control (D-09
 *                           incluido) o una correccion de AFC fuera de rango.
 */
#ifndef DRX_STATUS_FRAME_H
#define DRX_STATUS_FRAME_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "drx_dsp_v0_1.h"

typedef struct {
    uint32_t uptime_s;
    uint32_t ssa_underruns;
    uint32_t dma_overruns;
    uint32_t ssi_errors;
    uint32_t ddc_overflows;
    uint32_t config_rejects;
    uint8_t last_error; /* ultimo codigo de error del plano de control */
    bool link_down;
    bool mmcm_unlocked;
} DrxStatusInputs;

/* Banderas de BITE segun el catalogo `bite_flag`. Un contador a cero no levanta
 * su bandera; cualquier valor distinto de cero si. Los contadores son
 * acumulados desde el arranque, asi que la bandera queda en alto desde el
 * primer fallo -- es un BITE, no un estado instantaneo. */
uint32_t DrxStatus_BiteFlags(const DrxStatusInputs *in);

void DrxStatus_Fill(drx_dsp_status_t *out, const DrxStatusInputs *in);

/* Monta la trama completa (cabecera + cuerpo). Devuelve los bytes escritos, o 0
 * si no caben en `cap`. */
size_t DrxStatus_Encode(uint8_t *out, size_t cap, const DrxStatusInputs *in);

#endif /* DRX_STATUS_FRAME_H */
