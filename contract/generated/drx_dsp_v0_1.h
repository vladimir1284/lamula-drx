/* GENERADO por tools/gen_contract.py a partir de
 * contract/schema/drx_dsp_v0_1.toml. NO EDITAR A MANO.
 *
 * Contrato DRx↔DSP v0.6 — lado DRx.
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
#define DRX_DSP_VERSION_MINOR 6

/* Cabecera común a todo mensaje. */
typedef struct __attribute__((packed)) {
  uint32_t magic;  /* 0x4C4D4452. Si no coincide, el flujo no es de este contrato. */
  uint8_t version_major;  /* Incompatible al cambiar. */
  uint8_t version_minor;  /* Compatible hacia atrás dentro del mismo major. */
  uint8_t msg_type;  /* Ver la tabla de tipos de mensaje. */
  uint8_t flags;  /* Reservado en v0.1; tiene que valer 0. */
  uint32_t payload_len;  /* Bytes que siguen a ESTA cabecera de 12 B: la cabecera del mensaje más su carga útil variable si la tiene. Un lector de tramas hace por tanto: leer 12 B, leer payload_len B, y ya tiene el mensaje entero sin conocer su tipo. Un ray de 1844 bins x 4 canales vale 36 + 1844x4x4 = 29540; un mensaje sin carga variable vale el tamaño de su struct (status 28, config 60, config_ack 8, afc 16, test_stimulus_select 8), nunca 0. */
} drx_dsp_header_t;
_Static_assert(sizeof(drx_dsp_header_t) == 12, "layout de drx_dsp_header_t");

