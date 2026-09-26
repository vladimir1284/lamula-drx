// L1 — `drx_ddc_quad_top` (N_CH=3, configs A/B de ZedBoard) seguido de
// `drx_range_gate_quad_top`: cierra la parte de ZM1 que `tb_l1_ddc_tri.sv`
// deja fuera — coincidencia bit a bit *por rayo*, con `m_last` en la muestra
// correcta, no solo la coincidencia de la muestra decimada suelta.
//
// Réplica deliberada de `tb_l1_ddc_tri.sv` en vez de una modificación de ese
// fichero: mismo argumento que llevó a `drx_range_gate_quad_top.sv` a ser un
// fichero nuevo en vez de tocar `drx_ddc_quad_top.sv` — el gating es una
// etapa aguas abajo, no una variación del cierre ya verificado del DDC.
//
// Los valores I/Q que produce `drx_range_gate` son exactamente los mismos que
// produce `drx_ddc_top` — el gating reordena en el tiempo, no toca ni un bit
// del dato —, así que reutiliza los MISMOS ficheros `.hex` del modelo dorado
// que ya genera `tools/gen_l1_vectors.py` para `tb_l1_ddc_tri.sv`: no hace
// falta un generador de vectores nuevo. Lo que sí es nuevo es el criterio de
// `m_last`, que no necesita fichero de oráculo.
//
// `BINS_MAX` de `drx_range_gate_quad_top` va a `L1TestBinsFine` (pequeño), NO
// a `BINS_MODE_FINE` (3689) — hallazgo de la primera corrida real de este
// fichero: con el rayo a profundidad real, el ping-pong no entrega NADA hasta
// llenar el primer banco entero, y estos manifiestos (heredados de
// `tb_l1_ddc_tri.sv`, que compara muestra a muestra suelta) solo traen 315/157
// muestras decimadas — muy por debajo de 3689. El comparador se habría
// quedado en `checked=0` para siempre, sin llegar nunca a `done`, y el único
// límite real habría sido `TimeoutCycles` de más abajo: a la velocidad medida
// de xsim con esta IP real (~15 ciclos/s en esta máquina, medida contra el
// propio `tb_l1_ddc_tri.sv`), eso son >70 horas, no un cuelgue. La cuenta bit
// a bit de `drx_range_gate` a la profundidad REAL (3689) ya está demostrada,
// exhaustiva y rápida, en `sim/tb/tb_drx_range_gate.py` sobre Verilator (L0)
// — este fichero, en xsim, demuestra otra cosa: que la IP real de Xilinx, no
// un generador sintético, alimenta correctamente el framing y el `m_last` cae
// donde toca, con varios rayos completos dentro de los mismos manifiestos ya
// existentes.
//
// D-15 (25-sep-2026): `drx_range_gate_quad_top` ya no toma `mode_coarse` --
// toma `bin_count` (registro). Este testbench no tiene motor de timing de Z2
// (solo DDC + gating), así que sigue derivando `bin_count` del mismo
// `+mode=` plusarg de siempre (`L1TestBinsFine`/`L1TestBinsCoarse`), calculado
// localmente en vez de recibir el registro real -- ver `gate_bins` más abajo.
// `mode_coarse` sigue existiendo para `drx_ddc_quad_top` (decimación), que sí
// lo necesita.
//
// `m_ready` va fijo a 1 en las tres salidas: el backpressure real y el
// disparo de `overrun` ya los cubre `sim/tb/tb_drx_range_gate.py` en L0, con
// rayos cortos para poder barrer casos deprisa.
//
// Plusargs: idénticos a `tb_l1_ddc_tri.sv` — este testbench no añade ninguno,
// solo consume los mismos `+stimulus_path_N=` / `+expected_*_N=` / `+mode=`.

`ifndef TB_L1_DDC_RANGE_TRI_SV
`define TB_L1_DDC_RANGE_TRI_SV

