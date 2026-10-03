/* Implementacion de fw/include/drx_ray.h.
 *
 * Reparto entre interrupcion y tarea, y por que asi: el manejador NO recoge
 * descriptores ni toca el sumidero. Solo reconoce la interrupcion y suelta un
 * semaforo. Recoger descriptores obliga a invalidar cache y recorrer el
 * anillo, y entregar un rayo puede acabar en una pila TCP; hacer cualquiera de
 * las dos cosas en contexto de interrupcion, a 223 rayos por segundo, alarga
 * el camino critico del sistema entero por un trabajo que no tiene plazo duro
 * -- el plazo lo fija el anillo de DRX_RAY_BUFFERS descriptores, que da ~18 ms
 * de margen.
 *
 * Los descriptores se dimensionan al rayo MAS GRANDE que el bitstream puede
 * producir, no al que la configuracion actual produce: el DMA cierra el
 * descriptor antes por RXEOF (que viene de TLAST), asi que un rayo del lote
 * alto ocupa menos de lo reservado y no hay que reprogramar el anillo al
 * cambiar de lote a mitad de radial. La longitud REAL se lee de
 * `XAxiDma_BdGetActualLength`.
 */
#include "drx_ray.h"

#include "drx_afc_app.h"
#include "drx_dma.h"
#include "drx_regs.h"
#include "drx_regs_hw.h"

#include "FreeRTOS.h"
#include "semphr.h"
#include "task.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xparameters.h"

#include <string.h>

/* Identificador de la interrupcion de fin de descriptor del canal S2MM.
 *
 * El nombre `XPAR_FABRIC_*` lo genera el BSP a partir del nombre de la celda
 * del block design, asi que puede cambiar si alguien renombra `dma` en
 * tcl/gen_zynq_bd.tcl. `XPS_FPGA0_INT_ID` es la alternativa que no depende del
 * nombre: `s2mm_introut` esta cableado a In0 del `xlconcat`, es decir al bit 0
 * de IRQ_F2P, que en el Zynq-7000 es siempre esa ID. */
#if defined(XPAR_FABRIC_DMA_S2MM_INTROUT_INTR)
#define DRX_RAY_IRQ_ID XPAR_FABRIC_DMA_S2MM_INTROUT_INTR
#else
#define DRX_RAY_IRQ_ID XPS_FPGA0_INT_ID
#endif

#define DRX_RAY_TASK_STACK_WORDS 2048
#define DRX_RAY_TASK_PRIORITY (tskIDLE_PRIORITY + 2)

/* Un descriptor por rayo. Ver `c_sg_length_width` en tcl/gen_zynq_bd.tcl. */
#define DRX_RAY_BD_RING (DRX_RAY_BUFFERS * 2u)

static XAxiDma *g_dma;
static bool g_ready;

static SemaphoreHandle_t g_sem;
static DrxRayStatus g_status;
static DrxRay_Sink g_sink;
static void *g_sink_user;

/* El DMA ESCRIBE estos buffers y la CPU los lee: hay que invalidar antes de
 * mirarlos. Alineados a linea de cache para que invalidar uno no arrastre al
 * vecino. */
static uint32_t g_buf[DRX_RAY_BUFFERS][DRX_RAY_BUF_WORDS] __attribute__((aligned(64)));

static char g_bd_space[XAXIDMA_BD_MINIMUM_ALIGNMENT * DRX_RAY_BD_RING]
    __attribute__((aligned(XAXIDMA_BD_MINIMUM_ALIGNMENT)));

/* Congelado: indice del buffer que NO se rearma, para que una lectura por
 * JTAG vea un rayo entero y quieto. -1 = ninguno. */
static volatile bool g_freeze_request;
static volatile int g_frozen_index = -1;

/* Ultimo rayo completo, para DrxRay_DumpLast(). */
static const uint32_t *g_last_buf;
static uint32_t g_last_words;
static DrxRayHeader g_last_header;

