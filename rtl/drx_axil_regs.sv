// Mapa de registros AXI-Lite de `drx_top` — v1, congelado para Z1
// (docs/implementacion/registros.md, config/registers.toml es la fuente única
// de verdad de los offsets que importa este módulo vía `drx_regs_pkg`).
//
// Slave AXI4-Lite mínimo, a propósito: AXI-Lite no tiene bursts, así que basta
// con un canal de escritura y uno de lectura, cada uno con UNA transacción en
// vuelo (no se acepta AW/W siguiente hasta que B se aceptó; ídem AR/R con
// RVALID). Responde siempre OKAY — no hay dirección de este mapa que pueda
// fallar de una forma que valga la pena reportar en v1. `s_axi_wstrb` se
// ignora deliberadamente: todos los registros de este mapa se escriben
// completos de 32 bits, no hay ninguno donde escribir solo un byte tenga
// sentido.
//
// CTRL (offset REG_CTRL_ADDR) — bit 0 es `mode_coarse`, el mismo generic
// compartido por los N_CH canales que antes era `localparam ModeCoarse` fijo
// en `drx_top.sv`. Bits 31:1 reservados: leen 0, una escritura ahí no hace
// nada (no hay registro que actualizar).
//
// STATUS (offset REG_STATUS_ADDR) — bit `c` es el `overrun` sticky del canal
// `c` de `drx_range_gate_quad_top`, leído tal cual (`overrun_in`): este bloque
// no mantiene su propia copia latcheada, el latch real vive en
// `drx_range_gate` (ya lo hacía antes de este módulo, para el debug_probe).
// Escribir 1 en el bit `c` genera un pulso de un ciclo en `overrun_clear[c]`
// hacia el nuevo puerto `clear` de `drx_range_gate` — limpiar aquí sin tocar
// la fuente habría dejado el bit releído en 1 el ciclo siguiente, porque el
// propio `overrun_in` nunca se apaga solo. Si un overrun genuino ocurre el
// mismo ciclo que el clear, gana el set (ver el comentario en
// `drx_range_gate.sv`): no se puede perder un fallo real por una carrera con
// firmware limpiando el anterior.
//
// v1 NO expone el overflow de saturación del DDC (`drx_saturate`, dentro de
// `drx_ddc_top`) — ver la cabecera de `config/registers.toml` para por qué.

`ifndef DRX_AXIL_REGS_SV
`define DRX_AXIL_REGS_SV

module drx_axil_regs
  import drx_regs_pkg::*;