module tb_l1_ddc_range_tri;

  import drx_params_pkg::*;

  localparam int N_CH = 3;

  // Profundidad de rayo para ESTE testbench, no la real — ver el hallazgo de
  // arriba. 32/16 caben varias veces en los 315/157 muestras que traen los
  // manifiestos de fine/coarse (9 rayos completos + resto, en los dos casos),
  // así que se ejercitan de sobra el ping-pong y varios `m_last` sin
  // necesitar vectores nuevos. El resto (27/13 muestras) se queda escrito en
  // el banco para siempre sin completar un rayo más — `tcl/sim_l1_range_tri.tcl`
  // trunca `+expected_count_N=` a un múltiplo exacto de estos mismos números
  // por esa razón. Si cambian aquí, cambian también allí.
  localparam int L1TestBinsFine = 32;
  localparam int L1TestBinsCoarse = 16;

  localparam longint ClkHalfPeriodPs = 64'd1_000_000_000_000 / (2 * FS_HZ);

  logic clk = 1'b0;
  logic rst_n = 1'b0;

  /* verilator lint_off BLKSEQ */
  always #(ClkHalfPeriodPs) clk = ~clk;
  /* verilator lint_on BLKSEQ */

  // --- estímulo, uno por canal ----------------------------------------------
  logic                          stim_valid[N_CH];
  logic                          stim_ready[N_CH];
  logic                          stim_last [N_CH];
  logic                          stim_done [N_CH];
  logic signed [SAMPLE_BITS-1:0] stim_data [N_CH];

  genvar gs;
  generate
    for (gs = 0; gs < N_CH; gs = gs + 1) begin : g_stimulus
      drx_l1_file_source #(
          .WIDTH(SAMPLE_BITS),
          .KIND ("stimulus"),
          .CH   (gs)
      ) u_stimulus (
          .clk  (clk),
          .rst_n(rst_n),
          .ready(stim_ready[gs]),
          .valid(stim_valid[gs]),
          .data (stim_data[gs]),
          .last (stim_last[gs]),
          .done (stim_done[gs])
      );
    end
  endgenerate

  // --- DUT: drx_ddc_quad_top (N_CH=3) -> drx_range_gate_quad_top (N_CH=3) --
  logic                      ddc_valid[N_CH];
  logic signed [IQ_BITS-1:0] ddc_i    [N_CH];
  logic signed [IQ_BITS-1:0] ddc_q    [N_CH];

  logic                      gate_valid[N_CH];
  logic                      gate_ready[N_CH];
  logic signed [IQ_BITS-1:0] gate_i    [N_CH];
  logic signed [IQ_BITS-1:0] gate_q    [N_CH];
  logic                      gate_last [N_CH];
  logic                      gate_clear[N_CH];
  logic                      gate_overrun[N_CH];

  logic mode_coarse;

  int mode_arg;
  initial begin
    if (!$value$plusargs("mode=%d", mode_arg)) mode_arg = 0;
    mode_coarse = (mode_arg != 0);
  end

  // D-15: `bin_count` de `drx_range_gate_quad_top` ya no es `mode_coarse` --
  // este testbench no tiene motor de timing de Z2 que lo alimente en runtime,
  // así que lo deriva del mismo `+mode=` de siempre (ver la cabecera).
  logic [31:0] gate_bins;
  assign gate_bins = mode_coarse ? 32'(L1TestBinsCoarse) : 32'(L1TestBinsFine);

  genvar gr;
  generate
    for (gr = 0; gr < N_CH; gr = gr + 1) begin : g_ready
      // Backpressure real ya la cubre L0 (tb_drx_range_gate.py); aquí el
      // lector nunca frena, igual que el resto de la cadena L1.
      assign gate_ready[gr] = 1'b1;
      // Puerto `clear` (mapa de registros AXI-Lite) nuevo en `drx_range_gate`:
      // el disparo de `overrun` y su limpieza ya los cubre
      // `sim/tb/tb_drx_range_gate.py`/`sim/tb/tb_drx_axil_regs.py` en L0; aquí
      // se ata a 0, igual que el resto de la cadena L1 no ejercita reset
      // parcial de status.
      assign gate_clear[gr] = 1'b0;
    end
  endgenerate

  // `ray_start` (D-14) nuevo en `drx_range_gate_quad_top`: el resync con
  // `pulse_trig` ya lo cubre `sim/tb/tb_drx_range_gate.py` en L0 (motor de
  // timing de Z2 no existe en esta cadena L1, solo DDC + gating); aquí se ata
  // a 0 a propósito -- esto es justo lo que confirma que el puerto nuevo no
  // cambia ni un bit del comportamiento ya verificado bajo D-12 (ver la
  // cabecera de `drx_range_gate.sv`).
  logic gate_ray_start;
  assign gate_ray_start = 1'b0;

