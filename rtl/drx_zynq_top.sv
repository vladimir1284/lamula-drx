// Top físico real de la build con PS7 (ZedBoard, `-top zynq` en
// `tcl/build.tcl`). Instancia el wrapper del block design que genera
// `tcl/gen_zynq_bd.tcl` (PS7 + interconnect + `axi_protocol_converter` hacia
// AXI4-Lite, ver la cabecera de ese fichero) y `drx_top` (el datapath ya
// verificado, sin tocar), y los conecta en SystemVerilog normal.
//
// Por qué no vive `drx_top` DENTRO del block design como referencia de
// módulo: probado en esta misma sesión que `create_bd_cell -type module
// -reference` no admite un top SystemVerilog en Vivado 2022.2 ("This type is
// not allowed as the top file in the reference"). De ahí este fichero.
//
// `DDR`/`FIXED_IO` son los pines dedicados del PS7 -- pasan derechos a los
// puertos de este top con los mismos nombres de señal que genera el wrapper
// (Vivado los resuelve por bonding fijo del part, no por XDC). `pl_clk0` /
// `pl_resetn0` sustituyen al oscilador externo (Y9) y al BTNC como reloj/
// reset de `drx_top` en esta build -- ese pin físico deja de usarse aquí,
// pero `drx_top.sv`/`tcl/xdc/zedboard.xdc` (el flujo sin PS7, `-top drx_top`)
// no cambian: siguen usándolo igual que siempre.
//
// `m_axi_regs_awprot`/`m_axi_regs_arprot` (parte del AXI4-Lite mínimo, según
// el estándar) se dejan sin conectar a propósito: `drx_axil_regs`/`drx_top`
// nunca comprobaron permisos (todo responde OKAY, ver la cabecera de
// `drx_axil_regs.sv`) y nunca tuvieron puerto para ellas -- no hay nada del
// otro lado que conectar.
//
// Z4.0 (fases.md#z4): `s_axis_ray_*` es el AXI4-Stream de `drx_top.m_ray_*`
// (empaquetador de rayo, N_CH canales entrelazados) hacia el AXI DMA S2MM
// que ya vive DENTRO del block design (`tcl/gen_zynq_bd.tcl`) -- por eso este
// top solo pasa las señales derechas, sin lógica propia, mismo patrón que
// `m_axi_regs_*`.

`ifndef DRX_ZYNQ_TOP_SV
`define DRX_ZYNQ_TOP_SV

module drx_zynq_top
  import drx_params_pkg::*;
  import drx_regs_pkg::*;
