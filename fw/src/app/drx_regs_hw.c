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

uint32_t DrxReg_ReadNcoPinc(void)
{
    return DrxReg_Read(DRX_REG_NCO_PINC_OFFSET);
}

void DrxReg_WriteNcoPinc(uint32_t pinc)
{
    DrxReg_Write(DRX_REG_NCO_PINC_OFFSET, pinc);
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

/* Lectura-modificacion-escritura desde v10, no una escritura cruda: el bit 1
 * de TIMING_CTRL es `timing_paced` (P-16) y un `DrxReg_Write(..., 1u)` lo
 * borraria al arrancar el motor. Ese es exactamente el fallo silencioso que
 * esta forma evita -- el barrido del catalogo quedaria sin pacear sin ningun
 * sintoma salvo que no sale ningun rayo. */
void DrxReg_TimingDisable(void)
{
    uint32_t ctrl = DrxReg_Read(DRX_REG_TIMING_CTRL_OFFSET);
    DrxReg_Write(DRX_REG_TIMING_CTRL_OFFSET, ctrl & ~DRX_REG_TIMING_CTRL_ENABLE_MASK);
}

void DrxReg_TimingEnable(void)
{
    uint32_t ctrl = DrxReg_Read(DRX_REG_TIMING_CTRL_OFFSET);
    DrxReg_Write(DRX_REG_TIMING_CTRL_OFFSET, ctrl | DRX_REG_TIMING_CTRL_ENABLE_MASK);
}

bool DrxReg_TimingEnabled(void)
{
    return (DrxReg_Read(DRX_REG_TIMING_CTRL_OFFSET) & DRX_REG_TIMING_CTRL_ENABLE_MASK) != 0u;
}

/* P-16: el motor cuenta avances de muestra en vez de ciclos. Solo seguro con
 * el secuenciador parado -- cambia el significado de `prf_div` a mitad de
 * radial -- y por eso no se toca desde aqui el bit de enable. */
void DrxReg_TimingSetPaced(bool paced)
{
    uint32_t ctrl = DrxReg_Read(DRX_REG_TIMING_CTRL_OFFSET);
    if (paced) {
        ctrl |= DRX_REG_TIMING_CTRL_PACED_MASK;
    } else {
        ctrl &= ~DRX_REG_TIMING_CTRL_PACED_MASK;
    }
    DrxReg_Write(DRX_REG_TIMING_CTRL_OFFSET, ctrl);
}

bool DrxReg_TimingPaced(void)
{
    return (DrxReg_Read(DRX_REG_TIMING_CTRL_OFFSET) & DRX_REG_TIMING_CTRL_PACED_MASK) != 0u;
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

/* --- Ventana de carga del vector de estimulo (mapa v11) ------------------ */

void DrxReg_VecSetLoad(bool loading)
{
    uint32_t ctrl = DrxReg_Read(DRX_REG_CTRL_OFFSET);
    if (loading) {
        ctrl |= DRX_REG_CTRL_VECTOR_LOAD_MASK;
    } else {
        ctrl &= ~DRX_REG_CTRL_VECTOR_LOAD_MASK;
    }
    /* Lectura-modificacion-escritura: CTRL comparte palabra con
     * `mode_coarse`, y pisarlo aqui cambiaria la decimacion al cargar un
     * vector. Mismo criterio que los helpers de TIMING_CTRL. */
    DrxReg_Write(DRX_REG_CTRL_OFFSET, ctrl);
}

bool DrxReg_VecLoading(void)
{
    return (DrxReg_Read(DRX_REG_CTRL_OFFSET) & DRX_REG_CTRL_VECTOR_LOAD_MASK) != 0u;
}

void DrxReg_VecSetAddr(uint32_t bank, uint32_t addr)
{
    uint32_t word = (addr & DRX_REG_VEC_ADDR_PTR_MASK)
                    | ((bank << DRX_REG_VEC_ADDR_BANK_SHIFT) & DRX_REG_VEC_ADDR_BANK_MASK);
    DrxReg_Write(DRX_REG_VEC_ADDR_OFFSET, word);
}

void DrxReg_VecWrite(int16_t sample)
{
    /* El cast a uint16_t antes de ensanchar es lo que mantiene el complemento
     * a dos: ensanchar un int16_t negativo a uint32_t directamente rellena de
     * unos hasta el bit 31, y aunque el hardware ignora los bits 31:16, una
     * lectura de VEC_DATA devolveria algo que no se parece a lo escrito. */
    DrxReg_Write(DRX_REG_VEC_DATA_OFFSET,
                 (uint32_t)(uint16_t)sample & DRX_REG_VEC_DATA_SAMPLE_MASK);
}

bool DrxReg_VecSetLen(uint32_t len)
{
    /* El tope es DEPTH-1, no DEPTH: el puntero tiene $clog2(DEPTH) bits y con
     * DEPTH potencia de dos exacta el propio DEPTH no cabe en ellos. Si se
     * dejara pasar, el hardware lo truncaria a 0 y el bucle pasaria a ser de
     * una sola muestra -- un tono convertido en continua, sin ningun error. */
    if (len == 0u || len > (uint32_t)DRX_VECTOR_BRAM_DEPTH - 1u) {
        xil_printf("drx_regs: VEC_LEN %lu fuera de rango (1..%lu)\r\n",
                   (unsigned long)len,
                   (unsigned long)DRX_VECTOR_BRAM_DEPTH - 1u);
        return false;
    }
    DrxReg_Write(DRX_REG_VEC_LEN_OFFSET, len & DRX_REG_VEC_LEN_MASK);
    return true;
}

uint32_t DrxReg_VecGetLen(void)
{
    return DrxReg_Read(DRX_REG_VEC_LEN_OFFSET) & DRX_REG_VEC_LEN_MASK;
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
