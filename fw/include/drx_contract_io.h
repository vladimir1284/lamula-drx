/* Framer y parser del contrato DRx<->DSP (Z4.3).
 *
 * `contract/generated/drx_dsp_v0_1.h` da los structs y los `_Static_assert` de
 * layout, pero nada que convierta un struct en bytes de cable ni que recupere
 * un mensaje de un flujo TCP. Esto es eso, y nada mas: no abre sockets, no
 * conoce lwIP y no toca registros. Esa separacion no es estetica -- es lo que
 * permite compilar ESTE MISMO fichero para el host y comprobarlo contra la
 * implementacion de Python generada del mismo esquema, que es la unica forma
 * barata de atrapar un desacuerdo de formato antes de que aparezca en campo.
 *
 * El flujo llega por TCP, asi que un mensaje puede venir partido en cualquier
 * punto y varios pueden venir en el mismo segmento. El parser es por tanto
 * incremental y con estado: se le empujan los bytes que haya y llama a un
 * callback por cada mensaje completo.
 *
 * Reglas del formato que esto impone, todas del esquema (D-08):
 *   - cabecera comun de 12 B, little-endian, empaquetada;
 *   - `payload_len` cuenta el struct del mensaje MAS su carga variable, y
 *     nunca vale 0 -- la lectura normativa que fijo la v0.4;
 *   - `flags` esta reservado y tiene que valer 0.
 */
#ifndef DRX_CONTRACT_IO_H
#define DRX_CONTRACT_IO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "drx_dsp_v0_1.h"

/* El cable es little-endian y los structs del contrato se copian tal cual, sin
 * conversion campo a campo. Eso vale en el Cortex-A9 (little-endian) y en el
 * host de los tests, pero seria un error silencioso en un big-endian: los
 * bytes saldrian al reves y el otro lado parsearia basura con `magic` roto.
 * Mejor no compilar. */
#if defined(__BYTE_ORDER__) && (__BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__)
#error "el contrato DRx<->DSP es little-endian; este objetivo no lo es"
#endif

#define DRX_FRAME_HEADER_SIZE 12u

/* Resultado de examinar una trama.
 *
 * Deliberadamente NO es `drx_dsp_error_t`: son dos cosas distintas. El enum del
 * contrato son codigos que viajan en un `config_ack`, es decir fallos de un
 * mensaje concreto dentro de un flujo que sigue siendo valido. Un `magic` que
 * no cuadra no es eso -- significa que el flujo entero no es de este contrato y
 * lo que procede es cerrar la conexion, no contestar. Mezclarlos obligaria a
 * inventar un codigo de contrato para algo que el contrato no cubre.
 * DrxFrame_ErrorCode() traduce los que si son contestables. */
typedef enum {
    DRX_FRAME_OK = 0,
    DRX_FRAME_NEED_MORE,    /* todavia no hay bytes para decidir */
    DRX_FRAME_BAD_MAGIC,    /* el flujo no es de este contrato: cerrar */
    DRX_FRAME_BAD_VERSION,  /* version_major desconocido */
    DRX_FRAME_BAD_FLAGS,    /* `flags` reservado y distinto de 0 */
    DRX_FRAME_BAD_LENGTH,   /* payload_len no cuadra con el msg_type */
    DRX_FRAME_UNKNOWN_TYPE, /* msg_type desconocido o de sentido "up" */
    DRX_FRAME_TOO_LARGE,    /* no cabe en el buffer del receptor */
} DrxFrameStatus;

/* Codigo del contrato con el que contestar, o DRX_DSP_ERROR_OK si este estado
 * no es contestable (OK, NEED_MORE) o si lo que procede es cerrar la conexion
 * (BAD_MAGIC, TOO_LARGE). */
drx_dsp_error_t DrxFrame_ErrorCode(DrxFrameStatus status);

/* Bytes que ocupa en el cable un mensaje de `msg_type` sin carga variable, o 0
 * si el tipo es desconocido. Es el `payload_len` que la cabecera tiene que
 * declarar para ese mensaje. */
uint32_t DrxFrame_BodySize(uint8_t msg_type);

/* true si `msg_type` es un mensaje que el DRx puede RECIBIR (sentido "down" en
 * el esquema). Un `ray` o un `status` entrantes son un error del par remoto, no
 * un mensaje a procesar. */
bool DrxFrame_IsDownstream(uint8_t msg_type);

/* --- Lado emisor ---------------------------------------------------------
 *
 * Escribe en `out` la cabecera comun seguida del cuerpo y, si la hay, la carga
 * variable. `payload` puede ser NULL con `payload_len` 0 (todo mensaje salvo
 * `ray` esta en ese caso). Devuelve los bytes escritos, o 0 si no caben en
 * `out_cap` o si `msg_type` no es conocido.
 *
 * `body_len` se comprueba contra DrxFrame_BodySize(msg_type) en vez de
 * confiarse: un `sizeof` del struct equivocado en el llamante produciria una
 * trama que parsea pero desincroniza al lector en el mensaje siguiente, que es
 * el fallo mas caro de diagnosticar que tiene este formato. */
size_t DrxFrame_Encode(uint8_t *out, size_t out_cap, uint8_t msg_type,
                       const void *body, size_t body_len,
                       const void *payload, size_t payload_len);

/* --- Lado receptor -------------------------------------------------------- */

struct DrxParser;

/* Se llama una vez por mensaje completo. `body` apunta al struct del mensaje ya
 * contiguo en el buffer del parser, con `body_len` bytes de carga variable
 * detras (0 salvo en `ray`). El puntero vale solo durante la llamada: el
 * parser reutiliza el buffer para el mensaje siguiente. */
typedef void (*DrxParser_OnMessage)(const drx_dsp_header_t *header,
                                    const uint8_t *body, uint32_t body_len,
                                    void *user);

typedef struct DrxParser {
    uint8_t *buf;  /* buffer del llamante: acumula cabecera + cuerpo */
    size_t cap;
    size_t len;             /* bytes validos en `buf` */
    bool have_header;       /* `header` ya esta rellena y validada */
    drx_dsp_header_t header;
    DrxFrameStatus status;  /* motivo de la ultima parada, si la hubo */
    uint32_t accepted;      /* mensajes entregados al callback */
    uint32_t rejected;      /* tramas descartadas por fallo de validacion */
} DrxParser;

void DrxParser_Init(DrxParser *parser, uint8_t *buf, size_t cap);

/* Empuja `n` bytes. Devuelve cuantos consumio. Si devuelve menos de `n`, el
 * parser se paro: `parser->status` dice por que y ya no avanza hasta que
 * DrxParser_Reset() lo rearme. Esa parada es deliberada -- tras un fallo de
 * validacion el punto de sincronizacion del flujo se ha perdido, y seguir
 * leyendo desde ahi solo produce basura que parece datos. */
size_t DrxParser_Push(DrxParser *parser, const uint8_t *data, size_t n,
                      DrxParser_OnMessage on_message, void *user);

/* Descarta lo acumulado y vuelve a esperar una cabecera. No borra los
 * contadores: `accepted`/`rejected` son diagnostico acumulado. */
void DrxParser_Reset(DrxParser *parser);

#endif /* DRX_CONTRACT_IO_H */
