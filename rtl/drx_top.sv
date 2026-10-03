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
//   - `s_last` de `vector_source` pulsa cada `DEPTH` muestras — marcador
//     artificial de "fin de ventana" para ejercitar el framing de
//     `drx_range_gate`, NO el PRF real (Z2 no existe todavía).
//
// Ray packer (Z4.0, fases.md#z4, 26-sep-2026): las dos entradas de arriba ya
// NO aplican — `gate_ready`/las salidas de I/Q de range-gate por fin tienen
// consumidor real, `drx_ray_packer` (nuevo), que entrelaza los N_CH canales
// en un único AXI4-Stream (`m_ray_*`, puertos reales de este top). Llevarlo
// hasta un AXI DMA S2MM real es responsabilidad de quien instancie este top
// (`rtl/drx_zynq_top.sv` + `tcl/gen_zynq_bd.tcl`) — pero `drx_top` también
// se sintetiza SOLO, sin ese consumidor (`rtl/drx_top_tieoff.sv`, para medir
// WNS/utilización del datapath sin PS7), así que `debug_probe_xor` (más
// abajo) sigue plegando `m_ray_valid`/`m_ray_data`/`m_ray_last` — ya no
// `gate_valid`/`gate_i`/`gate_q`/`gate_last` directamente, que ahora es
// `drx_ray_packer` quien los consume — para que esa build sin DMA no pierda
// la cadena entera bajo `opt_design`, ver el comentario junto a
// `debug_probe_xor`.
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
// añadido. Lo que esto NO resuelve, a propósito: si `pulse_trig` debe
// disparar también `vector_source`/algo del lado Tx (no existe ese lado
// todavía); y el tiempo muerto entre el fin de un rayo real y el siguiente
// `ray_start` se descarta en silencio, sin ningún contador de diagnóstico --
// no hay hoy ningún BITE que distinga "PRI bien calibrado" de "un
// `ray_start` llegó tarde y truncó un rayo en curso". Esto es independiente
// de D-09 (PRF x rango), que desde el 22-sep-2026 (más tarde) sí se aplica
// completo en RTL -- ver la cabecera de `drx_timing_engine.sv`.
//
// D-15 (25-sep-2026): el conteo de bins por lote que D-13/D-14 dejaban
// abierto ya está resuelto -- `mode_coarse` deja de llegar a
// `drx_range_gate_quad_top` (sigue yendo a `drx_ddc_quad_top`, que es quien
// de verdad lo necesita para decimación). En su lugar, `bins_low`/`bins_high`
// (registros AXI-Lite nuevos, mapa v5) alimentan `drx_timing_engine`, que
// expone el conteo del lote ACTIVO (`timing_bins`, mismo mux que ya hace con
// `pulse_width`) hacia `drx_range_gate_quad_top`. El techo físico (BRAM real,
// BINS_MODE_FINE) se valida en `drx_timing_config_valid.sv`, no aquí -- ver
// decisiones.md#d-15.
//
// BITE de tiempo muerto (25-sep-2026, más tarde, mapa v6): el párrafo de D-14
// de arriba ("el tiempo muerto... se descarta en silencio, sin ningún
// contador de diagnóstico") ya no aplica -- `drx_range_gate_quad_top` gana
// `ray_truncated`/`clear_truncated` por canal, expuestos como GATE_TRUNCATED
// en el mapa de registros (mismo patrón W1C que STATUS/overrun, registro
// propio). Ver decisiones.md#d-14 (actualización) y registros.md#z2-en-v6.

`ifndef DRX_TOP_SV
`define DRX_TOP_SV

module drx_top
  import drx_params_pkg::*;
  import drx_regs_pkg::*;
