/* Implementacion de fw/include/drx_transport.h. */
#include "drx_transport.h"

#include "drx_afc_app.h"
#include "drx_contract_io.h"
#include "drx_control.h"
#include "drx_ray.h"
#include "drx_ray_ctx.h"
#include "drx_ray_frame.h"
#include "drx_status_task.h"
#include "drx_stimulus.h"
#include "drx_timing_cfg.h"

#include "FreeRTOS.h"
#include "queue.h"
#include "semphr.h"
#include "task.h"
#include "xil_printf.h"

#include "lwip/sockets.h"

#include <string.h>

#define DRX_TRANSPORT_STACK_WORDS 2048
#define DRX_TRANSPORT_PRIORITY (tskIDLE_PRIORITY + 2)
#define DRX_TRANSPORT_BACKLOG 1

/* Tramas `ray` en vuelo. Dimensionadas al rayo mas grande que el bitstream
 * puede producir: la carga util de la DDR viene en {I[31:16], Q[15:0]} y el
 * contrato pide el par en orden I,Q, asi que `DrxRayFrame_Encode` tiene que
 * escribir en algun sitio.
 *
 * Son VARIAS, y una tarea aparte las envia, porque la primera version --una
 * sola trama y el sumidero enviando el mismo-- bloqueaba la tarea de rayos
 * dentro de `lwip_send`. Mientras esa tarea espera al socket nadie recicla
 * descriptores del S2MM, el range-gate se queda sin sitio y desborda: un hipo
 * de red de ~50 ms costaba ~11 rayos, no uno.
 *
 * Medido, con un control limpio (3-oct-2026). Con cliente conectado, 2 h:
 * ~18 eventos de `STATUS (overrun) = 0x7` y 20 rafagas de `trig_gaps`. Sin
 * cliente --el sumidero ni se instala, no hay socket en el camino-- 41 min y
 * 556 757 rayos: CERO en todos los contadores. Misma placa, mismo firmware.
 *
 * Con el pool, el sumidero solo escribe y encola; si no hay hueco descarta UN
 * rayo y sigue, que es el coste que D-16 acepta. */
#define DRX_RAY_FRAME_MAX (DRX_RAY_MAX_BINS * DRX_RAY_N_CH * 4u + 64u)
#define DRX_TX_SLOTS 4u

static uint8_t g_pool[DRX_TX_SLOTS][DRX_RAY_FRAME_MAX];
static size_t g_pool_len[DRX_TX_SLOTS];
static QueueHandle_t g_libres; /* indices de hueco disponible */
static QueueHandle_t g_listos; /* indices con trama lista para enviar */

static uint8_t g_rx[2048];
static uint8_t g_parse_buf[256];

static DrxParser g_parser;
static DrxControl g_ctl;
static DrxTransportStatus g_status;

/* Serializa a los dos emisores (tarea de rayos y tarea de diagnostico) y
 * protege el descriptor contra un cierre a medio envio. */
static SemaphoreHandle_t g_tx;
static volatile int g_fd = -1;

static drx_dsp_error_t tr_apply_config(const drx_dsp_config_t *config, void *user)
{
    (void)user;
    return DrxTiming_Apply(config);
}

static drx_dsp_error_t tr_select_stimulus(uint8_t vector_id, uint16_t repeat, void *user)
{
    (void)user;
    return DrxStimulus_Select(vector_id, repeat);
}

/* Envia `len` bytes enteros o falla. `send` puede aceptar menos de lo pedido
 * --es un flujo, no un mensaje-- y dar por entregada una trama a medias
 * desincroniza al DSP en el mensaje SIGUIENTE, no en este. */
static bool envia_todo(int fd, const uint8_t *data, size_t len)
{
    size_t puesto = 0u;
    while (puesto < len) {
        int n = lwip_send(fd, &data[puesto], len - puesto, 0);
        if (n <= 0) {
            return false;
        }
        puesto += (size_t)n;
    }
    return true;
}

static bool envia_bloqueando(const uint8_t *frame, size_t len)
{
    if (frame == NULL || len == 0u) {
        return false;
    }
    /* La tarea de diagnostico se crea ANTES que esta (main.c la arranca antes
     * de `lwip_init`, a proposito: no debe depender de que haya enlace), asi
     * que puede llegar aqui cuando todavia no existe ni el mutex. Sin esta
     * guarda, `xSemaphoreTake(NULL, ...)` revienta el configASSERT de
     * FreeRTOS -- medido en placa: "Assert failed in file queue.c, line 1507".
     * Mirar `g_fd` aqui fuera es solo para no bloquear sin falta; quien manda
     * es la comprobacion de dentro del mutex. */
    if (g_tx == NULL || g_fd < 0) {
        return false;
    }
    if (xSemaphoreTake(g_tx, portMAX_DELAY) != pdTRUE) {
        return false;
    }

    bool ok = false;
    int fd = g_fd;
    if (fd >= 0) {
        ok = envia_todo(fd, frame, len);
        if (ok) {
            g_status.tx_bytes += (uint64_t)len;
        } else {
            /* No se cierra aqui: el duenno del descriptor es la tarea
             * servidora, y cerrarlo bajo sus pies la dejaria haciendo `recv`
             * sobre un numero reutilizado. Se marca y ella lo ve. */
            g_status.send_errors++;
            g_fd = -1;
        }
    }
    xSemaphoreGive(g_tx);
    return ok;
}

