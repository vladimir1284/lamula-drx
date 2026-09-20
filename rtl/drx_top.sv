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
//   - **`drx_axil_regs` se instancia aquí pero sus puertos AXI-Lite NO llegan
//     a puertos de `drx_top`** (hallazgo real, 20-sep-2026, corriendo P&R por
//     primera vez con el mapa de registros integrado): el bus de 32 bits de
//     datos pide del orden de 94 pines físicos, muy por encima de los 50
//     sitios del paquete de la ZedBoard — `place_design` falló con "IO
//     placement is infeasible", el mismo límite físico que ya encontraron las
//     salidas de range-gate el 19-sep. Se atan a valores inertes (ningún
//     maestro emite transacciones nunca en esta build): exactamente la misma
//     situación que `mode_coarse` ya tenía como `localparam` fijo antes de
//     que existiera este mapa, así que el WNS medido con esto no es una
//     regresión frente al del 19-sep, es la misma medición. Lo que sí queda
//     expuesto, real: nada todavía en este repo instancia un PS7 ni un
//     interconnect AXI que pudiera ser ese maestro — hace falta uno (PS7 vía
//     AXI GP, o un puente JTAG-a-AXI) antes de que el mapa de registros sea
//     alcanzable desde firmware de verdad. Prerrequisito nuevo, no diseñado
//     aquí a propósito (AGENTS.md: no se diseña por adelantado).
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
    output logic debug_probe
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

  // Sin PS7/interconnect AXI todavía en este repo (ver la cabecera de más
  // arriba): nada dentro del chip puede manejar el maestro de este slave en
  // esta build de ZedBoard, así que sus puertos AXI-Lite NO se exponen como
  // puertos de `drx_top` — un bus de 32 bits de datos pide del orden de 94
  // pines físicos, muy por encima de los 50 sitios del paquete de la
  // ZedBoard (mismo tipo de límite que ya documentó el hallazgo de
  // range-gate del 19-sep, "IO placement is infeasible"). Atado aquí a
  // valores inertes: ningún maestro emite transacciones nunca en esta build,
  // exactamente la misma situación que ya tenía `mode_coarse` como
  // `localparam` fijo antes de que existiera este mapa de registros — no es
  // una regresión frente al WNS del 19-sep, es la misma medición. Un maestro
  // real (PS7 vía AXI GP, o un puente JTAG-a-AXI) es un prerrequisito nuevo,
  // real, para que el mapa de registros sea alcanzable desde firmware — no
  // diseñado aquí, ver `docs/implementacion/registros.md`.
  logic [REGS_ADDR_WIDTH-1:0] axi_tie_addr;
  logic [                31:0] axi_tie_wdata;
  logic axi_tie_awready, axi_tie_wready, axi_tie_arready;
  logic [1:0] axi_tie_bresp, axi_tie_rresp;
  logic axi_tie_bvalid, axi_tie_rvalid;
  logic [31:0] axi_tie_rdata;

  assign axi_tie_addr  = '0;
  assign axi_tie_wdata = '0;

  // Nada lee estas salidas (ver la nota de arriba: sin maestro real todavía).
  logic unused_axi_tie;
  assign unused_axi_tie = &{1'b0, axi_tie_awready, axi_tie_wready, axi_tie_arready,
                            axi_tie_bresp, axi_tie_rresp, axi_tie_bvalid, axi_tie_rvalid,
                            axi_tie_rdata};

  drx_axil_regs #(
      .N_CH(N_CH)
  ) u_regs (
      .clk  (clk),
      .rst_n(rst_n),

      .s_axi_awaddr (axi_tie_addr),
      .s_axi_awvalid(1'b0),
      .s_axi_awready(axi_tie_awready),
      .s_axi_wdata  (axi_tie_wdata),
      .s_axi_wstrb  (4'h0),
      .s_axi_wvalid (1'b0),
      .s_axi_wready (axi_tie_wready),
      .s_axi_bresp  (axi_tie_bresp),
      .s_axi_bvalid (axi_tie_bvalid),
      .s_axi_bready (1'b1),
      .s_axi_araddr (axi_tie_addr),
      .s_axi_arvalid(1'b0),
      .s_axi_arready(axi_tie_arready),
      .s_axi_rdata  (axi_tie_rdata),
      .s_axi_rresp  (axi_tie_rresp),
      .s_axi_rvalid (axi_tie_rvalid),
      .s_axi_rready (1'b1),

      .mode_coarse(mode_coarse),

      .overrun_in   (gate_overrun_packed),
      .overrun_clear(gate_clear_packed),

      .overflow_in(ddc_overflow_packed)
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
      .overrun(gate_overrun)
  );

  // Un solo bit, registrado, que depende de toda la cadena — ver la cabecera
  // sobre por qué hace falta llegar a un puerto real. El valor en sí no
  // significa nada (no es un BITE ni un estado utilizable): existe solo para
  // que la síntesis real no elimine la cadena que alimenta.
  logic debug_probe_xor;
  always_comb begin
    debug_probe_xor = 1'b0;
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