/* Copia del anterior en el instante de congelar. Hace falta aparte: una misma
 * pasada del recolector puede entregar varios rayos, y se congela el primero
 * mientras `g_last_*` acaba apuntando al ultimo -- que sigue en el anillo y se
 * reescribe. La primera version no lo separaba, y la lectura por JTAG traia un
 * rayo distinto del que la UART habia anunciado. */
static uint32_t g_frozen_words;
static DrxRayHeader g_frozen_header;

static bool submit_buffer(uint32_t index)
{
    XAxiDma_BdRing *ring = XAxiDma_GetRxRing(g_dma);
    XAxiDma_Bd *bd = NULL;

    if (XAxiDma_BdRingAlloc(ring, 1, &bd) != XST_SUCCESS) {
        return false;
    }
    if (XAxiDma_BdSetBufAddr(bd, (UINTPTR)&g_buf[index][0]) != XST_SUCCESS ||
        XAxiDma_BdSetLength(bd, DRX_RAY_MAX_BYTES, ring->MaxTransferLen) != XST_SUCCESS) {
        XAxiDma_BdRingUnAlloc(ring, 1, bd);
        return false;
    }
    /* En S2MM los bits de control de SOF/EOF los pone el HARDWARE en el
     * estado, a partir de TLAST; aqui no se ponen. El Id es el indice del
     * buffer, que es como se recupera al recoger. */
    XAxiDma_BdSetCtrl(bd, 0);
    XAxiDma_BdSetId(bd, index);

    /* Invalida antes de entregarlo, no despues de recogerlo nada mas: si
     * quedara una linea sucia de la CPU sobre este buffer, el write-back
     * posterior pisaria lo que el DMA acaba de escribir. */
    Xil_DCacheInvalidateRange((INTPTR)&g_buf[index][0], DRX_RAY_MAX_BYTES);

    if (XAxiDma_BdRingToHw(ring, 1, bd) != XST_SUCCESS) {
        XAxiDma_BdRingUnAlloc(ring, 1, bd);
        return false;
    }
    return true;
}

static void ray_isr(void *ref)
{
    (void)ref;

    XAxiDma_BdRing *ring = XAxiDma_GetRxRing(g_dma);
    u32 irq = XAxiDma_BdRingGetIrq(ring);

    XAxiDma_BdRingAckIrq(ring, irq);

    if ((irq & XAXIDMA_IRQ_ERROR_MASK) != 0u) {
        g_status.dma_errors++;
        /* Y se desarma la interrupcion de error. Una condicion de error del
         * DMA puede quedarse asertada: reconocerla no la borra, asi que el
         * manejador volveria a entrar sin parar y el sistema se quedaria sin
         * avanzar, con la UART muda -- un sintoma que en esta placa solo
         * arregla el interruptor SW8. El contador ya registro el fallo; el
         * siguiente DrxRay_Init() la vuelve a armar. */
        XAxiDma_BdRingIntDisable(ring, XAXIDMA_IRQ_ERROR_MASK);
    }
    if ((irq & (XAXIDMA_IRQ_IOC_MASK | XAXIDMA_IRQ_DELAY_MASK)) != 0u) {
        BaseType_t woken = pdFALSE;
        xSemaphoreGiveFromISR(g_sem, &woken);
        portYIELD_FROM_ISR(woken);
    }
}

/* Deshace las DRX_RAY_META_WORDS palabras de cabecera en banda. Devuelve false
 * si el buffer no empieza por un rayo: con backpressure y un anillo mal
 * rearmado, el sintoma sin esta comprobacion serian muestras desplazadas medio
 * rayo, que parecen datos validos. */
static bool parse_header(const uint32_t *words, DrxRayHeader *out)
{
    if (words[0] != DRX_RAY_MAGIC) {
        return false;
    }
    uint32_t flags = words[3];

    out->trig_count = words[1];
    out->ray_index = words[2];
    out->bin_count = (uint16_t)(flags & 0xFFFFu);
    out->batch_high = ((flags >> 16) & 1u) != 0u;
    out->mode_coarse = ((flags >> 17) & 1u) != 0u;
    out->n_ch = (uint8_t)((flags >> 24) & 0xFFu);
    return true;
}

