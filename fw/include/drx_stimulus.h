/* Carga de vectores de estimulo en la BRAM de la PL por AXI-Lite (mapa v11).
 *
 * Cierra el camino que empieza en el mensaje `test_stimulus_select` del
 * contrato y termina en los bancos de BRAM de `rtl/vector_source.sv`:
 *
 *   DSP --test_stimulus_select--> drx_contract_io --> DrxStimulus_Select()
 *     --> VEC_ADDR/VEC_DATA/VEC_LEN --> BRAM de vector_source
 *     --> DDC --> range gate
 *
 * Antes de Z4.3 el vector quedaba fijado en tiempo de SINTESIS (`$readmemh`
 * sobre la misma BRAM), asi que barrer el catalogo de ocho casos costaba ocho
 * corridas de Vivado. Z4.3 lo hizo elegible en caliente metiendolo por un AXI
 * DMA MM2S desde la DDR; el 4-oct-2026 ese camino se retiro por P-16 (ver la
 * cabecera de drx_stimulus.c) y lo sustituyo esta ventana de registros. El
 * catalogo sigue costando ocho mensajes, y ahora ademas sale a tasa plena.
 *
 * El catalogo lo genera `tools/gen_stimulus_catalog.py` a partir de los MISMOS
 * ocho casos de `tools/gen_l1_vectors.py` que nombra la enumeracion
 * `stimulus_vector` del contrato; `vector_id` es el indice en esa lista.
 */
#ifndef DRX_STIMULUS_H
#define DRX_STIMULUS_H

#include <stdbool.h>
#include <stdint.h>

#include "drx_dsp_v0_1.h"
#include "drx_params.h"

/* Canales que `drx_top` instancia (Config A/B de P-12: Tx burst + dos Rx).
 *
 * Z4.3 lo tenia escrito a mano aqui y en `rtl/drx_top.sv`, sin nada que
 * comparara los dos; si divergian no habia ningun error, solo un espectro raro
 * en la placa. Desde Z4.4 el numero sale de `config/params.toml` (`n_ch_top`)
 * para los dos lados, y ademas la cabecera en banda del rayo lo lleva, asi que
 * `drx_ray.c` lo comprueba contra el bitstream cargado en runtime. */
#define DRX_STIMULUS_N_CH ((uint32_t)DRX_N_CH_TOP)

/* Comprueba que el bitstream trae la ventana de carga y fija la base de
 * tiempo del motor. Una vez, al arrancar el firmware. Devuelve false y lo
 * explica por UART si VERSION no coincide con el mapa que este firmware
 * conoce -- en un bitstream de v10 o anterior las tres direcciones de la
 * ventana estan reservadas y las escrituras no tendrian ningun efecto. */
bool DrxStimulus_Init(void);

/* Carga el vector `vector_id` en la BRAM y lo deja sonando en bucle.
 *
 * `repeat` TIENE que ser 0 (bucle indefinido). La BRAM reproduce en bucle por
 * hardware y no hay nada que cuente pasadas, asi que un `repeat` distinto se
 * contesta `unimplemented` en vez de aceptarse y reproducir indefinidamente
 * -- el par remoto que pidio dos pasadas se enteraria de que no se cumplio
 * solo mirando el espectro. Hasta v10 el conteo lo llevaba una tarea que
 * rearmaba el DMA entre pasadas; ese DMA ya no existe.
 *
 * Devuelve el codigo del contrato con el que contestar: `ok`,
 * `vector_unknown` si `vector_id` no esta en el catalogo, `unimplemented` si
 * `repeat` no es 0, o `not_configured` si DrxStimulus_Init() no ha corrido o
 * fallo. */
drx_dsp_error_t DrxStimulus_Select(uint8_t vector_id, uint16_t repeat);

/* Marca que ya no hay vector seleccionado. Seguro de llamar aunque no hubiera
 * nada en curso.
 *
 * NO para la fuente, y es un cambio de semantica frente a v8..v10: aquel Stop
 * devolvia `vector_source` a BRAM-loop con el tono que `$readmemh` dejo en el
 * bitstream. Ahora la BRAM se queda con el ultimo vector cargado sonando,
 * porque el `$readmemh` solo corre al cargar el bitstream y no hay forma de
 * recuperarlo por software. Para volver al tono nominal, cargar el vector
 * `tono_if` (id 0), que es el mismo. */
void DrxStimulus_Stop(void);

/* Estado para la tarea de diagnostico. `name` es NULL si nunca se selecciono
 * ningun vector. */
typedef struct {
    const char *name;
    uint8_t vector_id;
    uint16_t remaining;   /* siempre 0: la BRAM reproduce en bucle indefinido */
    bool looping;         /* siempre true mientras haya un vector cargado */
    bool running;
    uint32_t loads;       /* vectores cargados con exito desde el arranque */
    uint32_t errors;      /* cargas que no se pudieron completar */
} DrxStimulusStatus;

void DrxStimulus_GetStatus(DrxStimulusStatus *out);

/* No-op desde v11. Era la tarea que rearmaba el DMA entre pasadas; con la
 * BRAM en bucle por hardware no hay nada que rearmar. Se conserva el simbolo
 * para no tocar el arranque de main.c por una funcion vacia. */
void DrxStimulusTask_Create(void);

/* Comprobacion de bring-up de la ventana de carga, para correr una vez al
 * arrancar y antes de que haya un DSP al otro lado.
 *
 * Carga el vector y RELEE VEC_LEN y CTRL por AXI-Lite. Eso dice que las tres
 * direcciones existen en este bitstream, que el slave acepto las escrituras y
 * que el lector quedo suelto.
 *
 * Lo que NO dice es si el CONTENIDO de la BRAM es el correcto: la memoria no
 * tiene camino de lectura hacia AXI-Lite. Esto es MAS DEBIL que la
 * comprobacion de v8..v10, donde una pasada completa del DMA probaba que los
 * bytes habian llegado dentro de la PL porque el unico que levantaba `tready`
 * era `vector_source`. La prueba del dato es ahora el espectro del rayo
 * contra el modelo dorado (DrxRay_SelfTest + tools/dump_ray.py), que es de
 * todas formas la que de verdad importa.
 *
 * De paso informa de OVERFLOW antes y despues: el catalogo trae un vector a
 * +6 dBFS pensado para saturar. Se informa, no se exige -- que un vector
 * concreto llegue a saturar la salida del DDC depende del ajuste de ganancia
 * de la cadena y no esta medido en placa todavia. */
bool DrxStimulus_SelfTest(uint8_t vector_id);

#endif /* DRX_STIMULUS_H */
