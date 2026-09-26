/* Implementacion de fw/include/drx_status_task.h. Copiado por
 * tcl/gen_bsp.tcl al proyecto de Vitis del dominio FreeRTOS (Z4.2).
 */
#include "drx_status_task.h"
#include "drx_regs_hw.h"

#include "FreeRTOS.h"
#include "task.h"
#include "xil_printf.h"

#define DRX_STATUS_TASK_STACK_WORDS 1024
#define DRX_STATUS_TASK_PRIORITY (tskIDLE_PRIORITY + 1)
#define DRX_STATUS_POLL_MS 1000

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

    for (;;) {
        uint32_t status = DrxReg_ReadStatus();
        uint32_t overflow = DrxReg_ReadOverflow();
        uint32_t gate_truncated = DrxReg_ReadGateTruncated();
        uint32_t timing_status = DrxReg_ReadTimingStatus();
        uint32_t trig_count = DrxReg_TrigCount();

        if (status != 0u) {
            xil_printf("drx_status: STATUS (overrun) = 0x%lx\r\n", (unsigned long)status);
            DrxReg_ClearStatus(status);
        }
        if (overflow != 0u) {
            xil_printf("drx_status: OVERFLOW = 0x%lx\r\n", (unsigned long)overflow);
            DrxReg_ClearOverflow(overflow);
        }
        if (gate_truncated != 0u) {
            xil_printf("drx_status: GATE_TRUNCATED = 0x%lx\r\n", (unsigned long)gate_truncated);
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

        vTaskDelay(pdMS_TO_TICKS(DRX_STATUS_POLL_MS));
    }
}

void DrxStatusTask_Create(void)
{
    xTaskCreate(DrxStatusTask, "drx_status", DRX_STATUS_TASK_STACK_WORDS, NULL,
                DRX_STATUS_TASK_PRIORITY, NULL);
}