static void deliver(uint32_t index, uint32_t bytes)
{
    const uint32_t *words = &g_buf[index][0];
    DrxRayHeader header;

    /* Invalidar DE NUEVO, ahora que el DMA ya escribio. La invalidacion de
     * `submit_buffer` marca las lineas antes de entregarlo, pero entre ese
     * momento y esta lectura el A9 puede haber vuelto a traer lineas por
     * prefetch especulativo: son direcciones que el codigo acaba de tocar. Sin
     * esto se leeria el rayo ANTERIOR en parte del buffer, que es un fallo
     * intermitente y dependiente del tamano del rayo. */
    Xil_DCacheInvalidateRange((INTPTR)words, DRX_RAY_MAX_BYTES);

    if (bytes < DRX_RAY_META_WORDS * 4u || !parse_header(words, &header)) {
        if (g_status.rays == 0u && g_status.resync == 0u) {
            /* El PRIMER descriptor se arma a mitad de un rayo en curso: el
             * motor de timing lleva corriendo desde antes de que este modulo
             * existiera. Lo que recoge es la COLA de ese rayo, sin cabecera, y
             * se cierra en su TLAST. Es inevitable y se cuenta aparte: a partir
             * del siguiente, el anillo ya esta en frontera de rayo. */
            g_status.resync++;
        } else {
            g_status.bad_magic++;
        }
        return;
    }
    if ((uint32_t)header.n_ch != DRX_RAY_N_CH) {
        /* El bitstream cargado instancia otro numero de canales que el que
         * este firmware compilo. Sin esta comprobacion el rayo se recorreria
         * con el paso equivocado y cada canal traeria muestras de otro. */
        g_status.bad_n_ch++;
        return;
    }

    uint32_t n_words = (bytes / 4u) - DRX_RAY_META_WORDS;
    uint32_t esperadas = (uint32_t)header.bin_count * DRX_RAY_N_CH;

    /* Asimetria deliberada hasta Z4.6, y costo una noche de soak entenderla:
     * esto solo cuenta el rayo CORTO. Uno que llega LARGO no lo marca nadie
     * aqui, y sin embargo `DrxRayFrame_Encode` lo rechaza igual, porque
     * compara `n_words` con `bin_count * n_ch` usando `!=`. El resultado era
     * un descarte con `cortos=0`, que parecia imposible. Se cuentan los dos. */
    if (n_words < esperadas) {
        g_status.short_rays++;
    } else if (n_words > esperadas) {
        g_status.long_rays++;
    }

    /* Continuidad. Los dos contadores avanzan de uno en uno y por caminos
     * distintos: `trig_count` lo lleva el motor de timing, `ray_index` el
     * empaquetador. Que uno salte y el otro no dice cual de los dos lados
     * perdio el paso. El primer rayo no tiene con que compararse. */
    if (g_status.rays > 0u) {
        if (header.trig_count != g_status.last_trig_count + 1u) {
            g_status.trig_gaps++;
            g_status.last_trig_delta = header.trig_count - g_status.last_trig_count;
        }
        if (header.ray_index != g_status.last_ray_index + 1u) {
            g_status.ray_gaps++;
        }
    }
    g_status.last_trig_count = header.trig_count;
    g_status.last_ray_index = header.ray_index;

    g_last_buf = words;
    g_last_words = n_words;
    g_last_header = header;
    g_status.rays++;

    if (g_sink != NULL) {
        if (!g_sink(&header, &words[DRX_RAY_META_WORDS], n_words, g_sink_user)) {
            g_status.sink_drops++;
        }
    }

    /* Z4.5: una correccion de AFC con `apply_at_seq` se aplica AQUI, entre dos
     * rayos, que es la unica frontera en la que el salto de palabra de fase no
     * parte un rayo en dos frecuencias de mezcla. */
    DrxAfcApp_OnRay(header.ray_index);
}

