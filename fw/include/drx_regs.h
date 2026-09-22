/* GENERADO por tools/gen_registers.py a partir de
 * config/registers.toml. NO EDITAR A MANO.
 *
 * Mapa de registros AXI-Lite de drx_top (Z1). Ver la cabecera de
 * config/registers.toml para el historial de versiones y
 * docs/implementacion/registros.md para la descripcion completa.
 */

#ifndef DRX_REGS_H
#define DRX_REGS_H

#define DRX_REGS_VERSION 3

#define DRX_REG_VERSION_OFFSET 0x00u
#define DRX_REG_CTRL_OFFSET 0x04u
#define DRX_REG_STATUS_OFFSET 0x08u
#define DRX_REG_OVERFLOW_OFFSET 0x0Cu
#define DRX_REG_TIMING_CTRL_OFFSET 0x10u
#define DRX_REG_TIMING_STATUS_OFFSET 0x14u
#define DRX_REG_PRF_DIV_LOW_OFFSET 0x18u
#define DRX_REG_PRF_DIV_HIGH_OFFSET 0x1Cu
#define DRX_REG_PULSE_WIDTH_OFFSET 0x20u
#define DRX_REG_N_PULSES_OFFSET 0x24u
#define DRX_REG_TRIG_DELAY_0_OFFSET 0x28u
#define DRX_REG_TRIG_DELAY_1_OFFSET 0x2Cu
#define DRX_REG_TRIG_DELAY_2_OFFSET 0x30u
#define DRX_REG_TRIG_DELAY_3_OFFSET 0x34u
#define DRX_REG_TRIG_WIDTH_0_OFFSET 0x38u
#define DRX_REG_TRIG_WIDTH_1_OFFSET 0x3Cu
#define DRX_REG_TRIG_WIDTH_2_OFFSET 0x40u
#define DRX_REG_TRIG_WIDTH_3_OFFSET 0x44u

#define DRX_REG_CTRL_MODE_COARSE_BIT 0u
#define DRX_REG_CTRL_MODE_COARSE_MASK (1u << DRX_REG_CTRL_MODE_COARSE_BIT)

#endif /* DRX_REGS_H */
