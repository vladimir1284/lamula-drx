// Sonda de depuración de la cadena de muestras — instrumento de P-21.
//
// P-21 (3-oct-2026): encadenando `test_stimulus_select` el canal MM2S se
// atasca. La mitad de la causa ya está corregida en firmware (pausar el DMA
// antes de drenarlo fugaba los descriptores de la pasada en vuelo, ver
// `fw/src/app/drx_stimulus.c`); la otra mitad es que, con eso arreglado, la
// pasada SIGUE sin completar en 50 ms cuando el DDC la consume en ~0,3 ms. O
// sea que la cadena se para de verdad entre el MM2S y el DDC, y nada de lo
// que hay hoy dice DÓNDE: los registros de estado del AXI DMA leídos por JTAG
// no son fiables (`xsct` para el Cortex-A9 en cada `mrd`, ver
// `docs/implementacion/fases.md`) y el mapa AXI-Lite no expone un solo
// handshake de la cadena.
//
// Este módulo existe para que un ILA pueda contestar esa pregunta en una sola
// captura. Dos responsabilidades, las dos deliberadamente fuera del camino de
// datos:
//
//   1. Empaquetar en un bus único todos los handshakes de la cadena, desde el
//      beat que entra por el MM2S hasta el rayo que sale hacia el S2MM. El
//      orden de los bits lo fija `drx_debug_pkg`, y es la ÚNICA definición:
//      `rtl/drx_zynq_top.sv` lo trocea en probes del ILA por esos mismos
//      nombres, no por números mágicos repetidos.
//
//   2. Contar ciclos desde el último avance de muestra y levantar `stalled`
//      cuando pasan de 2**STALL_LOG2. Esto es lo que hace útil la captura: el
//      atasco se detecta milisegundos DESPUÉS de empezar (16,78 ms con el
//      umbral de hoy), y a 62,5 MHz la ventana de un ILA de 4096 muestras son
//      65 µs. Sin un
//      disparo propio habría que acertar el instante a ciegas; con él, el ILA
//      dispara con `stalled` y, calificando el almacenamiento por actividad,
//      el buffer guarda los últimos ciclos en que algo se movió — que es
//      exactamente la evidencia que falta.
//
// El contador solo cuenta mientras tenga sentido preguntarse por un atasco, y
// esa condición NO es simplemente "modo Throttled(DDR)". Es
// `ddr_mode || s_vec_valid`, y el segundo término es imprescindible:
//
//   - En BRAM-loop sin DMA, la fuente entrega una muestra por ciclo y un hueco
//     largo no significa nada; `ddr_mode` y `s_vec_valid` están los dos en
//     bajo y el contador queda quieto. Correcto.
//   - Pero el atasco que se persigue puede dejar `ddr_mode` en BAJO con un
//     descriptor del MM2S todavía en vuelo: `DrxStimulus_Stop()` termina con
//     `set_modo_ddr(false)`, así que si el drenado salió antes de tiempo el
//     DMA se queda ofreciendo un beat (`s_vec_valid = 1`) que
//     `vector_source` ya no puede aceptar (`s_axis_ready = ddr_mode && …`).
//     Con el contador atado solo a `ddr_mode`, ESE caso —el más probable, ver
//     la hipótesis de P-21— desarmaría la sonda justo al entrar en el estado
//     que hay que capturar, y el ILA no dispararía nunca.
//
// Un `s_vec_valid` alto durante 67 ms seguidos ya es, por sí solo, un fallo:
// nadie ofrece un beat tanto tiempo si la cadena funciona.
//
// Umbral: `DrxStimulusTask` sondea cada DRX_STIMULUS_POLL_MS = 10 ms, así que
// entre dos pasadas hay huecos legítimos de ese orden. 2**22 ciclos a 62,5 MHz
// son 67 ms — bastante por encima del hueco normal y bastante por debajo de
// un atasco, que es permanente.
//
// NO es un BITE ni entra en el mapa de registros: es un instrumento, vive solo
// en la build de depuración (`tcl/build.tcl -debug 1`) y con el ILA fuera el
// sintetizador se lo lleva entero salvo el propio contador, que `drx_top`
// expone por un puerto. Ver `docs/implementacion/ila.md`.
//
// Puertos empaquetados, no arrays de escalares, por el mismo límite de
// cocotb sobre Verilator que ya documenta `rtl/drx_sample_pacer.sv`: el VPI
// no sabe indexar un array sin empaquetar de señales de 1 bit.

`ifndef DRX_DEBUG_PROBE_SV
`define DRX_DEBUG_PROBE_SV

module drx_debug_probe
  import drx_debug_pkg::*;
