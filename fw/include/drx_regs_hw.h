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

uint32_t DrxReg_Read(uint32_t offset);
void DrxReg_Write(uint32_t offset, uint32_t value);

uint32_t DrxReg_Version(void);
uint32_t DrxReg_TrigCount(void);

uint32_t DrxReg_ReadStatus(void);
void DrxReg_ClearStatus(uint32_t mask);

uint32_t DrxReg_ReadOverflow(void);
void DrxReg_ClearOverflow(uint32_t mask);

uint32_t DrxReg_ReadGateTruncated(void);
void DrxReg_ClearGateTruncated(uint32_t mask);

uint32_t DrxReg_ReadTimingStatus(void);
void DrxReg_ClearTimingStatus(uint32_t mask);

/* true si VERSION == DRX_REGS_VERSION (fw/include/drx_regs.h): confirma que
 * el firmware que corre y el bitstream cargado hablan el mismo mapa de
 * registros antes de tocar nada mas. */
bool DrxReg_SelfTest(void);

#endif /* DRX_REGS_HW_H */
