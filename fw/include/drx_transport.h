/* Transporte DRx->DSP sobre TCP (Z4.6).
 *
 * Es la pieza que faltaba para cerrar ZM4: hasta Z4.5 el contrato se
 * ejercitaba contra tramas que el propio firmware se fabricaba, y nadie abria
 * un socket.
 *
 * Forma, por [D-16](docs/alcance/decisiones.md#d-16): UNA conexion TCP para
 * los dos sentidos, el DRx ESCUCHA en `DRX_DSP_TCP_PORT` (constante del
 * esquema del contrato, no un numero escrito aqui) y el DSP conecta. Un solo
 * cliente a la vez: un segundo DSP pidiendo los mismos rayos no es un caso de
 * uso, es un error de despliegue, y aceptarlo en silencio lo escondería.
 *
 * Reparto de tareas, que importa porque hay dos y comparten el socket:
 *
 *   - La tarea de este modulo hace `accept` y luego solo RECIBE, alimentando
 *     el parser del contrato. Se bloquea en `recv`, que es donde debe estar.
 *   - El sumidero de rayos (`DrxRay_SetSink`) corre en la tarea de rayos y
 *     solo ENVIA. La tarea de diagnostico tambien envia, su `status`.
 *
 * Enviar desde dos tareas y recibir desde una tercera sobre el mismo descriptor
 * es correcto en lwIP mientras cada sentido tenga un solo escritor a la vez;
 * aqui lo garantiza `g_tx` (un mutex) y no el azar.
 */
#ifndef DRX_TRANSPORT_H
#define DRX_TRANSPORT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint32_t accepts;      /* conexiones aceptadas desde el arranque */
    uint32_t rays_sent;    /* tramas `ray` entregadas enteras */
    uint32_t rays_dropped; /* rayos que no se pudieron enviar (ver abajo) */
    uint32_t status_sent;
    /* 64 bits, no 32: a 28,9 Mbps un contador de 32 bits envuelve cada ~20
     * minutos, y se vio envolver en el primer soak de una hora -- el total
     * impreso bajaba en vez de subir. */
    uint64_t rx_bytes;
    uint64_t tx_bytes;
    uint32_t send_errors;  /* `send` fallido: cierra la conexion */
    bool connected;
} DrxTransportStatus;

/* Crea la tarea servidora. Una vez, al arrancar, DESPUES de `lwip_init()` y de
 * que la interfaz tenga direccion. */
void DrxTransportTask_Create(void);

/* Entrega una trama ya formada al DSP conectado. Devuelve false si no hay
 * nadie conectado o si el envio fallo a medias. La usa la tarea de diagnostico
 * para su `status`; los rayos no pasan por aqui, van por el sumidero. */
bool DrxTransport_Send(const uint8_t *frame, size_t len);

void DrxTransport_GetStatus(DrxTransportStatus *out);

#endif /* DRX_TRANSPORT_H */