#(
    parameter int N_CH = 3
) (
    input logic clk,
    input logic rst_n,

    // Canal de escritura.
    input  logic [REGS_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic                       s_axi_awvalid,
    output logic                       s_axi_awready,

    input  logic [31:0] s_axi_wdata,
    input  logic [ 3:0] s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    output logic [1:0] s_axi_bresp,
    output logic       s_axi_bvalid,
    input  logic       s_axi_bready,

    // Canal de lectura.
    input  logic [REGS_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic                       s_axi_arvalid,
    output logic                       s_axi_arready,

    output logic [31:0] s_axi_rdata,
    output logic [ 1:0] s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // Registro -> planta.
    output logic mode_coarse,

    // Planta -> registro (ver cabecera: `overrun_in` ya viene latcheado desde
    // `drx_range_gate`, este bloque solo lo expone y pulsa el clear). Vector
    // empaquetado, no array — son literalmente los bits de STATUS, y un
    // vector es además lo único que Verilator/cocotb saben indexar por canal
    // sobre un puerto de top-level (un array sin empaquetar de puertos no es
    // indexable vía VPI en esta versión). `drx_top.sv` hace el empaquetado/
    // desempaquetado contra los arrays de `drx_range_gate_quad_top`.
    input  logic [N_CH-1:0] overrun_in,
    output logic [N_CH-1:0] overrun_clear
);

  // `s_axi_wstrb` no se usa a propósito (ver cabecera); se silencia en vez de
  // dejarlo colgado, mismo patrón que el resto del árbol para puertos sin
  // consumidor (`unused_s_last` en `drx_ddc_top.sv`).
  logic unused_wstrb;
  assign unused_wstrb = &{1'b0, s_axi_wstrb};

  // -----------------------------------------------------------------------
  // Canal de escritura: acepta AW y W de forma independiente (no exige que
  // lleguen en el mismo ciclo, AXI-Lite no lo garantiza) y aplica el registro
  // en el ciclo en que las dos ya están capturadas. Sin outstanding: no se
  // vuelve a aceptar AW/W hasta que B se aceptó.
  // -----------------------------------------------------------------------
  logic                       have_aw;
  logic [REGS_ADDR_WIDTH-1:0] awaddr_r;
  logic                       have_w;
  logic [                31:0] wdata_r;

  logic write_commit;
  assign write_commit = have_aw && have_w;

  assign s_axi_awready = !have_aw && !s_axi_bvalid;
  assign s_axi_wready  = !have_w && !s_axi_bvalid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      have_aw  <= 1'b0;
      awaddr_r <= '0;
    end else if (s_axi_awvalid && s_axi_awready) begin
      have_aw  <= 1'b1;
      awaddr_r <= s_axi_awaddr;
    end else if (write_commit) begin
      have_aw <= 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      have_w  <= 1'b0;
      wdata_r <= '0;
    end else if (s_axi_wvalid && s_axi_wready) begin
      have_w  <= 1'b1;
      wdata_r <= s_axi_wdata;
    end else if (write_commit) begin
      have_w <= 1'b0;
    end
  end

  logic mode_coarse_r;
  assign mode_coarse = mode_coarse_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mode_coarse_r <= 1'b0;  // fino, el mismo default que el `ModeCoarse` fijo anterior
    end else if (write_commit && awaddr_r == REG_CTRL_ADDR) begin
      mode_coarse_r <= wdata_r[0];
    end
  end

  // `overrun_clear[c]` es un pulso combinacional de un solo ciclo: `write_commit`
  // solo está en alto el ciclo en que `have_aw`/`have_w` coinciden (se bajan al
  // ciclo siguiente), así que no hace falta registrarlo aparte.
  always_comb begin
    for (int c = 0; c < N_CH; c++) begin
      overrun_clear[c] = write_commit && (awaddr_r == REG_STATUS_ADDR) && wdata_r[c];
    end
  end

  assign s_axi_bresp = 2'b00;  // OKAY siempre, ver cabecera

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axi_bvalid <= 1'b0;
    end else if (write_commit) begin
      s_axi_bvalid <= 1'b1;
    end else if (s_axi_bvalid && s_axi_bready) begin
      s_axi_bvalid <= 1'b0;
    end
  end

  // -----------------------------------------------------------------------
  // Canal de lectura: mismo principio que el de escritura, sin outstanding.
  // -----------------------------------------------------------------------
  logic                       have_ar;
  logic [REGS_ADDR_WIDTH-1:0] araddr_r;

  logic read_commit;
  assign read_commit = have_ar && !s_axi_rvalid;

  assign s_axi_arready = !have_ar && !s_axi_rvalid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      have_ar  <= 1'b0;
      araddr_r <= '0;
    end else if (s_axi_arvalid && s_axi_arready) begin
      have_ar  <= 1'b1;
      araddr_r <= s_axi_araddr;
    end else if (read_commit) begin
      have_ar <= 1'b0;
    end
  end

  logic [31:0] rdata_next;

  always_comb begin
    rdata_next = 32'h0000_0000;
    unique case (araddr_r)
      REG_VERSION_ADDR: rdata_next = 32'(REGS_VERSION);
      REG_CTRL_ADDR:    rdata_next[0] = mode_coarse_r;
      REG_STATUS_ADDR: begin
        for (int c = 0; c < N_CH; c++) rdata_next[c] = overrun_in[c];
      end
      default: rdata_next = 32'h0000_0000;  // dirección reservada: lee 0
    endcase
  end

  assign s_axi_rresp = 2'b00;  // OKAY siempre, ver cabecera

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axi_rvalid <= 1'b0;
      s_axi_rdata  <= '0;
    end else if (read_commit) begin
      s_axi_rvalid <= 1'b1;
      s_axi_rdata  <= rdata_next;
    end else if (s_axi_rvalid && s_axi_rready) begin
      s_axi_rvalid <= 1'b0;
    end
  end

endmodule : drx_axil_regs

`endif  // DRX_AXIL_REGS_SV
