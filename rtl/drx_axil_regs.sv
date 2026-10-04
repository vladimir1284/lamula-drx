// Mapa de registros AXI-Lite de `drx_top` — Z1
// (docs/implementacion/registros.md, config/registers.toml es la fuente única
// de verdad de los offsets que importa este módulo vía `drx_regs_pkg`).
//
// Slave AXI4-Lite mínimo, a propósito: AXI-Lite no tiene bursts, así que basta
// con un canal de escritura y uno de lectura, cada uno con UNA transacción en
// vuelo (no se acepta AW/W siguiente hasta que B se aceptó; ídem AR/R con
// RVALID). Responde siempre OKAY — no hay dirección de este mapa que pueda
// fallar de una forma que valga la pena reportar en v1. `s_axi_wstrb` se
// ignora deliberadamente: todos los registros de este mapa se escriben
// completos de 32 bits, no hay ninguno donde escribir solo un byte tenga
// sentido.
//
// CTRL (offset REG_CTRL_ADDR) — bit 1 (v8, Z4.3) es `vector_source_ddr`, el
// selector entre BRAM-loop y Throttled(DDR) de `vector_source.sv`; bit 0 es
// `mode_coarse`, el mismo generic
// compartido por los N_CH canales que antes era `localparam ModeCoarse` fijo
// en `drx_top.sv`. Bits 31:1 reservados: leen 0, una escritura ahí no hace
// nada (no hay registro que actualizar).
//
// STATUS (offset REG_STATUS_ADDR) — bit `c` es el `overrun` sticky del canal
// `c` de `drx_range_gate_quad_top`, leído tal cual (`overrun_in`): este bloque
// no mantiene su propia copia latcheada, el latch real vive en
// `drx_range_gate` (ya lo hacía antes de este módulo, para el debug_probe).
// Escribir 1 en el bit `c` genera un pulso de un ciclo en `overrun_clear[c]`
// hacia el nuevo puerto `clear` de `drx_range_gate` — limpiar aquí sin tocar
// la fuente habría dejado el bit releído en 1 el ciclo siguiente, porque el
// propio `overrun_in` nunca se apaga solo. Si un overrun genuino ocurre el
// mismo ciclo que el clear, gana el set (ver el comentario en
// `drx_range_gate.sv`): no se puede perder un fallo real por una carrera con
// firmware limpiando el anterior.
//
// OVERFLOW (offset REG_OVERFLOW_ADDR, añadido en v2) — bit `c` es el overflow
// de saturación del canal `c` (`drx_ddc_quad_top.overflow`, combinación de
// las ramas I/Q de `drx_ddc_top`). A DIFERENCIA de STATUS, el latch sticky
// vive AQUÍ, no en la fuente: `drx_saturate` es deliberadamente combinacional
// y sin estado (ver su propia cabecera), así que este bloque es quien lo
// convierte en sticky-con-W1C, con la misma prioridad set-sobre-clear que
// STATUS. No hace falta un puerto de vuelta hacia `drx_ddc_top` — el clear no
// tiene que llegar a ninguna fuente externa, se resuelve entero aquí dentro.
//
// Z2 (v3, D-13) — TIMING_CTRL/TIMING_STATUS/PRF_DIV_*/PULSE_WIDTH/N_PULSES/
// TRIG_DELAY_*/TRIG_WIDTH_* alimentan `drx_timing_engine` (instanciado en
// `drx_top.sv`), puro paso de registro a planta salvo TIMING_STATUS, que
// sigue el mismo patrón sticky-con-W1C que OVERFLOW (el `radial_done` de
// `drx_prf_batch_seq` es un pulso de un ciclo; sin latch aquí, firmware
// tendría que sondear en la ventana exacta del pulso). Los 4 canales de
// TRIG_DELAY/TRIG_WIDTH son puertos escalares con nombre por canal, no un
// array — mismo motivo que documenta `drx_trigger_gen.sv`: un array sin
// empaquetar de puertos de SALIDA no es indexable de forma fiable vía VPI
// (confirmado empíricamente con `trig_out`); `drx_top.sv` hace el
// empaquetado hacia el array de entrada de `drx_timing_engine` (que sí
// acepta arrays sin empaquetar como entrada, sin ese problema).
//
// TIMING_STATUS bits 1/2 (v4, luego D-09 completo desde v5) —
// `config_invalid_low`/`_high` de `drx_timing_engine` (D-09 completo: tabla,
// cabe en su propio PRI, PRF x rango, y desde D-15 también el techo de bins)
// son NIVELES combinacionales, no pulsos: mismo motivo que OVERFLOW para
// latchearlos aquí (la fuente, `drx_timing_config_valid.sv`, es
// deliberadamente combinacional y sin estado), misma prioridad
// set-sobre-clear-concurrente.
//
// BINS_LOW/BINS_HIGH (v5, D-15) — mismo patrón RW de paso directo que
// PRF_DIV_LOW/HIGH: el conteo de bins de range-gate por lote, configurable en
// runtime (viene de DSP/RCP según el VCP), sin validar aquí -- se valida en
// `drx_timing_config_valid.sv` contra el techo físico de BRAM.
//
// GATE_TRUNCATED (offset REG_GATE_TRUNCATED_ADDR, v6) — BITE de D-14: bit `c`
// es el `ray_truncated` sticky del canal `c` de `drx_range_gate_quad_top`,
// MISMO patrón que STATUS/overrun (el latch vive en `drx_range_gate`, este
// bloque solo lo expone y pulsa `ray_truncated_clear[c]`) — registro propio,
// no bits nuevos de STATUS: es un diagnóstico distinto, con su propia fuente
// y su propio clear en RTL (`drx_range_gate.clear_truncated`, no comparte
// `clear`/`overrun`).
//
// TRIG_COUNT (offset REG_TRIG_COUNT_ADDR, v7, Z4.1) — contador libre de 32
// bits, incrementa un pulso de `pulse_trig_in` (el mismo `pulse_trig` de
// `drx_timing_engine` que ya dispara `ray_start`, D-14) por ciclo. A
// diferencia de STATUS/OVERFLOW/GATE_TRUNCATED, NO es sticky-con-W1C: es RO
// puro, un conteo monótono sin ningún puerto de limpieza — envuelve en 2^32
// pulsos en vez de saturar o requerir que firmware lo rearme.

