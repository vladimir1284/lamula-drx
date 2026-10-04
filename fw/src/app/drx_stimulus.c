/* Implementacion de fw/include/drx_stimulus.h.
 *
 * Carga el vector de estimulo en los bancos de BRAM de `rtl/vector_source.sv`
 * por la ventana AXI-Lite del mapa de registros v11 (CTRL bit 2 +
 * VEC_ADDR/VEC_DATA/VEC_LEN). Ni DMA, ni descriptores, ni buffer en DDR, ni
 * tarea que rearme nada: la BRAM reproduce en bucle por hardware hasta que
 * alguien cargue otra cosa.
 *
 * --- Por que ya no hay DMA ------------------------------------------------
 *
 * Entre Z4.3 (1-oct-2026) y el 4-oct-2026 esto era otra cosa: el vector vivia
 * en un buffer entrelazado en DDR y llegaba a la PL por el canal MM2S de un
 * AXI DMA en scatter-gather, con una tarea de FreeRTOS que rearmaba la
 * transferencia entre pasadas. Funcionaba -- el DMA completaba pasadas
 * enteras y eso probaba que los bytes llegaban a la PL -- pero el DATO salia
 * mal: `vector_source` junta N_CH beats de 16 bits por conjunto, o sea una
 * muestra cada N_CH ciclos, y el DDS Compiler no tiene `aclken`, asi que
 * avanza un paso de fase por ciclo de reloj mire o no `valid`. El DDC mezclaba
 * a ~N_CH veces el IF y la salida caia al suelo de ruido: -87,3 dBFS medidos
 * contra -9,02 del modelo dorado (P-16, 3-oct-2026).
 *
 * Desde BRAM la fuente entrega una muestra por ciclo y las dos bases de tiempo
 * vuelven a coincidir. Eso tambien hace innecesario el pacing del motor de
 * timing (TIMING_CTRL bit 1): paceado y sin pacear son el mismo circuito
 * cuando no hay huecos, y 0 es la configuracion ya medida buena en placa.
 *
 * Esto NO arregla la causa raiz. El DDS sigue sin `aclken` y volvera a romper
 * el dia que haya una fuente con huecos de verdad (ADC real, ZU9). Ver P-16.
 *
 * --- Lo que se perdio por el camino ---------------------------------------
 *
 * Con el canal MM2S fuera del block design, nada en el diseno ejercita ya el
 * camino DMA PS->PL. Era la unica cobertura que habia de ese sentido. Decision
 * explicita, no un descuido.
 *
 * Tambien desaparece el mecanismo entero donde vivia P-21 (el MM2S se atascaba
 * de forma permanente tras unas pocas selecciones encadenadas). P-21 queda
 * aparcado, no cerrado: el bug no esta ni arreglado ni entendido, solo
 * inalcanzable. Evidencia en docs/implementacion/evidencia/p-21/.
 */
#include "drx_stimulus.h"

#include "drx_regs.h"
#include "drx_regs_hw.h"
#include "drx_stimulus_catalog.h"

#include "xil_printf.h"

#include <string.h>

/* El catalogo se genera con la misma longitud que el bucle precargado en el
 * bitstream (`vector_loop_len` de config/params.toml, via
 * tools/gen_stimulus_catalog.py). Si divergieran, un vector cargado sonaria
 * con una longitud distinta a la que VEC_LEN dice, y el espectro saldria con
 * faldas alrededor del tono sin ningun error de por medio. */
#if DRX_STIMULUS_DEPTH != DRX_VECTOR_LOOP_LEN
#error "el catalogo y vector_loop_len tienen que medir lo mismo"
#endif
#if DRX_STIMULUS_DEPTH > (DRX_VECTOR_BRAM_DEPTH - 1)
#error "un vector del catalogo no cabe en el banco de BRAM"
#endif

static bool g_ready;
static DrxStimulusStatus g_status;

/* Escribe el vector en los N_CH bancos a la vez y lo deja sonando.
 *
 * Difusion (banco 7) y no tres pasadas: los bancos son independientes en RTL
 * -- un estimulo distinto por canal, que es lo que Config A (Tx + H + V) va a
 * pedir algun dia, es llamar a esto tres veces con banco 0, 1 y 2 -- pero hoy
 * los tres llevan la misma forma de onda y escribirla una vez cuesta un tercio.
 *
 * DRX_STIMULUS_DEPTH escrituras AXI-Lite de 32 bits. Con el bus de registros
 * del PS7 eso es del orden de milisegundos, y ocurre una vez por seleccion de
 * vector: no hay nada que optimizar aqui. Una ventana de memoria direccionable
 * habria necesitado un axi_bram_ctrl, un maestro mas en el interconnect y un
 * segmento nuevo en el mapa de direcciones, para ahorrar unos milisegundos que
 * nadie estaba esperando. */
