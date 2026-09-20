/* GENERADO por tools/gen_registers.py a partir de
 * config/registers.toml. NO EDITAR A MANO.
 *
 * Mapa de registros AXI-Lite de drx_top -- v1, congelado para Z1
 * (docs/implementacion/registros.md). NO cubre el overflow de saturacion
 * del DDC ni ningun registro de Z2: ver la cabecera de config/registers.toml.
 */

#ifndef DRX_REGS_H
#define DRX_REGS_H

#define DRX_REGS_VERSION 1

#define DRX_REG_VERSION_OFFSET 0x00u
#define DRX_REG_CTRL_OFFSET 0x04u
#define DRX_REG_STATUS_OFFSET 0x08u

#define DRX_REG_CTRL_MODE_COARSE_BIT 0u
#define DRX_REG_CTRL_MODE_COARSE_MASK (1u << DRX_REG_CTRL_MODE_COARSE_BIT)

#endif /* DRX_REGS_H */
