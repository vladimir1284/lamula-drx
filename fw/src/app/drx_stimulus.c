/* Implementacion de fw/include/drx_stimulus.h.
 *
 * Usa el driver `xaxidma` del BSP, no un driver propio sobre los registros del
 * DMA: el criterio Xilinx-IP-first de AGENTS.md vale igual para el software de
 * la IP que para la IP. El DMA esta configurado en scatter-gather
 * (`c_include_sg {1}` en tcl/gen_zynq_bd.tcl, decision de Z4.0 para los
 * buffers circulares de rayo), asi que `XAxiDma_SimpleTransfer` no existe aqui
 * y hay que pasar por un anillo de descriptores aunque la transferencia sea
 * una sola region contigua.
 *
 * Por sondeo y no por interrupcion, a proposito. La interrupcion de fin de
 * descriptor del canal MM2S existe en el bitstream (bit 1 de IRQ_F2P, ver
 * tcl/gen_zynq_bd.tcl) y la va a necesitar Z4.4 para el canal S2MM, donde el
 * firmware tiene que reaccionar a cada rayo. Aqui no compra nada: la tarea que
 * rearma el DMA entre pasadas es la unica que espera, no tiene plazo que
 * cumplir, y montar el GIC para ella seria codigo que Z4.4 va a reescribir.
 */
#include "drx_stimulus.h"

#include "drx_dma.h"
#include "drx_regs.h"
#include "drx_regs_hw.h"
#include "drx_stimulus_catalog.h"

#include "FreeRTOS.h"
#include "task.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xparameters.h"

#include <string.h>

#define DRX_STIMULUS_TASK_STACK_WORDS 1024
#define DRX_STIMULUS_TASK_PRIORITY (tskIDLE_PRIORITY + 1)
#define DRX_STIMULUS_POLL_MS 10

/* Muestras del buffer entrelazado: una pasada completa del vector por los
 * N_CH canales. `vector_source` consume el stream canal 0, 1, ..., N_CH-1 y
 * repite, y exige que el total sea multiplo de N_CH -- un conjunto a medio
 * llenar nunca se presenta y la cadena se queda parada en silencio (ver la
 * cabecera de rtl/vector_source.sv). Aqui lo es por construccion. */
#define DRX_STIMULUS_SAMPLES (DRX_STIMULUS_DEPTH * DRX_STIMULUS_N_CH)
#define DRX_STIMULUS_BYTES (DRX_STIMULUS_SAMPLES * sizeof(int16_t))

/* Bytes por descriptor. El tope lo fija el ancho del campo de longitud del
 * DMA (`c_sg_length_width`, 14 bits en esta configuracion -> 16383 B); se
 * redondea hacia abajo a multiplo de N_CH*2 para que ningun descriptor corte
 * un conjunto de canales por la mitad. Que el corte caiga en una frontera de
 * conjunto no es cosmetico: `vector_source` no ve descriptores, solo beats, y
 * un corte a mitad de conjunto desplazaria el reparto por canal de todo lo que
 * viene detras. */
#define DRX_STIMULUS_SET_BYTES (DRX_STIMULUS_N_CH * sizeof(int16_t))
#define DRX_STIMULUS_MAX_BD_BYTES \
    ((((1u << XPAR_AXIDMA_0_c_sg_length_width) - 1u) / DRX_STIMULUS_SET_BYTES) \
     * DRX_STIMULUS_SET_BYTES)

#define DRX_STIMULUS_BD_COUNT \
    ((DRX_STIMULUS_BYTES + DRX_STIMULUS_MAX_BD_BYTES - 1u) / DRX_STIMULUS_MAX_BD_BYTES)

/* Holgura sobre los descriptores que hacen falta: el anillo se reusa pasada
 * tras pasada y tener sitio de sobra evita que una pasada tenga que esperar a
 * que el hardware libere la anterior. */
#define DRX_STIMULUS_BD_RING (DRX_STIMULUS_BD_COUNT * 4u)

/* La instancia del DMA es compartida con el camino de rayos (drx_dma.c):
 * `XAxiDma_CfgInitialize` resetea el periferico entero, asi que una instancia
 * por canal haria que el segundo en arrancar tirase el anillo del primero. */
static XAxiDma *g_dma;
static bool g_ready;

/* El buffer vive en DDR y lo lee el DMA, no la CPU: cada vez que se rellena
 * hay que volcar la cache antes de entregarlo (Xil_DCacheFlushRange mas
 * abajo). Alineado a linea de cache para que el volcado no arrastre datos
 * vecinos. */
static int16_t g_buf[DRX_STIMULUS_SAMPLES] __attribute__((aligned(64)));

