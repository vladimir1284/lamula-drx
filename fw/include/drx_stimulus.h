/* Carga de vectores de estimulo en la PL por AXI DMA MM2S (Z4.3).
 *
 * Cierra el camino que empieza en el mensaje `test_stimulus_select` del
 * contrato (v0.5) y termina en el modo Throttled(DDR) de `rtl/vector_source.sv`
 * (`CTRL` bit 1 del mapa de registros v8):
 *
 *   DSP --test_stimulus_select--> drx_contract_io --> DrxStimulus_Select()
 *     --> buffer entrelazado en DDR --> AXI DMA MM2S --> m_axis_vec
 *     --> vector_source --> DDC --> range gate
 *
 * Antes de esto el vector quedaba fijado en tiempo de SINTESIS (`$readmemh`
 * sobre la BRAM), asi que barrer el catalogo de ocho casos costaba ocho
 * corridas de Vivado. Ahora cuesta ocho mensajes.
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

/* Canales que `drx_top` instancia (`parameter int N_CH = 3`, Config A/B de
 * P-12: Tx burst + dos Rx).
 *
 * ESTE NUMERO NO SALE DEL PAQUETE DE PARAMETROS, y es la unica constante de
 * este fichero que no sale de `drx_params.h`. `N_CH` vive hoy solo como valor
 * por defecto de un `parameter` de SystemVerilog en `rtl/drx_top.sv`, no en
 * `config/params.toml`. Si los dos divergen no hay ningun error: el buffer se
 * entrelaza con un paso distinto del que `vector_source` deshace, cada canal
 * recibe muestras del vector corridas respecto de las suyas, y en la placa eso
 * se ve como un espectro raro sin ninguna pista de donde viene. Cambiar `N_CH`
 * en el RTL obliga a cambiarlo aqui. */
#define DRX_STIMULUS_N_CH 3u

/* Arranca el driver del DMA y construye el anillo de descriptores. Una vez, al
 * arrancar el firmware. Devuelve false y lo explica por UART si el DMA no esta
 * donde el XSA dice, si el canal MM2S no esta compilado en el bitstream, o si
 * el anillo no cabe. */
bool DrxStimulus_Init(void);

/* Carga el vector `vector_id` y lo reproduce `repeat` veces; 0 = en bucle
 * indefinido, el mismo comportamiento que tenia el modo BRAM-loop. Pone
 * `CTRL` bit 1 a 1 (modo Throttled(DDR)) antes del primer beat.
 *
 * Devuelve el codigo del contrato con el que contestar: `ok`,
 * `vector_unknown` si `vector_id` no esta en el catalogo, o `not_configured`
 * si DrxStimulus_Init() no ha corrido o fallo. */
drx_dsp_error_t DrxStimulus_Select(uint8_t vector_id, uint16_t repeat);

/* Para la reproduccion y devuelve `vector_source` a BRAM-loop (`CTRL` bit 1 a
 * 0). Seguro de llamar aunque no hubiera nada en curso. */
void DrxStimulus_Stop(void);

/* Estado para la tarea de diagnostico. `name` es NULL si nunca se selecciono
 * ningun vector. */
typedef struct {
    const char *name;
    uint8_t vector_id;
    uint16_t remaining;   /* pasadas que faltan; 0 con `looping` = indefinido */
    bool looping;
    bool running;
    uint32_t passes;      /* pasadas completadas desde el ultimo Select */
    uint32_t errors;      /* transferencias que el DMA marco como fallidas */
} DrxStimulusStatus;

void DrxStimulus_GetStatus(DrxStimulusStatus *out);

/* Crea la tarea de FreeRTOS que rearma el DMA entre pasadas. Hay que crearla
 * para que `repeat` distinto de 1 signifique algo. */
void DrxStimulusTask_Create(void);

/* Comprobacion de bring-up del camino DDR -> MM2S -> vector_source, para
 * correr una vez al arrancar y antes de que haya un DSP al otro lado.
 *
 * El criterio es que una pasada del DMA se COMPLETE, y eso no es un detalle de
 * contabilidad: el stream tiene backpressure y el unico que levanta
 * `m_axis_vec_tready` es `vector_source` en modo Throttled(DDR) consumiendo
 * beats. Si el modo no estuviera puesto, si el ancho del stream no cuadrara o
 * si el conjunto de N_CH no se llenara, el DMA se quedaria a medias y la
 * pasada no contaria. Una pasada completa es por tanto prueba de que los
 * bytes llegaron de la DDR hasta dentro de la PL, sin necesidad de leer
 * ningun rayo -- que es Z4.4.
 *
 * De paso informa de OVERFLOW antes y despues, que es lo que mas se parece a
 * mirar el DATO sin tener todavia camino de vuelta: el catalogo trae un vector
 * a +6 dBFS pensado para saturar. Se informa, no se exige: que un vector
 * concreto llegue a saturar la salida del DDC depende del ajuste de ganancia
 * de la cadena y no esta medido en placa todavia. */
bool DrxStimulus_SelfTest(uint8_t vector_id);

#endif /* DRX_STIMULUS_H */
