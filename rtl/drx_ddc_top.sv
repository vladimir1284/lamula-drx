// Cadena DDC de UN canal — Z1, hito ZM1. Interfaz exacta con la que ya
// instancia `sim/tb_sv/tb_l1_ddc.sv` (ese fichero no se toca: su guardia
// `` `ifdef DRX_HAVE_DDC `` la activa `tcl/sim_l1.tcl` en cuanto detecta este
// fichero en `rtl/filelist.f`).
//
// Xilinx-IP-first (D-06): NCO, CIC y FIR salen de DDS/CIC/FIR Compiler; el
// HDL propio es solo el mezclador (`drx_ddc_mixer`), el recorte de ganancia
// (`drx_round`/`drx_saturate`) y el pegamento de este fichero. Los cuatro
// cores de Xilinx se piden a PRECISIÓN COMPLETA (sin redondeo ni saturación
// interna) para que el único redondeo de toda la cadena sea `drx_round`/
// `drx_saturate` — concentra en un sitio auditable el riesgo de discrepancia
// bit a bit contra `model/drx_model/chain.py`, en vez de esparcirlo en modos
// de redondeo de IP que no se pueden confirmar sin Vivado.
//
// Los anchos de cada corte (`CIC_GROWTH_BITS`, `FIR_GROWTH_BITS`,
// `HALFBAND_GROWTH_BITS`, `*_COEFF_BITS`) los genera `tools/gen_params.py`
// corriendo el propio modelo dorado — no hay un número de este fichero que no
// venga de `drx_params_pkg`.
//
// `mode_coarse` es una entrada de tiempo de ejecución, pero en esta pasada se
// trata como estática durante una corrida (igual que `tb_l1_ddc.sv`, que la
// fija una vez por simulación vía `+mode`): la rama fina (droop) y la gruesa
// (droop + semibanda ÷2) corren las dos siempre, y un mux combinacional
// selecciona cuál sale por `m_i`/`m_q`. La conmutación limpia en caliente
// entre modos (continuidad de fase, sin artefactos en el rayo de transición)
// es del plan de pruebas de Z1 y no se ataca aquí.
//
// `s_last` no se conecta a nada todavía: el framing de rayos (TLAST de salida,
// range gating) es trabajo de Z1 posterior a este núcleo, y ningún puerto de
// este módulo lo necesita hoy.
//
// Los nombres de puerto de cada core (`aclk`/`aresetn`, `s_axis_data_*`,
// `m_axis_data_*`) y el empaquetado de `M_AXIS_DATA_TDATA` del DDS Compiler
// ({coseno, seno}, coseno en la mitad alta) están confirmados contra la
// plantilla de instanciación real que genera `tcl/gen_ip.tcl` sobre Vivado
// 2022.2 — no son una suposición de la documentación. Lo que SÍ hay que tener
// presente: el ancho de `M_AXIS_DATA_TDATA` de CIC/FIR/semibanda que produce
// la IP real no sale de una fórmula de taps/coeficientes — depende de si el
// core detecta la estructura de coeficientes como simétrica y de a qué
// múltiplo de 8 bits redondea el bus — así que este fichero los importa de
// `rtl/generated/drx_ddc_ip_pkg.sv`, que también genera `tcl/gen_ip.tcl` a
// partir de la IP ya generada, en vez de recalcularlos aquí.

`ifndef DRX_DDC_TOP_SV
`define DRX_DDC_TOP_SV

module drx_ddc_top
  import drx_params_pkg::*;
  import drx_ddc_ip_pkg::*;
