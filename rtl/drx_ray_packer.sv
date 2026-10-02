// Empaquetador de rayo — Z4.0 (fases.md#z4): primer consumidor real de las
// N_CH salidas de `drx_range_gate_quad_top`. Hasta ahora (Z1-Z2) esas
// salidas no tenían destino físico (`gate_ready` atado a 1, I/Q plegados en
// `debug_probe_xor` solo para que la síntesis no se llevara la cadena por
// delante — ver la cabecera vieja de `drx_top.sv`); este módulo es ese
// destino: entrelaza los N_CH canales en un único AXI4-Stream que
// `drx_zynq_top`/`tcl/gen_zynq_bd.tcl` llevan hasta un AXI DMA S2MM real.
//
// Por qué serializar en vez de empaquetar los N_CH canales en un solo TDATA
// ancho (`N_CH*2*IQ_BITS` bits, como ya insinúa — sin consumidor real —
// `drx_ssa_pkg.SSA_TDATA_BITS` del lado de entrada): con N_CH=3 e
// IQ_BITS=16 eso son 96 bits, y el AXI DMA de Xilinx (`axi_dma`, ver
// `tcl/gen_zynq_bd.tcl`) solo admite anchos de `S_AXIS_S2MM_TDATA_WIDTH` en
// potencias de dos (8/16/32/64/...). Forzar 96 a la potencia de dos superior
// (128) desperdicia una cuarta parte de cada palabra escrita a DDR sin razón
// funcional. Serializar a 2*IQ_BITS=32 bits (un canal por palabra, ancho ya
// potencia de dos) no desperdicia nada y no depende de N_CH para el ancho
// del bus.
//
// Contrato de entrada: los N_CH streams de `drx_range_gate_quad_top` son
// independientes (cada uno su propio ping-pong, ver la cabecera de
// `drx_range_gate.sv`), así que este módulo NO asume que sus `valid`/`last`
// caigan sincronizados ciclo a ciclo — aunque en la práctica los N_CH
// canales comparten `bin_count`/`ray_start` y una cadena DDC idéntica, y por
// tanto sí deberían caer juntos. Solo captura una muestra nueva cuando los
// N_CH `s_valid` están altos A LA VEZ (`all_valid`); mientras alguno no lo
// esté, el registro de salida FWFT de cada `drx_range_gate` retiene su dato
// (no hay `s_ready` hasta entonces), así que un canal adelantado espera al
// más lento sin perder ni reordenar nada — ninguna carrera nueva que
// depender de sincronismo perfecto.
//
// `m_last` (TLAST hacia el AXI DMA, cierre de descriptor de scatter-gather)
// es el AND de los N_CH `s_last` de la muestra capturada, no de un canal
// cualquiera — un rayo no se da por completo hasta que TODOS los canales
// coinciden en que esa muestra es la última de su propio banco. Se evalúa
// una sola vez al capturar (no en cada beat de la serialización): con
// `bin_count`/`ray_start` compartidos entre canales esto siempre coincide en
// la práctica, pero AND explícito documenta la intención sin apostar a esa
// sincronía.
//
// `s_ready` sale en alto para los N_CH canales A LA VEZ, un único ciclo por
// muestra capturada — igual que el resto de esta cadena (`ray_start`,
// `bin_count`), un solo evento de captura avanza los N_CH bancos de golpe.
//
// -------------------------------------------------------------------------
// Z4.4: cabecera de metadato EN BANDA, al principio de cada rayo
// -------------------------------------------------------------------------
//
// Cada rayo sale ahora como `META_BEATS` palabras de metadato seguidas de los
// `bin_count * N_CH` beats de datos; TLAST sigue cayendo en el último beat de
// DATOS, así que el descriptor de scatter-gather cubre cabecera + datos y el
// firmware recibe las dos cosas en la misma transferencia.
//
// Por qué en banda y no en registros AXI-Lite leídos desde la interrupción de
// fin de descriptor: porque leerlos entonces llega TARDE. El banco de
// ping-pong de `drx_range_gate` se completa unos pocos cientos de ciclos
// antes del siguiente disparo de PRF (con la configuración que el firmware
// escribe hoy: 766896 ciclos de llenado contra un PRI de 767198 en el lote
// bajo, 208000 contra 208333 en el alto), y una interrupción de FreeRTOS no
// atiende en 5 us. Para cuando el manejador leyera TRIG_COUNT, el contador ya
// habría avanzado uno — y justo en el borde entre los dos lotes del radial
// (D-13) eso atribuye el rayo al lote equivocado, que es precisamente el caso
// que el metadato existe para distinguir.
//
// El margen de ese "unos pocos cientos de ciclos" NO es gratis: sale del bin
// de guarda que `bins_for_pri()` reserva en el firmware
// (`fw/src/app/drx_timing_cfg.c`). Una configuración con
// `bin_count * R1 == prf_div` lo elimina — D-09 valida `bin_count <= BinsMax`,
// no que el rayo quepa en el PRI, así que el RTL la aceptaría. El firmware
// comprueba por eso que `trig_count` avanza exactamente de uno entre rayos
// consecutivos; si no, lo cuenta como BITE en vez de entregar rayos mal
// etiquetados en silencio.
//
// El metadato se captura al empezar a VACIAR el rayo (transición
// `ST_IDLE -> ST_HEADER`, el primer ciclo en que el banco pendiente presenta
// dato), no al `ray_start` que lo originó: entre esos dos instantes pasa un
// rayo entero, y guardar el valor de `ray_start` exigiría una FIFO cuya
// profundidad habría que mantener sincronizada con los bancos del range-gate
// — y que se desincronizaría para siempre al primer rayo descartado
// (`ray_truncated`), produciendo el mismo error que se quería evitar pero
// permanente.
//
// `ray_index` es un contador propio de este módulo, no viene de fuera: cuenta
// rayos EMITIDOS, mientras que `trig_count` cuenta disparos. Que los dos
// avancen de uno en uno a la vez es lo que demuestra que no se perdió ningún
// rayo; si divergen, la diferencia dice cuántos.

