// Top del LAMULA DRx.
//
// Z0 fue diseño vacío a propósito (solo el latido) para cerrar el lazo del
// substrato. Esta integración (Z1) es la primera vez que el top de verdad
// instancia la cadena real: `vector_source` (BRAM-loop, nuevo — ver su propia
// cabecera) -> `drx_ddc_quad_top` -> `drx_range_gate_quad_top`, con `N_CH=3`
// (Config A/B de P-12, no los 4 canales Rx homogéneos: es lo que de verdad se
// usa en la mayoría de las pruebas en ZedBoard).
//
// Deliberadamente incompleto todavía, documentado aquí para que no se lea como
// olvido:
//   - `mode_coarse`, el `overrun` por canal de range-gate y el `overflow` de
//     saturación del DDC ya son AXI-Lite de verdad (`rtl/drx_axil_regs.sv`,
//     ver `docs/implementacion/registros.md`), no el `localparam ModeCoarse`
//     fijo que tenía este fichero antes. El overflow se añadió después que
//     mode_coarse/overrun (v2 del mapa, misma fase Z1) — ver la cabecera de
//     `config/registers.toml` para el porqué de esa secuencia.
//   - **`drx_axil_regs` se instancia aquí y sus puertos AXI-Lite SÍ son
//     puertos reales de `drx_top`, desde el 20-sep-2026 (más tarde).**
//     Hallazgo previo, ya resuelto: exponerlos pedía del orden de 94 pines
//     físicos, muy por encima de los 50 sitios del paquete de la ZedBoard —
//     `place_design` falló con "IO placement is infeasible" atándolos
//     directamente a pines de `drx_top`. La causa raíz no era el ancho del
//     bus: era que nada en este repo instanciaba un PS7 ni un interconnect
//     AXI que pudiera ser el maestro de este slave *dentro* del chip. Con eso
//     resuelto (ver `rtl/drx_zynq_top.sv`, nuevo), `drx_top` vuelve a ser lo
//     que siempre debió ser — un slave AXI-Lite pass-through, sin opinión
//     sobre quién lo maneja — y es `drx_zynq_top` quien decide el maestro:
//     el wrapper del block design con `processing_system7` (`M_AXI_GP0` vía
//     un `axi_interconnect` 1×1), generado por `tcl/gen_zynq_bd.tcl`.
//     `drx_top` standalone (sin `drx_zynq_top`, el `-top drx_top` de
//     `tcl/build.tcl` de siempre) sigue sintetizable exactamente igual que
//     antes con sus puertos AXI-Lite atados a valores inertes por quien lo
//     instancie — ese flujo no cambia, sigue existiendo para medir solo el
//     datapath.
//   - `m_ready` de range-gate va siempre a alto: no hay consumidor real (el
//     AXI DMA es Z4).
//   - Las salidas de I/Q de range-gate no tienen consumidor real todavía (ni
//     DMA/Z4), así que se reducen a un único bit `debug_probe` registrado, en
//     vez de exponerse una a una. Dos hallazgos de síntesis real (19-sep-2026)
//     llevan a esto: (1) exponerlas todas como puertos — primer intento —
//     hace fallar `place_design` ("IO placement is infeasible", 105 puertos
//     pedidos contra 50 sitios físicos disponibles en el paquete de la
//     ZedBoard); (2) `(* keep = "true" *)` sobre señales internas sin ningún
//     puerto real aguas abajo —segundo intento— no evita que `opt_design` se
//     lleve por delante la cadena entera de todas formas (post-route quedó en
//     22 LUTs, 0 DSP, 0 BRAM: solo el latido). Lo único que de verdad
//     sobrevive a la eliminación de lógica muerta de la implementación es
//     alcanzar un puerto real — un solo bit basta, mismo patrón que ya usa
//     este árbol para "hacer real" una señal sin consumidor
//     (`unused_nco_ready` en `drx_ddc_top.sv`), llevado hasta el top. Esta
//     build se corre hasta `-step impl` (P&R con cierre de temporización real
//     de este datapath, primera vez que se mide algo distinto del diseño
//     vacío), no hasta `-step bitstream`. El `overrun` por canal, a
//     diferencia del resto de las salidas de range-gate, SÍ tiene ahora un
//     consumidor real (STATUS de `drx_axil_regs`) y por eso ya no depende de
//     este hack para sobrevivir a la síntesis.
//   - `s_last` de `vector_source` pulsa cada `DEPTH` muestras — marcador
//     artificial de "fin de ventana" para ejercitar el framing de
//     `drx_range_gate`, NO el PRF real (Z2 no existe todavía).
//
// Z2 (v3 del mapa de registros, 22-sep-2026): `drx_timing_engine` (D-13, 2
// lotes de PRF/ancho de pulso + N_TRIGGERS de retardo/ancho) ya se instancia
// aquí, configurado desde AXI-Lite (TIMING_CTRL/TIMING_STATUS/PRF_DIV_*/
// PULSE_WIDTH/N_PULSES/TRIG_DELAY_*/TRIG_WIDTH_*, ver
// docs/implementacion/registros.md). `trig_out` sí es un puerto físico real
// de este top -- su único consumo hoy es medirlo con osciloscopio (el
// propósito de ZM2) -- pero NO tiene todavía pines XDC asignados:
// `tcl/xdc/zedboard.xdc` no tiene mapeado ningún Pmod de la ZedBoard, y no
// hay una referencia de pinout física verificada en este repo para inventar
// una asignación. Sintetiza y lintea limpio; el P&R real con estos 4 pines
// nuevos no se ha vuelto a correr en esta sesión.
//
// Z2 (más tarde, mismo día, D-14): `timing_pulse_trig` ya sincroniza el
// corte de rayo de `drx_range_gate_quad_top` -- cada pulso de PRF (de
// cualquiera de los 2 lotes) resetea el puntero de escritura vía el puerto
// `ray_start` nuevo (ver la cabecera de `drx_range_gate.sv`). Esto SÍ toca
// RTL de Z1 ya cerrado y verificado bajo D-12, pero de forma aditiva y hacia
// atrás compatible: con `ray_start` en bajo (como en toda la matriz L1 ya
// corrida) el comportamiento es bit a bit idéntico al de antes, así que no
// hizo falta generar vectores nuevos del modelo dorado, solo reconfirmar
// (xsim real) que `tb_l1_ddc_range_tri.sv` sigue en verde con el puerto
// añadido. Lo que esto NO resuelve, a propósito: si `drx_range_gate` necesita
// un conteo de bins distinto por lote (ya lo deja abierto D-13, sin relación
// con esta sincronización); si `pulse_trig` debe disparar también
// `vector_source`/algo del lado Tx (no existe ese lado todavía); y el tiempo
// muerto entre el fin de un rayo real y el siguiente `ray_start` se descarta
// en silencio, sin ningún contador de diagnóstico -- no hay hoy ningún BITE
// que distinga "PRI bien calibrado" de "un `ray_start` llegó tarde y truncó
// un rayo en curso" (D-09 no se aplica en RTL, ver `drx_prf_batch_seq.sv`).