static char g_bd_space[XAXIDMA_BD_MINIMUM_ALIGNMENT * DRX_STIMULUS_BD_RING]
    __attribute__((aligned(XAXIDMA_BD_MINIMUM_ALIGNMENT)));

static DrxStimulusStatus g_status;
static bool g_in_flight;

static void fill_buffer(const DrxStimulusVector *vector)
{
    /* Replica el mismo vector en los N_CH canales, igual que el modo BRAM-loop
     * replica el mismo INIT_FILE en los N_CH bancos. Contenido distinto por
     * canal es un cambio de este bucle, no de estructura. */
    for (uint32_t i = 0; i < DRX_STIMULUS_DEPTH; i++) {
        int16_t sample = vector->samples[i];

        for (uint32_t c = 0; c < DRX_STIMULUS_N_CH; c++) {
            g_buf[i * DRX_STIMULUS_N_CH + c] = sample;
        }
    }
    Xil_DCacheFlushRange((INTPTR)g_buf, DRX_STIMULUS_BYTES);
}

bool DrxStimulus_Init(void)
{
    memset(&g_status, 0, sizeof(g_status));
    g_ready = false;
    g_in_flight = false;

    if (!DrxDma_Init()) {
        return false;
    }
    g_dma = DrxDma_Get();

    XAxiDma_Config *config = XAxiDma_LookupConfig(XPAR_AXIDMA_0_DEVICE_ID);
    if (config == NULL || config->HasMm2S == 0) {
        /* El sintoma sin este aviso seria que todo "funciona" y no sale ni un
         * beat: el bitstream cargado es anterior a Z4.3. */
        xil_printf("drx_stimulus: el bitstream no trae el canal MM2S\r\n");
        return false;
    }

    XAxiDma_BdRing *ring = XAxiDma_GetTxRing(g_dma);
    XAxiDma_BdRingIntDisable(ring, XAXIDMA_IRQ_ALL_MASK);

    int count = XAxiDma_BdRingCreate(ring, (UINTPTR)&g_bd_space[0],
                                     (UINTPTR)&g_bd_space[0],
                                     XAXIDMA_BD_MINIMUM_ALIGNMENT,
                                     DRX_STIMULUS_BD_RING);
    if (count != XST_SUCCESS) {
        xil_printf("drx_stimulus: XAxiDma_BdRingCreate fallo (%d)\r\n", count);
        return false;
    }

    XAxiDma_Bd template_bd;
    XAxiDma_BdClear(&template_bd);
    if (XAxiDma_BdRingClone(ring, &template_bd) != XST_SUCCESS) {
        xil_printf("drx_stimulus: XAxiDma_BdRingClone fallo\r\n");
        return false;
    }
    if (XAxiDma_BdRingStart(ring) != XST_SUCCESS) {
        xil_printf("drx_stimulus: XAxiDma_BdRingStart fallo\r\n");
        return false;
    }

    g_ready = true;
    xil_printf("drx_stimulus: AXI DMA MM2S listo, %lu vectores de %lu muestras\r\n",
               (unsigned long)DRX_STIMULUS_COUNT, (unsigned long)DRX_STIMULUS_DEPTH);
    return true;
}

/* Encola una pasada completa del buffer, troceada en tantos descriptores como
 * haga falta. SOF en el primero y EOF en el ultimo: EOF es lo que el DMA
 * convierte en `tlast`, y `tlast` es lo que `vector_source` propaga como
 * `last` a los N_CH canales. Sin EOF el vector se reproduciria sin ningun fin
 * de ventana. */
static bool submit_pass(void)
{
    XAxiDma_BdRing *ring = XAxiDma_GetTxRing(g_dma);
    XAxiDma_Bd *bd_set = NULL;

    if (XAxiDma_BdRingAlloc(ring, DRX_STIMULUS_BD_COUNT, &bd_set) != XST_SUCCESS) {
        return false;
    }

    XAxiDma_Bd *bd = bd_set;
    UINTPTR addr = (UINTPTR)g_buf;
    uint32_t left = DRX_STIMULUS_BYTES;

    for (uint32_t i = 0; i < DRX_STIMULUS_BD_COUNT; i++) {
        uint32_t chunk = (left > DRX_STIMULUS_MAX_BD_BYTES) ? DRX_STIMULUS_MAX_BD_BYTES
                                                            : left;

        if (XAxiDma_BdSetBufAddr(bd, addr) != XST_SUCCESS ||
            XAxiDma_BdSetLength(bd, chunk, ring->MaxTransferLen) != XST_SUCCESS) {
            XAxiDma_BdRingUnAlloc(ring, DRX_STIMULUS_BD_COUNT, bd_set);
            return false;
        }

        uint32_t flags = 0;
        if (i == 0u) flags |= XAXIDMA_BD_CTRL_TXSOF_MASK;
        if (i == DRX_STIMULUS_BD_COUNT - 1u) flags |= XAXIDMA_BD_CTRL_TXEOF_MASK;
        XAxiDma_BdSetCtrl(bd, flags);
        XAxiDma_BdSetId(bd, (UINTPTR)g_buf);

        addr += chunk;
        left -= chunk;
        bd = (XAxiDma_Bd *)XAxiDma_BdRingNext(ring, bd);
    }

    if (XAxiDma_BdRingToHw(ring, DRX_STIMULUS_BD_COUNT, bd_set) != XST_SUCCESS) {
        XAxiDma_BdRingUnAlloc(ring, DRX_STIMULUS_BD_COUNT, bd_set);
        return false;
    }
    g_in_flight = true;
    return true;
}

