/* Implementacion de fw/include/drx_status_task.h. Copiado por
 * tcl/gen_bsp.tcl al proyecto de Vitis del dominio FreeRTOS (Z4.2).
 */
#include "drx_status_task.h"

#include "drx_ray.h"
#include "drx_regs_hw.h"
#include "drx_status_frame.h"
#include "drx_stimulus.h"
#include "drx_transport.h"

#include "FreeRTOS.h"
#include "task.h"
#include "xil_printf.h"

#define DRX_STATUS_TASK_STACK_WORDS 1024
#define DRX_STATUS_TASK_PRIORITY (tskIDLE_PRIORITY + 1)
#define DRX_STATUS_POLL_MS 1000

/* Contadores acumulados del mensaje `status`. Viven aqui porque los registros
 * de los que salen son write-1-to-clear: cada lectura que limpia es el UNICO
 * aviso de ese evento, y si no se acumula aqui se pierde. */
static DrxStatusInputs g_inputs;
static DrxControl *g_control;

static uint32_t cuenta_bits(uint32_t v)
{
    uint32_t n = 0u;
    while (v != 0u) {
        n += (v & 1u);
        v >>= 1;
    }
    return n;
}

void DrxStatusTask_AttachControl(DrxControl *ctl)
{
    g_control = ctl;
}

void DrxStatusTask_GetInputs(DrxStatusInputs *out)
{
    *out = g_inputs;
    if (g_control != NULL) {
        out->config_rejects = g_control->rejects;
        out->last_error = g_control->last_error;
    }
}