(
    input logic clk,
    input logic rst_n,

    input  logic                          s_valid,
    output logic                          s_ready,
    input  logic signed [SAMPLE_BITS-1:0] s_data,
    input  logic                          s_last,

    input logic mode_coarse,

    output logic                       m_valid,
    output logic signed [IQ_BITS-1:0] m_i,
    output logic signed [IQ_BITS-1:0] m_q
);

  // s_last no tiene consumidor todavía (ver aviso arriba); se silencia en vez
  // de dejarlo colgado.
  logic unused_s_last;
  assign unused_s_last = &{1'b0, s_last};

  // ---------------------------------------------------------------------
  // HALLAZGO, primera ejecución real contra IP de verdad: el reset de 8
  // ciclos que da `tb_l1_ddc.sv` (fijo, y ese fichero no se toca — ver aviso
  // de cabecera) deja el CIC Compiler con `s_axis_data_tready` en 0 para
  // siempre: se comprobó en simulación que sigue en 0 más de 4000 ciclos
  // después de soltar `rst_n`, con `s_axis_data_tvalid` en 0 todo ese tiempo
  // (no es cuestión de que nadie más lo pida: el core simplemente no llega a
  // «listo»). Con N=5 etapas y R=52, el recorrido interno del CIC son del
  // orden de cientos de ciclos, y 8 no alcanza para que el core complete su
  // propia inicialización. Se alarga el reset EN ESTE MÓDULO antes de
  // dárselo a la IP — un estirador de reset es el patrón estándar para
  // acoplar un reset corto de sistema a IP con pipelines profundos, y no
  // afecta al resto de `drx_ddc_top` (el mezclador y `drx_round`/
  // `drx_saturate` siguen viendo `rst_n` tal cual).
  localparam int IpResetCycles = 512;
  localparam int IpResetCntW = $clog2(IpResetCycles + 1);

  logic [IpResetCntW-1:0] ip_reset_count;
  logic                   ip_rst_n;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ip_reset_count <= '0;
      ip_rst_n       <= 1'b0;
    end else if (ip_reset_count < IpResetCntW'(IpResetCycles)) begin
      ip_reset_count <= ip_reset_count + 1'b1;
      ip_rst_n       <= 1'b0;
    end else begin
      ip_rst_n <= 1'b1;
    end
  end

  // ---------------------------------------------------------------------
  // NCO: DDS Compiler en modo generador de fase libre (incremento fijo,
  // NCO_PHASE_INC, congelado en la personalización de la IP; sin
  // S_AXIS_PHASE ni S_AXIS_CONFIG — el retune en caliente de AFC es Z4).
  // M_AXIS_DATA_TDATA empaqueta {coseno, seno}, cada uno a NCO_OUT_BITS,
  // coseno en la mitad alta — confirmar contra la plantilla real.
  //
  // Sin `m_axis_data_tready`: la IP se genera con `Has_TREADY {false}` (ver
  // el hallazgo en `tcl/gen_ip.tcl`) precisamente porque `drx_ddc_mixer`
  // nunca contrapresura al NCO, y pedir TREADY solo compraba una FIFO
  // interna de latencia no determinista (pg141, "Latency Options") — la
  // causa real de que la primera muestra tras reset no fuera fase 0. Sin
  // esa FIFO el core tiene latencia fija y `nco_ready` (salida de
  // `drx_ddc_mixer`, atada a 1'b1) no tiene con qué conectarse aquí.
  // ---------------------------------------------------------------------
  logic                          nco_valid, nco_ready;
  logic        [DDS_TDATA_BITS-1:0] nco_data;
  logic signed [    NCO_OUT_BITS-1:0] nco_cos, nco_sin;

  logic unused_nco_ready;
  assign unused_nco_ready = &{1'b0, nco_ready};

  assign nco_cos = nco_data[2*NCO_OUT_BITS-1:NCO_OUT_BITS];
  assign nco_sin = nco_data[NCO_OUT_BITS-1:0];

  dds_compiler_nco u_nco (
      .aclk   (clk),
      .aresetn(ip_rst_n),

      .m_axis_data_tvalid(nco_valid),
      .m_axis_data_tdata (nco_data)
  );

  // ---------------------------------------------------------------------
  // Mezclador complejo (custom, D-06) — alinea muestra y fase sin asumir la
  // latencia del DDS Compiler; ver el encabezado de drx_ddc_mixer.sv.
  // ---------------------------------------------------------------------
  logic                          mix_valid, mix_ready;
  logic signed [SAMPLE_BITS-1:0] mix_i, mix_q;

  drx_ddc_mixer #(
      .SAMPLE_BITS (SAMPLE_BITS),
      .NCO_OUT_BITS(NCO_OUT_BITS)
  ) u_mixer (
      .clk (clk),
      .rst_n(rst_n),

      .s_valid(s_valid),
      .s_ready(s_ready),
      .s_data (s_data),

      .nco_valid(nco_valid),
      .nco_ready(nco_ready),
      .nco_cos  (nco_cos),
      .nco_sin  (nco_sin),

      .m_valid(mix_valid),
      .m_ready(mix_ready),
      .m_i    (mix_i),
      .m_q    (mix_q)
  );

  // ---------------------------------------------------------------------
  // Anchos de SALIDA de cada `drx_round` (cuánto necesita el valor YA
  // recortado, no lo que produce la IP): son una cota segura calculada con
  // la misma fórmula de crecimiento de taps/coeficientes que usa
  // `model/drx_model/fixed.growth_bits`, y sirven para dimensionar los
  // registros propios de este fichero — no para conectar puertos de IP, eso
  // usa `drx_ddc_ip_pkg` (ver el aviso de cabecera). Como el crecimiento real
  // de un core con estructura simétrica (la semibanda lo es) es igual o
  // menor que esta cota no simétrica, dimensionar con ella nunca trunca.
  // 23: número de taps de la semibanda (config/coeffs/halfband_decim2.txt).
  // No sale de drx_params_pkg porque nada más lo necesita todavía; si eso
  // cambia, es candidato a HALFBAND_TAPS generado junto a FIR_TAPS.
  localparam int HalfbandTaps = 23;

  localparam int FirProdBits = SAMPLE_BITS + FIR_COEFF_BITS;
  localparam int FirFullBits = FirProdBits + $clog2(FIR_TAPS);
  localparam int FirOutBits = FirFullBits - FIR_GROWTH_BITS;

  localparam int HbProdBits = FirOutBits + HALFBAND_COEFF_BITS;
  localparam int HbFullBits = HbProdBits + $clog2(HalfbandTaps);
  localparam int HbOutBits = HbFullBits - HALFBAND_GROWTH_BITS;

  localparam int FinalW = (HbOutBits > FirOutBits) ? HbOutBits : FirOutBits;

  genvar gi;
  generate
    for (gi = 0; gi < 2; gi = gi + 1) begin : g_branch
      // gi==0 -> I, gi==1 -> Q. Las dos ramas son idénticas: CIC -> round ->
      // FIR droop -> round -> (si coarse) semibanda -> round -> mux final.

      logic signed [SAMPLE_BITS-1:0] mix_out;
      assign mix_out = (gi == 0) ? mix_i : mix_q;

      // Entrada del CIC a su ancho real (CIC_IN_BITS): en esta configuración
      // coincide con SAMPLE_BITS (16, ya múltiplo de 8, sin relleno), pero se
      // ensancha de forma explícita y con signo en vez de confiar en la
      // extensión implícita de una conexión de puerto con ancho distinto.
      logic signed [CIC_IN_BITS-1:0] mix_out_wide;
      assign mix_out_wide = CIC_IN_BITS'(mix_out);

      // --- CIC Compiler, precisión completa -----------------------------
      // `m_axis_data_tready` de CIC/FIR/semibanda va atado a 1'b1: cada etapa
      // decima al menos ×4 lo que entrega la anterior (CIC ÷52, FIR ÷4,
      // semibanda ÷2), así que aguas abajo siempre hay margen de sobra para
      // aceptar antes de que la etapa siguiente vuelva a producir. La interfaz
      // externa de este módulo tampoco tiene `m_ready` (el testbench no lo
      // necesita), así que en el extremo final no hay contra quién
      // backpressurear de todas formas.
      logic                          cic_valid, cic_ready;
      logic signed [CIC_TDATA_BITS-1:0] cic_data;

      cic_compiler_ddc u_cic (
          .aclk   (clk),
          .aresetn(ip_rst_n),

          .s_axis_data_tvalid(mix_valid),
          .s_axis_data_tready(cic_ready),
          .s_axis_data_tdata (mix_out_wide),

          .m_axis_data_tvalid(cic_valid),
          .m_axis_data_tready(1'b1),
          .m_axis_data_tdata (cic_data)
      );

      // `cic_data` es más ancho (CIC_TDATA_BITS) que la precisión real
      // (CIC_REGISTER_BITS, Hogenauer): la IP rellena las MSB de más con
      // extensión de signo (comportamiento estándar y documentado de estos
      // cores AXI4-Stream de Xilinx), así que desplazar con signo sobre el
      // ancho real completo da el mismo valor que hacerlo sobre los
      // CIC_REGISTER_BITS bits significativos — no hace falta recortar antes.
      logic signed [SAMPLE_BITS-1:0] cic_rounded;
      drx_round #(
          .IN_W (CIC_TDATA_BITS),
          .SHIFT(CIC_GROWTH_BITS),
          .OUT_W(SAMPLE_BITS)
      ) u_round_cic (
          .in_data (cic_data),
          .out_data(cic_rounded)
      );

      logic signed [FIR_DROOP_IN_BITS-1:0] cic_rounded_wide;
      assign cic_rounded_wide = FIR_DROOP_IN_BITS'(cic_rounded);

      // --- FIR Compiler, droop + ÷4, precisión completa -----------------
      logic                                 fir_valid, fir_ready;
      logic signed [FIR_DROOP_TDATA_BITS-1:0] fir_data;

      fir_compiler_droop u_fir (
          .aclk   (clk),
          .aresetn(ip_rst_n),

          .s_axis_data_tvalid(cic_valid),
          .s_axis_data_tready(fir_ready),
          .s_axis_data_tdata (cic_rounded_wide),

          .m_axis_data_tvalid(fir_valid),
          .m_axis_data_tready(1'b1),
          .m_axis_data_tdata (fir_data)
      );

      logic signed [FirOutBits-1:0] fir_rounded;
      drx_round #(
          .IN_W (FIR_DROOP_TDATA_BITS),
          .SHIFT(FIR_GROWTH_BITS),
          .OUT_W(FirOutBits)
      ) u_round_fir (
          .in_data (fir_data),
          .out_data(fir_rounded)
      );

      logic signed [FIR_HALFBAND_IN_BITS-1:0] fir_rounded_wide;
      assign fir_rounded_wide = FIR_HALFBAND_IN_BITS'(fir_rounded);

      // --- FIR Compiler, semibanda ÷2 (solo aporta en modo grueso) ------
      logic                                     hb_valid, hb_ready;
      logic signed [FIR_HALFBAND_TDATA_BITS-1:0] hb_data;

      fir_compiler_halfband u_halfband (
          .aclk   (clk),
          .aresetn(ip_rst_n),

          .s_axis_data_tvalid(fir_valid),
          .s_axis_data_tready(hb_ready),
          .s_axis_data_tdata (fir_rounded_wide),

          .m_axis_data_tvalid(hb_valid),
          .m_axis_data_tready(1'b1),
          .m_axis_data_tdata (hb_data)
      );

      logic signed [HbOutBits-1:0] hb_rounded;
      drx_round #(
          .IN_W (FIR_HALFBAND_TDATA_BITS),
          .SHIFT(HALFBAND_GROWTH_BITS),
          .OUT_W(HbOutBits)
      ) u_round_hb (
          .in_data (hb_data),
          .out_data(hb_rounded)
      );

      // --- mux fino/grueso + saturación final a IQ_BITS -----------------
      logic branch_valid;
      logic signed [FinalW-1:0] branch_wide;

      assign branch_valid = mode_coarse ? hb_valid : fir_valid;
      assign branch_wide  = mode_coarse ? FinalW'(hb_rounded) : FinalW'(fir_rounded);

      logic signed [IQ_BITS-1:0] branch_sat;
      logic                      branch_overflow;

      drx_saturate #(
          .IN_W (FinalW),
          .OUT_W(IQ_BITS)
      ) u_saturate (
          .in_data (branch_wide),
          .out_data(branch_sat),
          .overflow(branch_overflow)
      );

      // reservado para status/BITE (ver drx_saturate.sv); sin consumidor hoy.
      // fir_ready/hb_ready se capturan por si acaso (visibilidad en forma de
      // onda / debug) pero no se usan para backpressurear, por la razón de
      // margen de tasa de la nota de arriba.
      logic unused_overflow;
      assign unused_overflow = &{1'b0, branch_overflow, fir_ready, hb_ready};

      if (gi == 0) begin : g_out_i
        assign m_i    = branch_sat;
        assign m_valid = branch_valid;
      end else begin : g_out_q
        assign m_q = branch_sat;
      end
    end
  endgenerate

  // El mezclador solo avanza cuando el CIC de las DOS ramas (I y Q) puede
  // aceptar muestra nueva. Las dos ramas son idénticas y deberían responder
  // el mismo ciclo, pero se comprueban las dos en vez de asumirlo.
  assign mix_ready = g_branch[0].cic_ready && g_branch[1].cic_ready;

endmodule : drx_ddc_top

`endif  // DRX_DDC_TOP_SV