#(
    parameter int HEARTBEAT_DIV = int'(FS_HZ / 2),
    parameter int N_CH = N_CH_TOP
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
    input  logic        s_axi_rready,

    // Z4.0: AXI4-Stream de salida de `drx_ray_packer` (N_CH canales
    // entrelazados) -- ver la cabecera. Quien instancie este top lo lleva
    // hasta un AXI DMA S2MM real (`rtl/drx_zynq_top.sv`) o a valores
    // inertes (`rtl/drx_top_tieoff.sv`, el flujo sin PS7).
    output logic                 m_ray_valid,
    input  logic                 m_ray_ready,
    output logic [2*IQ_BITS-1:0] m_ray_data,
    output logic                 m_ray_last,

    // Z4.3: AXI4-Stream de ENTRADA del modo Throttled(DDR) de `vector_source`
    // -- 16 bits, una muestra por beat, canales en orden ascendente (ver la
    // cabecera de `vector_source.sv`). Quien instancie este top lo trae de un
    // AXI DMA MM2S real (`rtl/drx_zynq_top.sv`) o lo ata inerte
    // (`rtl/drx_top_tieoff.sv`). Con CTRL bit 1 en 0 -- el valor de reset --
    // este puerto no se mira, asi que el flujo sin PS7 sigue funcionando
    // exactamente igual que antes de Z4.3.
    input  logic                          s_vec_valid,
    output logic                          s_vec_ready,
    input  logic signed [SAMPLE_BITS-1:0] s_vec_data,
    input  logic                          s_vec_last
);

  logic                      gate_valid  [N_CH];
  logic signed [IQ_BITS-1:0] gate_i      [N_CH];
  logic signed [IQ_BITS-1:0] gate_q      [N_CH];
  logic                      gate_last   [N_CH];
  logic                      gate_overrun[N_CH];
  logic                      gate_clear  [N_CH];
  logic                      gate_ray_truncated  [N_CH];
  logic                      gate_clear_truncated[N_CH];

  drx_heartbeat #(
      .DIV(HEARTBEAT_DIV)
  ) u_heartbeat (
      .clk  (clk),
      .rst_n(rst_n),
      .level(led_heartbeat)
  );

  logic mode_coarse;

  // Z4.4: TRIG_COUNT sacado a fabric para la cabecera en banda del rayo.
  logic [31:0] timing_trig_count;
  logic vector_source_ddr;

  // Actuación AFC (Z4.5): NCO_PINC del mapa v9 hacia el canal S_AXIS_CONFIG de
  // los N_CH NCO del DDC. Una sola palabra para los N_CH: todos ven el mismo IF.
  logic [31:0] nco_pinc;
  logic        nco_pinc_we;

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

  // Mismo empaquetado, para el BITE de tiempo muerto (GATE_TRUNCATED, v6) --
  // ver la cabecera.
  logic [N_CH-1:0] gate_ray_truncated_packed;
  logic [N_CH-1:0] gate_clear_truncated_packed;

  always_comb begin
    for (int c = 0; c < N_CH; c++) gate_ray_truncated_packed[c] = gate_ray_truncated[c];
  end

  always_comb begin
    for (int c = 0; c < N_CH; c++) gate_clear_truncated[c] = gate_clear_truncated_packed[c];
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
  logic        timing_paced;
  // Lo conduce `u_sample_pacer`, instanciado mas abajo junto a la fuente de
  // muestras (es donde viven `vs_valid`/`vs_ready`). Declarado aqui porque
  // `u_timing_engine` lo consume antes en el fichero.
  logic        timing_advance;
  logic [31:0] prf_div_low, prf_div_high;
  logic [15:0] pulse_width_low, pulse_width_high;
  logic [15:0] n_pulses_low, n_pulses_high;
  logic [31:0] bins_low, bins_high;
  logic [31:0] trig_delay_0, trig_delay_1, trig_delay_2, trig_delay_3;
  logic [31:0] trig_width_0, trig_width_1, trig_width_2, trig_width_3;
  logic        timing_radial_done;
  logic        timing_config_invalid_low, timing_config_invalid_high;

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
      .vector_source_ddr(vector_source_ddr),
      .nco_pinc(nco_pinc),
      .nco_pinc_we(nco_pinc_we),

      .overrun_in   (gate_overrun_packed),
      .overrun_clear(gate_clear_packed),

      .overflow_in(ddc_overflow_packed),

      .ray_truncated_in   (gate_ray_truncated_packed),
      .ray_truncated_clear(gate_clear_truncated_packed),

      .timing_enable   (timing_enable),
      .timing_paced    (timing_paced),
      .prf_div_low     (prf_div_low),
      .prf_div_high    (prf_div_high),
      .pulse_width_low (pulse_width_low),
      .pulse_width_high(pulse_width_high),
      .n_pulses_low    (n_pulses_low),
      .n_pulses_high   (n_pulses_high),
      .bins_low        (bins_low),
      .bins_high       (bins_high),
      .trig_delay_0    (trig_delay_0),
      .trig_delay_1    (trig_delay_1),
      .trig_delay_2    (trig_delay_2),
      .trig_delay_3    (trig_delay_3),
      .trig_width_0    (trig_width_0),
      .trig_width_1    (trig_width_1),
      .trig_width_2    (trig_width_2),
      .trig_width_3    (trig_width_3),

      .radial_done_in(timing_radial_done),

      .config_invalid_low_in (timing_config_invalid_low),
      .config_invalid_high_in(timing_config_invalid_high),

      // Z4.1: TRIG_COUNT -- mismo pulse_trig que ya dispara ray_start (D-14),
      // ver la cabecera de drx_axil_regs.sv.
      .pulse_trig_in(timing_pulse_trig),
      .trig_count_out(timing_trig_count)
  );

  // `pulse_trig` SÍ tiene consumidor real ahora (D-14: `ray_start` de
  // range-gate, más abajo). `batch_sel`/`pulse_width`/`tx_gate` siguen sin
  // ninguno (ver la cabecera del fichero); se pliegan en `debug_probe_xor`
  // más abajo, mismo patrón que ya usa este árbol para que la síntesis no se
  // lleve por delante una cadena sin puerto real aguas abajo
  // (`unused_nco_ready` en drx_ddc_top.sv).
  logic timing_pulse_trig, timing_batch_sel, timing_tx_gate;
  logic [15:0] timing_pulse_width;
  logic [31:0] timing_bins;

  drx_timing_engine u_timing_engine (
      .clk   (clk),
      .rst_n (rst_n),
      .enable(timing_enable),
      .advance(timing_advance),

      .prf_div_low     (prf_div_low),
      .pulse_width_low (pulse_width_low),
      .n_pulses_low    (n_pulses_low),
      .prf_div_high    (prf_div_high),
      .pulse_width_high(pulse_width_high),
      .n_pulses_high   (n_pulses_high),

      .bins_low (bins_low),
      .bins_high(bins_high),

      .trig_delay(trig_delay_arr),
      .trig_width(trig_width_arr),

      .pulse_trig (timing_pulse_trig),
      .batch_sel  (timing_batch_sel),
      .pulse_width(timing_pulse_width),
      .bin_count  (timing_bins),
      .tx_gate    (timing_tx_gate),
      .radial_done(timing_radial_done),

      .config_invalid_low (timing_config_invalid_low),
      .config_invalid_high(timing_config_invalid_high),

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

      .ddr_mode(vector_source_ddr),

      .s_axis_valid(s_vec_valid),
      .s_axis_ready(s_vec_ready),
      .s_axis_data (s_vec_data),
      .s_axis_last (s_vec_last),

      .ready(vs_ready),
      .valid(vs_valid),
      .data (vs_data),
      .last (vs_last)
  );

  // P-16: el motor de timing cuenta avances de muestra en vez de ciclos
  // cuando TIMING_CTRL bit 1 esta en alto. Con el bit en 0 (reset) `advance`
  // es constante 1 y el motor es el de v3..v9. Ver `drx_sample_pacer.sv`.
  // Empaquetado para el pacer: sus puertos son buses y no arrays
  // desempaquetados por un limite de Verilator/cocotb, no por diseno -- ver
  // su cabecera.
  logic [N_CH-1:0] vs_valid_pk;
  logic [N_CH-1:0] vs_ready_pk;
  always_comb begin
    for (int c = 0; c < N_CH; c = c + 1) begin
      vs_valid_pk[c] = vs_valid[c];
      vs_ready_pk[c] = vs_ready[c];
    end
  end

  drx_sample_pacer #(
      .N_CH(N_CH)
  ) u_sample_pacer (
      .paced(timing_paced),
      .valid(vs_valid_pk),
      .ready(vs_ready_pk),
      .advance(timing_advance)
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

      .nco_pinc   (nco_pinc),
      .nco_pinc_we(nco_pinc_we),

      .m_valid(ddc_valid),
      .m_i    (ddc_i),
      .m_q    (ddc_q),

      .overflow(ddc_overflow)
  );

  logic gate_ready[N_CH];

  drx_range_gate_quad_top #(
      .N_CH(N_CH)
  ) u_gate (
      .clk (clk),
      .rst_n(rst_n),

      .s_valid(ddc_valid),
      .s_i    (ddc_i),
      .s_q    (ddc_q),

      .bin_count(timing_bins),

      .m_valid(gate_valid),
      .m_ready(gate_ready),
      .m_i    (gate_i),
      .m_q    (gate_q),
      .m_last (gate_last),

      .clear  (gate_clear),
      .overrun(gate_overrun),

      // D-14: cada pulso de PRF (lote bajo o alto) resetea el corte de rayo.
      .ray_start(timing_pulse_trig),

      // BITE de tiempo muerto (v6, ver la cabecera del fichero).
      .clear_truncated(gate_clear_truncated),
      .ray_truncated  (gate_ray_truncated)
  );

  // Un solo bit, registrado, que depende de toda la cadena — ver la cabecera
  // sobre por qué hace falta llegar a un puerto real. El valor en sí no
  // significa nada (no es un BITE ni un estado utilizable): existe solo para
  // que la síntesis real no elimine la cadena que alimenta. `timing_pulse_trig`/
  // `timing_batch_sel`/`timing_pulse_width`/`timing_tx_gate` se suman aquí por
  // el mismo motivo (ver el comentario junto a u_timing_engine): sin esto,
  // esas cuatro salidas de drx_timing_engine no llegan a ningún puerto real.
  //
  // Z4.0: `m_ray_valid`/`m_ray_data`/`m_ray_last` (puertos reales de este
  // top, más abajo) SE SUMAN AQUÍ TAMBIÉN, no en su lugar de gate_valid/
  // gate_i/gate_q/gate_last — a propósito, no redundante. En la build con
  // PS7 (`drx_zynq_top`) esos tres ya alcanzan un sink real (el AXI DMA), y
  // en esa build este fold es puro cinturón y tirantes. Pero `drx_top` mismo
  // también se sintetiza SOLO, sin PS7 y sin DMA (`drx_top_tieoff.sv`, para
  // medir WNS/utilización del datapath) — ahí nadie conecta `m_ray_*` a
  // nada, y sin este fold `opt_design` se llevaría por delante
  // `drx_ray_packer` entero y, con él, la cadena completa de range-gate/DDC/
  // vector_source que alimenta, exactamente el mismo fallo que este hack ya
  // resolvió una vez (ver la cabecera). Metiéndolo aquí, DENTRO de
  // `drx_top`, la protección no depende de que quien lo instancie se acuerde
  // de darle un sink real.
  logic debug_probe_xor;
  always_comb begin
    debug_probe_xor = timing_batch_sel ^ timing_tx_gate ^ (^timing_pulse_width)
        ^ m_ray_valid ^ m_ray_last ^ (^m_ray_data);
    for (int c = 0; c < N_CH; c++) begin
      debug_probe_xor ^= gate_overrun[c] ^ gate_ray_truncated[c];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) debug_probe <= 1'b0;
    else debug_probe <= debug_probe_xor;
  end

  // Z4.0: primer consumidor real de gate_valid/gate_i/gate_q/gate_last/
  // gate_ready -- ver la cabecera del fichero.
  drx_ray_packer #(
      .N_CH(N_CH)
  ) u_ray_packer (
      .clk  (clk),
      .rst_n(rst_n),

      .s_valid(gate_valid),
      .s_ready(gate_ready),
      .s_i    (gate_i),
      .s_q    (gate_q),
      .s_last (gate_last),

      // Z4.4: metadato en banda. `timing_trig_count` sale del MISMO contador
      // que TRIG_COUNT expone por AXI-Lite (no una copia: un segundo contador
      // podria divergir del primero y no habria forma de saber cual miente).
      // `timing_batch_sel` deja de ser una salida sin consumidor con esto.
      .meta_trig_count (timing_trig_count),
      .meta_bin_count  (16'(timing_bins)),
      .meta_batch_high (timing_batch_sel),
      .meta_mode_coarse(mode_coarse),

      .m_valid(m_ray_valid),
      .m_ready(m_ray_ready),
      .m_data (m_ray_data),
      .m_last (m_ray_last)
  );

endmodule : drx_top

`endif  // DRX_TOP_SV
