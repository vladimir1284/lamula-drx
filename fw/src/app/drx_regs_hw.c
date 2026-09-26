/* Implementacion del driver de fw/include/drx_regs_hw.h. Copiado por
 * tcl/gen_bsp.tcl al proyecto de Vitis del dominio FreeRTOS (Z4.2) -- fuente
 * real versionada aqui, no dentro de build/.
 */
#include "drx_regs_hw.h"
#include "drx_regs.h"

#include "xparameters.h"
#include "xil_io.h"
#include "xil_printf.h"

uint32_t DrxReg_Read(uint32_t offset)
{
    return Xil_In32(XPAR_M_AXI_REGS_BASEADDR + offset);
}

void DrxReg_Write(uint32_t offset, uint32_t value)
{
    Xil_Out32(XPAR_M_AXI_REGS_BASEADDR + offset, value);
}

uint32_t DrxReg_Version(void)
{
    return DrxReg_Read(DRX_REG_VERSION_OFFSET);
}

uint32_t DrxReg_TrigCount(void)
{
    return DrxReg_Read(DRX_REG_TRIG_COUNT_OFFSET);
}

uint32_t DrxReg_ReadStatus(void)
{
    return DrxReg_Read(DRX_REG_STATUS_OFFSET);
}

void DrxReg_ClearStatus(uint32_t mask)
{
    DrxReg_Write(DRX_REG_STATUS_OFFSET, mask);
}

uint32_t DrxReg_ReadOverflow(void)
{
    return DrxReg_Read(DRX_REG_OVERFLOW_OFFSET);
}

void DrxReg_ClearOverflow(uint32_t mask)
{
    DrxReg_Write(DRX_REG_OVERFLOW_OFFSET, mask);
}

uint32_t DrxReg_ReadGateTruncated(void)
{
    return DrxReg_Read(DRX_REG_GATE_TRUNCATED_OFFSET);
}

void DrxReg_ClearGateTruncated(uint32_t mask)
{
    DrxReg_Write(DRX_REG_GATE_TRUNCATED_OFFSET, mask);
}

uint32_t DrxReg_ReadTimingStatus(void)
{
    return DrxReg_Read(DRX_REG_TIMING_STATUS_OFFSET);
}

void DrxReg_ClearTimingStatus(uint32_t mask)
{
    DrxReg_Write(DRX_REG_TIMING_STATUS_OFFSET, mask);
}

bool DrxReg_SelfTest(void)
{
    uint32_t version = DrxReg_Version();

    if (version != DRX_REGS_VERSION) {
        xil_printf("drx_regs: version leida %lu, esperada %lu -- mapa desincronizado\r\n",
                   (unsigned long)version, (unsigned long)DRX_REGS_VERSION);
        return false;
    }
    return true;
}
