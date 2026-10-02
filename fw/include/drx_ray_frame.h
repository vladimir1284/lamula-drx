/* Monta la trama `ray` del contrato a partir de un rayo de la DDR (Z4.4).
 *
 * Separado de drx_ray.c y SIN dependencias de Xilinx ni de FreeRTOS, por el
 * mismo motivo que drx_contract_io.c: asi este fichero —el que decide el
 * formato de cable— se compila tambien para el host y se contrasta contra la
 * implementacion de Python generada del mismo esquema, sin placa de por medio.
 *
 * El detalle que mas facil es equivocar, y por eso vive aqui con su test: el
 * buffer de la DDR trae palabras de 32 bits {I[31:16], Q[15:0]}, que en
 * memoria little-endian son Q_lo Q_hi I_lo I_hi. El contrato pide los pares en
 * orden I,Q. Copiar la palabra tal cual produciria una trama que PARSEA sin
 * error y que lleva I y Q cambiados en todos los bins -- un fallo que en el
 * DSP se ve como un espectro reflejado, sin ninguna pista de donde viene.
 */
#ifndef DRX_RAY_FRAME_H
#define DRX_RAY_FRAME_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "drx_dsp_v0_1.h"
#include "drx_ray.h"

/* Lo que el rayo no sabe de si mismo y hay que decirle: sale de la ultima
 * configuracion aplicada (`config` del contrato, o la de bring-up) y del
 * cableado del frontal. */
typedef struct {
    uint32_t prf_div_low;
    uint32_t prf_div_high;
    uint8_t pulse_width_idx_low;
    uint8_t pulse_width_idx_high;
    uint8_t pulse_mode;
    uint8_t channel_mask;
    /* Encoders SSI: todavia no existen (P-02). Mientras `azel_valid` sea
     * false, azimut y elevacion viajan a 0 y el rayo se marca con
     * `azel_invalid` -- se MARCA, no se descarta, que es lo que dice el
     * contrato sobre un rayo con problemas. */
    bool azel_valid;
    uint32_t azimuth_raw;
    uint32_t elevation_raw;
    /* Instante del disparo, reloj del DRx. Sin fuente de tiempo real todavia;
     * se deriva de `trig_count` y de FS_HZ, que es monotono y exacto en
     * ciclos aunque no este atado a ninguna hora de pared. */
    uint64_t timestamp_ns;
    /* Primer rayo tras un `config` nuevo: lo marca el contrato con su propia
     * bandera para que el DSP sepa donde empieza la configuracion nueva. */
    bool first_after_config;
    bool ddc_overflow;
    bool truncated;
} DrxRayContext;

/* Bytes que ocupa la trama de un rayo de `bins` bins y `n_ch` canales. */
size_t DrxRayFrame_Size(uint32_t bins, uint32_t n_ch);

/* Escribe en `out` la trama `ray` completa: cabecera comun del contrato,
 * cabecera del mensaje y carga util. Devuelve los bytes escritos, o 0 si no
 * caben en `cap` o si el rayo no cuadra con su propia cabecera.
 *
 * `iq` son las palabras de la DDR SIN el metadato en banda; `n_words` tiene
 * que valer `bins * n_ch`. */
size_t DrxRayFrame_Encode(uint8_t *out, size_t cap, const DrxRayHeader *header,
                          const DrxRayContext *ctx, const uint32_t *iq,
                          uint32_t n_words);

#endif /* DRX_RAY_FRAME_H */