bool DrxTransport_Send(const uint8_t *frame, size_t len)
{
    return envia_bloqueando(frame, len);
}

static size_t control_send(const uint8_t *frame, size_t len, void *user)
{
    (void)user;
    return envia_bloqueando(frame, len) ? len : 0u;
}

/* Sumidero de rayos. Corre en la tarea de rayos, no en la interrupcion.
 *
 * NO toca la red: coge un hueco del pool, enmarca y encola. Ese es el punto --
 * ver la nota del pool sobre lo que costaba enviar desde aqui.
 *
 * Devolver false cuenta como `sink_drops` en `drx_ray.c`: descartar el rayo
 * nuevo, no bloquear la tarea de rayos ni dejar crecer una cola sin limite. Es
 * la unica opcion que no rompe el tiempo real, y lo que cuesta --que una
 * congestion de red se traduzca en huecos de radial-- esta dicho en D-16. */
static bool ray_sink(const DrxRayHeader *header, const uint32_t *iq,
                     uint32_t n_words, void *user)
{
    (void)user;

    uint8_t slot;
    if (g_libres == NULL || xQueueReceive(g_libres, &slot, 0) != pdTRUE) {
        /* El transmisor no da abasto. Un rayo menos, y la tarea de rayos
         * sigue reciclando descriptores, que es lo que importa. */
        g_status.rays_dropped++;
        g_status.queue_full++;
        return false;
    }

    DrxRayContext ctx;
    DrxRayCtx_Fill(&ctx, header);

    size_t len = DrxRayFrame_Encode(g_pool[slot], DRX_RAY_FRAME_MAX, header,
                                    &ctx, iq, n_words);
    if (len == 0u) {
        g_status.rays_dropped++;
        g_status.encode_fails++;
        /* Las cifras del rayo que no se pudo enmarcar, en el momento. Contarlo
         * no bastaba: `DrxRayFrame_Encode` rechaza por varias razones y desde
         * fuera se ven igual. Y `drx_ray.c` solo marca `short_rays` cuando el
         * rayo llega CORTO; uno que llega LARGO no lo marcaba nadie y aun asi
         * el encoder lo rechaza, que compara con `!=` (ver P-18). */
        xil_printf("drx_transport: rayo sin enmarcar idx=%lu trig=%lu "
                   "bins=%lu n_ch=%lu n_words=%lu esperadas=%lu batch=%lu\r\n",
                   (unsigned long)header->ray_index,
                   (unsigned long)header->trig_count,
                   (unsigned long)header->bin_count,
                   (unsigned long)header->n_ch,
                   (unsigned long)n_words,
                   (unsigned long)((uint32_t)header->bin_count * (uint32_t)header->n_ch),
                   (unsigned long)header->batch_high);
        (void)xQueueSend(g_libres, &slot, 0);
        return false;
    }

    g_pool_len[slot] = len;
    if (xQueueSend(g_listos, &slot, 0) != pdTRUE) {
        g_status.rays_dropped++;
        g_status.queue_full++;
        (void)xQueueSend(g_libres, &slot, 0);
        return false;
    }
    return true;
}

/* Tarea de transmision: la UNICA que se bloquea en el socket. */
static void DrxTxTask(void *pvParameters)
{
    (void)pvParameters;
    for (;;) {
        uint8_t slot;
        if (xQueueReceive(g_listos, &slot, portMAX_DELAY) != pdTRUE) {
            continue;
        }
        if (envia_bloqueando(g_pool[slot], g_pool_len[slot])) {
            g_status.rays_sent++;
        } else {
            g_status.rays_dropped++;
            g_status.send_fails++;
        }
        (void)xQueueSend(g_libres, &slot, portMAX_DELAY);
    }
}

static void atiende(int fd)
{
    DrxControlOps ops = {
        .select_stimulus = tr_select_stimulus,
        .apply_config = tr_apply_config,
        .apply_afc = DrxAfcApp_Apply,
        .user = NULL,
    };
    DrxControl_Init(&g_ctl, &ops, control_send, NULL);
    DrxParser_Init(&g_parser, g_parse_buf, sizeof(g_parse_buf));
    DrxStatusTask_AttachControl(&g_ctl);

    /* El sumidero se instala SOLO mientras hay cliente. Dejarlo puesto sin
     * nadie conectado haria que cada rayo contase como `sink_drops`, y ese
     * contador dejaria de significar "el DSP no da abasto" para significar
     * "no hay DSP", que es otra cosa. */
    DrxRay_SetSink(ray_sink, NULL);

    for (;;) {
        int n = lwip_recv(fd, g_rx, sizeof(g_rx), 0);
        if (n <= 0) {
            break; /* 0 = el DSP cerro; <0 = error */
        }
        g_status.rx_bytes += (uint64_t)n;
        (void)DrxParser_Push(&g_parser, g_rx, (size_t)n, DrxControl_OnMessage, &g_ctl);
        if (g_fd < 0) {
            break; /* un emisor marco el descriptor como muerto */
        }
    }

    DrxRay_SetSink(NULL, NULL);
}