`ifdef DRX_HAVE_DDC
  drx_ddc_quad_top #(
      .N_CH(N_CH)
  ) u_ddc (
      .clk (clk),
      .rst_n(rst_n),

      .s_valid(stim_valid),
      .s_ready(stim_ready),
      .s_data (stim_data),
      .s_last (stim_last),

      .mode_coarse(mode_coarse),

      .m_valid(ddc_valid),
      .m_i    (ddc_i),
      .m_q    (ddc_q)
  );

  drx_range_gate_quad_top #(
      .N_CH(N_CH),
      .BINS_MAX(L1TestBinsFine)
  ) u_gate (
      .clk (clk),
      .rst_n(rst_n),

      .s_valid(ddc_valid),
      .s_i    (ddc_i),
      .s_q    (ddc_q),

      .bin_count(gate_bins),

      .m_valid(gate_valid),
      .m_ready(gate_ready),
      .m_i    (gate_i),
      .m_q    (gate_q),
      .m_last (gate_last),

      .clear  (gate_clear),
      .overrun(gate_overrun),

      .ray_start(gate_ray_start)
  );
`else
  // Mismo razonamiento que tb_l1_ddc_tri.sv: sin DUT no hay nada que
  // comparar, y un testbench que termina en verde sin DUT es peor que uno
  // que no compila. Aborta en cuanto arranca.
  genvar gu;
  generate
    for (gu = 0; gu < N_CH; gu = gu + 1) begin : g_no_dut
      assign stim_ready[gu] = 1'b1;
      assign ddc_valid[gu]  = 1'b0;
      assign ddc_i[gu]      = '0;
      assign ddc_q[gu]      = '0;
      assign gate_valid[gu] = 1'b0;
      assign gate_i[gu]       = '0;
      assign gate_q[gu]       = '0;
      assign gate_last[gu]    = 1'b0;
      assign gate_overrun[gu] = 1'b0;

      logic unused_no_dut_ch;
      assign unused_no_dut_ch = &{1'b0, stim_valid[gu], stim_last[gu], stim_done[gu], stim_data[gu],
                                   gate_ready[gu], gate_clear[gu], ddc_valid[gu], ddc_i[gu], ddc_q[gu]};
    end
  endgenerate

  logic unused_no_dut;
  assign unused_no_dut = &{1'b0, mode_coarse, gate_ray_start, (^gate_bins)};

  initial begin
    $fatal(1, "tb_l1_ddc_range_tri: falta drx_ddc_quad_top (trabajo de Z1). Elabora con +define+DRX_HAVE_DDC cuando exista.");
  end
`endif

  // --- comparación de datos, una por canal ----------------------------------
  logic        check_done [N_CH];
  int unsigned checked    [N_CH];
  int unsigned mismatches [N_CH];

  genvar gc;
  generate
    for (gc = 0; gc < N_CH; gc = gc + 1) begin : g_checker
      drx_l1_checker #(
          .WIDTH(IQ_BITS),
          .CH   (gc),
          .TOLERANCE_LSB(5)  // D-12: techo aceptado del residuo de cuantización del NCO — TLAST, más abajo, sigue bit a bit
      ) u_checker (
          .clk       (clk),
          .rst_n     (rst_n),
          .valid     (gate_valid[gc]),
          .i_data    (gate_i[gc]),
          .q_data    (gate_q[gc]),
          .done      (check_done[gc]),
          .checked   (checked[gc]),
          .mismatches(mismatches[gc])
      );
    end
  endgenerate

  // --- comparación de TLAST, una por canal ----------------------------------
  //
  // Sin fichero de oráculo: la posición de `m_last` dentro de un rayo es
  // `gate_bins-1` muestras después del inicio -- el mismo `bin_count` que
  // recibe `u_gate` arriba, no `BINS_MODE_FINE`/`BINS_MODE_COARSE` (ver el
  // hallazgo de la cabecera) --, igual para los tres canales porque
  // `gate_bins` es compartido.
  genvar gt;
  generate
    for (gt = 0; gt < N_CH; gt = gt + 1) begin : g_tlast
      int unsigned ray_pos;
      int unsigned last_mismatches;
      int unsigned last_checked;

      logic expected_last;
      assign expected_last = (ray_pos == unsigned'(gate_bins - 32'd1));

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          ray_pos         <= '0;
          last_mismatches <= 0;
          last_checked    <= 0;
        end else if (gate_valid[gt] && gate_ready[gt]) begin
          last_checked <= last_checked + 1;
          if (gate_last[gt] != expected_last) begin
            last_mismatches <= last_mismatches + 1;
          end
          ray_pos <= gate_last[gt] ? '0 : ray_pos + 1'b1;
        end
      end
    end
  endgenerate

  logic all_channels_done;
  always_comb begin
    all_channels_done = 1'b1;
    for (int c = 0; c < N_CH; c++) all_channels_done &= check_done[c];
  end

  // Latido de progreso: sin esto, un run largo de verdad y un run colgado se
  // ven idénticos desde fuera hasta que uno de los dos termina. No forma
  // parte del criterio de paso/fallo.
  localparam longint HeartbeatCycles = 200_000;  // clock-const-ok: ciclos, no frecuencia
  longint unsigned heartbeat_count;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      heartbeat_count <= 0;
    end else begin
      heartbeat_count <= heartbeat_count + 1;
      if (heartbeat_count % longint'(HeartbeatCycles) == 0) begin
        $display("L1 range-tri: latido en ciclo %0d, checked=%0d/%0d/%0d", heartbeat_count,
                  checked[0], checked[1], checked[2]);
      end
    end
  end

  // --- secuencia -------------------------------------------------------------
  initial begin
    repeat (8) @(posedge clk);
    rst_n = 1'b1;

    wait (all_channels_done);
    repeat (4) @(posedge clk);

    // TLAST se comprueba ANTES que el dato, a propósito: `g_tlast[*]` corre en
    // un `always_ff` continuo desde el reset, no como parte de esta secuencia,
    // así que para cuando llegamos aquí los tres canales YA tienen su cuenta
    // completa de `last_mismatches`/`last_checked` — es independiente de si
    // el dato de algún canal coincide o no con el modelo dorado. Poner esta
    // comprobación después de la de dato (como estaba antes) significa que un
    // residuo de dato ya aceptado (P-10/P-12: ±2-3 LSB, visto en más de un
    // caso — no solo en `tono_if`, ver hallazgo del 10-sep-2026) hace `$fatal`
    // primero y esconde para siempre si TLAST estaba bien o mal, aunque el
    // dato ya estuviera comprobado. Con TLAST primero, ese resultado queda en
    // el log pase lo que pase con el dato.
    if (g_tlast[0].last_mismatches != 0 || g_tlast[1].last_mismatches != 0
        || g_tlast[2].last_mismatches != 0) begin
      $fatal(1, "L1 range-tri: TLAST mal colocado — canal 0: %0d, canal 1: %0d, canal 2: %0d (de %0d/%0d/%0d muestras)",
             g_tlast[0].last_mismatches, g_tlast[1].last_mismatches, g_tlast[2].last_mismatches,
             g_tlast[0].last_checked, g_tlast[1].last_checked, g_tlast[2].last_checked);
    end
    $display("L1 range-tri: TLAST coincide bit a bit en los tres canales (%0d/%0d/%0d muestras)",
              g_tlast[0].last_checked, g_tlast[1].last_checked, g_tlast[2].last_checked);

    for (int c = 0; c < N_CH; c++) begin
      if (gate_overrun[c]) begin
        $fatal(1, "L1 range-tri: canal %0d, overrun del ping-pong con el lector siempre listo: bug de framing",
               c);
      end
    end

    for (int c = 0; c < N_CH; c++) begin
      if (mismatches[c] != 0) begin
        $fatal(1, "L1 range-tri: canal %0d, %0d discrepancias de dato de %0d muestras contra el modelo dorado (fuera de la tolerancia de D-12)",
               c, mismatches[c], checked[c]);
      end
    end

    for (int c = 0; c < N_CH; c++) begin
      $display("L1 range-tri: canal %0d, %0d muestras dentro de tolerancia (D-12) y TLAST bit a bit con el modelo dorado", c,
                checked[c]);
    end
    $finish;
  end

  // Red de seguridad, igual que tb_l1_ddc_tri.sv.
  localparam longint TimeoutCycles = 4_000_000;  // clock-const-ok: ciclos, no frecuencia

  initial begin
    #(TimeoutCycles * 2 * ClkHalfPeriodPs);
    $fatal(1, "L1 range-tri: timeout");
  end

endmodule : tb_l1_ddc_range_tri

`endif  // TB_L1_DDC_RANGE_TRI_SV
