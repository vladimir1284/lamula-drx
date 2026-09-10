// Range gating — Z1 (fases.md#z1): trocea el flujo continuo de I/Q que sale de
// `drx_ddc_top` en rayos de `BINS_FINE`/`BINS_COARSE` muestras, con `m_last`
// (TLAST) en la última de cada rayo. Es el equivalente en hardware de
// `model/drx_model/gating.py::gate` — mismo criterio de corte, un bin de rango
// es una muestra decimada, nada más.
//
// Entrada push-only / salida AXI4-Stream real, a propósito: `drx_ddc_top` no
// admite backpressure (su NCO y su mezclador nunca la piden — ver la cabecera
// de ese fichero), así que este módulo no puede pedirla tampoco aguas arriba.
// El ping-pong de dos bancos es lo que hace posible tener `m_ready` real aguas
// abajo sin perder una muestra: mientras un banco se llena a la fuerza al
// ritmo del DDC, el otro (el rayo ya completo) se vacía al ritmo que el
// consumidor imponga. Es la primera vez en la cadena que hay backpressure de
// verdad, y por diseño: aquí, y no antes.
//
// `overrun` se trata igual que `overflow` en `drx_saturate.sv`: sticky, sin
// nada que lo lea todavía porque el mapa de registros AXI-Lite es trabajo
// posterior de esta misma fase (fases.md#z1) — se conecta el día que exista.
// Dispara si el consumidor no vació un banco durante el rayo entero que tardó
// en llenarse el otro; con solo dos bancos ese es el único margen que hay, y
// con cualquier consumidor a la velocidad de fabric (órdenes de magnitud por
// encima de la tasa decimada) no debería dispararse nunca en operación normal.
// No hay forma de frenar al DDC para evitarlo, así que la muestra entrante
// sigue escribiéndose encima del banco no vaciado en vez de perderse en
// silencio — el propio `overrun` es la señal de que eso pasó.
//
// `BINS_FINE`/`BINS_COARSE` son parámetros, no los `localparam` del paquete
// directamente, por lo mismo que `DIV` lo es en `drx_heartbeat.sv`: para que
// los testbenches puedan simular rayos de unas pocas muestras en vez de los
// 3689/1844 reales. La instancia de producción no pasa nada y hereda los
// valores de `drx_params_pkg` (D-02: single source of truth).
//
// `mode_coarse` se trata igual que en `drx_ddc_top`: entrada de tiempo de
// ejecución pero estática durante una corrida. Cambiarla a mitad de rayo no
// está cubierto aquí, igual que la conmutación fina/gruesa en caliente es del
// plan de pruebas de Z1, no de este primer corte.
//
// El puerto de lectura es REGISTRADO (`m_i`/`m_q`/`m_valid`/`m_last` salen de
// un registro que se carga con la lectura de `mem0`/`mem1`, no de un `assign`
// combinacional sobre el array indexado por `rd_ptr`), a propósito, y no por
// estilo: una BRAM real de Xilinx tiene el puerto de lectura registrado —
// mapear un `assign` combinacional sobre un array de 3689 entradas no
// corresponde a ningún puerto real de BRAM. Se encontró corriendo esto en
// xsim de verdad (ver el hallazgo de esta fecha en pendientes.md): con
// lectura combinacional, la simulación de L1 con la IP real dejó de terminar
// en el entorno de minutos que documentan los casos anteriores del mismo
// testbench — el propio arnés de Verilator/cocotb (L0, sin la IP) seguía
// pasando rápido y bien, así que el bug era específico de xsim frente a un
// array leído por índice variable fuera de un patrón de lectura síncrona, no
// un error de los VALORES que produce el módulo.

`ifndef DRX_RANGE_GATE_SV
`define DRX_RANGE_GATE_SV

module drx_range_gate
  import drx_params_pkg::*;