static void reap(void)
{
    XAxiDma_BdRing *ring = XAxiDma_GetRxRing(g_dma);
    XAxiDma_Bd *bd_set = NULL;

    int done = XAxiDma_BdRingFromHw(ring, XAXIDMA_ALL_BDS, &bd_set);
    if (done <= 0) {
        return;
    }

    /* Los indices se apuntan antes de liberar: `XAxiDma_BdRingFree` devuelve
     * los descriptores al anillo libre y a partir de ahi su contenido puede
     * reescribirse. */
    uint32_t indices[DRX_RAY_BD_RING];
    int n = 0;
    XAxiDma_Bd *bd = bd_set;

    for (int i = 0; i < done && n < (int)DRX_RAY_BD_RING; i++) {
        uint32_t index = (uint32_t)XAxiDma_BdGetId(bd);
        uint32_t bytes = XAxiDma_BdGetActualLength(bd, ring->MaxTransferLen);

        if ((XAxiDma_BdGetSts(bd) & XAXIDMA_BD_STS_ALL_ERR_MASK) != 0u) {
            g_status.dma_errors++;
        } else if (index < DRX_RAY_BUFFERS) {
            deliver(index, bytes);
        }
        if (index < DRX_RAY_BUFFERS) {
            if (g_freeze_request && g_frozen_index < 0) {
                /* Este buffer se queda fuera del anillo hasta DrxRay_Thaw().
                 * Se congela DESPUES de entregarlo, asi que la cabecera que
                 * DrxRay_DumpLast() imprime es la del rayo que seguira ahi. */
                g_freeze_request = false;
                g_frozen_index = (int)index;
                g_frozen_header = g_last_header;
                g_frozen_words = g_last_words;
            } else {
                indices[n++] = index;
            }
        }
        bd = (XAxiDma_Bd *)XAxiDma_BdRingNext(ring, bd);
    }

    XAxiDma_BdRingFree(ring, done, bd_set);

    for (int i = 0; i < n; i++) {
        (void)submit_buffer(indices[i]);
    }
}

static void ray_task(void *arg)
{
    (void)arg;

    for (;;) {
        if (xSemaphoreTake(g_sem, portMAX_DELAY) == pdTRUE) {
            reap();
        }
    }
}

bool DrxRay_Init(void)
{
    memset(&g_status, 0, sizeof(g_status));
    g_ready = false;
    g_last_buf = NULL;
    g_last_words = 0u;

    if (!DrxDma_Init()) {
        return false;
    }
    g_dma = DrxDma_Get();

    XAxiDma_Config *config = XAxiDma_LookupConfig(XPAR_AXIDMA_0_DEVICE_ID);
    if (config == NULL || config->HasS2Mm == 0) {
        /* El sintoma sin este aviso seria que no llega ni un rayo y que
         * STATUS(overrun) se queda en 0x7: el bitstream es anterior a Z4.0. */
        xil_printf("drx_ray: el bitstream no trae el canal S2MM\r\n");
        return false;
    }

    g_sem = xSemaphoreCreateBinary();
    if (g_sem == NULL) {
        xil_printf("drx_ray: no hay memoria para el semaforo\r\n");
        return false;
    }

    XAxiDma_BdRing *ring = XAxiDma_GetRxRing(g_dma);
    XAxiDma_BdRingIntDisable(ring, XAXIDMA_IRQ_ALL_MASK);

    int status = XAxiDma_BdRingCreate(ring, (UINTPTR)&g_bd_space[0],
                                      (UINTPTR)&g_bd_space[0],
                                      XAXIDMA_BD_MINIMUM_ALIGNMENT,
                                      DRX_RAY_BD_RING);
    if (status != XST_SUCCESS) {
        xil_printf("drx_ray: XAxiDma_BdRingCreate fallo (%d)\r\n", status);
        return false;
    }

    XAxiDma_Bd template_bd;
    XAxiDma_BdClear(&template_bd);
    if (XAxiDma_BdRingClone(ring, &template_bd) != XST_SUCCESS) {
        xil_printf("drx_ray: XAxiDma_BdRingClone fallo\r\n");
        return false;
    }

    /* Una interrupcion por descriptor. Agrupar varias ahorraria interrupciones
     * pero retrasaria el primer rayo del grupo por el tiempo del ultimo, y a
     * 223 rayos/s no hay ningun problema de carga que resolver. */
    XAxiDma_BdRingSetCoalesce(ring, 1, 0);

    if (xPortInstallInterruptHandler(DRX_RAY_IRQ_ID, ray_isr, NULL) != pdPASS) {
        xil_printf("drx_ray: no se pudo instalar la interrupcion %d\r\n",
                   (int)DRX_RAY_IRQ_ID);
        return false;
    }
    vPortEnableInterrupt(DRX_RAY_IRQ_ID);
    XAxiDma_BdRingIntEnable(ring, XAXIDMA_IRQ_ALL_MASK);

    if (XAxiDma_BdRingStart(ring) != XST_SUCCESS) {
        xil_printf("drx_ray: XAxiDma_BdRingStart fallo\r\n");
        return false;
    }

    g_ready = true;

    for (uint32_t i = 0; i < DRX_RAY_BUFFERS; i++) {
        if (!submit_buffer(i)) {
            xil_printf("drx_ray: no se pudo encolar el buffer %lu\r\n",
                       (unsigned long)i);
            g_ready = false;
            return false;
        }
    }

    xil_printf("drx_ray: S2MM listo, %lu buffers de %lu B\r\n",
               (unsigned long)DRX_RAY_BUFFERS, (unsigned long)DRX_RAY_MAX_BYTES);
    return true;
}

