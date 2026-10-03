// Secuenciador de 2 lotes de PRF/ancho de pulso por radial — Z2 (fases.md#z2),
// Batch mode de NEXRAD, D-13. Es el primer RTL custom del motor de timing:
// equivalente en hardware de `model/drx_model/timing.py` (`Batch` +
// `RadialBatches(low, high)`), verificado bit a bit contra ese modelo en
// `sim/tb/tb_drx_prf_batch_seq.py` (D-03).
//
// D-13 fija exactamente 2 lotes -- no una tabla de N entradas por sector, como
// especulaba P-04 -- y exige que la alternancia se secuencie de forma AUTÓNOMA
// en fabric: el RCP no puede comandarla en vivo por 1GbE a la cadencia de un
// radial (10-15 ms de dwell). Por eso este módulo no tiene ningún puerto de
// "siguiente lote": una vez armado con `enable`, recorre lote bajo -> lote alto
// -> lote bajo... solo, para siempre, sin intervención externa.
//
// Convención de PRI: un lote de `n_pulses` pulsos con divisor `prf_div` ocupa
// exactamente `n_pulses * prf_div` ciclos de `fs` (`Batch.dwell_cycles()` en el
// modelo). `pulse_trig` sube un ciclo en cada frontera de PRI, empezando en el
// ciclo 0 tras `enable` -- igual que `trigger_times_cycles(batch, start_cycle=0)`
// en el modelo, que arranca la lista en `start_cycle`. El lote alto empieza
// justo cuando el bajo termina, sin hueco: no hay guarda de sincronización
// porque `batch_sel` conmuta en el mismo flanco que `pri_cnt` vuelve a 0, así
// que el PRI del primer pulso del lote nuevo ya usa el divisor del lote nuevo
// (ver el cuerpo de `always_ff` para el porqué exacto de ese orden).
//
// Lo que este módulo NO hace, a propósito: no valida nada él mismo -- ni PRF x
// rango (D-09) ni que `pulse_width` quepa en su propio PRI. Un `Batch` del
// modelo dorado rechaza esas combinaciones en construcción; aquí se asume que
// quien escribe estos registros ya pasó por ese validador -- esta pieza no
// vuelve a comprobar un invariante de un límite del sistema.
//
// Desde el 22-sep-2026 (más tarde) el `enable` que este módulo recibe YA viene
// gateado un nivel arriba, en `drx_timing_engine.sv`, contra
// `drx_timing_config_valid.sv` (D-09 completo desde el 25-sep: tabla, cabe en
// el PRI, PRF x rango, y desde D-15 también el techo de `bins`). Este módulo
// sigue sin saber nada de eso; desde su punto de vista `enable` simplemente
// está en 0 mientras el lote activo sea inválido.
//
// `bin_count` (D-15, 25-sep-2026): mismo mux que `pulse_width` -- el conteo
// de bins de range-gate es configurable POR LOTE (viene de DSP, que a su vez
// lo recibe de RCP según el VCP: la proporción entre el lote bajo y el alto
// nunca es la misma). Este módulo no interpreta el valor, solo lo pasa a
// través seleccionado por `batch_sel`, igual que ya hace con `pulse_width`.
// Se llama `bin_count`, no `bins`: SystemVerilog reserva `bins` como palabra
// clave de coverpoints/randomize, Verilator lo rechaza como identificador.

`ifndef DRX_PRF_BATCH_SEQ_SV
`define DRX_PRF_BATCH_SEQ_SV