`ifndef DRX_RAY_PACKER_SV
`define DRX_RAY_PACKER_SV

module drx_ray_packer
  import drx_params_pkg::*;
#(
    parameter int N_CH = N_RX_CH
) (
    input logic clk,
    input logic rst_n,

    input  logic                      s_valid[N_CH],
    output logic                      s_ready[N_CH],
    input  logic signed [IQ_BITS-1:0] s_i    [N_CH],
    input  logic signed [IQ_BITS-1:0] s_q    [N_CH],
    input  logic                      s_last [N_CH],

    // Metadato del rayo, muestreado al empezar a vaciarlo. Ver la cabecera.
    input logic [31:0] meta_trig_count,
    input logic [15:0] meta_bin_count,
    input logic        meta_batch_high,
    input logic        meta_mode_coarse,

    output logic                  m_valid,
    input  logic                  m_ready,
    output logic [2*IQ_BITS-1:0]  m_data,
    output logic                  m_last
);

  // Igual que `AddrW` en `drx_range_gate.sv`: N_CH=1 pediría `$clog2(1)=0`
  // bits, un registro de ancho cero. No es un caso real (N_CH siempre es 3 o
  // 4 en este repo), pero el guard es gratis.
  localparam int IdxBits = (N_CH > 1) ? $clog2(N_CH) : 1;

  // Ancho del beat de salida. Las palabras de metadato se construyen contra
  // este ancho, no contra un 32 literal: si IQ_BITS dejara de ser 16, el
  // magic se truncaría y el firmware lo rechazaría en el primer rayo en vez
  // de interpretar basura (`DRX_RAY_MAGIC` en fw/include/drx_ray.h).
  localparam int BeatBits = 2 * IQ_BITS;

  // Palabras de metadato por rayo. Ver la cabecera.
  localparam int MetaBeats = 4;
  localparam int MetaIdxBits = $clog2(MetaBeats);

  // "RY" + version 1 del formato de cabecera. Marca el principio de rayo en
  // el buffer de DDR: el firmware no tiene otra forma de confirmar que el
  // descriptor empieza donde cree que empieza.
  localparam logic [31:0] RayMagic = 32'h5259_0001;

  typedef enum logic [1:0] {ST_IDLE, ST_HEADER, ST_CAPTURE, ST_SEND} state_e;

  state_e                    state;
  logic     [   IdxBits-1:0] send_idx;
  logic [MetaIdxBits-1:0]    meta_idx;
  logic signed [IQ_BITS-1:0] cap_i[N_CH];
  logic signed [IQ_BITS-1:0] cap_q[N_CH];
  logic                      cap_ray_last;

  // Metadato congelado para el rayo en curso, y contador de rayos emitidos.
  logic [31:0] ray_trig_count;
  logic [31:0] ray_index;
  logic [15:0] ray_bin_count;
  logic        ray_batch_high;
  logic        ray_mode_coarse;

  logic all_valid;
  always_comb begin
    all_valid = 1'b1;
    for (int c = 0; c < N_CH; c++) all_valid &= s_valid[c];
  end

  // AND de los N_CH `s_last` de la muestra que se captura ESTE ciclo,
  // calculado combinacional para poder asignarse a `cap_ray_last` con una
  // sola no bloqueante — repetir `cap_ray_last <= cap_ray_last & s_last[c]`
  // dentro de un `for` en `always_ff` sería un bug clásico de Verilog: todas
  // las asignaciones no bloqueantes de la misma vuelta leen el valor VIEJO de
  // `cap_ray_last`, así que solo la última del bucle (c = N_CH-1) ganaría.
  logic ray_last_capture;
  always_comb begin
    ray_last_capture = 1'b1;
    for (int c = 0; c < N_CH; c++) ray_last_capture &= s_last[c];
  end

  logic capture;
  assign capture = (state == ST_CAPTURE) && all_valid;

  always_comb begin
    for (int c = 0; c < N_CH; c++) s_ready[c] = capture;
  end

  // Palabra de metadato que toca emitir. `ray_flags` deja sitio de sobra: hoy
  // sólo dos bits tienen significado, y el firmware ignora los reservados en
  // vez de exigir que valgan 0, para que añadir uno no rompa un lector viejo.
  logic [31:0] meta_word;
  always_comb begin
    unique case (meta_idx)
      MetaIdxBits'(0): meta_word = RayMagic;
      MetaIdxBits'(1): meta_word = ray_trig_count;
      MetaIdxBits'(2): meta_word = ray_index;
      default:
      meta_word = {8'(N_CH), 6'b0, ray_mode_coarse, ray_batch_high, ray_bin_count};
    endcase
  end

  assign m_valid = (state == ST_SEND) || (state == ST_HEADER);
  assign m_data  = (state == ST_HEADER) ? BeatBits'(meta_word)
                                        : {cap_i[send_idx], cap_q[send_idx]};
  assign m_last  = (state == ST_SEND) && (send_idx == IdxBits'(N_CH - 1)) && cap_ray_last;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE;
      send_idx <= '0;
      meta_idx <= '0;
      cap_ray_last <= 1'b0;
      ray_trig_count <= '0;
      ray_index <= '0;
      ray_bin_count <= '0;
      ray_batch_high <= 1'b0;
      ray_mode_coarse <= 1'b0;
      for (int c = 0; c < N_CH; c++) begin
        cap_i[c] <= '0;
        cap_q[c] <= '0;
      end
    end else begin
      unique case (state)
        // Entre rayos. `s_ready` está en bajo, así que el registro FWFT del
        // range-gate retiene su primera muestra hasta que la cabecera salga
        // entera: no se pierde nada por esperar aquí.
        ST_IDLE: begin
          if (all_valid) begin
            ray_trig_count <= meta_trig_count;
            ray_bin_count <= meta_bin_count;
            ray_batch_high <= meta_batch_high;
            ray_mode_coarse <= meta_mode_coarse;
            meta_idx <= '0;
            state <= ST_HEADER;
          end
        end

        ST_HEADER: begin
          if (m_ready) begin
            if (meta_idx == MetaIdxBits'(MetaBeats - 1)) begin
              state <= ST_CAPTURE;
            end else begin
              meta_idx <= meta_idx + MetaIdxBits'(1);
            end
          end
        end

        ST_CAPTURE: begin
          if (capture) begin
            for (int c = 0; c < N_CH; c++) begin
              cap_i[c] <= s_i[c];
              cap_q[c] <= s_q[c];
            end
            cap_ray_last <= ray_last_capture;
            send_idx <= '0;
            state <= ST_SEND;
          end
        end

        ST_SEND: begin
          if (m_ready) begin
            if (send_idx == IdxBits'(N_CH - 1)) begin
              // Fin del rayo: vuelve a ST_IDLE para que el siguiente empiece
              // por su cabecera. `ray_index` cuenta rayos EMITIDOS, así que
              // sólo avanza aquí, nunca en un rayo descartado aguas arriba.
              if (cap_ray_last) begin
                ray_index <= ray_index + 32'd1;
                state <= ST_IDLE;
              end else begin
                state <= ST_CAPTURE;
              end
            end else begin
              send_idx <= send_idx + IdxBits'(1);
            end
          end
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule : drx_ray_packer

`endif  // DRX_RAY_PACKER_SV