(
    inout wire [14:0] DDR_addr,
    inout wire [ 2:0] DDR_ba,
    inout wire        DDR_cas_n,
    inout wire        DDR_ck_n,
    inout wire        DDR_ck_p,
    inout wire        DDR_cke,
    inout wire        DDR_cs_n,
    inout wire [ 3:0] DDR_dm,
    inout wire [31:0] DDR_dq,
    inout wire [ 3:0] DDR_dqs_n,
    inout wire [ 3:0] DDR_dqs_p,
    inout wire        DDR_odt,
    inout wire        DDR_ras_n,
    inout wire        DDR_reset_n,
    inout wire        DDR_we_n,
    inout wire        FIXED_IO_ddr_vrn,
    inout wire        FIXED_IO_ddr_vrp,
    inout wire [53:0] FIXED_IO_mio,
    inout wire        FIXED_IO_ps_clk,
    inout wire        FIXED_IO_ps_porb,
    inout wire        FIXED_IO_ps_srstb,

    output logic led_heartbeat,
    output logic debug_probe,
    output logic [N_TRIGGERS-1:0] trig_out
);

  logic        pl_clk0;
  logic [0:0]  pl_resetn0;

  logic [31:0] m_axi_regs_araddr;
  logic        m_axi_regs_arprot;
  logic        m_axi_regs_arready;
  logic        m_axi_regs_arvalid;
  logic [31:0] m_axi_regs_awaddr;
  logic        m_axi_regs_awprot;
  logic        m_axi_regs_awready;
  logic        m_axi_regs_awvalid;
  logic        m_axi_regs_bready;
  logic [ 1:0] m_axi_regs_bresp;
  logic        m_axi_regs_bvalid;
  logic [31:0] m_axi_regs_rdata;
  logic        m_axi_regs_rready;
  logic [ 1:0] m_axi_regs_rresp;
  logic        m_axi_regs_rvalid;
  logic [31:0] m_axi_regs_wdata;
  logic        m_axi_regs_wready;
  logic [ 3:0] m_axi_regs_wstrb;
  logic        m_axi_regs_wvalid;

  logic                 s_axis_ray_tvalid;
  logic                 s_axis_ray_tready;
  logic [2*IQ_BITS-1:0] s_axis_ray_tdata;
  logic                 s_axis_ray_tlast;

  drx_zynq_bd_wrapper u_bd (
      .DDR_addr         (DDR_addr),
      .DDR_ba           (DDR_ba),
      .DDR_cas_n        (DDR_cas_n),
      .DDR_ck_n         (DDR_ck_n),
      .DDR_ck_p         (DDR_ck_p),
      .DDR_cke          (DDR_cke),
      .DDR_cs_n         (DDR_cs_n),
      .DDR_dm           (DDR_dm),
      .DDR_dq           (DDR_dq),
      .DDR_dqs_n        (DDR_dqs_n),
      .DDR_dqs_p        (DDR_dqs_p),
      .DDR_odt          (DDR_odt),
      .DDR_ras_n        (DDR_ras_n),
      .DDR_reset_n      (DDR_reset_n),
      .DDR_we_n         (DDR_we_n),
      .FIXED_IO_ddr_vrn (FIXED_IO_ddr_vrn),
      .FIXED_IO_ddr_vrp (FIXED_IO_ddr_vrp),
      .FIXED_IO_mio     (FIXED_IO_mio),
      .FIXED_IO_ps_clk  (FIXED_IO_ps_clk),
      .FIXED_IO_ps_porb (FIXED_IO_ps_porb),
      .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),

      .pl_clk0   (pl_clk0),
      .pl_resetn0(pl_resetn0),

      .m_axi_regs_araddr (m_axi_regs_araddr),
      .m_axi_regs_arprot (m_axi_regs_arprot),
      .m_axi_regs_arready(m_axi_regs_arready),
      .m_axi_regs_arvalid(m_axi_regs_arvalid),
      .m_axi_regs_awaddr (m_axi_regs_awaddr),
      .m_axi_regs_awprot (m_axi_regs_awprot),
      .m_axi_regs_awready(m_axi_regs_awready),
      .m_axi_regs_awvalid(m_axi_regs_awvalid),
      .m_axi_regs_bready (m_axi_regs_bready),
      .m_axi_regs_bresp  (m_axi_regs_bresp),
      .m_axi_regs_bvalid (m_axi_regs_bvalid),
      .m_axi_regs_rdata  (m_axi_regs_rdata),
      .m_axi_regs_rready (m_axi_regs_rready),
      .m_axi_regs_rresp  (m_axi_regs_rresp),
      .m_axi_regs_rvalid (m_axi_regs_rvalid),
      .m_axi_regs_wdata  (m_axi_regs_wdata),
      .m_axi_regs_wready (m_axi_regs_wready),
      .m_axi_regs_wstrb  (m_axi_regs_wstrb),
      .m_axi_regs_wvalid (m_axi_regs_wvalid),

      .s_axis_ray_tvalid(s_axis_ray_tvalid),
      .s_axis_ray_tready(s_axis_ray_tready),
      .s_axis_ray_tdata (s_axis_ray_tdata),
      .s_axis_ray_tlast (s_axis_ray_tlast),
      // El stream nunca trae bytes parciales -- `drx_top`/`drx_ray_packer` no
      // tienen ni necesitan noción de TKEEP, ver la cabecera.
      .s_axis_ray_tkeep (4'hF)
  );

  drx_top u_drx_top (
      .clk          (pl_clk0),
      .rst_n        (pl_resetn0[0]),
      .led_heartbeat(led_heartbeat),
      .debug_probe  (debug_probe),
      .trig_out     (trig_out),

      .s_axi_awaddr (m_axi_regs_awaddr[REGS_ADDR_WIDTH-1:0]),
      .s_axi_awvalid(m_axi_regs_awvalid),
      .s_axi_awready(m_axi_regs_awready),
      .s_axi_wdata  (m_axi_regs_wdata),
      .s_axi_wstrb  (m_axi_regs_wstrb),
      .s_axi_wvalid (m_axi_regs_wvalid),
      .s_axi_wready (m_axi_regs_wready),
      .s_axi_bresp  (m_axi_regs_bresp),
      .s_axi_bvalid (m_axi_regs_bvalid),
      .s_axi_bready (m_axi_regs_bready),
      .s_axi_araddr (m_axi_regs_araddr[REGS_ADDR_WIDTH-1:0]),
      .s_axi_arvalid(m_axi_regs_arvalid),
      .s_axi_arready(m_axi_regs_arready),
      .s_axi_rdata  (m_axi_regs_rdata),
      .s_axi_rresp  (m_axi_regs_rresp),
      .s_axi_rvalid (m_axi_regs_rvalid),
      .s_axi_rready (m_axi_regs_rready),

      .m_ray_valid(s_axis_ray_tvalid),
      .m_ray_ready(s_axis_ray_tready),
      .m_ray_data (s_axis_ray_tdata),
      .m_ray_last (s_axis_ray_tlast)
  );

endmodule

`endif
