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
//   - `mode_coarse` está fijo a fino (`1'b0`) por parámetro. Ponerlo en tiempo
//     de ejecución es AXI-Lite, que es la fase siguiente — diseñarlo contra un
//     top que no existía todavía habría sido adivinar.
//   - `m_ready` de range-gate va siempre a alto: no hay consumidor real (el
//     AXI DMA es Z4).
//   - Las salidas de range-gate no tienen consumidor real todavía (ni
//     AXI-Lite ni DMA/Z4), así que se reducen a un único bit `debug_probe`
//     registrado, en vez de exponerse una a una. Dos hallazgos de síntesis
//     real (19-sep-2026) llevan a esto: (1) exponerlas todas como puertos —
//     primer intento — hace fallar `place_design` ("IO placement is
//     infeasible", 105 puertos pedidos contra 50 sitios físicos disponibles
//     en el paquete de la ZedBoard); (2) `(* keep = "true" *)` sobre señales
//     internas sin ningún puerto real aguas abajo —segundo intento— no evita
//     que `opt_design` se lleve por delante la cadena entera de todas formas
//     (post-route quedó en 22 LUTs, 0 DSP, 0 BRAM: solo el latido). Lo único
//     que de verdad sobrevive a la eliminación de lógica muerta de la
//     implementación es alcanzar un puerto real — un solo bit basta, mismo
//     patrón que ya usa este árbol para "hacer real" una señal sin consumidor
//     (`unused_nco_ready` en `drx_ddc_top.sv`), llevado hasta el top. Esta
//     build se corre hasta `-step impl` (P&R con cierre de temporización real
//     de este datapath, primera vez que se mide algo distinto del diseño
//     vacío), no hasta `-step bitstream`.
//   - `s_last` de `vector_source` pulsa cada `DEPTH` muestras — marcador
//     artificial de "fin de ventana" para ejercitar el framing de
//     `drx_range_gate`, NO el PRF real (Z2 no existe todavía).

`ifndef DRX_TOP_SV
`define DRX_TOP_SV

module drx_top
  import drx_params_pkg::*;
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

  drx_heartbeat #(
      .DIV(HEARTBEAT_DIV)
  ) u_heartbeat (
      .clk  (clk),
      .rst_n(rst_n),
      .level(led_heartbeat)
  );

  // Fijo por parámetro hasta que exista AXI-Lite (ver cabecera).
  localparam logic ModeCoarse = 1'b0;

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

      .mode_coarse(ModeCoarse),

      .m_valid(ddc_valid),
      .m_i    (ddc_i),
      .m_q    (ddc_q)
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

      .mode_coarse(ModeCoarse),

      .m_valid(gate_valid),
      .m_ready(gate_ready),
      .m_i    (gate_i),
      .m_q    (gate_q),
      .m_last (gate_last),

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
