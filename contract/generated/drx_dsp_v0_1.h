/* GENERADO por tools/gen_contract.py a partir de
 * contract/schema/drx_dsp_v0_1.toml. NO EDITAR A MANO.
 *
 * Contrato DRx↔DSP v0.1 — lado DRx.
 *
 * Little-endian, empaquetado, sin relleno implícito. Los _Static_assert
 * de abajo fallan la compilación si el compilador añade relleno: es el
 * único sitio donde un desacuerdo de layout se puede detectar barato.
 */

#ifndef DRX_DSP_V0_1_H
#define DRX_DSP_V0_1_H

#include <stdint.h>

#define DRX_DSP_MAGIC 0x4C4D4452u
#define DRX_DSP_VERSION_MAJOR 0
#define DRX_DSP_VERSION_MINOR 1

/* Cabecera común a todo mensaje. */
typedef struct __attribute__((packed)) {
  uint32_t magic;  /* 0x4C4D4452. Si no coincide, el flujo no es de este contrato. */
  uint8_t version_major;  /* Incompatible al cambiar. */
  uint8_t version_minor;  /* Compatible hacia atrás dentro del mismo major. */
  uint8_t msg_type;  /* Ver la tabla de tipos de mensaje. */
  uint8_t flags;  /* Reservado en v0.1; tiene que valer 0. */
  uint32_t payload_len;  /* Bytes de carga útil detrás de la cabecera del mensaje. */
} drx_dsp_header_t;
_Static_assert(sizeof(drx_dsp_header_t) == 12, "layout de drx_dsp_header_t");

/* Tipos de mensaje. */
typedef enum {
  DRX_DSP_MSG_RAY = 1,  /* up */
  DRX_DSP_MSG_STATUS = 2,  /* up */
  DRX_DSP_MSG_CONFIG = 3,  /* down */
  DRX_DSP_MSG_CONFIG_ACK = 4,  /* up */
  DRX_DSP_MSG_AFC = 5,  /* down */
} drx_dsp_msg_type_t;

/* Cabecera de un rayo. Detrás van `bins`·`n_channels` pares (I,Q) de int16
 * entrelazados como I0 Q0 I1 Q1..., canal más rápido que bin. */
typedef struct __attribute__((packed)) {
  uint32_t seq;  /* Contador de rayos, envuelve. Detecta pérdidas. */
  uint64_t timestamp_ns;  /* Instante del trigger, reloj del DRx. */
  uint32_t trigger_count;  /* Disparos desde el arranque. */
  uint32_t azimuth_raw;  /* Cuenta cruda del encoder SSI de azimut. */
  uint32_t elevation_raw;  /* Cuenta cruda del encoder SSI de elevación. */
  uint32_t prf_div;  /* Divisor de PRF vigente. PRF = FS_HZ/prf_div. */
  uint16_t bins;  /* Bins de rango en este rayo. */
  uint8_t pulse_width_idx;  /* Índice en la tabla de anchos de pulso. */
  uint8_t pulse_mode;  /* Modo de pulso vigente. */
  uint8_t cell_mode;  /* 0 = celda fina, 1 = celda gruesa. */
  uint8_t n_channels;  /* Canales presentes en la carga útil. */
  uint8_t channel_mask;  /* Qué canales físicos son, bit por canal. */
  uint8_t ray_flags;  /* Ver la tabla de banderas de rayo. */
} drx_dsp_ray_t;
_Static_assert(sizeof(drx_dsp_ray_t) == 36, "layout de drx_dsp_ray_t");

/* Status y BITE. Se emite periódicamente y ante cualquier cambio de estado. */
typedef struct __attribute__((packed)) {
  uint32_t uptime_s;  /* Segundos desde el arranque del firmware. */
  uint32_t bite_flags;  /* Ver la tabla de banderas de BITE. */
  uint32_t ssa_underruns;  /* Underruns de la fuente de muestras. */
  uint32_t dma_overruns;  /* Overruns del camino DMA. */
  uint32_t ssi_errors;  /* Timeouts y tramas malas de los encoders. */
  uint32_t ddc_overflows;  /* Muestras saturadas a la salida del DDC. */
  uint8_t last_error;  /* Último código de error del plano de control. */
  uint8_t pad0;  /* Relleno explícito; vale 0. */
  uint16_t pad1;  /* Relleno explícito; vale 0. */
} drx_dsp_status_t;
_Static_assert(sizeof(drx_dsp_status_t) == 28, "layout de drx_dsp_status_t");

/* Configuración completa. Se aplica de forma atómica: o entra entera o se
 * rechaza entera y el estado anterior se preserva. */