module drx_prf_batch_seq #(
    parameter int PrfDivBits    = 32,  // cubre PRF_DIV_MAX = 1.250.000 (D-02, params.toml)
    parameter int PulseWidthBits = 16,  // cubre los 825 ciclos de PULSE_WIDTH_CYCLES[2]
    parameter int NPulsesBits   = 16,  // margen de sobra sobre los ~40 pulsos de un lote Doppler
    parameter int BinsBits      = 32   // cubre BINS_MODE_FINE = 3689 de sobra (D-15)
) (
    input logic clk,
    input logic rst_n,

    // Arranca/para el secuenciador completo. Los registros de configuración de
    // abajo solo son seguros de cambiar con `enable` en bajo -- este módulo no
    // los vuelve a leer hasta el primer pulso tras rearmar, así que un cambio
    // a mitad de radial no corrompe un lote ya en curso, pero sí puede dejar
    // el radial en curso con una mezcla de configuración vieja y nueva; eso es
    // responsabilidad de quien controla `enable`, no de este módulo.
    input logic enable,

    // P-16: un "paso" del secuenciador. Con `advance` constante a 1 este
    // modulo es exactamente el de v1..v9 -- `prf_div` cuenta ciclos de `fs`,
    // como dice la convencion de PRI de arriba. Con `advance` paceado por el
    // avance de muestras (`drx_sample_pacer.sv`), `prf_div` cuenta MUESTRAS,
    // que es lo mismo mientras la fuente entregue una por ciclo y lo correcto
    // cuando no.
    //
    // Es un paso, NO un armado: `enable` sigue decidiendo si el secuenciador
    // corre, y es `enable` -- no `advance` -- quien borra `width_cnt`. Juntar
    // los dos conceptos dejaria `tx_gate` en pulsos de un ciclo cada vez que
    // la fuente se frena, que es precisamente el caso para el que existe.
    input logic advance,

    // Lote bajo: vigilancia, PRF baja, pocos pulsos, rango largo (D-13).
    input logic [ PrfDivBits-1:0] prf_div_low,
    input logic [PulseWidthBits-1:0] pulse_width_low,
    input logic [ NPulsesBits-1:0] n_pulses_low,

    // Lote alto: Doppler, PRF alta, muchos pulsos, rango corto (D-13).
    input logic [ PrfDivBits-1:0] prf_div_high,
    input logic [PulseWidthBits-1:0] pulse_width_high,
    input logic [ NPulsesBits-1:0] n_pulses_high,

    // Conteo de bins de range-gate por lote (D-15) -- ver la cabecera.
    input logic [BinsBits-1:0] bins_low,
    input logic [BinsBits-1:0] bins_high,

    output logic pulse_trig,  // 1 ciclo, en cada frontera de PRI (cada pulso, de cualquier lote)
    output logic batch_sel,  // 0 = lote bajo, 1 = lote alto; válido junto con pulse_trig
    output logic [PulseWidthBits-1:0] pulse_width,  // ancho de registro del lote activo
    output logic [BinsBits-1:0] bin_count,  // conteo de bins de range-gate del lote activo (D-15)
    output logic tx_gate,  // nivel alto durante `pulse_width` ciclos de `fs`, un ciclo después de pulse_trig
    output logic radial_done  // 1 ciclo: el lote alto acaba de completarse, empieza un radial nuevo
);

  logic [PrfDivBits-1:0] prf_div_sel;
  logic [NPulsesBits-1:0] n_pulses_sel;

  assign prf_div_sel  = batch_sel ? prf_div_high : prf_div_low;
  assign n_pulses_sel = batch_sel ? n_pulses_high : n_pulses_low;
  assign pulse_width  = batch_sel ? pulse_width_high : pulse_width_low;
  assign bin_count    = batch_sel ? bins_high : bins_low;

  logic [PrfDivBits-1:0] pri_cnt;
  logic [NPulsesBits-1:0] pulse_idx;

  // `pulse_trig` es puramente combinacional sobre `pri_cnt` (no un registro
  // propio): así el primer pulso cae exactamente en el ciclo 0 tras salir de
  // reset/rearmar, igual que `start_cycle=0` en el modelo, sin un ciclo de
  // latencia de más que el modelo no tiene.
  // `advance` entra TAMBIEN aqui, no solo en los `always_ff`: `pri_cnt` se
  // queda en 0 durante todos los ciclos en que el motor no avanza, asi que sin
  // este termino `pulse_trig` saldria ancho en vez de un ciclo -- y lo
  // consumen `ray_start` (D-14) y el contador TRIG_COUNT, que contarian varias
  // veces el mismo pulso de PRF.
  assign pulse_trig = enable && advance && (pri_cnt == '0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pri_cnt     <= '0;
      pulse_idx   <= '0;
      batch_sel   <= 1'b0;  // un radial siempre arranca por el lote bajo (D-13)
      radial_done <= 1'b0;
    end else if (enable && advance) begin
      radial_done <= 1'b0;
      if (pri_cnt == prf_div_sel - 1) begin
        pri_cnt <= '0;
        // Este es el último ciclo del PRI que arrancó con `pulse_idx` pulsos ya
        // disparados en este lote (incluido el que empezó ese PRI). Si ese fue
        // el último pulso del lote, `batch_sel` conmuta AQUÍ -- en el mismo
        // flanco que resetea `pri_cnt` a 0 -- así que el PRI del pulso que
        // arranca el próximo ciclo (pri_cnt==0, pulse_trig sube) ya lee
        // `prf_div_sel`/`n_pulses_sel` del lote NUEVO. El pulso que se acaba de
        // completar, en cambio, ya corrió su PRI entero con el lote VIEJO,
        // porque `prf_div_sel` no cambió hasta este flanco. Es la razón entera
        // de que no haga falta ningún hueco ni guarda extra entre lotes.
        if (pulse_idx == n_pulses_sel - 1) begin
          pulse_idx <= '0;
          batch_sel <= ~batch_sel;
          radial_done <= batch_sel;  // solo al cerrar el lote ALTO empieza un radial nuevo
        end else begin
          pulse_idx <= pulse_idx + 1'b1;
        end
      end else begin
        pri_cnt <= pri_cnt + 1'b1;
      end
    end
  end

  // `tx_gate`: registrado, un ciclo de latencia detrás de `pulse_trig` a
  // propósito (evita meter el ancho de pulso, que depende de `batch_sel` ya
  // actualizado, en el mismo camino combinacional que alimenta la salida de
  // trigger). El ancho es siempre el del lote al que pertenece el pulso que
  // acaba de empezar: `pulse_width` ya lee `batch_sel` post-conmutación el
  // mismo ciclo que `pulse_trig` sube, así que el valor cargado aquí es
  // correcto aunque se lea un ciclo después.
  logic [PulseWidthBits-1:0] width_cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      width_cnt <= '0;
    end else if (!enable) begin
      width_cnt <= '0;
    end else if (advance) begin
      if (pulse_trig) begin
        width_cnt <= pulse_width;
      end else if (width_cnt != '0) begin
        width_cnt <= width_cnt - 1'b1;
      end
    end
  end

  assign tx_gate = (width_cnt != '0);

endmodule : drx_prf_batch_seq

`endif  // DRX_PRF_BATCH_SEQ_SV
