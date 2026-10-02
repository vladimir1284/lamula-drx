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

/* --- Motor de timing ------------------------------------------------------
 *
 * Los offsets de los 4 retardos y los 4 anchos son contiguos en el mapa, pero
 * esto NO los indexa aritmeticamente: la tabla nombra cada macro generada por
 * tools/gen_registers.py, asi que si config/registers.toml reordena el mapa
 * el compilador sigue siendo correcto en vez de leer el registro de al lado.
 */
static const uint32_t kTrigDelayOffset[DRX_N_TRIGGERS] = {
    DRX_REG_TRIG_DELAY_0_OFFSET,
    DRX_REG_TRIG_DELAY_1_OFFSET,
    DRX_REG_TRIG_DELAY_2_OFFSET,
    DRX_REG_TRIG_DELAY_3_OFFSET,
};

static const uint32_t kTrigWidthOffset[DRX_N_TRIGGERS] = {
    DRX_REG_TRIG_WIDTH_0_OFFSET,
    DRX_REG_TRIG_WIDTH_1_OFFSET,
    DRX_REG_TRIG_WIDTH_2_OFFSET,
    DRX_REG_TRIG_WIDTH_3_OFFSET,
};

void DrxReg_TimingDisable(void)
{
    DrxReg_Write(DRX_REG_TIMING_CTRL_OFFSET, 0u);
}

void DrxReg_TimingEnable(void)
{
    DrxReg_Write(DRX_REG_TIMING_CTRL_OFFSET, 1u);
}

bool DrxReg_TimingEnabled(void)
{
    return (DrxReg_Read(DRX_REG_TIMING_CTRL_OFFSET) & 1u) != 0u;
}

/* PULSE_WIDTH y N_PULSES empaquetan los dos lotes en una palabra: lote bajo en
 * los bits 15:0, lote alto en los 31:16 (ver config/registers.toml). */
static uint32_t pack_batches(uint16_t low, uint16_t high)
{
    return (uint32_t)low | ((uint32_t)high << 16);
}

void DrxReg_WriteTimingConfig(const DrxTimingConfig *cfg)
{
    DrxReg_Write(DRX_REG_PRF_DIV_LOW_OFFSET, cfg->prf_div_low);
    DrxReg_Write(DRX_REG_PRF_DIV_HIGH_OFFSET, cfg->prf_div_high);
    DrxReg_Write(DRX_REG_PULSE_WIDTH_OFFSET,
                 pack_batches(cfg->pulse_width_low, cfg->pulse_width_high));
    DrxReg_Write(DRX_REG_N_PULSES_OFFSET,
                 pack_batches(cfg->n_pulses_low, cfg->n_pulses_high));
    DrxReg_Write(DRX_REG_BINS_LOW_OFFSET, cfg->bins_low);
    DrxReg_Write(DRX_REG_BINS_HIGH_OFFSET, cfg->bins_high);

    for (unsigned i = 0u; i < DRX_N_TRIGGERS; i++) {
        DrxReg_Write(kTrigDelayOffset[i], cfg->trig_delay[i]);
        DrxReg_Write(kTrigWidthOffset[i], cfg->trig_width[i]);
    }
}

static bool check_reg(const char *name, uint32_t offset, uint32_t expected)
{
    uint32_t got = DrxReg_Read(offset);

    if (got != expected) {
        xil_printf("drx_timing: %s (0x%02lx) escrito 0x%08lx, leido 0x%08lx\r\n",
                   name, (unsigned long)offset, (unsigned long)expected,
                   (unsigned long)got);
        return false;
    }
    return true;
}

bool DrxReg_VerifyTimingConfig(const DrxTimingConfig *cfg)
{
    bool ok = true;

    ok &= check_reg("PRF_DIV_LOW", DRX_REG_PRF_DIV_LOW_OFFSET, cfg->prf_div_low);
    ok &= check_reg("PRF_DIV_HIGH", DRX_REG_PRF_DIV_HIGH_OFFSET, cfg->prf_div_high);
    ok &= check_reg("PULSE_WIDTH", DRX_REG_PULSE_WIDTH_OFFSET,
                    pack_batches(cfg->pulse_width_low, cfg->pulse_width_high));
    ok &= check_reg("N_PULSES", DRX_REG_N_PULSES_OFFSET,
                    pack_batches(cfg->n_pulses_low, cfg->n_pulses_high));
    ok &= check_reg("BINS_LOW", DRX_REG_BINS_LOW_OFFSET, cfg->bins_low);
    ok &= check_reg("BINS_HIGH", DRX_REG_BINS_HIGH_OFFSET, cfg->bins_high);

    for (unsigned i = 0u; i < DRX_N_TRIGGERS; i++) {
        ok &= check_reg("TRIG_DELAY", kTrigDelayOffset[i], cfg->trig_delay[i]);
        ok &= check_reg("TRIG_WIDTH", kTrigWidthOffset[i], cfg->trig_width[i]);
    }

    return ok;
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
