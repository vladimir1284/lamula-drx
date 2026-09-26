/* Tarea de bring-up de Z4.2: primer consumidor real de drx_regs_hw.c.
 *
 * Sondea el mapa de registros de drx_top (STATUS/OVERFLOW/GATE_TRUNCATED/
 * TIMING_STATUS/TRIG_COUNT) sobre UART y limpia los bits sticky que
 * encuentra activos. No es el ensamblado de rayos (eso es Z4.4): aqui no se
 * escribe ninguna configuracion de timing, solo se demuestra que el AXI-Lite
 * PS7->fabric funciona de verdad desde firmware.
 */
#ifndef DRX_STATUS_TASK_H
#define DRX_STATUS_TASK_H

/* Crea la tarea de FreeRTOS. Debe llamarse antes de vTaskStartScheduler();
 * no depende de que lwIP/la red esten arriba. */
void DrxStatusTask_Create(void);

#endif /* DRX_STATUS_TASK_H */
