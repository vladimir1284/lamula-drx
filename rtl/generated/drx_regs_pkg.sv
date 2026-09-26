// GENERADO por tools/gen_registers.py a partir de
// config/registers.toml. NO EDITAR A MANO.
// Mapa de registros AXI-Lite de drx_top (Z1). Ver la cabecera de
// config/registers.toml para el historial de versiones y
// docs/implementacion/registros.md para la descripcion completa.

`ifndef DRX_REGS_PKG_SV
`define DRX_REGS_PKG_SV

package drx_regs_pkg;

  localparam int REGS_VERSION = 6;
  localparam int REGS_ADDR_WIDTH = 7;

  localparam logic [REGS_ADDR_WIDTH-1:0] REG_VERSION_ADDR = REGS_ADDR_WIDTH'(32'h00000000);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_CTRL_ADDR = REGS_ADDR_WIDTH'(32'h00000004);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_STATUS_ADDR = REGS_ADDR_WIDTH'(32'h00000008);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_OVERFLOW_ADDR = REGS_ADDR_WIDTH'(32'h0000000C);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_TIMING_CTRL_ADDR = REGS_ADDR_WIDTH'(32'h00000010);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_TIMING_STATUS_ADDR = REGS_ADDR_WIDTH'(32'h00000014);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_PRF_DIV_LOW_ADDR = REGS_ADDR_WIDTH'(32'h00000018);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_PRF_DIV_HIGH_ADDR = REGS_ADDR_WIDTH'(32'h0000001C);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_PULSE_WIDTH_ADDR = REGS_ADDR_WIDTH'(32'h00000020);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_N_PULSES_ADDR = REGS_ADDR_WIDTH'(32'h00000024);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_TRIG_DELAY_0_ADDR = REGS_ADDR_WIDTH'(32'h00000028);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_TRIG_DELAY_1_ADDR = REGS_ADDR_WIDTH'(32'h0000002C);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_TRIG_DELAY_2_ADDR = REGS_ADDR_WIDTH'(32'h00000030);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_TRIG_DELAY_3_ADDR = REGS_ADDR_WIDTH'(32'h00000034);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_TRIG_WIDTH_0_ADDR = REGS_ADDR_WIDTH'(32'h00000038);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_TRIG_WIDTH_1_ADDR = REGS_ADDR_WIDTH'(32'h0000003C);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_TRIG_WIDTH_2_ADDR = REGS_ADDR_WIDTH'(32'h00000040);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_TRIG_WIDTH_3_ADDR = REGS_ADDR_WIDTH'(32'h00000044);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_BINS_LOW_ADDR = REGS_ADDR_WIDTH'(32'h00000048);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_BINS_HIGH_ADDR = REGS_ADDR_WIDTH'(32'h0000004C);
  localparam logic [REGS_ADDR_WIDTH-1:0] REG_GATE_TRUNCATED_ADDR = REGS_ADDR_WIDTH'(32'h00000050);

endpackage : drx_regs_pkg

`endif  // DRX_REGS_PKG_SV