static void DrxStatusTask(void *pvParameters)
{
    (void)pvParameters;

    if (!DrxReg_SelfTest()) {
        xil_printf("drx_status: mapa de registros no coincide, tarea detenida\r\n");
        vTaskDelete(NULL);
        return;
    }
    xil_printf("drx_status: mapa de registros v%lu confirmado por AXI-Lite\r\n",
               (unsigned long)DrxReg_Version());

    uint32_t last_trig_count = DrxReg_TrigCount();
    uint32_t enviados = 0u; /* tramas `status` que el transporte acepto */
    const TickType_t arranque = xTaskGetTickCount();

    for (;;) {
        uint32_t status = DrxReg_ReadStatus();
        uint32_t overflow = DrxReg_ReadOverflow();
        uint32_t gate_truncated = DrxReg_ReadGateTruncated();
        uint32_t timing_status = DrxReg_ReadTimingStatus();
        uint32_t trig_count = DrxReg_TrigCount();

        if (status != 0u) {
            xil_printf("drx_status: STATUS (overrun) = 0x%lx\r\n", (unsigned long)status);
            /* Un overrun de range-gate es una muestra que el camino de datos no
             * llego a llevarse: a efectos del BITE es exactamente lo mismo que
             * un descriptor del S2MM fallido, y el catalogo del contrato tiene
             * una sola bandera para los dos (`dma_overrun`). Se cuenta por
             * CANAL, no por lectura: dos canales desbordados en el mismo
             * segundo son dos eventos. */
            g_inputs.dma_overruns += cuenta_bits(status);
            DrxReg_ClearStatus(status);
        }
        if (overflow != 0u) {
            xil_printf("drx_status: OVERFLOW = 0x%lx\r\n", (unsigned long)overflow);
            g_inputs.ddc_overflows += cuenta_bits(overflow);
            DrxReg_ClearOverflow(overflow);
        }
        if (gate_truncated != 0u) {
            xil_printf("drx_status: GATE_TRUNCATED = 0x%lx\r\n", (unsigned long)gate_truncated);
            /* Un rayo truncado NO es un overrun: el dato no se perdio por falta
             * de sitio, se corto porque llego el `ray_start` siguiente (D-14).
             * El catalogo de BITE no tiene bandera propia para esto; viaja en
             * `ray_flags` del rayo afectado (`truncated`), que es donde el DSP
             * puede atribuirlo al rayo correcto. Aqui solo se limpia. */
            DrxReg_ClearGateTruncated(gate_truncated);
        }
        if (timing_status != 0u) {
            xil_printf("drx_status: TIMING_STATUS = 0x%lx\r\n", (unsigned long)timing_status);
            DrxReg_ClearTimingStatus(timing_status);
        }
        if (trig_count != last_trig_count) {
            xil_printf("drx_status: TRIG_COUNT = %lu\r\n", (unsigned long)trig_count);
            last_trig_count = trig_count;
        }

        /* Lo que no sale de registros sticky sale de los drivers, que ya llevan
         * su propio acumulado desde el arranque. */
        DrxRayStatus rayos;
        DrxRay_GetStatus(&rayos);

        DrxStimulusStatus estimulo;
        DrxStimulus_GetStatus(&estimulo);

        DrxStatusInputs instantanea;
        DrxStatusTask_GetInputs(&instantanea);
        instantanea.uptime_s =
            (uint32_t)((xTaskGetTickCount() - arranque) / configTICK_RATE_HZ);
        instantanea.dma_overruns += rayos.dma_errors;
        /* Una pasada de estimulo que el DMA marca como fallida es la fuente de
         * muestras quedandose sin datos a tiempo: eso es `ssa_underrun`, no un
         * error del camino de vuelta. */
        instantanea.ssa_underruns += estimulo.errors;
        /* `link_down` lo sabe lwIP y el transporte es Z4.6; `mmcm_unlocked` no
         * llega al mapa de registros (haria falta un bit nuevo en STATUS) y
         * `ssi_errors` son los encoders, que son Z3. Los tres se reportan a
         * cero y eso esta dicho en drx_status_frame.h, no escondido aqui. */

        uint8_t trama[128];
        size_t n = DrxStatus_Encode(trama, sizeof(trama), &instantanea);

        /* Z4.6: la misma trama que se contaba por UART va ahora al DSP, si hay
         * alguno conectado. Que no lo haya no es un error -- el `status` es
         * periodico y el siguiente sale dentro de un segundo. */
        if (n > 0u && DrxTransport_Send(trama, n)) {
            enviados++;
        }

        DrxTransportStatus red;
        DrxTransport_GetStatus(&red);

        xil_printf("drx_status: BITE=0x%lx uptime=%lus rayos=%lu "
                   "dma_overruns=%lu ddc_overflows=%lu ssa_underruns=%lu "
                   "last_error=%lu trama=%luB\r\n",
                   (unsigned long)DrxStatus_BiteFlags(&instantanea),
                   (unsigned long)instantanea.uptime_s,
                   (unsigned long)rayos.rays,
                   (unsigned long)instantanea.dma_overruns,
                   (unsigned long)instantanea.ddc_overflows,
                   (unsigned long)instantanea.ssa_underruns,
                   (unsigned long)instantanea.last_error,
                   (unsigned long)n);
        xil_printf("drx_status: red %s rayos_tx=%lu descartados=%lu "
                   "status_tx=%lu tx=%luMB rx=%luB\r\n",
                   red.connected ? "conectada" : "sin DSP",
                   (unsigned long)red.rays_sent,
                   (unsigned long)red.rays_dropped,
                   (unsigned long)enviados,
                   (unsigned long)(red.tx_bytes >> 20),
                   (unsigned long)red.rx_bytes);

        /* Los contadores finos del camino de vuelta, no solo el total. Sin
         * esto, un `descartados` que sube no dice NADA de por que: un rayo
         * corto, un `n_ch` que no cuadra y un descriptor fallido del DMA se
         * ven todos igual desde fuera, y cada uno apunta a un sitio distinto.
         * Se imprimen solo cuando alguno no es cero, que en marcha normal es
         * nunca. */
        if ((rayos.dma_errors | rayos.resync | rayos.bad_magic |
             rayos.bad_n_ch | rayos.short_rays | rayos.long_rays | rayos.trig_gaps |
             rayos.ray_gaps | rayos.sink_drops) != 0u) {
            xil_printf("drx_status: rayo dma_err=%lu resync=%lu magic=%lu "
                       "n_ch=%lu cortos=%lu largos=%lu trig_gaps=%lu(d=%lu) "
                       "ray_gaps=%lu sink_drops=%lu enc_fail=%lu snd_fail=%lu\r\n",
                       (unsigned long)rayos.dma_errors,
                       (unsigned long)rayos.resync,
                       (unsigned long)rayos.bad_magic,
                       (unsigned long)rayos.bad_n_ch,
                       (unsigned long)rayos.short_rays,
                       (unsigned long)rayos.long_rays,
                       (unsigned long)rayos.trig_gaps,
                       (unsigned long)rayos.last_trig_delta,
                       (unsigned long)rayos.ray_gaps,
                       (unsigned long)rayos.sink_drops,
                       (unsigned long)red.encode_fails,
                       (unsigned long)red.send_fails);
        }

        /* `last_error` se reporta una vez y se rearma; `rejects` no, porque la
         * bandera `config_rejected` tiene que quedarse en alto. */
        if (g_control != NULL) {
            DrxControl_ClearLastError(g_control);
        }

        vTaskDelay(pdMS_TO_TICKS(DRX_STATUS_POLL_MS));
    }
}

void DrxStatusTask_Create(void)
{
    xTaskCreate(DrxStatusTask, "drx_status", DRX_STATUS_TASK_STACK_WORDS, NULL,
                DRX_STATUS_TASK_PRIORITY, NULL);
}
