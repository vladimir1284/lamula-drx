/* Driver de registros AXI-Lite de drx_top, Z4.2.
 *
 * Envuelve los offsets generados en fw/include/drx_regs.h (tools/gen_registers.py,
 * NO editar a mano) con la base fisica real que Vivado asigna al puerto
 * externo `m_axi_regs` del block design (tcl/gen_zynq_bd.tcl) -- capturada
 * por Vitis en xparameters.h como XPAR_M_AXI_REGS_BASEADDR a partir del XSA.
 * Este fichero SI se edita a mano: es codigo de firmware real, no generado.
 *
 * Solo Xil_In32/Xil_Out32 -- ningun estado propio. Los latches sticky
 * (STATUS/OVERFLOW/GATE_TRUNCATED/TIMING_STATUS) viven en el propio
 * hardware (drx_axil_regs.sv, write-1-to-clear); este driver no cachea nada.
 */
#ifndef DRX_REGS_HW_H
#define DRX_REGS_HW_H

#include <stdint.h>
#include <stdbool.h>

#include "drx_params.h"

uint32_t DrxReg_Read(uint32_t offset);
void DrxReg_Write(uint32_t offset, uint32_t value);

uint32_t DrxReg_Version(void);
uint32_t DrxReg_TrigCount(void);

/* NCO_PINC (v9, Z4.5): palabra de incremento de fase del NCO. Cada escritura
 * dispara un pulso hacia el canal S_AXIS_CONFIG del DDS Compiler, asi que
 * escribir el mismo valor dos veces reprograma dos veces -- quien decide es el
 * plano de control (fw/include/drx_afc.h), no este driver. */
uint32_t DrxReg_ReadNcoPinc(void);
void DrxReg_WriteNcoPinc(uint32_t pinc);

uint32_t DrxReg_ReadStatus(void);
void DrxReg_ClearStatus(uint32_t mask);

uint32_t DrxReg_ReadOverflow(void);
void DrxReg_ClearOverflow(uint32_t mask);

uint32_t DrxReg_ReadGateTruncated(void);
void DrxReg_ClearGateTruncated(uint32_t mask);

uint32_t DrxReg_ReadTimingStatus(void);
void DrxReg_ClearTimingStatus(uint32_t mask);

/* --- Motor de timing (Z2, D-13/D-09/D-15) --------------------------------
 *
 * Los registros de configuracion de abajo solo son seguros de escribir con el
 * secuenciador parado: drx_prf_batch_seq.sv no los vuelve a leer hasta el
 * primer pulso tras rearmar, asi que un cambio a mitad de radial no corrompe
 * el lote en curso pero si puede dejar el siguiente a medias. El orden
 * correcto es DrxReg_TimingDisable() -> DrxReg_WriteTimingConfig() ->
 * DrxReg_TimingEnable(), y es el que implementa drx_timing_cfg.c.
 *
 * Unidades: prf_div, pulse_width, trig_delay y trig_width estan todos en
 * ciclos de FS_HZ. bins_* es un conteo de muestras decimadas, no de ciclos.
 */
typedef struct {
    uint32_t prf_div_low;   /* ciclos de FS_HZ por PRI del lote bajo  */
    uint32_t prf_div_high;  /* idem, lote alto                        */
    uint16_t pulse_width_low;   /* tiene que estar en DRX_PULSE_WIDTH_CYCLES */
    uint16_t pulse_width_high;
    uint16_t n_pulses_low;  /* pulsos antes de pasar al lote alto     */
    uint16_t n_pulses_high; /* pulsos antes de radial_done            */
    uint32_t bins_low;      /* bins de range-gate del lote bajo (D-15) */
    uint32_t bins_high;
    uint32_t trig_delay[DRX_N_TRIGGERS];
    uint32_t trig_width[DRX_N_TRIGGERS]; /* cada uno tiene que ser >= 1 */
} DrxTimingConfig;

void DrxReg_TimingDisable(void);
void DrxReg_TimingEnable(void);
bool DrxReg_TimingEnabled(void);