uint32_t DrxRay_LastIndex(void)
{
    return (g_status.rays == 0u) ? 0u : g_status.last_ray_index;
}

void DrxRay_SetSink(DrxRay_Sink sink, void *user)
{
    g_sink = sink;
    g_sink_user = user;
}

void DrxRayTask_Create(void)
{
    (void)xTaskCreate(ray_task, "drx_ray", DRX_RAY_TASK_STACK_WORDS, NULL,
                      DRX_RAY_TASK_PRIORITY, NULL);
}

bool DrxRay_Freeze(void)
{
    if (g_frozen_index >= 0) {
        return false;
    }
    g_freeze_request = true;
    return true;
}

void DrxRay_Thaw(void)
{
    int index = g_frozen_index;

    g_freeze_request = false;
    if (index >= 0) {
        g_frozen_index = -1;
        (void)submit_buffer((uint32_t)index);
    }
}

bool DrxRay_GetLast(DrxRayHeader *header, const uint32_t **iq, uint32_t *n_words)
{
    /* Si hay uno congelado se devuelve ESE: es el unico que no se va a
     * reescribir mientras se mira. */
    if (g_frozen_index >= 0) {
        if (header != NULL) *header = g_frozen_header;
        if (iq != NULL) *iq = &g_buf[g_frozen_index][DRX_RAY_META_WORDS];
        if (n_words != NULL) *n_words = g_frozen_words;
        return true;
    }
    if (g_last_buf == NULL) {
        return false;
    }
    if (header != NULL) *header = g_last_header;
    if (iq != NULL) *iq = &g_last_buf[DRX_RAY_META_WORDS];
    if (n_words != NULL) *n_words = g_last_words;
    return true;
}

void DrxRay_GetStatus(DrxRayStatus *out)
{
    if (out != NULL) {
        *out = g_status;
    }
}