/* Recoge lo que el hardware haya terminado. Devuelve true si la pasada entera
 * se completo en esta llamada. */
static bool reap_pass(void)
{
    XAxiDma_BdRing *ring = XAxiDma_GetTxRing(g_dma);
    XAxiDma_Bd *bd_set = NULL;

    int done = XAxiDma_BdRingFromHw(ring, XAXIDMA_ALL_BDS, &bd_set);
    if (done <= 0) {
        return false;
    }

    XAxiDma_Bd *bd = bd_set;
    for (int i = 0; i < done; i++) {
        if ((XAxiDma_BdGetSts(bd) & XAXIDMA_BD_STS_ALL_ERR_MASK) != 0u) {
            g_status.errors++;
        }
        bd = (XAxiDma_Bd *)XAxiDma_BdRingNext(ring, bd);
    }
    XAxiDma_BdRingFree(ring, done, bd_set);

    g_in_flight = false;
    return true;
}

drx_dsp_error_t DrxStimulus_Select(uint8_t vector_id, uint16_t repeat)
{
    if (!g_ready) {
        return DRX_DSP_ERROR_NOT_CONFIGURED;
    }
    if (vector_id >= DRX_STIMULUS_COUNT) {
        return DRX_DSP_ERROR_VECTOR_UNKNOWN;
    }

    const DrxStimulusVector *vector = &kDrxStimulusCatalog[vector_id];

    DrxStimulus_Stop();
    fill_buffer(vector);

    g_status.name = vector->name;
    g_status.vector_id = vector_id;
    g_status.looping = (repeat == 0u);
    g_status.remaining = repeat;
    g_status.passes = 0u;
    g_status.errors = 0u;
    g_status.running = true;

    /* El modo se cambia ANTES del primer beat y con la cadena ya parada por
     * DrxStimulus_Stop(): `vector_source` no vacia el conjunto a medio llenar
     * al conmutar (ver su cabecera y el doc de CTRL en config/registers.toml). */
    uint32_t ctrl = DrxReg_Read(DRX_REG_CTRL_OFFSET);
    DrxReg_Write(DRX_REG_CTRL_OFFSET, ctrl | DRX_REG_CTRL_VECTOR_SOURCE_DDR_MASK);

    /* P-16: en Throttled(DDR) el motor de timing TIENE que contar avances de
     * muestra. `vector_source` junta N_CH beats de 16 bits por conjunto, asi
     * que contando ciclos el rayo tarda ~N_CH veces el PRI en llenarse,
     * `ray_start` lo trunca y no se completa ninguno.
     *
     * Los dos bits de registro son independientes a proposito (ver
     * drx_sample_pacer.sv); que vayan juntos es una POLITICA, y su sitio es
     * aqui, no el mapa de registros. Se bracketea con el secuenciador parado
     * porque pacear cambia lo que significa `prf_div`, y hacerlo a mitad de
     * radial deja ese radial con dos bases de tiempo. */
    const bool timing_corria = DrxReg_TimingEnabled();
    if (timing_corria) {
        DrxReg_TimingDisable();
    }
    DrxReg_TimingSetPaced(true);
    if (timing_corria) {
        DrxReg_TimingEnable();
    }

    if (!submit_pass()) {
        g_status.running = false;
        xil_printf("drx_stimulus: no se pudo encolar la primera pasada\r\n");
        return DRX_DSP_ERROR_NOT_CONFIGURED;
    }

    xil_printf("drx_stimulus: vector %lu (%s), repeat=%lu\r\n",
               (unsigned long)vector_id, vector->name,
               (unsigned long)repeat);
    return DRX_DSP_ERROR_OK;
}

