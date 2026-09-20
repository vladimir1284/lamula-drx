// GENERADO por tools/gen_registers.py a partir de
// config/registers.toml. NO EDITAR A MANO.
// Mapa de registros AXI-Lite de drx_top (Z1). Ver la cabecera de
// config/registers.toml para el historial de versiones y
// docs/implementacion/registros.md para la descripcion completa.

`ifndef DRX_REGS_PKG_SV
`define DRX_REGS_PKG_SV

package drx_regs_pkg;

  localparam int REGS_VERSION = 2;
  localparam int REGS_ADDR_WIDTH = 6;

  localparam logic [REGS_ADDR_WIDTH-1:0] REG_VERSION_ADDR = REGS_ADDR_WIDTH'(32'h00000000);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_CTRL_ADDR = REGS_ADDR_WIDTH'(32'h00000004);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_STATUS_ADDR = REGS_ADDR_WIDTH'(32'h00000008);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_OVERFLOW_ADDR = REGS_ADDR_WIDTH'(32'h0000000C);

endpackage : drx_regs_pkg

`endif  // DRX_REGS_PKG_SV