static void DrxTransportTask(void *pvParameters)
{
    (void)pvParameters;

    int srv = lwip_socket(AF_INET, SOCK_STREAM, 0);
    if (srv < 0) {
        xil_printf("drx_transport: no hay socket, tarea detenida\r\n");
        vTaskDelete(NULL);
        return;
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = lwip_htons(DRX_DSP_TCP_PORT);
    addr.sin_addr.s_addr = INADDR_ANY;

    if (lwip_bind(srv, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
        lwip_listen(srv, DRX_TRANSPORT_BACKLOG) < 0) {
        xil_printf("drx_transport: bind/listen fallo en el puerto %u\r\n",
                   (unsigned)DRX_DSP_TCP_PORT);
        lwip_close(srv);
        vTaskDelete(NULL);
        return;
    }

    xil_printf("drx_transport: escuchando en el puerto %u (contrato v%u.%u)\r\n",
               (unsigned)DRX_DSP_TCP_PORT, (unsigned)DRX_DSP_VERSION_MAJOR,
               (unsigned)DRX_DSP_VERSION_MINOR);

    for (;;) {
        struct sockaddr_in cli;
        socklen_t cli_len = sizeof(cli);
        int fd = lwip_accept(srv, (struct sockaddr *)&cli, &cli_len);
        if (fd < 0) {
            continue;
        }

        /* Nagle fuera: un rayo son decenas de kB y sale entero de una vez,
         * pero una respuesta de control son 16 bytes, y con Nagle se quedaria
         * esperando a que hubiera mas datos que enviar. El DSP mide el tiempo
         * de ida y vuelta del `config_ack`. */
        int uno = 1;
        (void)lwip_setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &uno, sizeof(uno));

        xSemaphoreTake(g_tx, portMAX_DELAY);
        g_fd = fd;
        xSemaphoreGive(g_tx);

        g_status.accepts++;
        g_status.connected = true;
        xil_printf("drx_transport: DSP conectado (%lu en total)\r\n",
                   (unsigned long)g_status.accepts);

        atiende(fd);

        xSemaphoreTake(g_tx, portMAX_DELAY);
        g_fd = -1;
        xSemaphoreGive(g_tx);

        g_status.connected = false;
        /* Las tramas que quedaran encoladas son de una conexion que ya no
         * existe. Se devuelven al pool en vez de mandarse al siguiente DSP,
         * que recibiria rayos de antes de conectarse. */
        uint8_t slot;
        while (xQueueReceive(g_listos, &slot, 0) == pdTRUE) {
            (void)xQueueSend(g_libres, &slot, 0);
        }
        lwip_close(fd);
        xil_printf("drx_transport: DSP desconectado "
                   "(rayos=%lu descartados=%lu tx=%luMB)\r\n",
                   (unsigned long)g_status.rays_sent,
                   (unsigned long)g_status.rays_dropped,
                   (unsigned long)(g_status.tx_bytes >> 20));
    }
}

void DrxTransport_GetStatus(DrxTransportStatus *out)
{
    if (out != NULL) {
        *out = g_status;
    }
}

void DrxTransportTask_Create(void)
{
    g_tx = xSemaphoreCreateMutex();
    g_libres = xQueueCreate(DRX_TX_SLOTS, sizeof(uint8_t));
    g_listos = xQueueCreate(DRX_TX_SLOTS, sizeof(uint8_t));
    if (g_tx == NULL || g_libres == NULL || g_listos == NULL) {
        xil_printf("drx_transport: sin mutex o colas, no se crean las tareas\r\n");
        return;
    }
    for (uint8_t i = 0u; i < (uint8_t)DRX_TX_SLOTS; i++) {
        (void)xQueueSend(g_libres, &i, 0);
    }

    /* El transmisor va por DEBAJO del servidor y, sobre todo, por debajo de la
     * tarea de rayos: si la red se atasca, quien tiene que seguir corriendo es
     * la que recicla descriptores del S2MM. */
    xTaskCreate(DrxTxTask, "drx_tx", DRX_TRANSPORT_STACK_WORDS, NULL,
                DRX_TRANSPORT_PRIORITY - 1, NULL);
    xTaskCreate(DrxTransportTask, "drx_transport", DRX_TRANSPORT_STACK_WORDS,
                NULL, DRX_TRANSPORT_PRIORITY, NULL);
}
