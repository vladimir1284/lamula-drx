// Réplica de `drx_ddc_top` a los N_RX_CH canales Rx — cierre de ZM1.
//
// `drx_ddc_top` es la cadena DDC completa para UN canal, ya verificada bit a
// bit contra el modelo dorado en `sim/tb_sv/tb_l1_ddc.sv`. El hito ZM1
// (docs/implementacion/fases.md) pide esa coincidencia "en los cuatro
// canales" — N_RX_CH = 4 (rtl/generated/drx_params_pkg.sv, derivado de
// config/params.toml) — así que este fichero solo replica: un `generate` con
// N_CH instancias independientes de `drx_ddc_top`, sin lógica propia.
//
// Puertos en arrays por canal, sin decodificar el stream SSA entrelazado de
// `drx_ssa_pkg.sv` (TDATA con SSA_N_CH muestras y TUSER con channel_id /
// sample_valid_mask): ese demux es responsabilidad de `vector_source` /
// `jesd204b_source`, que todavía no existen. Este módulo asume que ya llegó
// una muestra por canal, demultiplexada, y solo replica la cadena DDC.
//
// SIN resource-sharing entre canales: cada canal instancia su propio juego
// completo de IP de Xilinx (DDS/CIC/FIR/semibanda), igual que `drx_ddc_top`
// ya hace hoy entre sus dos ramas I/Q. Esto es DISTINTO del supuesto de
// `docs/plataforma/recursos.md` ("FIR compensador + final, time-shared, 8
// streams, 10 DSP48 en vez de uno por stream) — ese time-sharing es una
// optimización de recursos para más adelante, no un requisito de ZM1: el
// propio `recursos.md` ya concluye "cabe con holgura", con margen para 8
// canales incluso sin compartir. La cifra real de DSP48/LUT/BRAM de esta
// réplica sin compartir se mide con `report_utilization` sobre una build de
// 4 canales y sustituye la tabla estimada — no se asume aquí.
//
// `mode_coarse` es una sola entrada compartida por los N_CH canales, igual
// que en `drx_ddc_top` es "estática durante una corrida": todos los canales
// procesan el mismo IF y necesitan el mismo modo fino/grueso en un instante
// dado, así que no hay razón para que difiera por canal.
//
// N_CH=3, 9-sep-2026 (P-12): este mismo módulo, sin cambio de código, es el
// top-level de las dos configuraciones de 3 canales de ZedBoard — Config A
// (Tx+H+V) y Config B (Tx+nominal+atenuado), ver docs/alcance/pendientes.md
// #p-12 y docs/implementacion/fases.md#z1 — instanciándolo con N_CH=3 en vez
// de N_RX_CH. Es "el mismo con generics", no un top-level nuevo: el
// `generate` de arriba no distingue Rx de Tx ni asume N_CH=4, y la muestra
// de Tx está confirmada con el mismo ancho/framing (`SAMPLE_BITS`, `s_last`)
// que un canal Rx, así que sus tres entradas son intercambiables a este
// nivel. El testbench de L1 para N_CH=3 es `sim/tb_sv/tb_l1_ddc_tri.sv`
// (`tcl/sim_l1_tri.tcl`), réplica de `tb_l1_ddc_quad.sv` para esta
// instanciación — no se toca este fichero ni `tb_l1_ddc_quad.sv`, que sigue
// siendo el camino de N_RX_CH canales homogéneos para la ZU9.

`ifndef DRX_DDC_QUAD_TOP_SV
`define DRX_DDC_QUAD_TOP_SV

module drx_ddc_quad_top
  import drx_params_pkg::*;
#(
    parameter int N_CH = N_RX_CH
) (
    input logic clk,
    input logic rst_n,

    input  logic                          s_valid[N_CH],
    output logic                          s_ready[N_CH],
    input  logic signed [SAMPLE_BITS-1:0] s_data [N_CH],
    input  logic                          s_last [N_CH],

    input logic mode_coarse,

    output logic                      m_valid[N_CH],
    output logic signed [IQ_BITS-1:0] m_i    [N_CH],
    output logic signed [IQ_BITS-1:0] m_q    [N_CH]
);

  genvar gc;
  generate
    for (gc = 0; gc < N_CH; gc = gc + 1) begin : g_ch
      drx_ddc_top u_ddc (
          .clk (clk),
          .rst_n(rst_n),

          .s_valid(s_valid[gc]),
          .s_ready(s_ready[gc]),
          .s_data (s_data[gc]),
          .s_last (s_last[gc]),

          .mode_coarse(mode_coarse),

          .m_valid(m_valid[gc]),
          .m_i    (m_i[gc]),
          .m_q    (m_q[gc])
      );
    end
  endgenerate

endmodule : drx_ddc_quad_top

`endif  // DRX_DDC_QUAD_TOP_SV
