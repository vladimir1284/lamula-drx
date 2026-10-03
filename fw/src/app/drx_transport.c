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
#include "semphr.h"
#include "task.h"
#include "xil_printf.h"

#include "lwip/sockets.h"

#include <string.h>

#define DRX_TRANSPORT_STACK_WORDS 2048
#define DRX_TRANSPORT_PRIORITY (tskIDLE_PRIORITY + 2)
#define DRX_TRANSPORT_BACKLOG 1

/* Buffer de salida de una trama `ray`, dimensionado al rayo mas grande que el
 * bitstream puede producir. No se puede evitar: la carga util de la DDR viene
 * en {I[31:16], Q[15:0]} y el contrato pide el par en orden I,Q, asi que
 * `DrxRayFrame_Encode` tiene que escribir en algun sitio. Lo usa SOLO la tarea
 * de rayos, que es la unica que llama al sumidero. */
static uint8_t g_ray_frame[DRX_RAY_MAX_BINS * DRX_RAY_N_CH * 4u + 64u];

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
 * Devolver false cuenta como `sink_drops` en `drx_ray.c` y es lo correcto
 * cuando el envio falla: descartar el rayo nuevo, no bloquear la tarea de
 * rayos ni dejar crecer una cola sin limite. Es la unica opcion que no rompe
 * el tiempo real, y lo que cuesta --que una congestion de red se traduzca en
 * huecos de radial-- esta dicho en D-16. */
static bool ray_sink(const DrxRayHeader *header, const uint32_t *iq,
                     uint32_t n_words, void *user)
{
    (void)user;

    DrxRayContext ctx;
    DrxRayCtx_Fill(&ctx, header);

    size_t len = DrxRayFrame_Encode(g_ray_frame, sizeof(g_ray_frame), header,
                                    &ctx, iq, n_words);
    if (len == 0u) {
        g_status.rays_dropped++;
        return false;
    }
    if (!envia_bloqueando(g_ray_frame, len)) {
        g_status.rays_dropped++;
        return false;
    }
    g_status.rays_sent++;
    return true;
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
    if (g_tx == NULL) {
        xil_printf("drx_transport: sin mutex, no se crea la tarea\r\n");
        return;
    }
    xTaskCreate(DrxTransportTask, "drx_transport", DRX_TRANSPORT_STACK_WORDS,
                NULL, DRX_TRANSPORT_PRIORITY, NULL);
}
