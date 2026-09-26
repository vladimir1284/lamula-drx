// Range gating — Z1 (fases.md#z1): trocea el flujo continuo de I/Q que sale de
// `drx_ddc_top` en rayos de `bin_count` muestras (registro de entrada, D-15),
// con `m_last` (TLAST) en la última de cada rayo. Es el equivalente en hardware de
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
// `overrun` es sticky: dispara si el consumidor no vació un banco durante el
// rayo entero que tardó en llenarse el otro; con solo dos bancos ese es el
// único margen que hay, y con cualquier consumidor a la velocidad de fabric
// (órdenes de magnitud por encima de la tasa decimada) no debería dispararse
// nunca en operación normal. No hay forma de frenar al DDC para evitarlo, así
// que la muestra entrante sigue escribiéndose encima del banco no vaciado en
// vez de perderse en silencio — el propio `overrun` es la señal de que eso
// pasó.
//
// `clear` (nuevo, mapa de registros AXI-Lite — `rtl/drx_axil_regs.sv`, STATUS
// write-1-to-clear): sin este puerto, `overrun` una vez disparado se queda en
// alto para siempre (solo lo borra `rst_n`), así que firmware jamás podría ver
// un SEGUNDO overrun tras limpiar el primero — no habría forma de rearmarlo.
// Un evento de overrun nuevo el mismo ciclo que `clear` gana (ver el
// `always_ff` de abajo): un fallo real nunca se pierde por una carrera con la
// limpieza de firmware.
//
// `BINS_MAX` es un parámetro, no el `localparam` del paquete directamente,
// por lo mismo que `DIV` lo es en `drx_heartbeat.sv`: para que los
// testbenches puedan simular rayos de unas pocas muestras en vez de los 3689
// reales. La instancia de producción no pasa nada y hereda `BINS_MODE_FINE`
// de `drx_params_pkg` (D-02: single source of truth) -- es el techo físico
// de esta BRAM, no un "modo fino"; ver D-15 más abajo.
//
// `ray_start` (D-14, 22-sep-2026, mapa de registros v3/Z2): pulso de un ciclo
// que fuerza `wr_ptr` a 0 -- lo conecta `drx_top` a `pulse_trig` de
// `drx_timing_engine`, así que cada pulso de PRF (de cualquiera de los 2
// lotes, D-13) arranca un rayo nuevo aquí, en vez de dejar que el contador de
// bins libre por su cuenta decida dónde cortar. Sin esto, con la entrada
// muestreando sin parar (el ADC/DDC no tiene forma de pausarse entre pulsos),
// el free-run de este módulo trocearía el tiempo muerto entre el eco y el
// siguiente disparo como si fuera parte de un rayo real.
//
// Deliberadamente NO marca el banco actual como pendiente al recortar: si
// `ray_start` llega con `wr_ptr` != 0 (tiempo muerto acumulado, o un PRI mal
// configurado más corto que `bins` -- D-09 no lo valida en RTL, ver la
// cabecera de `drx_prf_batch_seq.sv`), lo que había escrito en ese banco se
// descarta sin más: nunca se pone `bank_pending`, así que el lector nunca lo
// ve. Solo el camino ya existente (`wr_ptr == last_idx` alcanzado por
// muestras reales) produce un rayo válido; `ray_start` solo decide DÓNDE
// empieza el próximo intento, nunca fuerza uno incompleto a salir. Cuando la
// configuración es correcta (D-09: el PRI en muestras decimadas cabe
// `bins` veces o más), los dos caminos coinciden en el mismo ciclo y
// `ray_start` es un no-op redundante -- ver D-14 para por qué esto no
// necesita vectores nuevos del modelo dorado (`ray_start` en bajo es
// bit a bit idéntico al comportamiento ya verificado bajo D-12).
//
// `ray_truncated` (BITE, 25-sep-2026, mapa de registros v6): D-14 dejaba
// ese descarte completamente mudo -- ni un contador ni un bit distinguían
// "PRI bien calibrado, ray_start llegó justo al wrap natural" de "ray_start
// llegó tarde y truncó un rayo real en curso". Se dispara (sticky, mismo
// patrón W1C que `overrun`, con `clear_truncated` como su propio puerto de
// limpieza -- NO comparte `clear`, porque son dos diagnósticos distintos con
// registros distintos en el mapa) cuando `ray_start` encuentra el banco en
// curso con algo escrito que no se completa en este mismo ciclo -- NO es
// simplemente `wr_ptr != 0` (ver el comentario junto al `always_ff`: ese
// valor sigue siendo `last_idx` en el ciclo exacto del wrap natural, la
// asignación a 0 del bloque de escritura todavía no se ha "visto"). Con el
// banco vacío (`wr_ptr == 0`) o completándose por cuenta propia ese mismo
// ciclo (wrap natural) NO se activa -- eso es operación normal, no un fallo.
//
// `bin_count` (D-15, 25-sep-2026, reemplaza `mode_coarse` en ESTE módulo): el
// conteo de bins ya no es una elección binaria fino/grueso fija en
// `config/params.toml` -- es un registro por lote (D-13: lote bajo/alto
// tienen requisitos de rango distintos), configurable en runtime, que viene
// de DSP y en última instancia de RCP según el VCP (la proporción entre el
// rango del lote bajo y el del alto nunca es la misma). `drx_timing_engine`
// ya expone el valor del lote ACTIVO como su salida `bin_count` (mismo mux
// que `pulse_width`); este módulo solo lo usa tal cual para `last_idx`, sin
// saber nada de lotes ni de PRF. `mode_coarse` sigue existiendo, pero solo
// para `drx_ddc_top` (decimación/tamaño de celda) -- ya no llega hasta aquí.
// Validar que `bin_count` no supere `BINS_MAX` (el techo físico real de esta
// BRAM) es responsabilidad de `drx_timing_config_valid.sv`, no de este
// módulo (D-09 completo) -- ver decisiones.md#d-15. Se llama `bin_count`, no
// `bins`: SystemVerilog reserva `bins` como palabra clave de coverpoints.
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
    parameter int BINS_MAX = BINS_MODE_FINE,
    parameter int BinsBits = 32
) (
    input logic clk,
    input logic rst_n,

    // Entrada: push-only, igual que `m_valid`/`m_i`/`m_q` de `drx_ddc_top`.
    input logic                      s_valid,
    input logic signed [IQ_BITS-1:0] s_i,
    input logic signed [IQ_BITS-1:0] s_q,

    // Conteo de bins del rayo EN CURSO (D-15, reemplaza `mode_coarse` en este
    // módulo -- ver la cabecera). Validado <= BINS_MAX aguas arriba, en
    // `drx_timing_config_valid.sv`; este módulo no vuelve a comprobarlo.
    input logic [BinsBits-1:0] bin_count,

    // Salida: AXI4-Stream real, con m_ready.
    output logic                      m_valid,
    input  logic                      m_ready,
    output logic signed [IQ_BITS-1:0] m_i,
    output logic signed [IQ_BITS-1:0] m_q,
    output logic                      m_last,

    // Write-1-to-clear desde el mapa de registros AXI-Lite (ver cabecera).
    input  logic clear,
    output logic overrun,

    // Resync con el motor de timing de Z2 (D-14, ver cabecera).
    input logic ray_start,

    // BITE de tiempo muerto (ver cabecera): write-1-to-clear PROPIO, no
    // comparte `clear` con `overrun` -- son dos registros distintos del mapa.
    input  logic clear_truncated,
    output logic ray_truncated
);

  localparam int Depth = BINS_MAX;
  localparam int AddrW = $clog2(Depth);

  // Último índice del rayo (bins-1), no el conteo: el conteo puede no caber en
  // AddrW bits cuando Depth es una potencia de dos exacta (p. ej. un
  // testbench con BINS_MAX=8 pide AddrW=3, y "8" no cabe en 3 bits, pero "7"
  // sí). El índice máximo siempre cabe, por construcción de `$clog2`.
  logic [AddrW-1:0] last_idx;
  assign last_idx = AddrW'(bin_count - BinsBits'(1));

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
  //
  // `mem0_rd_r`/`mem1_rd_r`/`rd_from_bank1_r` + el `assign m_data_r` de más
  // abajo sustituyen lo que antes era un solo `m_data_r` cargado con un
  // if/else entre `mem0[rd_ptr]`/`mem1[rd_ptr]` en el mismo proceso que la
  // escritura de las dos memorias. Contra Vivado real (19-sep-2026) esa
  // forma nunca sintetizó a BRAM —ni con el if/else, ni con
  // `(* ram_style = "block" *)` (Vivado la marcó "Infeasible... trying to
  // implement using LUTRAM")—, aunque siempre fue bit a bit correcta en
  // xsim: la simulación funcional no verifica qué primitiva usaría síntesis
  // real. La estructura de abajo separa cada banco en su propio proceso de
  // lectura y de escritura, sin ninguna sentencia compartida entre `mem0` y
  // `mem1` — el patrón que Vivado sí reconoce como BRAM de libro. El
  // resultado es EL MISMO valor en el MISMO ciclo: `rd_from_bank1_r` se
  // registra en el proceso de control exactamente cuando se decide leer
  // (misma condición que antes decidía `mem0` vs `mem1`), y el `assign`
  // combinacional de `m_data_r` solo elige entre los dos registros de
  // lectura YA cargados ese mismo ciclo — cero ciclos de latencia extra, no
  // invalida la matriz L1 ya corrida.
  logic                  m_valid_r;
  logic                  m_last_r;
  logic [2*IQ_BITS-1:0]  mem0_rd_r;
  logic [2*IQ_BITS-1:0]  mem1_rd_r;
  logic                  rd_from_bank1_r;
  logic [2*IQ_BITS-1:0]  m_data_r;
  logic                  can_advance;

  assign can_advance = !m_valid_r || m_ready;
  assign m_data_r    = rd_from_bank1_r ? mem1_rd_r : mem0_rd_r;

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
      ray_truncated <= 1'b0;
      m_valid_r <= 1'b0;
      m_last_r  <= 1'b0;
      rd_from_bank1_r <= 1'b0;
    end else begin
      // `clear` tiene prioridad más baja que un overrun nuevo el mismo ciclo:
      // si las dos coinciden, el `overrun <= 1'b1` de más abajo se evalúa
      // después en este mismo `always_ff` y gana (última asignación no
      // bloqueante sobre la misma señal manda). Ver la cabecera del fichero.
      if (clear) overrun <= 1'b0;
      if (clear_truncated) ray_truncated <= 1'b0;

      // Escritura: nunca se detiene, sigue el ritmo de `s_valid`. El propio
      // dato (`mem0`/`mem1`) se escribe en los procesos de abajo, cada uno
      // bajo esta misma condición exacta más su propio banco.
      if (s_valid) begin
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

      // `ray_start` va DESPUÉS del bloque de arriba a propósito: si los dos
      // coinciden el mismo ciclo (PRI mal configurado, más corto que `bins`),
      // la asignación no bloqueante que manda es esta -- `ray_start` gana y
      // fuerza `wr_ptr` a 0 pase lo que pase, descartando el intento en
      // curso. Cuando la configuración es correcta y coinciden en el ciclo
      // exacto en que `wr_ptr` ya llegó a `last_idx`, esto es un no-op (los
      // dos escriben el mismo valor). No toca `bank_pending`/`bank_last_idx`:
      // ver la cabecera del fichero sobre por qué un recorte forzado nunca
      // marca un banco como listo para leer.
      //
      // `ray_truncated` (BITE) NO es simplemente "`wr_ptr` != 0": ese valor
      // sigue siendo `last_idx` (no cero) en el ciclo exacto del wrap
      // natural, porque el `wr_ptr <= '0` del bloque de escritura de arriba
      // todavía no se ha "visto" (es una asignación no bloqueante sobre el
      // mismo registro que se lee aquí). El caso de no-op de verdad es
      // `s_valid && (wr_ptr == last_idx)` -- el banco se completa por cuenta
      // propia ESTE mismo ciclo, `ray_start` no descarta nada real. Cualquier
      // otro `wr_ptr` != 0 sí es un descarte genuino (con o sin `s_valid` a
      // la vez: una muestra que llega el mismo ciclo que un `ray_start` que
      // NO alcanza a completar el banco también se pierde). Va DESPUÉS de
      // `if (clear_truncated) ray_truncated <= 1'b0;` de arriba a propósito,
      // misma prioridad set-sobre-clear-concurrente que `overrun`.
      if (ray_start) begin
        wr_ptr <= '0;
        if ((wr_ptr != '0) && !(s_valid && (wr_ptr == last_idx))) begin
          ray_truncated <= 1'b1;
        end
      end

      // Lectura: registrada. Solo intenta cargar el siguiente dato cuando el
      // registro de salida está libre (nunca tuvo nada válido, o lo que tenía
      // ya se aceptó este mismo ciclo). `mem0_rd_r`/`mem1_rd_r` se cargan en
      // los procesos de abajo, cada uno bajo esta misma condición exacta más
      // su propio banco; `rd_from_bank1_r` registra aquí cuál de los dos hay
      // que mirar.
      if (can_advance) begin
        if (bank_pending[rd_bank]) begin
          m_last_r  <= (rd_ptr == bank_last_idx[rd_bank]);
          m_valid_r <= 1'b1;
          rd_from_bank1_r <= rd_bank;
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

  // Cuatro procesos, uno por (banco × operación), cada uno tocando UN solo
  // array sin reset y sin ninguna sentencia compartida con el otro banco —
  // ver la nota de arriba sobre por qué. Ninguna BRAM real de Xilinx tiene
  // borrado asíncrono de contenido, y mezclar los dos bancos en un mismo
  // proceso (con o sin ternario) es lo que Vivado real no reconocía como
  // BRAM. Las condiciones son las mismas de siempre, solo repartidas.
  always_ff @(posedge clk) begin
    if (s_valid && !wr_bank) mem0[wr_ptr] <= {s_i, s_q};
  end

  always_ff @(posedge clk) begin
    if (s_valid && wr_bank) mem1[wr_ptr] <= {s_i, s_q};
  end

  always_ff @(posedge clk) begin
    if (can_advance && bank_pending[rd_bank] && !rd_bank) mem0_rd_r <= mem0[rd_ptr];
  end

  always_ff @(posedge clk) begin
    if (can_advance && bank_pending[rd_bank] && rd_bank) mem1_rd_r <= mem1[rd_ptr];
  end

endmodule : drx_range_gate

`endif  // DRX_RANGE_GATE_SV