bool DrxRay_SelfTest(uint32_t ms)
{
    if (!g_ready) {
        xil_printf("drx_ray: autoprueba sin driver arrancado\r\n");
        return false;
    }

    /* Primero dejar que el camino se asiente, y DESPUES limpiar los sticky.
     *
     * El orden importa y costo una corrida descubrirlo. `drx_range_gate` lleva
     * desde el arranque del motor de timing llenando bancos que nadie vaciaba
     * -- el consumidor es este modulo, que acaba de existir -- asi que los dos
     * bancos estan marcados como pendientes. El primer banco que se completa
     * despues de armar el anillo encuentra el suyo todavia pendiente y levanta
     * `overrun` una vez, unos milisegundos despues de armar. Limpiar antes de
     * esa ventana y medir a continuacion contaba ese arrastre como un fallo de
     * regimen permanente, que es justo lo contrario de lo que se quiere medir.
     *
     * Medido en placa el 1-oct-2026: con esta espera, overrun y
     * GATE_TRUNCATED se quedan en 0 mientras llegan ~231 rayos por segundo. */
    vTaskDelay(pdMS_TO_TICKS(DRX_RAY_SETTLE_MS));
    DrxReg_ClearStatus(0xFFFFFFFFu);
    DrxReg_ClearGateTruncated(0xFFFFFFFFu);

    uint32_t rays_antes = g_status.rays;
    vTaskDelay(pdMS_TO_TICKS(ms));

    uint32_t rays = g_status.rays - rays_antes;
    uint32_t overrun = DrxReg_Read(DRX_REG_STATUS_OFFSET);
    uint32_t truncated = DrxReg_Read(DRX_REG_GATE_TRUNCATED_OFFSET);

    xil_printf("drx_ray: %lu rayos en %lu ms, overrun=0x%lx truncated=0x%lx\r\n",
               (unsigned long)rays, (unsigned long)ms,
               (unsigned long)overrun, (unsigned long)truncated);
    xil_printf("drx_ray: dma_errors=%lu resync=%lu bad_magic=%lu bad_n_ch=%lu "
               "short=%lu trig_gaps=%lu ray_gaps=%lu\r\n",
               (unsigned long)g_status.dma_errors, (unsigned long)g_status.resync,
               (unsigned long)g_status.bad_magic, (unsigned long)g_status.bad_n_ch,
               (unsigned long)g_status.short_rays,
               (unsigned long)g_status.trig_gaps, (unsigned long)g_status.ray_gaps);

    /* `resync` NO cuenta como fallo: es el descriptor que se armo a mitad de un
     * rayo en curso, y hay exactamente uno por arranque. */
    bool ok = (rays > 0u) && (overrun == 0u) && (truncated == 0u) &&
              (g_status.bad_magic == 0u) && (g_status.bad_n_ch == 0u);
    if (!ok) {
        xil_printf("drx_ray: autoprueba FALLO\r\n");
    }
    return ok;
}

void DrxRay_DumpLast(uint32_t n_words)
{
    DrxRayHeader cabecera;
    const uint32_t *base = NULL;
    uint32_t palabras = 0u;

    if (!DrxRay_GetLast(&cabecera, &base, &palabras)) {
        xil_printf("drx_ray: todavia no llego ningun rayo\r\n");
        return;
    }
    /* `base` apunta ya detras del metadato; la direccion que se imprime es la
     * del PRINCIPIO del rayo, que es lo que tools/dump_ray.py necesita para
     * encontrar el magic. */
    const uint32_t *inicio = base - DRX_RAY_META_WORDS;

    xil_printf("drx_ray: rayo idx=%lu trig=%lu bins=%lu n_ch=%lu batch=%lu "
               "coarse=%lu palabras=%lu addr=0x%08lx congelado=%lu\r\n",
               (unsigned long)cabecera.ray_index,
               (unsigned long)cabecera.trig_count,
               (unsigned long)cabecera.bin_count,
               (unsigned long)cabecera.n_ch,
               (unsigned long)(cabecera.batch_high ? 1u : 0u),
               (unsigned long)(cabecera.mode_coarse ? 1u : 0u),
               (unsigned long)palabras,
               (unsigned long)(UINTPTR)inicio,
               (unsigned long)(g_frozen_index >= 0 ? 1u : 0u));

    uint32_t n = (n_words < palabras) ? n_words : palabras;
    for (uint32_t i = 0; i < n; i++) {
        xil_printf("%08lx%s", (unsigned long)base[i],
                   ((i % 8u) == 7u) ? "\r\n" : " ");
    }
    if (n > 0u && (n % 8u) != 0u) {
        xil_printf("\r\n");
    }
}