#(
    parameter int BINS_FINE   = BINS_MODE_FINE,
    parameter int BINS_COARSE = BINS_MODE_COARSE
) (
    input logic clk,
    input logic rst_n,

    // Entrada: push-only, igual que `m_valid`/`m_i`/`m_q` de `drx_ddc_top`.
    input logic                      s_valid,
    input logic signed [IQ_BITS-1:0] s_i,
    input logic signed [IQ_BITS-1:0] s_q,

    input logic mode_coarse,

    // Salida: AXI4-Stream real, con m_ready.
    output logic                      m_valid,
    input  logic                      m_ready,
    output logic signed [IQ_BITS-1:0] m_i,
    output logic signed [IQ_BITS-1:0] m_q,
    output logic                      m_last,

    output logic overrun
);

  localparam int Depth = (BINS_FINE > BINS_COARSE) ? BINS_FINE : BINS_COARSE;
  localparam int AddrW = $clog2(Depth);

  // Último índice del rayo (bins-1), no el conteo: el conteo puede no caber en
  // AddrW bits cuando Depth es una potencia de dos exacta (p. ej. un
  // testbench con BINS_FINE=8 pide AddrW=3, y "8" no cabe en 3 bits, pero
  // "7" sí). El índice máximo siempre cabe, por construcción de `$clog2`.
  logic [AddrW-1:0] last_idx;
  assign last_idx = mode_coarse ? AddrW'(BINS_COARSE - 1) : AddrW'(BINS_FINE - 1);

  // Dos bancos independientes en vez de un array indexado por `wr_bank`: cada
  // uno es un simple-dual-port de libro (un puerto de escritura, uno de
  // lectura), el patrón que Vivado infiere como BRAM sin ambigüedad. Indexar
  // un único array por una señal de banco variable en los dos puertos es
  // justo lo que confunde la inferencia.
  logic [2*IQ_BITS-1:0] mem0[0:Depth-1];
  logic [2*IQ_BITS-1:0] mem1[0:Depth-1];

  logic             wr_bank;
  logic [AddrW-1:0] wr_ptr;
  logic [AddrW-1:0] rd_ptr;
  logic             bank_pending[0:1];
  logic [AddrW-1:0] bank_last_idx[0:1];

  logic rd_bank;
  assign rd_bank = ~wr_bank;

  // Registro de salida (FWFT de una etapa): se carga con la lectura de
  // `mem0`/`mem1` cuando no hay nada válido todavía, o cuando lo que había
  // acaba de aceptarse — nunca pisa un dato que el consumidor no ha tomado
  // todavía.
  logic                  m_valid_r;
  logic                  m_last_r;
  logic [2*IQ_BITS-1:0]  m_data_r;
  logic                  can_advance;

  assign can_advance = !m_valid_r || m_ready;

  assign m_valid = m_valid_r;
  assign m_last  = m_last_r;
  assign m_i     = m_data_r[2*IQ_BITS-1-:IQ_BITS];
  assign m_q     = m_data_r[IQ_BITS-1:0];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_bank <= 1'b0;
      wr_ptr <= '0;
      rd_ptr <= '0;
      bank_pending[0] <= 1'b0;
      bank_pending[1] <= 1'b0;
      overrun <= 1'b0;
      m_valid_r <= 1'b0;
      m_last_r  <= 1'b0;
    end else begin
      // Escritura: nunca se detiene, sigue el ritmo de `s_valid`.
      if (s_valid) begin
        if (wr_bank) mem1[wr_ptr] <= {s_i, s_q};
        else mem0[wr_ptr] <= {s_i, s_q};

        if (wr_ptr == last_idx) begin
          bank_last_idx[wr_bank] <= last_idx;
          if (bank_pending[wr_bank]) overrun <= 1'b1;
          bank_pending[wr_bank] <= 1'b1;
          wr_ptr  <= '0;
          wr_bank <= ~wr_bank;
        end else begin
          wr_ptr <= wr_ptr + AddrW'(1);
        end
      end

      // Lectura: registrada. Solo intenta cargar el siguiente dato cuando el
      // registro de salida está libre (nunca tuvo nada válido, o lo que tenía
      // ya se aceptó este mismo ciclo).
      if (can_advance) begin
        if (bank_pending[rd_bank]) begin
          m_data_r  <= rd_bank ? mem1[rd_ptr] : mem0[rd_ptr];
          m_last_r  <= (rd_ptr == bank_last_idx[rd_bank]);
          m_valid_r <= 1'b1;
          if (rd_ptr == bank_last_idx[rd_bank]) begin
            rd_ptr <= '0;
            bank_pending[rd_bank] <= 1'b0;
          end else begin
            rd_ptr <= rd_ptr + AddrW'(1);
          end
        end else begin
          m_valid_r <= 1'b0;
        end
      end
    end
  end

endmodule : drx_range_gate

`endif  // DRX_RANGE_GATE_SV