`ifndef DRX_TOP_SV
`define DRX_TOP_SV

module drx_top
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

    // Z2 (D-13): salida física de los N_TRIGGERS triggers de
    // drx_timing_engine -- ver la cabecera de este fichero, sin pines XDC
    // todavía.
    output logic [N_TRIGGERS-1:0] trig_out,

    // Slave AXI4-Lite de `drx_axil_regs`, pass-through puro hacia/desde quien
    // instancie `drx_top` (ver la cabecera: hoy `drx_zynq_top`, o valores
    // inertes si se sintetiza `drx_top` solo).
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

    input  logic [REGS_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic                       s_axi_arvalid,
    output logic                       s_axi_arready,

    output logic [31:0] s_axi_rdata,
    output logic [ 1:0] s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready
);

  logic                      gate_valid  [N_CH];
  logic signed [IQ_BITS-1:0] gate_i      [N_CH];
  logic signed [IQ_BITS-1:0] gate_q      [N_CH];
  logic                      gate_last   [N_CH];
  logic                      gate_overrun[N_CH];
  logic                      gate_clear  [N_CH];

  drx_heartbeat #(
      .DIV(HEARTBEAT_DIV)
  ) u_heartbeat (
      .clk  (clk),
      .rst_n(rst_n),
      .level(led_heartbeat)
  );

  logic mode_coarse;

  // `drx_axil_regs` recibe/devuelve el overrun por canal como vector
  // empaquetado (STATUS es literalmente eso), mientras que
  // `drx_range_gate_quad_top` usa arrays sin empaquetar (mismo patrón que el
  // resto de sus puertos por canal) — este par de `always_comb` es el único
  // sitio que convierte entre las dos formas.
  logic [N_CH-1:0] gate_overrun_packed;
  logic [N_CH-1:0] gate_clear_packed;

  always_comb begin
    for (int c = 0; c < N_CH; c++) gate_overrun_packed[c] = gate_overrun[c];
  end

  always_comb begin
    for (int c = 0; c < N_CH; c++) gate_clear[c] = gate_clear_packed[c];
  end

  // Mismo empaquetado que arriba, para el overflow de saturación del DDC
  // (`drx_ddc_quad_top.overflow`, array sin empaquetar) hacia OVERFLOW de
  // `drx_axil_regs` (vector empaquetado, ver la cabecera de ese módulo).
  logic                      ddc_overflow[N_CH];
  logic [N_CH-1:0]           ddc_overflow_packed;

  always_comb begin
    for (int c = 0; c < N_CH; c++) ddc_overflow_packed[c] = ddc_overflow[c];
  end

  // Z2 (v3, D-13): registro -> planta hacia `drx_timing_engine`. `drx_axil_regs`
  // expone los 4 canales de TRIG_DELAY/TRIG_WIDTH como puertos escalares con
  // nombre (ver su cabecera: un array sin empaquetar de puertos de SALIDA no
  // es indexable vía VPI); `drx_timing_engine` los toma como array sin
  // empaquetar de entrada (eso sí funciona, ver la cabecera de
  // drx_trigger_gen.sv). Este es el único sitio que empaqueta.
  logic        timing_enable;
  logic [31:0] prf_div_low, prf_div_high;
  logic [15:0] pulse_width_low, pulse_width_high;
  logic [15:0] n_pulses_low, n_pulses_high;
  logic [31:0] trig_delay_0, trig_delay_1, trig_delay_2, trig_delay_3;
  logic [31:0] trig_width_0, trig_width_1, trig_width_2, trig_width_3;
  logic        timing_radial_done;

  logic [31:0] trig_delay_arr[N_TRIGGERS];
  logic [31:0] trig_width_arr[N_TRIGGERS];
  assign trig_delay_arr = '{trig_delay_0, trig_delay_1, trig_delay_2, trig_delay_3};
  assign trig_width_arr = '{trig_width_0, trig_width_1, trig_width_2, trig_width_3};

  drx_axil_regs #(
      .N_CH(N_CH)
  ) u_regs (
      .clk  (clk),
      .rst_n(rst_n),

      .s_axi_awaddr (s_axi_awaddr),
      .s_axi_awvalid(s_axi_awvalid),
      .s_axi_awready(s_axi_awready),
      .s_axi_wdata  (s_axi_wdata),
      .s_axi_wstrb  (s_axi_wstrb),
      .s_axi_wvalid (s_axi_wvalid),
      .s_axi_wready (s_axi_wready),
      .s_axi_bresp  (s_axi_bresp),
      .s_axi_bvalid (s_axi_bvalid),
      .s_axi_bready (s_axi_bready),
      .s_axi_araddr (s_axi_araddr),
      .s_axi_arvalid(s_axi_arvalid),
      .s_axi_arready(s_axi_arready),
      .s_axi_rdata  (s_axi_rdata),
      .s_axi_rresp  (s_axi_rresp),
      .s_axi_rvalid (s_axi_rvalid),
      .s_axi_rready (s_axi_rready),

      .mode_coarse(mode_coarse),

      .overrun_in   (gate_overrun_packed),
      .overrun_clear(gate_clear_packed),

      .overflow_in(ddc_overflow_packed),

      .timing_enable   (timing_enable),
      .prf_div_low     (prf_div_low),
      .prf_div_high    (prf_div_high),
      .pulse_width_low (pulse_width_low),
      .pulse_width_high(pulse_width_high),
      .n_pulses_low    (n_pulses_low),
      .n_pulses_high   (n_pulses_high),
      .trig_delay_0    (trig_delay_0),
      .trig_delay_1    (trig_delay_1),
      .trig_delay_2    (trig_delay_2),
      .trig_delay_3    (trig_delay_3),
      .trig_width_0    (trig_width_0),
      .trig_width_1    (trig_width_1),
      .trig_width_2    (trig_width_2),
      .trig_width_3    (trig_width_3),

      .radial_done_in(timing_radial_done)
  );

  // `pulse_trig` SÍ tiene consumidor real ahora (D-14: `ray_start` de
  // range-gate, más abajo). `batch_sel`/`pulse_width`/`tx_gate` siguen sin
  // ninguno (ver la cabecera del fichero); se pliegan en `debug_probe_xor`
  // más abajo, mismo patrón que ya usa este árbol para que la síntesis no se
  // lleve por delante una cadena sin puerto real aguas abajo
  // (`unused_nco_ready` en drx_ddc_top.sv).
  logic timing_pulse_trig, timing_batch_sel, timing_tx_gate;
  logic [15:0] timing_pulse_width;

  drx_timing_engine u_timing_engine (
      .clk   (clk),
      .rst_n (rst_n),
      .enable(timing_enable),

      .prf_div_low     (prf_div_low),
      .pulse_width_low (pulse_width_low),
      .n_pulses_low    (n_pulses_low),
      .prf_div_high    (prf_div_high),
      .pulse_width_high(pulse_width_high),
      .n_pulses_high   (n_pulses_high),

      .trig_delay(trig_delay_arr),
      .trig_width(trig_width_arr),

      .pulse_trig (timing_pulse_trig),
      .batch_sel  (timing_batch_sel),
      .pulse_width(timing_pulse_width),
      .tx_gate    (timing_tx_gate),
      .radial_done(timing_radial_done),

      .trig_out(trig_out)
  );

  // Mismo `` `ifdef DRX_PLATFORM_ZU9 `` que ya selecciona FS_HZ en
  // `drx_params_pkg.sv` (D-02) — el fichero de precarga de `vector_source`
  // también depende de la plataforma (`tools/gen_vector_source_init.py`
  // escribe uno por `params.name`), y decidirlo aquí, no dentro de
  // `vector_source.sv`, evita hardcodear una placa concreta en un módulo que
  // se supone reutilizable en las dos.