static bool cargar_vector(const DrxStimulusVector *vector)
{
    DrxReg_VecSetLoad(true);
    DrxReg_VecSetAddr(DRX_REG_VEC_ADDR_BANK_ALL, 0u);

    for (size_t i = 0u; i < vector->count; i++) {
        DrxReg_VecWrite(vector->samples[i]);
    }

    if (!DrxReg_VecSetLen((uint32_t)vector->count)) {
        /* El lector se queda congelado a proposito: con una longitud que no
         * se pudo fijar, soltarlo reproduciria el vector nuevo con la
         * longitud del anterior. Silencio es un sintoma mejor que un
         * espectro plausible y equivocado. */
        return false;
    }

    /* Al bajar, `vector_source` deja el puntero de lectura en la muestra 0:
     * la reproduccion empieza siempre en un punto conocido, y por tanto el
     * rayo que se compare contra el modelo dorado arranca igual en cada
     * seleccion. */
    DrxReg_VecSetLoad(false);
    return true;
}

bool DrxStimulus_Init(void)
{
    memset(&g_status, 0, sizeof(g_status));
    g_ready = false;

    /* Confirmar el mapa antes de escribir la ventana: si el bitstream es de
     * v10 o anterior, VEC_ADDR/VEC_DATA/VEC_LEN son direcciones reservadas,
     * las escrituras no tienen efecto y la carga fallaria en silencio. */
    if (!DrxReg_SelfTest()) {
        xil_printf("drx_stimulus: mapa de registros desincronizado, "
                   "la ventana de carga no existe en este bitstream\r\n");
        return false;
    }

    /* La fuente entrega una muestra por ciclo, asi que ciclos y avances de
     * muestra son lo mismo y el pacing no compra nada. Se fija a 0 una vez,
     * aqui, en vez de en cada Select: es una propiedad de la FUENTE, y la
     * fuente ya no cambia en tiempo de ejecucion.
     *
     * Con el secuenciador parado, porque pacear cambia lo que significa
     * `prf_div` y hacerlo a mitad de radial deja ese radial con dos bases de
     * tiempo. */
    const bool timing_corria = DrxReg_TimingEnabled();
    if (timing_corria) {
        DrxReg_TimingDisable();
    }
    DrxReg_TimingSetPaced(false);
    if (timing_corria) {
        DrxReg_TimingEnable();
    }

    g_ready = true;
    return true;
}

drx_dsp_error_t DrxStimulus_Select(uint8_t vector_id, uint16_t repeat)
{
    if (!g_ready) {
        return DRX_DSP_ERROR_NOT_CONFIGURED;
    }
    if (vector_id >= DRX_STIMULUS_COUNT) {
        return DRX_DSP_ERROR_VECTOR_UNKNOWN;
    }

    /* `repeat` distinto de 0 ya no tiene mecanismo: la BRAM reproduce en
     * bucle por hardware y no hay nada que cuente pasadas. Contestar
     * `unimplemented` -- que el contrato v0.8 ya define -- es mejor que
     * aceptarlo y reproducir indefinidamente: el par remoto que pidio dos
     * pasadas se enteraria de que no se cumplio solo mirando el espectro.
     *
     * El barrido del catalogo (tools/sweep_catalogo.py) usa repeat=0, que es
     * el unico caso que hubo nunca en placa. */
    if (repeat != 0u) {
        return DRX_DSP_ERROR_UNIMPLEMENTED;
    }

    const DrxStimulusVector *vector = &kDrxStimulusCatalog[vector_id];

    if (!cargar_vector(vector)) {
        g_status.running = false;
        g_status.errors++;
        xil_printf("drx_stimulus: no se pudo cargar %s\r\n", vector->name);
        return DRX_DSP_ERROR_NOT_CONFIGURED;
    }

    g_status.name = vector->name;
    g_status.vector_id = vector_id;
    g_status.looping = true;
    g_status.remaining = 0u;
    g_status.loads++;
    g_status.running = true;

    xil_printf("drx_stimulus: vector %lu (%s), %lu muestras en bucle\r\n",
               (unsigned long)vector_id, vector->name,
               (unsigned long)vector->count);
    return DRX_DSP_ERROR_OK;
}