#(
    // 2**STALL_LOG2 ciclos sin avance con `armed` en alto levantan `stalled`.
    // Parámetro y no constante para que el L0 pueda ejercitar el umbral en
    // unos pocos ciclos en vez de en un millón.
    //
    // El umbral tiene que quedar por encima del hueco legítimo más largo entre
    // dos avances de muestra, y ese hueco lo fija el sondeo del anillo del MM2S
    // en `DrxStimulusTask`. Con los 10 ms de sondeo originales hacía falta
    // 2**22 (67,1 ms a 62,5 MHz) para no disparar en cada recarga de
    // descriptores; eso tapaba cualquier atasco intermitente más corto que eso.
    // Con el sondeo a 1 ms (tick de FreeRTOS a 1 kHz, `tcl/gen_bsp.tcl`) el
    // hueco legítimo baja a ~1-2 ms y 2**20 = 16,78 ms deja 10x de margen.
    parameter int STALL_LOG2 = 20
) (
    input logic clk,
    input logic rst_n,

    // CTRL bit 1. No es por sí solo la condición de armado — ver la cabecera.
    input logic ddr_mode,

    input logic s_vec_valid,
    input logic s_vec_ready,
    input logic s_vec_last,

    input logic m_ray_valid,
    input logic m_ray_ready,
    input logic m_ray_last,

    input logic timing_enable,
    input logic timing_paced,
    input logic pulse_trig,

    input logic [DbgNCh-1:0] vs_valid,
    input logic [DbgNCh-1:0] vs_ready,
    input logic [DbgNCh-1:0] ddc_valid,
    input logic [DbgNCh-1:0] gate_valid,
    input logic [DbgNCh-1:0] gate_ready,
    input logic [DbgNCh-1:0] gate_overrun,
    input logic [DbgNCh-1:0] gate_truncated,

    output logic [DbgWidth-1:0] dbg_bus
);

  // "Un avance de muestra" con la MISMA definición que `drx_sample_pacer`:
  // el conjunto entero se retira cuando todos los canales lo toman. No se
  // reusa el `advance` del pacer a propósito — vale 1 constante cuando el
  // pacing está apagado, y entonces este contador no mediría nada.
  logic moved;
  assign moved = &(vs_valid & vs_ready);

  // Ver la cabecera: con `ddr_mode` a secas, el caso más probable de P-21
  // desarmaría la sonda al entrar en el estado que hay que capturar.
  logic armed;
  assign armed = ddr_mode || s_vec_valid;

  logic [DbgIdleBits-1:0] idle_cnt;
  logic                   stalled;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      idle_cnt <= '0;
    end else if (!armed || moved) begin
      idle_cnt <= '0;
    end else if (!(&idle_cnt)) begin
      idle_cnt <= idle_cnt + 1'b1;
    end
  end

  // Saturado en vez de envolvente: un contador que da la vuelta soltaría
  // `stalled` justo cuando el atasco lleva más tiempo.
  assign stalled = |idle_cnt[DbgIdleBits-1:STALL_LOG2];

  always_comb begin
    dbg_bus = '0;
    dbg_bus[DbgSVecValid]    = s_vec_valid;
    dbg_bus[DbgSVecReady]    = s_vec_ready;
    dbg_bus[DbgSVecLast]     = s_vec_last;
    dbg_bus[DbgMRayValid]    = m_ray_valid;
    dbg_bus[DbgMRayReady]    = m_ray_ready;
    dbg_bus[DbgMRayLast]     = m_ray_last;
    dbg_bus[DbgDdrMode]      = ddr_mode;
    dbg_bus[DbgTimingEnable] = timing_enable;
    dbg_bus[DbgTimingPaced]  = timing_paced;
    dbg_bus[DbgSampleMoved]  = moved;
    dbg_bus[DbgPulseTrig]    = pulse_trig;
    dbg_bus[DbgStalled]      = stalled;

    dbg_bus[DbgVsValid+:DbgNCh]    = vs_valid;
    dbg_bus[DbgVsReady+:DbgNCh]    = vs_ready;
    dbg_bus[DbgDdcValid+:DbgNCh]   = ddc_valid;
    dbg_bus[DbgGateValid+:DbgNCh]  = gate_valid;
    dbg_bus[DbgGateReady+:DbgNCh]  = gate_ready;
    dbg_bus[DbgOverrun+:DbgNCh]    = gate_overrun;
    dbg_bus[DbgTruncated+:DbgNCh]  = gate_truncated;

    dbg_bus[DbgIdleCnt+:DbgIdleBits] = idle_cnt;
  end

endmodule : drx_debug_probe

`endif  // DRX_DEBUG_PROBE_SV