`ifdef DRX_PLATFORM_ZU9
  localparam string VectorSourceInitFile = "build/vector-source-init/zu9/vector_source_init.hex";
`else
  localparam string VectorSourceInitFile = "build/vector-source-init/zedboard/vector_source_init.hex";
`endif

  logic                          vs_valid[N_CH];
  logic                          vs_ready[N_CH];
  logic signed [SAMPLE_BITS-1:0] vs_data [N_CH];
  logic                          vs_last [N_CH];

  vector_source #(
      .N_CH(N_CH),
      .INIT_FILE(VectorSourceInitFile)
  ) u_vector_source (
      .clk  (clk),
      .rst_n(rst_n),
      .ready(vs_ready),
      .valid(vs_valid),
      .data (vs_data),
      .last (vs_last)
  );

  logic                      ddc_valid[N_CH];
  logic signed [IQ_BITS-1:0] ddc_i    [N_CH];
  logic signed [IQ_BITS-1:0] ddc_q    [N_CH];

  drx_ddc_quad_top #(
      .N_CH(N_CH)
  ) u_ddc (
      .clk (clk),
      .rst_n(rst_n),

      .s_valid(vs_valid),
      .s_ready(vs_ready),
      .s_data (vs_data),
      .s_last (vs_last),

      .mode_coarse(mode_coarse),

      .m_valid(ddc_valid),
      .m_i    (ddc_i),
      .m_q    (ddc_q),

      .overflow(ddc_overflow)
  );

  logic gate_ready[N_CH];
  assign gate_ready = '{default: 1'b1};  // sin consumidor real todavía (DMA es Z4)

  drx_range_gate_quad_top #(
      .N_CH(N_CH)
  ) u_gate (
      .clk (clk),
      .rst_n(rst_n),

      .s_valid(ddc_valid),
      .s_i    (ddc_i),
      .s_q    (ddc_q),

      .mode_coarse(mode_coarse),

      .m_valid(gate_valid),
      .m_ready(gate_ready),
      .m_i    (gate_i),
      .m_q    (gate_q),
      .m_last (gate_last),

      .clear  (gate_clear),
      .overrun(gate_overrun),

      // D-14: cada pulso de PRF (lote bajo o alto) resetea el corte de rayo.
      .ray_start(timing_pulse_trig)
  );

  // Un solo bit, registrado, que depende de toda la cadena — ver la cabecera
  // sobre por qué hace falta llegar a un puerto real. El valor en sí no
  // significa nada (no es un BITE ni un estado utilizable): existe solo para
  // que la síntesis real no elimine la cadena que alimenta. `timing_pulse_trig`/
  // `timing_batch_sel`/`timing_pulse_width`/`timing_tx_gate` se suman aquí por
  // el mismo motivo (ver el comentario junto a u_timing_engine): sin esto,
  // esas cuatro salidas de drx_timing_engine no llegan a ningún puerto real.
  logic debug_probe_xor;
  always_comb begin
    debug_probe_xor = timing_batch_sel ^ timing_tx_gate ^ (^timing_pulse_width);
    for (int c = 0; c < N_CH; c++) begin
      debug_probe_xor ^= gate_valid[c] ^ gate_last[c] ^ gate_overrun[c]
          ^ (^gate_i[c]) ^ (^gate_q[c]);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) debug_probe <= 1'b0;
    else debug_probe <= debug_probe_xor;
  end

endmodule : drx_top

`endif  // DRX_TOP_SV
