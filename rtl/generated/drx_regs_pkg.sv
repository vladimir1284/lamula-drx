// GENERADO por tools/gen_registers.py a partir de
// config/registers.toml. NO EDITAR A MANO.
// Mapa de registros AXI-Lite de drx_top -- v1, congelado para Z1
// (docs/implementacion/registros.md). NO cubre el overflow de saturacion
// del DDC ni ningun registro de Z2: ver la cabecera de config/registers.toml.

`ifndef DRX_REGS_PKG_SV
`define DRX_REGS_PKG_SV

package drx_regs_pkg;

  localparam int REGS_VERSION = 1;
  localparam int REGS_ADDR_WIDTH = 6;

  localparam logic [REGS_ADDR_WIDTH-1:0] REG_VERSION_ADDR = REGS_ADDR_WIDTH'(32'h00000000);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_CTRL_ADDR = REGS_ADDR_WIDTH'(32'h00000004);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_STATUS_ADDR = REGS_ADDR_WIDTH'(32'h00000008);

endpackage : drx_regs_pkg

`endif  // DRX_REGS_PKG_SV