typedef struct __attribute__((packed)) {
  uint32_t seq;  /* Se devuelve tal cual en el config_ack. */
  uint32_t prf_div;  /* Divisor de PRF. PRF = FS_HZ/prf_div. */
  uint16_t range_bins;  /* Bins de rango pedidos. */
  uint8_t pulse_width_idx;  /* Índice en la tabla de anchos de pulso. */
  uint8_t pulse_mode;  /* Modo de pulso. */
  uint8_t cell_mode;  /* 0 = celda fina, 1 = celda gruesa. */
  uint8_t channel_mask;  /* Canales a capturar. */
  uint8_t scan_mode;  /* 0 = split cut, 1 = batch cut, 2 = doppler cut. */
  uint8_t pad0;  /* Relleno explícito; vale 0. */
  uint32_t trigger_delay_0;  /* Retardo del trigger 0, en ciclos de fs. */
  uint32_t trigger_delay_1;  /* Retardo del trigger 1, en ciclos de fs. */
  uint32_t trigger_delay_2;  /* Retardo del trigger 2, en ciclos de fs. */
  uint32_t trigger_delay_3;  /* Retardo del trigger 3, en ciclos de fs. */
  uint32_t trigger_width_0;  /* Ancho del trigger 0, en ciclos de fs. */
  uint32_t trigger_width_1;  /* Ancho del trigger 1, en ciclos de fs. */
  uint32_t trigger_width_2;  /* Ancho del trigger 2, en ciclos de fs. */
  uint32_t trigger_width_3;  /* Ancho del trigger 3, en ciclos de fs. */
} drx_dsp_config_t;
_Static_assert(sizeof(drx_dsp_config_t) == 48, "layout de drx_dsp_config_t");

/* Respuesta a un config. `error` distinto de 0 significa que NO se aplicó nada. */
typedef struct __attribute__((packed)) {
  uint32_t seq;  /* El `seq` del config al que responde. */
  uint8_t error;  /* Código de error; 0 es aceptado. */
  uint8_t pad0;  /* Relleno explícito; vale 0. */
  uint16_t pad1;  /* Relleno explícito; vale 0. */
} drx_dsp_config_ack_t;
_Static_assert(sizeof(drx_dsp_config_ack_t) == 8, "layout de drx_dsp_config_ack_t");

/* Corrección AFC: nueva palabra de fase del NCO, calculada por el DSP.
 * 
 * Viaja como palabra de fase absoluta y no como offset en Hz a propósito: en Hz
 * haría falta que el DSP conociera `FS_HZ` del DRx, y eso rompería D-02 en cuanto
 * las dos plataformas divergieran. */
typedef struct __attribute__((packed)) {
  uint64_t nco_phase_inc;  /* Palabra de fase absoluta del NCO. */
  uint32_t apply_at_seq;  /* Rayo a partir del cual aplicar; 0 = ya. */
  uint32_t pad0;  /* Relleno explícito; vale 0. */
} drx_dsp_afc_t;
_Static_assert(sizeof(drx_dsp_afc_t) == 16, "layout de drx_dsp_afc_t");

/* Códigos de rechazo del plano de control. */
typedef enum {
  DRX_DSP_ERROR_OK = 0,  /* Aceptado. */
  DRX_DSP_ERROR_PRF_RANGE_ILLEGAL = 1,  /* PRF y extensión de rango incompatibles (D-09). */
  DRX_DSP_ERROR_UNSUPPORTED_VERSION = 2,  /* version_major desconocido. */
  DRX_DSP_ERROR_UNKNOWN_MESSAGE = 3,  /* msg_type desconocido. */
  DRX_DSP_ERROR_BAD_LENGTH = 4,  /* payload_len no cuadra con el mensaje. */
  DRX_DSP_ERROR_CELL_MODE_INVALID = 5,  /* cell_mode fuera de {0,1}. */
  DRX_DSP_ERROR_PULSE_WIDTH_INVALID = 6,  /* Índice de ancho de pulso fuera de tabla. */
  DRX_DSP_ERROR_CHANNEL_MASK_INVALID = 7,  /* Máscara de canales vacía o fuera de rango. */
  DRX_DSP_ERROR_SCAN_MODE_INVALID = 8,  /* Modo de barrido desconocido. */
  DRX_DSP_ERROR_NOT_CONFIGURED = 9,  /* Llegó un mandato antes de la primera configuración. */
} drx_dsp_error_t;

/* Banderas por rayo. Un rayo con problemas se MARCA, no se descarta. */
typedef enum {
  DRX_DSP_RAY_FLAG_AZEL_INVALID = 1,  /* Lectura de encoder inválida en este rayo. */
  DRX_DSP_RAY_FLAG_DDC_OVERFLOW = 2,  /* Hubo saturación en el DDC dentro del rayo. */
  DRX_DSP_RAY_FLAG_TRUNCATED = 4,  /* El rayo salió corto. */
  DRX_DSP_RAY_FLAG_FIRST_AFTER_CONFIG = 8,  /* Primer rayo con la configuración nueva. */
} drx_dsp_ray_flag_t;

/* Catálogo de fallos del plan de testing. */
typedef enum {
  DRX_DSP_BITE_FLAG_SSA_UNDERRUN = 1,  /* Underrun de la fuente de muestras. */
  DRX_DSP_BITE_FLAG_DMA_OVERRUN = 2,  /* Overrun del camino DMA. */
  DRX_DSP_BITE_FLAG_SSI_TIMEOUT = 4,  /* Timeout de encoder SSI. */
  DRX_DSP_BITE_FLAG_SSI_FRAME_ERROR = 8,  /* Trama SSI corta, larga o salto de Gray. */
  DRX_DSP_BITE_FLAG_MMCM_UNLOCKED = 16,  /* Pérdida de lock del MMCM. */
  DRX_DSP_BITE_FLAG_LINK_DOWN = 32,  /* Enlace Ethernet caído. */
  DRX_DSP_BITE_FLAG_CONFIG_REJECTED = 64,  /* Se rechazó una configuración. */
} drx_dsp_bite_flag_t;

#endif /* DRX_DSP_V0_1_H */