void DrxStimulus_Stop(void)
{
    if (!g_ready) {
        return;
    }

    /* No hay nada que parar en el sentido de antes: no existe transferencia en
     * vuelo ni descriptores que drenar. Lo unico que hace falta es dejar de
     * declarar que hay un vector seleccionado.
     *
     * La BRAM se queda con el ultimo vector cargado SONANDO, y eso es un
     * cambio de semantica frente al Stop() de v8..v10, que devolvia la fuente
     * a BRAM-loop con el tono que `$readmemh` dejo en el bitstream. Recuperar
     * ese tono no es posible por software: el `$readmemh` solo corre al cargar
     * el bitstream. Si hiciera falta volver a el, el camino es cargar de nuevo
     * el vector `tono_if` del catalogo, que es el mismo tono. */
    g_status.running = false;
    g_status.looping = false;
    g_status.remaining = 0u;
}

void DrxStimulus_GetStatus(DrxStimulusStatus *out)
{
    if (out != NULL) {
        *out = g_status;
    }
}

void DrxStimulusTask_Create(void)
{
    /* Sin tarea. La que habia rearmaba el DMA entre pasadas cada
     * DRX_STIMULUS_POLL_MS; con la BRAM en bucle por hardware no hay nada que
     * rearmar. Se conserva el simbolo para no tocar el arranque de main.c por
     * una funcion vacia, y porque el dia que haga falta una tarea aqui (una
     * secuencia de vectores encadenada, por ejemplo) este es su sitio. */
}

bool DrxStimulus_SelfTest(uint8_t vector_id)
{
    if (!g_ready) {
        xil_printf("drx_stimulus: sin ventana de carga, no hay nada que comprobar\r\n");
        return false;
    }

    /* OVERFLOW es sticky: se limpia primero para que lo que se lea despues sea
     * de este vector y no de lo que hubiera corriendo antes. */
    DrxReg_ClearOverflow(DrxReg_ReadOverflow());
    uint32_t overflow_antes = DrxReg_ReadOverflow();

    drx_dsp_error_t error = DrxStimulus_Select(vector_id, 0u);
    if (error != DRX_DSP_ERROR_OK) {
        xil_printf("drx_stimulus: Select devolvio %lu\r\n", (unsigned long)error);
        return false;
    }

    /* La comprobacion que SI se puede hacer sin camino de vuelta: releer
     * VEC_LEN y CTRL por AXI-Lite. Dice que la ventana existe, que el slave
     * acepto la escritura y que el lector quedo suelto.
     *
     * Lo que NO dice es si el CONTENIDO de la BRAM es el correcto: no hay
     * camino de lectura desde la memoria hacia AXI-Lite (anadirlo costaria un
     * puerto mas por banco). La prueba de verdad es el espectro del rayo
     * contra el modelo dorado, y eso es DrxRay_SelfTest + tools/dump_ray.py.
     *
     * Es una comprobacion mas debil que la de v8..v10, y conviene decirlo: alli
     * una pasada COMPLETA del DMA probaba que los bytes habian llegado dentro
     * de la PL, porque el unico que levantaba `tready` era `vector_source`. */
    const DrxStimulusVector *vector = &kDrxStimulusCatalog[vector_id];
    uint32_t len = DrxReg_VecGetLen();
    bool cargando = DrxReg_VecLoading();
    uint32_t overflow_despues = DrxReg_ReadOverflow();

    xil_printf("drx_stimulus: vector %s -- VEC_LEN=%lu (esperado %lu) "
               "vector_load=%lu OVERFLOW %lx -> %lx\r\n",
               vector->name, (unsigned long)len, (unsigned long)vector->count,
               (unsigned long)cargando, (unsigned long)overflow_antes,
               (unsigned long)overflow_despues);

    if (len != (uint32_t)vector->count) {
        xil_printf("drx_stimulus: VEC_LEN no volvio con lo escrito -- "
                   "ventana de carga rota\r\n");
        return false;
    }
    if (cargando) {
        xil_printf("drx_stimulus: vector_load se quedo en alto -- "
                   "la fuente esta congelada\r\n");
        return false;
    }

    xil_printf("drx_stimulus: ventana de carga confirmada en placa "
               "(el DATO lo confirma el espectro del rayo, no esto)\r\n");
    return true;
}