`ifndef DRX_AXIL_REGS_SV
`define DRX_AXIL_REGS_SV

module drx_axil_regs
  import drx_regs_pkg::*;
  // `NCO_PHASE_INC` (valor de reset de NCO_PINC, v9) vive en el paquete de
  // parametros, no en el del mapa de registros: es un numero del modelo dorado,
  // no una direccion.
  import drx_params_pkg::NCO_PHASE_INC;
  // v11: capacidad fisica del banco de BRAM de `vector_source` y longitud del
  // bucle precargado. La primera fija el ancho del puntero de VEC_ADDR; la
  // segunda es el valor de reset de VEC_LEN, y tiene que ser la misma que
  // `$readmemh` precarga o el bucle de arranque en frio no cerraria fase.
  import drx_params_pkg::VECTOR_BRAM_DEPTH;
  import drx_params_pkg::VECTOR_LOOP_LEN;
#(
    parameter int N_CH = 3,

    // En la lista de parametros, no en el cuerpo: los puertos de la ventana de
    // carga son de este ancho.
    localparam int VecAddrBits = $clog2(VECTOR_BRAM_DEPTH)
) (
    input logic clk,
    input logic rst_n,

    // Canal de escritura.
    input  logic [REGS_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic                       s_axi_awvalid,
    output logic                       s_axi_awready,

    input  logic [31:0] s_axi_wdata,
    input  logic [ 3:0] s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    output logic [1:0] s_axi_bresp,
    output logic       s_axi_bvalid,
    input  logic       s_axi_bready,

    // Canal de lectura.
    input  logic [REGS_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic                       s_axi_arvalid,
    output logic                       s_axi_arready,

    output logic [31:0] s_axi_rdata,
    output logic [ 1:0] s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // Registro -> planta.
    output logic mode_coarse,

    // v11: ventana de carga del vector de estimulo hacia `vector_source`.
    //
    // CTRL bit 1 era `vector_source_ddr` entre v8 y v10 y ya no existe: el
    // modo Throttled(DDR) que seleccionaba salio del diseno junto con el canal
    // MM2S del AXI DMA. El bit vuelve a reservado y lee 0.
    //
    // `vec_we` es un pulso de un ciclo por cada escritura de VEC_DATA, con
    // `vec_addr`/`vec_bank`/`vec_data` validos en ESE mismo ciclo. No va
    // cualificado por `vec_load` aqui: quien decide si la escritura llega a la
    // memoria es `vector_source`, en un solo sitio.
    output logic                 vector_load,
    output logic                 vec_we,
    output logic [VecAddrBits-1:0] vec_addr,
    output logic [            2:0] vec_bank,
    output logic [           15:0] vec_data,
    output logic [VecAddrBits-1:0] vec_len,

    // v9 (Z4.5): NCO_PINC -- palabra de incremento de fase del NCO, hacia el
    // canal S_AXIS_CONFIG del DDS Compiler de cada canal del DDC. `nco_pinc_we`
    // es un pulso de un ciclo por CADA escritura del registro, incluso si el
    // valor no cambia: el que decide si reprogramar es el par remoto (mensaje
    // `afc`), no este modulo.
    output logic [31:0] nco_pinc,
    output logic        nco_pinc_we,

    // Planta -> registro (ver cabecera: `overrun_in` ya viene latcheado desde
    // `drx_range_gate`, este bloque solo lo expone y pulsa el clear). Vector
    // empaquetado, no array — son literalmente los bits de STATUS, y un
    // vector es además lo único que Verilator/cocotb saben indexar por canal
    // sobre un puerto de top-level (un array sin empaquetar de puertos no es
    // indexable vía VPI en esta versión). `drx_top.sv` hace el empaquetado/
    // desempaquetado contra los arrays de `drx_range_gate_quad_top`.
    input  logic [N_CH-1:0] overrun_in,
    output logic [N_CH-1:0] overrun_clear,

    // Overflow de saturación del DDC, por canal (ver cabecera: sticky
    // mantenido dentro de este módulo, no en la fuente).
    input logic [N_CH-1:0] overflow_in,

    // BITE de tiempo muerto (D-14/v6), por canal -- mismo patrón que
    // overrun_in/overrun_clear (latch en la fuente, ver cabecera).
    input  logic [N_CH-1:0] ray_truncated_in,
    output logic [N_CH-1:0] ray_truncated_clear,

    // Z2 (v3, D-13) — registro -> planta, hacia drx_timing_engine.
    output logic        timing_enable,
    // TIMING_CTRL bit 1 (v10, P-16): el motor cuenta avances de muestra en vez
    // de ciclos. Ver `drx_sample_pacer.sv`.
    output logic        timing_paced,
    output logic [31:0] prf_div_low,
    output logic [31:0] prf_div_high,
    output logic [15:0] pulse_width_low,
    output logic [15:0] pulse_width_high,
    output logic [15:0] n_pulses_low,
    output logic [15:0] n_pulses_high,
    output logic [31:0] bins_low,
    output logic [31:0] bins_high,
    output logic [31:0] trig_delay_0,
    output logic [31:0] trig_delay_1,
    output logic [31:0] trig_delay_2,
    output logic [31:0] trig_delay_3,
    output logic [31:0] trig_width_0,
    output logic [31:0] trig_width_1,
    output logic [31:0] trig_width_2,
    output logic [31:0] trig_width_3,

    // Planta -> registro (ver cabecera: pulso de un ciclo, latcheado aquí).
    input logic radial_done_in,

    // Planta -> registro (ver cabecera: niveles combinacionales, latcheados
    // aquí igual que OVERFLOW). D-09, checks autocontenidos.
    input logic config_invalid_low_in,
    input logic config_invalid_high_in,

    // Z4.1: pulso de un ciclo de drx_timing_engine.pulse_trig -- ver la
    // cabecera de TRIG_COUNT.
    input logic pulse_trig_in,

    // Z4.4: el MISMO contador que TRIG_COUNT expone por AXI-Lite, sacado
    // tambien a fabric para la cabecera en banda de `drx_ray_packer`. Se
    // exporta en vez de replicarlo alli porque dos contadores sobre el mismo
    // pulso pueden divergir tras un reset parcial y no habria forma de saber
    // cual de los dos miente.
    output logic [31:0] trig_count_out
);

  // `s_axi_wstrb` no se usa a propósito (ver cabecera); se silencia en vez de
  // dejarlo colgado, mismo patrón que el resto del árbol para puertos sin
  // consumidor (`unused_s_last` en `drx_ddc_top.sv`).
  logic unused_wstrb;
  assign unused_wstrb = &{1'b0, s_axi_wstrb};

  // -----------------------------------------------------------------------
  // Canal de escritura: acepta AW y W de forma independiente (no exige que
  // lleguen en el mismo ciclo, AXI-Lite no lo garantiza) y aplica el registro
  // en el ciclo en que las dos ya están capturadas. Sin outstanding: no se
  // vuelve a aceptar AW/W hasta que B se aceptó.
  // -----------------------------------------------------------------------
  logic                       have_aw;
  logic [REGS_ADDR_WIDTH-1:0] awaddr_r;
  logic                       have_w;
  logic [                31:0] wdata_r;

  logic write_commit;
  assign write_commit = have_aw && have_w;

  assign s_axi_awready = !have_aw && !s_axi_bvalid;
  assign s_axi_wready  = !have_w && !s_axi_bvalid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      have_aw  <= 1'b0;
      awaddr_r <= '0;
    end else if (s_axi_awvalid && s_axi_awready) begin
      have_aw  <= 1'b1;
      awaddr_r <= s_axi_awaddr;
    end else if (write_commit) begin
      have_aw <= 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      have_w  <= 1'b0;
      wdata_r <= '0;
    end else if (s_axi_wvalid && s_axi_wready) begin
      have_w  <= 1'b1;
      wdata_r <= s_axi_wdata;
    end else if (write_commit) begin
      have_w <= 1'b0;
    end
  end

  logic mode_coarse_r;
  logic vector_load_r;
  assign mode_coarse = mode_coarse_r;
  assign vector_load = vector_load_r;

  // El bit 1 no se decodifica: reservado desde v11, lee 0. No se reutiliza
  // para otra cosa a proposito, para que un firmware de v8..v10 que lo
  // escriba no active algo distinto en silencio.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mode_coarse_r <= 1'b0;  // fino, el mismo default que el `ModeCoarse` fijo anterior
      vector_load_r <= 1'b0;  // reproduciendo el bucle precargado
    end else if (write_commit && awaddr_r == REG_CTRL_ADDR) begin
      mode_coarse_r <= wdata_r[0];
      vector_load_r <= wdata_r[2];
    end
  end

  // NCO_PINC (v9, Z4.5): valor de reset = NCO_PHASE_INC, el mismo PINC1 que
  // lleva congelado la IP del DDS Compiler como valor inicial. Sin ninguna
  // escritura, `nco_pinc_we` nunca pulsa, el core nunca recibe configuracion y
  // la cadena es bit a bit la de v8 -- que es lo que permite seguir usando la
  // matriz de D-12 como oraculo del camino sin AFC.
  //
  // El strobe va REGISTRADO, al reves que los `*_clear` de mas abajo, y la
  // diferencia no es de estilo. Aquellos son write-1-to-clear y leen `wdata_r`
  // directamente, asi que el dato que acompana al pulso es correcto en el mismo
  // ciclo. Este no: el consumidor (`drx_ddc_top`) latchea `nco_pinc` con el
  // flanco en que ve `nco_pinc_we`, y `nco_pinc_r` no vale lo nuevo hasta el
  // final de ese ciclo. Con el strobe combinacional, el DDC se llevaba la
  // palabra de la escritura ANTERIOR.
  //
  // No es teoria: medido en placa el 2-oct-2026. Con `NCO_PINC = 0` escrito, el
  // pico del rayo salia donde correspondia a la palabra anterior, y al escribir
  // despues la nominal la salida se fue a cero exacto (|max| = 0) porque el NCO
  // aplico el 0 de antes. Un ciclo de retardo alinea el pulso con el dato.
  logic [31:0] nco_pinc_r;
  logic        nco_pinc_we_r;
  assign nco_pinc    = nco_pinc_r;
  assign nco_pinc_we = nco_pinc_we_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      nco_pinc_r    <= 32'(NCO_PHASE_INC);
      nco_pinc_we_r <= 1'b0;
    end else begin
      nco_pinc_we_r <= write_commit && (awaddr_r == REG_NCO_PINC_ADDR);
      if (write_commit && awaddr_r == REG_NCO_PINC_ADDR) begin
        nco_pinc_r <= wdata_r;
      end
    end
  end

  // Ventana de carga del vector de estimulo (v11): VEC_ADDR / VEC_DATA /
  // VEC_LEN. Es la via por la que el PS escribe los bancos de BRAM de
  // `vector_source` en tiempo de ejecucion, y sustituye entera al camino
  // DDR -> AXI DMA MM2S -> AXI4-Stream que v8 habia construido para lo mismo.
  //
  // Por que un par direccion/dato con autoincremento y no una ventana de
  // memoria direccionable: `REGS_ADDR_WIDTH` son 7 bits, 128 B en total, y no
  // cabe. Un `axi_bram_ctrl` habria pedido un maestro mas en el
  // `axi_interconnect` y un segmento nuevo en el mapa de direcciones. A cambio
  // de eso, una carga de VECTOR_LOOP_LEN muestras son otras tantas escrituras
  // de VEC_DATA, del orden de 1 ms, y ocurre una vez por seleccion de vector.
  //
  // Los cuatro (strobe, direccion, banco y dato) se registran JUNTOS, por la
  // misma razon que `nco_pinc_we` de arriba y con la misma cicatriz detras: el
  // consumidor escribe la memoria en el flanco en que ve el strobe, y un
  // strobe combinacional sobre `write_commit` llegaria acompanado del dato
  // de la escritura anterior.
  //
  // `vec_addr_q` es la direccion ANTES del incremento. Sin ella, la muestra se
  // grabaria una posicion mas alla de donde toca y el vector entero saldria
  // desplazado un sitio -- un fallo que en el espectro solo se ve como una
  // fase distinta, no como un error.
  logic [VecAddrBits-1:0] vec_addr_r;
  logic [VecAddrBits-1:0] vec_addr_q;
  logic [            2:0] vec_bank_r;
  logic [           15:0] vec_data_r;
  logic [VecAddrBits-1:0] vec_len_r;
  logic                   vec_we_r;

  assign vec_addr = vec_addr_q;
  assign vec_bank = vec_bank_r;
  assign vec_data = vec_data_r;
  assign vec_len  = vec_len_r;
  assign vec_we   = vec_we_r;

  logic vec_addr_write;
  logic vec_data_write;
  assign vec_addr_write = write_commit && (awaddr_r == REG_VEC_ADDR_ADDR);
  assign vec_data_write = write_commit && (awaddr_r == REG_VEC_DATA_ADDR);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      vec_addr_r <= '0;
      vec_addr_q <= '0;
      vec_bank_r <= '0;
      vec_data_r <= '0;
      // Reset = la longitud que `$readmemh` precarga de verdad en el
      // bitstream. Un sistema que nunca escriba VEC_LEN reproduce exactamente
      // el bucle de v10 y anteriores.
      vec_len_r  <= VecAddrBits'(VECTOR_LOOP_LEN);
      vec_we_r   <= 1'b0;
    end else begin
      vec_we_r <= vec_data_write;

      if (vec_addr_write) begin
        vec_addr_r <= wdata_r[VecAddrBits-1:0];
        vec_bank_r <= wdata_r[18:16];
      end else if (vec_data_write) begin
        vec_data_r <= wdata_r[15:0];
        vec_addr_q <= vec_addr_r;
        // Envuelve dentro de VecAddrBits y no para al llegar a la
        // profundidad: cargar de mas es un error del que carga, y pararlo
        // aqui costaria un comparador en un camino que ya es el critico del
        // diseno sin evitar el error, solo cambiando su sintoma.
        vec_addr_r <= vec_addr_r + VecAddrBits'(1);
      end

      if (write_commit && awaddr_r == REG_VEC_LEN_ADDR) begin
        vec_len_r <= wdata_r[VecAddrBits-1:0];
      end
    end
  end

  // `overrun_clear[c]` es un pulso combinacional de un solo ciclo: `write_commit`
  // solo está en alto el ciclo en que `have_aw`/`have_w` coinciden (se bajan al
  // ciclo siguiente), así que no hace falta registrarlo aparte.
  always_comb begin
    for (int c = 0; c < N_CH; c++) begin
      overrun_clear[c] = write_commit && (awaddr_r == REG_STATUS_ADDR) && wdata_r[c];
    end
  end

  // `ray_truncated_clear[c]` (BITE, v6): mismo pulso combinacional de un
  // ciclo que `overrun_clear`, sobre REG_GATE_TRUNCATED_ADDR en vez de
  // REG_STATUS_ADDR -- ver la cabecera del módulo sobre por qué es un
  // registro propio y no bits nuevos de STATUS.
  always_comb begin
    for (int c = 0; c < N_CH; c++) begin
      ray_truncated_clear[c] = write_commit && (awaddr_r == REG_GATE_TRUNCATED_ADDR) && wdata_r[c];
    end
  end

  // OVERFLOW: sticky mantenido aquí (ver cabecera del módulo y de
  // `config/registers.toml`), no en `drx_ddc_top`. El `if (overflow_in[c])`
  // antes del `else if` de clear es lo que hace que el set gane sobre un
  // clear concurrente, mismo orden de prioridad que ya usa
  // `drx_range_gate.sv` para `overrun`.
  logic [N_CH-1:0] overflow_sticky_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      overflow_sticky_r <= '0;
    end else begin
      for (int c = 0; c < N_CH; c++) begin
        if (overflow_in[c]) begin
          overflow_sticky_r[c] <= 1'b1;
        end else if (write_commit && (awaddr_r == REG_OVERFLOW_ADDR) && wdata_r[c]) begin
          overflow_sticky_r[c] <= 1'b0;
        end
      end
    end
  end

  // -----------------------------------------------------------------------
  // Z2 (v3, D-13; BINS_LOW/HIGH desde v5, D-15): registros de configuración
  // de drx_timing_engine, todos RW de paso directo salvo TIMING_STATUS
  // (sticky, ver más abajo). Este módulo NO valida nada él mismo --
  // PRF_DIV_*/PULSE_WIDTH/BINS_* se escriben tal cual -- pero drx_timing_engine
  // SÍ valida D-09 completo (tabla, cabe en su propio PRI, PRF x rango, y
  // desde D-15 el techo de bins) y se niega a correr si no se cumple,
  // reportándolo en TIMING_STATUS bits 1/2 (ver más abajo).
  // -----------------------------------------------------------------------
  logic        timing_enable_r;
  logic        timing_paced_r;
  logic [31:0] prf_div_low_r, prf_div_high_r;
  logic [15:0] pulse_width_low_r, pulse_width_high_r;
  logic [15:0] n_pulses_low_r, n_pulses_high_r;
  logic [31:0] bins_low_r, bins_high_r;
  logic [31:0] trig_delay_r[4];
  logic [31:0] trig_width_r[4];

  assign timing_enable    = timing_enable_r;
  assign timing_paced     = timing_paced_r;
  assign prf_div_low      = prf_div_low_r;
  assign prf_div_high     = prf_div_high_r;
  assign pulse_width_low  = pulse_width_low_r;
  assign pulse_width_high = pulse_width_high_r;
  assign n_pulses_low     = n_pulses_low_r;
  assign n_pulses_high    = n_pulses_high_r;
  assign bins_low         = bins_low_r;
  assign bins_high        = bins_high_r;
  assign trig_delay_0     = trig_delay_r[0];
  assign trig_delay_1     = trig_delay_r[1];
  assign trig_delay_2     = trig_delay_r[2];
  assign trig_delay_3     = trig_delay_r[3];
  assign trig_width_0     = trig_width_r[0];
  assign trig_width_1     = trig_width_r[1];
  assign trig_width_2     = trig_width_r[2];
  assign trig_width_3     = trig_width_r[3];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      timing_enable_r    <= 1'b0;
      timing_paced_r     <= 1'b0;  // cuenta ciclos, el comportamiento de v3..v9
      prf_div_low_r       <= '0;
      prf_div_high_r      <= '0;
      pulse_width_low_r   <= '0;
      pulse_width_high_r  <= '0;
      n_pulses_low_r      <= '0;
      n_pulses_high_r     <= '0;
      bins_low_r          <= '0;
      bins_high_r         <= '0;
      for (int t = 0; t < 4; t++) begin
        trig_delay_r[t] <= '0;
        trig_width_r[t] <= '0;
      end
    end else if (write_commit) begin
      unique case (awaddr_r)
        REG_TIMING_CTRL_ADDR: begin
          timing_enable_r <= wdata_r[0];
          timing_paced_r  <= wdata_r[1];
        end
        REG_PRF_DIV_LOW_ADDR: prf_div_low_r <= wdata_r;
        REG_PRF_DIV_HIGH_ADDR: prf_div_high_r <= wdata_r;
        REG_PULSE_WIDTH_ADDR: begin
          pulse_width_low_r  <= wdata_r[15:0];
          pulse_width_high_r <= wdata_r[31:16];
        end
        REG_N_PULSES_ADDR: begin
          n_pulses_low_r  <= wdata_r[15:0];
          n_pulses_high_r <= wdata_r[31:16];
        end
        REG_BINS_LOW_ADDR: bins_low_r <= wdata_r;
        REG_BINS_HIGH_ADDR: bins_high_r <= wdata_r;
        REG_TRIG_DELAY_0_ADDR: trig_delay_r[0] <= wdata_r;
        REG_TRIG_DELAY_1_ADDR: trig_delay_r[1] <= wdata_r;
        REG_TRIG_DELAY_2_ADDR: trig_delay_r[2] <= wdata_r;
        REG_TRIG_DELAY_3_ADDR: trig_delay_r[3] <= wdata_r;
        REG_TRIG_WIDTH_0_ADDR: trig_width_r[0] <= wdata_r;
        REG_TRIG_WIDTH_1_ADDR: trig_width_r[1] <= wdata_r;
        REG_TRIG_WIDTH_2_ADDR: trig_width_r[2] <= wdata_r;
        REG_TRIG_WIDTH_3_ADDR: trig_width_r[3] <= wdata_r;
        default: ;  // resto de direcciones: sin registro que actualizar aquí
      endcase
    end
  end

  // TIMING_STATUS: mismo patrón sticky + W1C que OVERFLOW, set gana sobre un
  // clear concurrente. `radial_done_in` es un pulso de un ciclo (ver la
  // cabecera de drx_prf_batch_seq.sv), de ahí el latch. Bits 1/2 (v4, D-09):
  // mismo patrón sobre `config_invalid_low_in`/`_high_in` (niveles
  // combinacionales, ver cabecera del módulo).
  logic radial_done_sticky_r;
  logic config_invalid_low_sticky_r;
  logic config_invalid_high_sticky_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      radial_done_sticky_r <= 1'b0;
    end else if (radial_done_in) begin
      radial_done_sticky_r <= 1'b1;
    end else if (write_commit && (awaddr_r == REG_TIMING_STATUS_ADDR) && wdata_r[0]) begin
      radial_done_sticky_r <= 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      config_invalid_low_sticky_r <= 1'b0;
    end else if (config_invalid_low_in) begin
      config_invalid_low_sticky_r <= 1'b1;
    end else if (write_commit && (awaddr_r == REG_TIMING_STATUS_ADDR) && wdata_r[1]) begin
      config_invalid_low_sticky_r <= 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      config_invalid_high_sticky_r <= 1'b0;
    end else if (config_invalid_high_in) begin
      config_invalid_high_sticky_r <= 1'b1;
    end else if (write_commit && (awaddr_r == REG_TIMING_STATUS_ADDR) && wdata_r[2]) begin
      config_invalid_high_sticky_r <= 1'b0;
    end
  end

  // TRIG_COUNT (v7, Z4.1): contador libre, sin W1C -- ver cabecera del
  // módulo. Ningún `write_commit` lo toca (RO puro); el `unique case` del
  // canal de escritura ya tiene un `default: ;` que cubre esta dirección sin
  // hacer nada.
  logic [31:0] trig_count_r;
  assign trig_count_out = trig_count_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      trig_count_r <= '0;
    end else if (pulse_trig_in) begin
      trig_count_r <= trig_count_r + 32'd1;
    end
  end

  assign s_axi_bresp = 2'b00;  // OKAY siempre, ver cabecera

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axi_bvalid <= 1'b0;
    end else if (write_commit) begin
      s_axi_bvalid <= 1'b1;
    end else if (s_axi_bvalid && s_axi_bready) begin
      s_axi_bvalid <= 1'b0;
    end
  end

  // -----------------------------------------------------------------------
  // Canal de lectura: mismo principio que el de escritura, sin outstanding.
  // -----------------------------------------------------------------------
  logic                       have_ar;
  logic [REGS_ADDR_WIDTH-1:0] araddr_r;

  logic read_commit;
  assign read_commit = have_ar && !s_axi_rvalid;

  assign s_axi_arready = !have_ar && !s_axi_rvalid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      have_ar  <= 1'b0;
      araddr_r <= '0;
    end else if (s_axi_arvalid && s_axi_arready) begin
      have_ar  <= 1'b1;
      araddr_r <= s_axi_araddr;
    end else if (read_commit) begin
      have_ar <= 1'b0;
    end
  end

  logic [31:0] rdata_next;

  always_comb begin
    rdata_next = 32'h0000_0000;
    unique case (araddr_r)
      REG_VERSION_ADDR: rdata_next = 32'(REGS_VERSION);
      REG_CTRL_ADDR: begin
        rdata_next[0] = mode_coarse_r;
        rdata_next[2] = vector_load_r;
      end
      REG_STATUS_ADDR: begin
        for (int c = 0; c < N_CH; c++) rdata_next[c] = overrun_in[c];
      end
      REG_GATE_TRUNCATED_ADDR: begin
        for (int c = 0; c < N_CH; c++) rdata_next[c] = ray_truncated_in[c];
      end
      REG_TRIG_COUNT_ADDR: rdata_next = trig_count_r;
      REG_NCO_PINC_ADDR: rdata_next = nco_pinc_r;
      REG_VEC_ADDR_ADDR: begin
        rdata_next[VecAddrBits-1:0] = vec_addr_r;
        rdata_next[18:16]           = vec_bank_r;
      end
      // Devuelve la ultima palabra escrita, NO el contenido de la BRAM: la
      // memoria no tiene camino de lectura hacia AXI-Lite, y anadirlo costaria
      // un puerto mas por banco sin comprar nada. Quien quiera verificar una
      // carga, que mida el espectro del rayo.
      REG_VEC_DATA_ADDR: rdata_next[15:0] = vec_data_r;
      REG_VEC_LEN_ADDR:  rdata_next[VecAddrBits-1:0] = vec_len_r;
      REG_OVERFLOW_ADDR: begin
        for (int c = 0; c < N_CH; c++) rdata_next[c] = overflow_sticky_r[c];
      end
      REG_TIMING_CTRL_ADDR: begin
        rdata_next[0] = timing_enable_r;
        rdata_next[1] = timing_paced_r;
      end
      REG_TIMING_STATUS_ADDR: begin
        rdata_next[0] = radial_done_sticky_r;
        rdata_next[1] = config_invalid_low_sticky_r;
        rdata_next[2] = config_invalid_high_sticky_r;
      end
      REG_PRF_DIV_LOW_ADDR: rdata_next = prf_div_low_r;
      REG_PRF_DIV_HIGH_ADDR: rdata_next = prf_div_high_r;
      REG_PULSE_WIDTH_ADDR: rdata_next = {pulse_width_high_r, pulse_width_low_r};
      REG_N_PULSES_ADDR: rdata_next = {n_pulses_high_r, n_pulses_low_r};
      REG_BINS_LOW_ADDR: rdata_next = bins_low_r;
      REG_BINS_HIGH_ADDR: rdata_next = bins_high_r;
      REG_TRIG_DELAY_0_ADDR: rdata_next = trig_delay_r[0];
      REG_TRIG_DELAY_1_ADDR: rdata_next = trig_delay_r[1];
      REG_TRIG_DELAY_2_ADDR: rdata_next = trig_delay_r[2];
      REG_TRIG_DELAY_3_ADDR: rdata_next = trig_delay_r[3];
      REG_TRIG_WIDTH_0_ADDR: rdata_next = trig_width_r[0];
      REG_TRIG_WIDTH_1_ADDR: rdata_next = trig_width_r[1];
      REG_TRIG_WIDTH_2_ADDR: rdata_next = trig_width_r[2];
      REG_TRIG_WIDTH_3_ADDR: rdata_next = trig_width_r[3];
      default: rdata_next = 32'h0000_0000;  // dirección reservada: lee 0
    endcase
  end

  assign s_axi_rresp = 2'b00;  // OKAY siempre, ver cabecera

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axi_rvalid <= 1'b0;
      s_axi_rdata  <= '0;
    end else if (read_commit) begin
      s_axi_rvalid <= 1'b1;
      s_axi_rdata  <= rdata_next;
    end else if (s_axi_rvalid && s_axi_rready) begin
      s_axi_rvalid <= 1'b0;
    end
  end

endmodule : drx_axil_regs

`endif  // DRX_AXIL_REGS_SV
