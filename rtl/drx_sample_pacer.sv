// Reloj de muestras para el motor de timing — cierre de P-16.
//
// EL PROBLEMA. `drx_prf_batch_seq` cuenta CICLOS DE RELOJ: un PRI dura
// `prf_div` ciclos de `fs` (D-13), y `ray_start` corta el rayo ahí (D-14). La
// cadena del DDC, en cambio, avanza solo con `valid`. Mientras la fuente
// entregue una muestra por ciclo las dos cosas son la misma, y por eso nadie
// lo había notado. En Throttled(DDR) no lo son: `vector_source` junta N_CH
// beats de 16 bits para formar un conjunto, así que presenta un conjunto cada
// N_CH+1 ciclos como mucho. Con N_CH = 3 el rayo tarda ~4 PRI en llenarse,
// `ray_start` lo trunca antes, `GATE_TRUNCATED` sube y no se completa ni un
// rayo. Ninguna de las dos piezas está mal; la combinación no estaba
// contemplada.
//
// LA IDEA. Que el motor cuente AVANCES DE MUESTRA en vez de ciclos. Las dos
// mitades se frenan entonces con el mismo factor y el rayo se llena con los
// mismos `prf_div / R1` bins a cualquier tasa. En tiempo real `valid` está
// siempre alto, así que un avance es un ciclo y el motor se comporta
// exactamente como antes -- no por argumento, por construcción: con
// `advance` constante a 1 los `always_ff` gateados son los de siempre y la
// síntesis colapsa el enable.
//
// POR QUÉ UN MÓDULO PARA TRES LÍNEAS. Porque la definición de "un avance" es
// la decisión entera, y conviene que tenga un sitio con nombre donde
// discutirse y un L0 propio. El resto del cambio en el motor es un puerto por
// módulo.
//
// QUÉ CUENTA COMO AVANCE: que el conjunto de N_CH muestras se retire, o sea
// `valid && ready` en TODOS los canales a la vez. No el de un canal suelto:
// `vector_source` mueve los N_CH en bloque a propósito (ver su cabecera) y
// `drx_ddc_quad_top` es un `generate` de cadenas idénticas, así que en la
// práctica suben juntos; pero si alguna vez dejaran de hacerlo, contar por el
// canal 0 adelantaría el motor respecto de los canales lentos y el desfase no
// daría ningún error visible. El AND es la lectura conservadora.
//
// LO QUE ESTO NO HACE. No convierte Throttled(DDR) en una fuente de tiempo
// real. Cierra el barrido del catálogo de estímulos contra rayos reales, que
// es lo que P-16 bloqueaba. No valida nada que dependa de la tasa -- rayos/s,
// caudal del transporte, temporización del anillo del DMA --; eso sigue
// midiéndose en BRAM-loop.

`ifndef DRX_SAMPLE_PACER_SV
`define DRX_SAMPLE_PACER_SV

module drx_sample_pacer #(
    parameter int N_CH = 3
) (
    // 0 = el motor cuenta ciclos, el comportamiento de v1..v9. Valor de reset
    // del registro que lo alimenta (TIMING_CTRL bit 1, mapa v10), para que un
    // sistema que nunca lo escriba se comporte como antes.
    //
    // No se deriva de `vector_source_ddr` aunque hoy sea el único modo que lo
    // necesita: atarlos escondería un grado de libertad que hace falta para
    // aislar un fallo -- poder correr DDR sin pacear, o pacear en BRAM-loop,
    // es justo lo que distingue "el pacer está mal" de "el modo DDR está mal".
    input logic paced,

    // Handshake de la fuente de muestras hacia el DDC.
    //
    // Buses EMPAQUETADOS, no los arrays desempaquetados que usan el resto de
    // puertos por canal de esta cadena: Verilator/cocotb (VPI
    // `--public-flat-rw`) no expone un array de escalares como objeto
    // indexable, asi que un banco L0 no puede ni escribirlos -- mismo
    // hallazgo, misma solucion que `trig_out` en `drx_trigger_gen.sv`
    // (`IndexError: valid(GPI_REGISTER) contains no object at index 0`). El
    // empaquetado lo hace `drx_top`, que es de todas formas quien tiene los
    // dos formatos a la vista.
    input logic [N_CH-1:0] valid,
    input logic [N_CH-1:0] ready,

    output logic advance
);

  assign advance = paced ? &(valid & ready) : 1'b1;

endmodule : drx_sample_pacer

`endif  // DRX_SAMPLE_PACER_SV
