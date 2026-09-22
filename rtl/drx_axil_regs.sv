// Mapa de registros AXI-Lite de `drx_top` — Z1
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
// OVERFLOW (offset REG_OVERFLOW_ADDR, añadido en v2) — bit `c` es el overflow
// de saturación del canal `c` (`drx_ddc_quad_top.overflow`, combinación de
// las ramas I/Q de `drx_ddc_top`). A DIFERENCIA de STATUS, el latch sticky
// vive AQUÍ, no en la fuente: `drx_saturate` es deliberadamente combinacional
// y sin estado (ver su propia cabecera), así que este bloque es quien lo
// convierte en sticky-con-W1C, con la misma prioridad set-sobre-clear que
// STATUS. No hace falta un puerto de vuelta hacia `drx_ddc_top` — el clear no
// tiene que llegar a ninguna fuente externa, se resuelve entero aquí dentro.
//
// Z2 (v3, D-13) — TIMING_CTRL/TIMING_STATUS/PRF_DIV_*/PULSE_WIDTH/N_PULSES/
// TRIG_DELAY_*/TRIG_WIDTH_* alimentan `drx_timing_engine` (instanciado en
// `drx_top.sv`), puro paso de registro a planta salvo TIMING_STATUS, que
// sigue el mismo patrón sticky-con-W1C que OVERFLOW (el `radial_done` de
// `drx_prf_batch_seq` es un pulso de un ciclo; sin latch aquí, firmware
// tendría que sondear en la ventana exacta del pulso). Los 4 canales de
// TRIG_DELAY/TRIG_WIDTH son puertos escalares con nombre por canal, no un
// array — mismo motivo que documenta `drx_trigger_gen.sv`: un array sin
// empaquetar de puertos de SALIDA no es indexable de forma fiable vía VPI
// (confirmado empíricamente con `trig_out`); `drx_top.sv` hace el
// empaquetado hacia el array de entrada de `drx_timing_engine` (que sí
// acepta arrays sin empaquetar como entrada, sin ese problema).
//
// TIMING_STATUS bits 1/2 (v4, D-09) — `config_invalid_low`/`_high` de
// `drx_timing_engine` (D-09, checks autocontenidos: pulse_width fuera de
// tabla o que no cabe en su propio PRI) son NIVELES combinacionales, no
// pulsos: mismo motivo que OVERFLOW para latchearlos aquí (la fuente,
// `drx_timing_config_valid.sv`, es deliberadamente combinacional y sin
// estado), misma prioridad set-sobre-clear-concurrente.

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
    output logic [N_CH-1:0] overrun_clear,

    // Overflow de saturación del DDC, por canal (ver cabecera: sticky
    // mantenido dentro de este módulo, no en la fuente).
    input logic [N_CH-1:0] overflow_in,

    // Z2 (v3, D-13) — registro -> planta, hacia drx_timing_engine.
    output logic        timing_enable,
    output logic [31:0] prf_div_low,
    output logic [31:0] prf_div_high,
    output logic [15:0] pulse_width_low,
    output logic [15:0] pulse_width_high,
    output logic [15:0] n_pulses_low,
    output logic [15:0] n_pulses_high,
    output logic [31:0] trig_delay_0,
    output logic [31:0] trig_delay_1,
    output logic [31:0] trig_delay_2,
    output logic [31:0] trig_delay_3,
    output logic [31:0] trig_width_0,
    output logic [31:0] trig_width_1,
    output logic [31:0] trig_width_2,
    output logic [31:0] trig_width_3,

    // Planta -> registro (ver cabecera: pulso de un ciclo, latcheado aquí).
    input logic radial_done_in,

    // Planta -> registro (ver cabecera: niveles combinacionales, latcheados
    // aquí igual que OVERFLOW). D-09, checks autocontenidos.
    input logic config_invalid_low_in,
    input logic config_invalid_high_in
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

  // OVERFLOW: sticky mantenido aquí (ver cabecera del módulo y de
  // `config/registers.toml`), no en `drx_ddc_top`. El `if (overflow_in[c])`
  // antes del `else if` de clear es lo que hace que el set gane sobre un
  // clear concurrente, mismo orden de prioridad que ya usa
  // `drx_range_gate.sv` para `overrun`.
  logic [N_CH-1:0] overflow_sticky_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      overflow_sticky_r <= '0;
    end else begin
      for (int c = 0; c < N_CH; c++) begin
        if (overflow_in[c]) begin
          overflow_sticky_r[c] <= 1'b1;
        end else if (write_commit && (awaddr_r == REG_OVERFLOW_ADDR) && wdata_r[c]) begin
          overflow_sticky_r[c] <= 1'b0;
        end
      end
    end
  end

  // -----------------------------------------------------------------------
  // Z2 (v3, D-13): registros de configuración de drx_timing_engine, todos
  // RW de paso directo salvo TIMING_STATUS (sticky, ver más abajo). Este
  // módulo NO valida nada él mismo -- PRF_DIV_*/PULSE_WIDTH se escriben tal
  // cual -- pero desde v4 drx_timing_engine SÍ valida los checks
  // autocontenidos de D-09 (pulse_width en tabla + cabe en su propio PRI) y
  // se niega a correr si no se cumplen, reportándolo en TIMING_STATUS bits
  // 1/2 (ver más abajo). PRF x rango no ambiguo sigue sin validar en ningún
  // sitio de RTL -- ver docs/implementacion/registros.md#deliberadamente-fuera-de-v3.
  // -----------------------------------------------------------------------
  logic        timing_enable_r;
  logic [31:0] prf_div_low_r, prf_div_high_r;
  logic [15:0] pulse_width_low_r, pulse_width_high_r;
  logic [15:0] n_pulses_low_r, n_pulses_high_r;
  logic [31:0] trig_delay_r[4];
  logic [31:0] trig_width_r[4];

  assign timing_enable    = timing_enable_r;
  assign prf_div_low      = prf_div_low_r;
  assign prf_div_high     = prf_div_high_r;
  assign pulse_width_low  = pulse_width_low_r;
  assign pulse_width_high = pulse_width_high_r;
  assign n_pulses_low     = n_pulses_low_r;
  assign n_pulses_high    = n_pulses_high_r;
  assign trig_delay_0     = trig_delay_r[0];
  assign trig_delay_1     = trig_delay_r[1];
  assign trig_delay_2     = trig_delay_r[2];
  assign trig_delay_3     = trig_delay_r[3];
  assign trig_width_0     = trig_width_r[0];
  assign trig_width_1     = trig_width_r[1];
  assign trig_width_2     = trig_width_r[2];
  assign trig_width_3     = trig_width_r[3];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      timing_enable_r    <= 1'b0;
      prf_div_low_r       <= '0;
      prf_div_high_r      <= '0;
      pulse_width_low_r   <= '0;
      pulse_width_high_r  <= '0;
      n_pulses_low_r      <= '0;
      n_pulses_high_r     <= '0;
      for (int t = 0; t < 4; t++) begin
        trig_delay_r[t] <= '0;
        trig_width_r[t] <= '0;
      end
    end else if (write_commit) begin
      unique case (awaddr_r)
        REG_TIMING_CTRL_ADDR: timing_enable_r <= wdata_r[0];
        REG_PRF_DIV_LOW_ADDR: prf_div_low_r <= wdata_r;
        REG_PRF_DIV_HIGH_ADDR: prf_div_high_r <= wdata_r;
        REG_PULSE_WIDTH_ADDR: begin
          pulse_width_low_r  <= wdata_r[15:0];
          pulse_width_high_r <= wdata_r[31:16];
        end
        REG_N_PULSES_ADDR: begin
          n_pulses_low_r  <= wdata_r[15:0];
          n_pulses_high_r <= wdata_r[31:16];
        end
        REG_TRIG_DELAY_0_ADDR: trig_delay_r[0] <= wdata_r;
        REG_TRIG_DELAY_1_ADDR: trig_delay_r[1] <= wdata_r;
        REG_TRIG_DELAY_2_ADDR: trig_delay_r[2] <= wdata_r;
        REG_TRIG_DELAY_3_ADDR: trig_delay_r[3] <= wdata_r;
        REG_TRIG_WIDTH_0_ADDR: trig_width_r[0] <= wdata_r;
        REG_TRIG_WIDTH_1_ADDR: trig_width_r[1] <= wdata_r;
        REG_TRIG_WIDTH_2_ADDR: trig_width_r[2] <= wdata_r;
        REG_TRIG_WIDTH_3_ADDR: trig_width_r[3] <= wdata_r;
        default: ;  // resto de direcciones: sin registro que actualizar aquí
      endcase
    end
  end

  // TIMING_STATUS: mismo patrón sticky + W1C que OVERFLOW, set gana sobre un
  // clear concurrente. `radial_done_in` es un pulso de un ciclo (ver la
  // cabecera de drx_prf_batch_seq.sv), de ahí el latch. Bits 1/2 (v4, D-09):
  // mismo patrón sobre `config_invalid_low_in`/`_high_in` (niveles
  // combinacionales, ver cabecera del módulo).
  logic radial_done_sticky_r;
  logic config_invalid_low_sticky_r;
  logic config_invalid_high_sticky_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      radial_done_sticky_r <= 1'b0;
    end else if (radial_done_in) begin
      radial_done_sticky_r <= 1'b1;
    end else if (write_commit && (awaddr_r == REG_TIMING_STATUS_ADDR) && wdata_r[0]) begin
      radial_done_sticky_r <= 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      config_invalid_low_sticky_r <= 1'b0;
    end else if (config_invalid_low_in) begin
      config_invalid_low_sticky_r <= 1'b1;
    end else if (write_commit && (awaddr_r == REG_TIMING_STATUS_ADDR) && wdata_r[1]) begin
      config_invalid_low_sticky_r <= 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      config_invalid_high_sticky_r <= 1'b0;
    end else if (config_invalid_high_in) begin
      config_invalid_high_sticky_r <= 1'b1;
    end else if (write_commit && (awaddr_r == REG_TIMING_STATUS_ADDR) && wdata_r[2]) begin
      config_invalid_high_sticky_r <= 1'b0;
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
      REG_OVERFLOW_ADDR: begin
        for (int c = 0; c < N_CH; c++) rdata_next[c] = overflow_sticky_r[c];
      end
      REG_TIMING_CTRL_ADDR: rdata_next[0] = timing_enable_r;
      REG_TIMING_STATUS_ADDR: begin
        rdata_next[0] = radial_done_sticky_r;
        rdata_next[1] = config_invalid_low_sticky_r;
        rdata_next[2] = config_invalid_high_sticky_r;
      end
      REG_PRF_DIV_LOW_ADDR: rdata_next = prf_div_low_r;
      REG_PRF_DIV_HIGH_ADDR: rdata_next = prf_div_high_r;
      REG_PULSE_WIDTH_ADDR: rdata_next = {pulse_width_high_r, pulse_width_low_r};
      REG_N_PULSES_ADDR: rdata_next = {n_pulses_high_r, n_pulses_low_r};
      REG_TRIG_DELAY_0_ADDR: rdata_next = trig_delay_r[0];
      REG_TRIG_DELAY_1_ADDR: rdata_next = trig_delay_r[1];
      REG_TRIG_DELAY_2_ADDR: rdata_next = trig_delay_r[2];
      REG_TRIG_DELAY_3_ADDR: rdata_next = trig_delay_r[3];
      REG_TRIG_WIDTH_0_ADDR: rdata_next = trig_width_r[0];
      REG_TRIG_WIDTH_1_ADDR: rdata_next = trig_width_r[1];
      REG_TRIG_WIDTH_2_ADDR: rdata_next = trig_width_r[2];
      REG_TRIG_WIDTH_3_ADDR: rdata_next = trig_width_r[3];
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