/* TIMING_CTRL bit 1 (mapa v10, P-16): el motor de timing cuenta avances de
 * muestra en vez de ciclos de reloj. Son lo mismo mientras la fuente entregue
 * una muestra por ciclo; en Throttled(DDR) `vector_source` junta N_CH beats
 * por conjunto, el rayo tarda ~N_CH veces el PRI en llenarse y `ray_start` lo
 * trunca antes -- sin esto, con el motor en marcha no se completa ni un rayo.
 *
 * Cambiar solo con el secuenciador parado (`DrxReg_TimingDisable()` antes):
 * cambia lo que significa `prf_div`, y hacerlo a mitad de radial deja ese
 * radial con dos bases de tiempo. Las dos funciones preservan el otro bit. */
void DrxReg_TimingSetPaced(bool paced);
bool DrxReg_TimingPaced(void);

void DrxReg_WriteTimingConfig(const DrxTimingConfig *cfg);

/* --- Ventana de carga del vector de estimulo (mapa v11) -------------------
 *
 * CTRL bit 2 + VEC_ADDR/VEC_DATA/VEC_LEN. Es la via por la que el PS escribe
 * los bancos de BRAM de `rtl/vector_source.sv` en tiempo de ejecucion, y
 * sustituye al camino DDR -> AXI DMA MM2S -> AXI4-Stream que existio entre
 * Z4.3 y el 4-oct-2026.
 *
 * Secuencia obligatoria, y el orden importa:
 *
 *   DrxReg_VecSetLoad(true);                  // congela el lector
 *   DrxReg_VecSetAddr(DRX_REG_VEC_ADDR_BANK_ALL, 0);
 *   for (...) DrxReg_VecWrite(muestra);       // autoincrementa solo
 *   DrxReg_VecSetLen(n);
 *   DrxReg_VecSetLoad(false);                 // reproduce desde la muestra 0
 *
 * Sin el VecSetLoad(true) las escrituras NO llegan a la memoria: el hardware
 * las descarta a proposito, para que no se pueda dejar medio vector viejo y
 * medio nuevo sonando a la vez. */
void DrxReg_VecSetLoad(bool loading);
bool DrxReg_VecLoading(void);

/* `bank` es 0..N_CH-1 para un canal, o DRX_REG_VEC_ADDR_BANK_ALL (7) para
 * difusion a todos -- que es lo que hace que una carga cueste una pasada y no
 * N_CH. `addr` es el indice de muestra dentro del banco. */
void DrxReg_VecSetAddr(uint32_t bank, uint32_t addr);

/* Graba una muestra en la direccion actual y la incrementa. Llamarla
 * DRX_VECTOR_LOOP_LEN veces tras un VecSetAddr(.., 0) carga un vector entero. */
void DrxReg_VecWrite(int16_t sample);

/* Longitud del bucle en muestras. Tiene que ser <= DRX_VECTOR_BRAM_DEPTH-1
 * (el puntero tiene $clog2(DEPTH) bits y la propia profundidad no cabe en
 * ellos cuando es potencia de dos exacta) y multiplo de DRX_IF_NORM_DEN si se
 * quiere un tono sin salto de fase al envolver. Devuelve false, sin escribir,
 * si no cabe. */
bool DrxReg_VecSetLen(uint32_t len);
uint32_t DrxReg_VecGetLen(void);

/* Relee por AXI-Lite los registros RW que acaba de escribir
 * DrxReg_WriteTimingConfig y los compara con `cfg`. Separa dos fallos que de
 * otro modo se confunden: un camino de escritura/lectura roto (los valores no
 * vuelven) frente a una configuracion que el hardware rechaza por D-09 (los
 * valores vuelven bien pero TIMING_STATUS marca el lote invalido). Imprime
 * por UART cada registro que no coincide. */
bool DrxReg_VerifyTimingConfig(const DrxTimingConfig *cfg);

/* true si VERSION == DRX_REGS_VERSION (fw/include/drx_regs.h): confirma que
 * el firmware que corre y el bitstream cargado hablan el mismo mapa de
 * registros antes de tocar nada mas. */
bool DrxReg_SelfTest(void);

#endif /* DRX_REGS_HW_H */
