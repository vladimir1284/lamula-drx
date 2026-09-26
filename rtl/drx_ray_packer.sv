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

    output logic                  m_valid,
    input  logic                  m_ready,
    output logic [2*IQ_BITS-1:0]  m_data,
    output logic                  m_last
);

  // Igual que `AddrW` en `drx_range_gate.sv`: N_CH=1 pediría `$clog2(1)=0`
  // bits, un registro de ancho cero. No es un caso real (N_CH siempre es 3 o
  // 4 en este repo), pero el guard es gratis.
  localparam int IdxBits = (N_CH > 1) ? $clog2(N_CH) : 1;

  typedef enum logic {ST_CAPTURE, ST_SEND} state_e;

  state_e                    state;
  logic     [   IdxBits-1:0] send_idx;
  logic signed [IQ_BITS-1:0] cap_i[N_CH];
  logic signed [IQ_BITS-1:0] cap_q[N_CH];
  logic                      cap_ray_last;

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

  assign m_valid = (state == ST_SEND);
  assign m_data  = {cap_i[send_idx], cap_q[send_idx]};
  assign m_last  = (state == ST_SEND) && (send_idx == IdxBits'(N_CH - 1)) && cap_ray_last;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_CAPTURE;
      send_idx <= '0;
      cap_ray_last <= 1'b0;
      for (int c = 0; c < N_CH; c++) begin
        cap_i[c] <= '0;
        cap_q[c] <= '0;
      end
    end else begin
      unique case (state)
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
              state <= ST_CAPTURE;
            end else begin
              send_idx <= send_idx + IdxBits'(1);
            end
          end
        end
      endcase
    end
  end

endmodule : drx_ray_packer

`endif  // DRX_RAY_PACKER_SV