/* Tipos de mensaje. */
typedef enum {
  DRX_DSP_MSG_RAY = 1,  /* up */
  DRX_DSP_MSG_STATUS = 2,  /* up */
  DRX_DSP_MSG_CONFIG = 3,  /* down */
  DRX_DSP_MSG_CONFIG_ACK = 4,  /* up */
  DRX_DSP_MSG_AFC = 5,  /* down */
  DRX_DSP_MSG_TEST_STIMULUS_SELECT = 6,  /* down */
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
 * rechaza entera y el estado anterior se preserva.
 * 
 * Lleva DOS lotes de PRF/ancho de pulso por radial, `low` y `high`, porque eso es
 * lo que secuencia el motor de timing (D-13, Batch mode de NEXRAD) y lo que el
 * mapa de registros AXI-Lite expone desde v3. Hasta v0.5 este mensaje declaraba un
 * único par, que modelaba un supuesto que D-13 descartó: con aquel esquema el DSP
 * no tenía dónde pedir el segundo lote. Ver P-15.
 * 
 * Los dos lotes se validan por separado contra D-09 y la configuración entra o se
 * rechaza como un todo: un `config` cuyo lote `high` sea inválido NO deja aplicado
 * el lote `low`. */
typedef struct __attribute__((packed)) {
  uint32_t seq;  /* Se devuelve tal cual en el config_ack. */
  uint32_t prf_div_low;  /* Divisor de PRF del lote bajo. PRF = FS_HZ/prf_div_low. */
  uint32_t prf_div_high;  /* Divisor de PRF del lote alto. PRF = FS_HZ/prf_div_high. */
  uint16_t range_bins_low;  /* Bins de rango del lote bajo (D-15). */
  uint16_t range_bins_high;  /* Bins de rango del lote alto (D-15). */
  uint16_t n_pulses_low;  /* Pulsos del lote bajo dentro del radial. */
  uint16_t n_pulses_high;  /* Pulsos del lote alto dentro del radial. */
  uint8_t pulse_width_idx_low;  /* Índice en la tabla de anchos de pulso, lote bajo. */
  uint8_t pulse_width_idx_high;  /* Índice en la tabla de anchos de pulso, lote alto. */
  uint8_t pulse_mode;  /* Modo de pulso. */
  uint8_t cell_mode;  /* 0 = celda fina, 1 = celda gruesa. */
  uint8_t channel_mask;  /* Canales a capturar. */
  uint8_t scan_mode;  /* 0 = split cut, 1 = batch cut, 2 = doppler cut. */
  uint8_t pad0;  /* Relleno explícito; vale 0. */
  uint8_t pad1;  /* Relleno explícito; vale 0. */
  uint32_t trigger_delay_0;  /* Retardo del trigger 0, en ciclos de fs. */
  uint32_t trigger_delay_1;  /* Retardo del trigger 1, en ciclos de fs. */
  uint32_t trigger_delay_2;  /* Retardo del trigger 2, en ciclos de fs. */
  uint32_t trigger_delay_3;  /* Retardo del trigger 3, en ciclos de fs. */
  uint32_t trigger_width_0;  /* Ancho del trigger 0, en ciclos de fs. */
  uint32_t trigger_width_1;  /* Ancho del trigger 1, en ciclos de fs. */
  uint32_t trigger_width_2;  /* Ancho del trigger 2, en ciclos de fs. */
  uint32_t trigger_width_3;  /* Ancho del trigger 3, en ciclos de fs. */
} drx_dsp_config_t;
_Static_assert(sizeof(drx_dsp_config_t) == 60, "layout de drx_dsp_config_t");

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

/* Elige qué vector de estímulo reproduce `vector_source` en la PL.
 * 
 * Existe porque en ZedBoard no hay ADC: el único origen de muestras es
 * `rtl/vector_source.sv`, y hasta v0.5 el vector que reproducía quedaba fijado en
 * tiempo de SÍNTESIS (`$readmemh` sobre la BRAM, `tools/gen_vector_source_init.py`).
 * Cambiar de estímulo costaba una corrida de Vivado entera, así que ninguna prueba
 * de punta a punta podía barrer el catálogo. Con este mensaje el par remoto elige
 * el vector en tiempo de ejecución y el firmware lo carga en la PL por AXI DMA
 * MM2S.
 * 
 * Es un mandato de BANCO DE PRUEBAS, no de operación: en la plataforma objetivo el
 * origen de muestras son los ADC reales y este mensaje no tiene efecto. El
 * receptor responde con `config_ack` reusando `seq`, igual que a un `config`. */
typedef struct __attribute__((packed)) {
  uint32_t seq;  /* Se devuelve tal cual en el config_ack. */
  uint8_t vector_id;  /* Índice en el catálogo; ver la enumeración stimulus_vector. */
  uint8_t pad0;  /* Relleno explícito; vale 0. */
  uint16_t repeat;  /* Veces que se reproduce el vector antes de parar. 0 = en bucle indefinido, que es el comportamiento que tenía el modo BRAM-loop. */
} drx_dsp_test_stimulus_select_t;
_Static_assert(sizeof(drx_dsp_test_stimulus_select_t) == 8, "layout de drx_dsp_test_stimulus_select_t");

/* Códigos de rechazo del plano de control. */
typedef enum {
  DRX_DSP_ERROR_OK = 0,  /* Aceptado. */
  DRX_DSP_ERROR_PRF_RANGE_ILLEGAL = 1,  /* PRF y extensión de rango incompatibles (D-09). */
  DRX_DSP_ERROR_UNSUPPORTED_VERSION = 2,  /* version_major desconocido. */
  DRX_DSP_ERROR_UNKNOWN_MESSAGE = 3,  /* msg_type desconocido. */
  DRX_DSP_ERROR_BAD_LENGTH = 4,  /* payload_len no cuadra: no coincide con el tamaño del struct del msg_type recibido más su carga útil variable si la tiene. */
  DRX_DSP_ERROR_CELL_MODE_INVALID = 5,  /* cell_mode fuera de {0,1}. */
  DRX_DSP_ERROR_PULSE_WIDTH_INVALID = 6,  /* Índice de ancho de pulso fuera de tabla. */
  DRX_DSP_ERROR_CHANNEL_MASK_INVALID = 7,  /* Máscara de canales vacía o fuera de rango. */
  DRX_DSP_ERROR_SCAN_MODE_INVALID = 8,  /* Modo de barrido desconocido. */
  DRX_DSP_ERROR_NOT_CONFIGURED = 9,  /* Llegó un mandato antes de la primera configuración. */
  DRX_DSP_ERROR_VECTOR_UNKNOWN = 10,  /* vector_id fuera del catálogo de stimulus_vector. */
  DRX_DSP_ERROR_UNIMPLEMENTED = 11,  /* msg_type conocido y bien formado, pero este receptor todavía no lo aplica. Distinto de unknown_message, que es para un msg_type que el receptor NO conoce: con ese el par remoto sabe que hablan versiones distintas, con este sabe que hablan la misma y que la función aún no está. Nada se aplicó. */
} drx_dsp_error_t;

/* Bit por canal físico presente en channel_mask. El orden de channels[] en el payload de ray sigue el orden ascendente de los bits puestos en channel_mask; cada canal aporta los mismos `bins` que el resto del rayo. rx_0..rx_3 son 2 conversores por polarización (H, V): uno a ganancia nominal y otro con la señal atenuada, para extender el rango dinámico (confirmado en sesión, 8-sep-2026). El emparejamiento H/V de arriba está confirmado; el orden concreto rx_0 vs rx_1 (¿cuál es el nominal y cuál el atenuado de cada polarización?) es una CONVENCIÓN asumida aquí, sin confirmar todavía contra el cableado físico — ver docs/alcance/pendientes.md, A10. */
typedef enum {
  DRX_DSP_CHANNEL_RX_0 = 1,  /* H, ganancia nominal (convención asumida, ver doc del enum). */
  DRX_DSP_CHANNEL_RX_1 = 2,  /* H, señal atenuada — rango dinámico extendido (convención asumida, ver doc del enum). */
  DRX_DSP_CHANNEL_RX_2 = 4,  /* V, ganancia nominal (convención asumida, ver doc del enum). */
  DRX_DSP_CHANNEL_RX_3 = 8,  /* V, señal atenuada — rango dinámico extendido (convención asumida, ver doc del enum). */
  DRX_DSP_CHANNEL_TX_BURST_0 = 16,  /* Muestra del transmisor. Un solo conversor físico (n_tx_burst_ch=1, 8-sep-2026): trae energía sólo durante la ventana del pulso transmitido; el resto de sus bins es ruido/silencio. */
} drx_dsp_channel_t;

/* Banderas por rayo. Un rayo con problemas se MARCA, no se descarta. */
typedef enum {
  DRX_DSP_RAY_FLAG_AZEL_INVALID = 1,  /* Lectura de encoder inválida en este rayo. */
  DRX_DSP_RAY_FLAG_DDC_OVERFLOW = 2,  /* Hubo saturación en el DDC dentro del rayo. */
  DRX_DSP_RAY_FLAG_TRUNCATED = 4,  /* El rayo salió corto. */
  DRX_DSP_RAY_FLAG_FIRST_AFTER_CONFIG = 8,  /* Primer rayo con la configuración nueva. */
  DRX_DSP_RAY_FLAG_TX_POL_V = 16,  /* Este pulso se transmitió en V; a cero, se transmitió en H. Sólo tiene sentido con polarización alternante H/V; en canal único o simultánea (STAR) el bit no se usa y vale 0. */
  DRX_DSP_RAY_FLAG_BATCH_HIGH = 32,  /* Este rayo lo produjo el lote ALTO del radial; a cero, el lote bajo (D-13). Es una bandera y no un campo porque prf_div, bins y pulse_width_idx de la cabecera ya llevan los valores VIGENTES para ese rayo: el bit sólo dice de cuál de los dos lotes salieron, que es lo que hace falta para agrupar rayos por lote sin reconstruir el radial. */
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

/* Catálogo v1 de vectores de estímulo, los ocho casos de tools/gen_l1_vectors.py — la misma lista contra la que L1 compara la IP real de Xilinx con el modelo dorado bajo D-12. El catálogo puede CRECER dentro del mismo version_major (añadir un valor es compatible hacia atrás); reordenar o quitar valores no. En la plataforma objetivo, con ADC reales, esta enumeración no tiene efecto. */
typedef enum {
  DRX_DSP_STIMULUS_VECTOR_TONO_IF = 0,  /* IF nominal: lo que el NCO tiene que llevar a continua exactamente. */
  DRX_DSP_STIMULUS_VECTOR_TONO_DESPLAZADO = 1,  /* Desplazado +0,001 dentro de la banda de paso: ejercita el FIR fuera de continua. */
  DRX_DSP_STIMULUS_VECTOR_DOS_TONOS = 2,  /* Rechazo de imagen e intermodulación del mezclador complejo. */
  DRX_DSP_STIMULUS_VECTOR_TONO_DESPLAZADO_NEG = 3,  /* Simétrico del anterior al otro lado del IF; cuarto estímulo distinto para los canales del quad. */
  DRX_DSP_STIMULUS_VECTOR_TONO_CON_RUIDO = 4,  /* Degradación D9: ruido a 10 dB de SNR. */
  DRX_DSP_STIMULUS_VECTOR_TONO_CON_OFFSET_DC = 5,  /* Degradación D9: offset de continua a -12 dBFS. */
  DRX_DSP_STIMULUS_VECTOR_TONO_DESBALANCEADO = 6,  /* Degradación D9: desbalance I/Q de 1 dB y 3 grados. */
  DRX_DSP_STIMULUS_VECTOR_TONO_SOBRE_ESCALA = 7,  /* Entrada a +6 dBFS: el ADC satura, no envuelve. Ejercita el reporte de overflow. */
} drx_dsp_stimulus_vector_t;

#endif /* DRX_DSP_V0_1_H */
