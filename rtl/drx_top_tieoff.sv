// Wrapper de compatibilidad para medir `drx_top` solo, sin PS7.
//
// `drx_top.sv` dejó de atar internamente el AXI-Lite de `drx_axil_regs` a
// valores inertes el 20-sep-2026 (más tarde): sus puertos AXI-Lite son ahora
// un pass-through real, y quien lo instancie decide el maestro
// (`rtl/drx_zynq_top.sv`, con PS7 de verdad). Para que `tcl/build.tcl -top
// drx_top` sin `-top zynq` siga siendo sintetizable — sin un maestro real que
// alimente esos puertos, exponerlos tal cual como puertos de este wrapper
// reproduce el mismo "IO placement is infeasible" de 94 pines que ya se
// documentó en la cabecera de `drx_top.sv` — este módulo hace exactamente lo
// que `drx_top.sv` hacía internamente antes de este cambio: instancia
// `drx_top` y ata su AXI-Lite a valores inertes. Mismo comportamiento medido
// (WNS, utilización) que la build de esta misma noche antes del puente PS7;
// no es una construcción nueva, es la misma de siempre movida un nivel hacia
// afuera.
//
// `tcl/build.tcl` usa este módulo como `-top` por defecto (sin `-top zynq`);
// `drx_zynq_top.sv` es la alternativa real con PS7.

`ifndef DRX_TOP_TIEOFF_SV
`define DRX_TOP_TIEOFF_SV

module drx_top_tieoff
  import drx_params_pkg::*;
  import drx_regs_pkg::*;
#(
    parameter int HEARTBEAT_DIV = int'(FS_HZ / 2),
    parameter int N_CH = 3
) (
    input  logic clk,
    input  logic rst_n,
    output logic led_heartbeat,
    output logic debug_probe,
    output logic [N_TRIGGERS-1:0] trig_out
);

  logic [REGS_ADDR_WIDTH-1:0] axi_tie_addr;
  logic [                31:0] axi_tie_wdata;
  logic axi_tie_awready, axi_tie_wready, axi_tie_arready;
  logic [1:0] axi_tie_bresp, axi_tie_rresp;
  logic axi_tie_bvalid, axi_tie_rvalid;
  logic [31:0] axi_tie_rdata;

  assign axi_tie_addr  = '0;
  assign axi_tie_wdata = '0;

  // Nada lee estas salidas: ningún maestro emite transacciones nunca en esta
  // build (ver la cabecera).
  logic unused_axi_tie;
  assign unused_axi_tie = &{1'b0, axi_tie_awready, axi_tie_wready, axi_tie_arready,
                            axi_tie_bresp, axi_tie_rresp, axi_tie_bvalid, axi_tie_rvalid,
                            axi_tie_rdata};

  drx_top #(
      .HEARTBEAT_DIV(HEARTBEAT_DIV),
      .N_CH(N_CH)
  ) u_drx_top (
      .clk           (clk),
      .rst_n         (rst_n),
      .led_heartbeat (led_heartbeat),
      .debug_probe   (debug_probe),
      .trig_out      (trig_out),
      .s_axi_awaddr  (axi_tie_addr),
      .s_axi_awvalid (1'b0),
      .s_axi_awready (axi_tie_awready),
      .s_axi_wdata   (axi_tie_wdata),
      .s_axi_wstrb   (4'h0),
      .s_axi_wvalid  (1'b0),
      .s_axi_wready  (axi_tie_wready),
      .s_axi_bresp   (axi_tie_bresp),
      .s_axi_bvalid  (axi_tie_bvalid),
      .s_axi_bready  (1'b1),
      .s_axi_araddr  (axi_tie_addr),
      .s_axi_arvalid (1'b0),
      .s_axi_arready (axi_tie_arready),
      .s_axi_rdata   (axi_tie_rdata),
      .s_axi_rresp   (axi_tie_rresp),
      .s_axi_rvalid  (axi_tie_rvalid),
      .s_axi_rready  (1'b1)
  );

endmodule

`endif