void DrxStimulus_Stop(void)
{
    if (!g_ready) {
        return;
    }

    g_status.running = false;
    g_status.looping = false;
    g_status.remaining = 0u;

    XAxiDma_BdRing *ring = XAxiDma_GetTxRing(g_dma);
    XAxiDma_Pause(&g_dma);
    (void)reap_pass();
    XAxiDma_BdRingStart(ring);
    XAxiDma_Resume(&g_dma);

    uint32_t ctrl = DrxReg_Read(DRX_REG_CTRL_OFFSET);
    DrxReg_Write(DRX_REG_CTRL_OFFSET, ctrl & ~DRX_REG_CTRL_VECTOR_SOURCE_DDR_MASK);

    /* De vuelta a BRAM-loop, de vuelta a contar ciclos: ahi la fuente entrega
     * una muestra por ciclo y pacear no cambia nada, pero dejarlo encendido
     * ataria el motor al `ready` del DDC sin ninguna razon. Mismo bracketeo
     * que en Select(). */
    const bool timing_corria = DrxReg_TimingEnabled();
    if (timing_corria) {
        DrxReg_TimingDisable();
    }
    DrxReg_TimingSetPaced(false);
    if (timing_corria) {
        DrxReg_TimingEnable();
    }
}

void DrxStimulus_GetStatus(DrxStimulusStatus *out)
{
    *out = g_status;
}

static void DrxStimulusTask(void *pvParameters)
{
    (void)pvParameters;

    for (;;) {
        if (g_status.running && g_in_flight && reap_pass()) {
            g_status.passes++;

            bool again = g_status.looping;
            if (!again && g_status.remaining > 1u) {
                g_status.remaining--;
                again = true;
            } else if (!again) {
                g_status.remaining = 0u;
                g_status.running = false;
                /* Fin de la ultima pasada: se vuelve a BRAM-loop para no dejar
                 * la cadena sin fuente. En Throttled(DDR) sin DMA en curso
                 * `vector_source` no entrega nada, y aguas abajo eso se ve
                 * igual que un DDC colgado. */
                uint32_t ctrl = DrxReg_Read(DRX_REG_CTRL_OFFSET);
                DrxReg_Write(DRX_REG_CTRL_OFFSET,
                             ctrl & ~DRX_REG_CTRL_VECTOR_SOURCE_DDR_MASK);
                xil_printf("drx_stimulus: vector %s terminado, %lu pasadas\r\n",
                           g_status.name ? g_status.name : "?",
                           (unsigned long)g_status.passes);
            }

            if (again && !submit_pass()) {
                g_status.errors++;
                g_status.running = false;
            }
        }
        vTaskDelay(pdMS_TO_TICKS(DRX_STIMULUS_POLL_MS));
    }
}

bool DrxStimulus_SelfTest(uint8_t vector_id)
{
    if (!g_ready) {
        xil_printf("drx_stimulus: sin DMA, no hay nada que comprobar\r\n");
        return false;
    }

    /* OVERFLOW es sticky: se limpia primero para que lo que se lea despues sea
     * de este vector y no de lo que hubiera corriendo antes. */
    DrxReg_ClearOverflow(DrxReg_ReadOverflow());
    uint32_t overflow_antes = DrxReg_ReadOverflow();

    drx_dsp_error_t error = DrxStimulus_Select(vector_id, 2u);
    if (error != DRX_DSP_ERROR_OK) {
        xil_printf("drx_stimulus: Select devolvio %lu\r\n", (unsigned long)error);
        return false;
    }

    /* Dos pasadas de 12000 muestras a la tasa que marque la cadena. El plazo es
     * generoso a proposito: en Throttled(DDR) el ritmo lo pone el consumidor,
     * no el DMA, y lo que se comprueba es que AVANCE, no que sea rapido. */
    DrxStimulusStatus status;
    for (unsigned ms = 0; ms < 2000u; ms += 50u) {
        vTaskDelay(pdMS_TO_TICKS(50));
        DrxStimulus_GetStatus(&status);
        if (status.passes > 0u) break;
    }

    DrxStimulus_GetStatus(&status);
    uint32_t overflow_despues = DrxReg_ReadOverflow();

    xil_printf("drx_stimulus: vector %s -- pasadas=%lu errores=%lu "
               "OVERFLOW %lx -> %lx\r\n",
               status.name ? status.name : "?", (unsigned long)status.passes,
               (unsigned long)status.errors, (unsigned long)overflow_antes,
               (unsigned long)overflow_despues);

    if (status.passes == 0u) {
        xil_printf("drx_stimulus: el DMA no completo ni una pasada -- "
                   "vector_source no esta consumiendo el stream\r\n");
        return false;
    }

    xil_printf("drx_stimulus: DDR -> MM2S -> vector_source confirmado en placa\r\n");
    return true;
}

void DrxStimulusTask_Create(void)
{
    xTaskCreate(DrxStimulusTask, "drx_stimulus", DRX_STIMULUS_TASK_STACK_WORDS, NULL,
                DRX_STIMULUS_TASK_PRIORITY, NULL);
}
