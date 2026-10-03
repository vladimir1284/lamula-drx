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

  // Z4.0: sin PS7 no hay AXI DMA que drene `m_ray_*` -- se ata `m_ray_ready`
  // a alto (nunca frena al empaquetador ni a la cadena que alimenta, mismo
  // criterio que el `gate_ready` de antes de este cambio). Las tres salidas
  // SÍ hace falta conectarlas a algo (Verilator con `-Wall` trata un puerto
  // de salida sin conectar como PINCONNECTEMPTY, y el lint gate de `make
  // check` sube warnings a error) -- van al mismo bote `unused_*` que el
  // AXI-Lite de arriba, solo por lint. No hace falta ningún truco de "puerto
  // real" para que Vivado no elimine la cadena que alimentan:
  // `debug_probe_xor`, DENTRO de `drx_top`, ya las pliega antes de que
  // lleguen a este límite de módulo -- ver la cabecera de `drx_top.sv`.
  logic        m_ray_valid_tie;
  logic        m_ray_last_tie;
  logic [31:0] m_ray_data_tie;
  logic        unused_ray_tie;
  assign unused_ray_tie = &{1'b0, m_ray_valid_tie, m_ray_last_tie, m_ray_data_tie};

  // Z4.3: sin PS7 tampoco hay AXI DMA MM2S que alimente el modo
  // Throttled(DDR), asi que la entrada se ata inerte -- `s_vec_valid` en bajo
  // y nada mas. No es una limitacion de este flujo: CTRL bit 1 vale 0 tras
  // reset y aqui NADIE puede escribirlo (el AXI-Lite esta atado a valores
  // inertes, ver arriba), asi que `vector_source` se queda en BRAM-loop para
  // siempre y este puerto no se mira nunca. `s_vec_ready` va al bote de lint
  // por el mismo motivo que las salidas de rayo.
  logic s_vec_ready_tie;
  logic unused_vec_tie;
  assign unused_vec_tie = &{1'b0, s_vec_ready_tie};

  // P-21: el bus de la sonda de depuracion solo tiene consumidor en la build
  // de depuracion con PS7 (`rtl/drx_zynq_top.sv` con DRX_DEBUG_ILA). Aqui va
  // al mismo bote de lint que el resto -- y con el bote, no sin conectar,
  // porque `-Wall` trata un puerto de salida vacio como PINCONNECTEMPTY.
  logic [drx_debug_pkg::DbgWidth-1:0] dbg_bus_tie;
  logic unused_dbg_tie;
  assign unused_dbg_tie = &{1'b0, dbg_bus_tie};

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
      .s_axi_rready  (1'b1),

      .m_ray_valid(m_ray_valid_tie),
      .m_ray_ready(1'b1),
      .m_ray_data (m_ray_data_tie),
      .m_ray_last (m_ray_last_tie),

      .s_vec_valid(1'b0),
      .s_vec_ready(s_vec_ready_tie),
      .s_vec_data ('0),
      .s_vec_last (1'b0),

      .dbg_bus(dbg_bus_tie)
  );

endmodule

`endif
