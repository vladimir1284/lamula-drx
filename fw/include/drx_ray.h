/* Ensamblado de rayos sobre el canal S2MM del AXI DMA (Z4.4).
 *
 * Cierra el camino de vuelta que Z4.0-Z4.3 dejaron a medias:
 *
 *   drx_range_gate_quad_top --> drx_ray_packer --> AXI DMA S2MM --> DDR
 *     --> esta interrupcion --> cabecera de contrato --> sumidero
 *
 * Hasta ahora nadie programaba descriptores de S2MM, asi que `s_axis_ray_tready`
 * nunca subia; por eso `STATUS (overrun)` y `GATE_TRUNCATED` llevaban desde el
 * bring-up del 1-oct en `0x7`. Que caigan a cero es el criterio de que esto
 * funciona, y no hace falta interpretar nada para leerlo.
 *
 * El metadato de cada rayo NO se lee de los registros AXI-Lite al atender la
 * interrupcion: viaja EN BANDA, en las primeras `DRX_RAY_META_WORDS` palabras
 * del propio descriptor, puesto por `rtl/drx_ray_packer.sv` en el instante en
 * que el rayo empieza a vaciarse. Ver la cabecera de ese fichero: leer
 * TRIG_COUNT desde el manejador llega tarde por unos pocos microsegundos, y
 * justo en el borde entre los dos lotes del radial (D-13) eso atribuye el rayo
 * al lote equivocado.
 */
#ifndef DRX_RAY_H
#define DRX_RAY_H

#include <stdbool.h>
#include <stdint.h>

#include "drx_params.h"

/* "RY" + version 1 del formato de cabecera en banda. Tiene que coincidir con
 * `RayMagic` de rtl/drx_ray_packer.sv y con `RAY_MAGIC` de
 * sim/tb/tb_drx_ray_packer.py: es el mismo formato visto desde tres lados. */
#define DRX_RAY_MAGIC 0x52590001u

/* Palabras de 32 bits de metadato por rayo, delante de los datos. */
#define DRX_RAY_META_WORDS 4u

/* Canales que el bitstream instancia. Sale de `config/params.toml`, igual que
 * el RTL; ademas se comprueba contra el `n_ch` que trae cada cabecera, asi que
 * una divergencia entre firmware y bitstream se ve en el primer rayo en vez de
 * como un espectro raro sin explicacion. */
#define DRX_RAY_N_CH ((uint32_t)DRX_N_CH_TOP)

/* Rayo mas grande que el bitstream puede producir: modo fino, bins al tope que
 * D-09 admite. Dimensiona los descriptores; un rayo real puede ser mas corto
 * (lote alto) y el DMA lo cierra antes por TLAST. */
#define DRX_RAY_MAX_BINS ((uint32_t)DRX_BINS_MODE_FINE)
#define DRX_RAY_MAX_WORDS (DRX_RAY_META_WORDS + DRX_RAY_MAX_BINS * DRX_RAY_N_CH)

/* Tamano REAL de cada buffer: el maximo redondeado hacia arriba a linea de
 * cache (64 B = 16 palabras).
 *
 * No es cosmetica. `Xil_DCacheInvalidateRange` trabaja por lineas enteras, e
 * invalidar DESCARTA lo que haya sucio en la linea sin escribirlo a memoria.
 * Con buffers de 44284 B consecutivos, solo el primero cae en frontera de
 * linea: invalidar cualquier otro arrastraria la linea compartida con el
 * vecino -- y la del primero, la que comparte con lo que el enlazador haya
 * puesto justo antes. El sintoma seria una variable cualquiera del firmware
 * volviendo a un valor viejo, de forma intermitente y sin relacion aparente
 * con los rayos. */
#define DRX_RAY_LINE_WORDS 16u
#define DRX_RAY_BUF_WORDS \
    (((DRX_RAY_MAX_WORDS + DRX_RAY_LINE_WORDS - 1u) / DRX_RAY_LINE_WORDS) \
     * DRX_RAY_LINE_WORDS)
#define DRX_RAY_MAX_BYTES (DRX_RAY_BUF_WORDS * 4u)

/* Rayos en vuelo en el anillo. Con 223 rayos/s y la tarea de entrega
 * despertando por semaforo, cuatro dan ~18 ms de margen antes de que el
 * hardware se quede sin descriptor libre. */
#define DRX_RAY_BUFFERS 4u

/* Ventana de la autoprueba de arranque. Con la configuracion de bring-up son
 * ~223 rayos, mas que de sobra para que un salto de trig_count o un overrun
 * aparezcan dentro de ella. */
#define DRX_RAY_SELFTEST_MS 1000u

/* Espera antes de limpiar los sticky y empezar a medir. Cubre de sobra el
 * arrastre del arranque: el range-gate lleva llenando bancos desde que arranco
 * el motor de timing y nadie los vaciaba, asi que el primer banco que se
 * completa tras armar el anillo levanta `overrun` una vez. Ver DrxRay_SelfTest. */
#define DRX_RAY_SETTLE_MS 200u

typedef struct {
    uint32_t trig_count;   /* disparos de PRF desde el arranque, al empezar este rayo */
    uint32_t ray_index;    /* rayos EMITIDOS desde el arranque; cuenta aparte */
    uint16_t bin_count;    /* bins de este rayo, del lote que lo produjo (D-15) */
    uint8_t n_ch;          /* canales que trae la carga util */
    bool batch_high;       /* lote alto del radial (D-13); a cero, lote bajo */
    bool mode_coarse;      /* celda gruesa; a cero, fina */
} DrxRayHeader;

typedef struct {
    uint32_t rays;             /* rayos entregados al sumidero */
    uint32_t dma_errors;       /* descriptores que el DMA marco como fallidos */
    uint32_t resync;           /* descriptores sin cabecera por armar a mitad de rayo */
    uint32_t bad_magic;        /* cabeceras sin DRX_RAY_MAGIC */
    uint32_t bad_n_ch;         /* cabeceras con un n_ch distinto del compilado */
    uint32_t short_rays;       /* rayos con menos bytes de los que su bin_count pide */
    uint32_t trig_gaps;        /* saltos de trig_count distintos de 1 entre rayos */
    uint32_t ray_gaps;         /* saltos de ray_index distintos de 1: rayos perdidos */
    uint32_t sink_drops;       /* rayos que el sumidero no acepto */
    uint32_t last_trig_count;
    uint32_t last_ray_index;
} DrxRayStatus;

/* Sumidero de rayos. `iq` apunta a la carga util YA sin cabecera, en palabras
 * de 32 bits {I[31:16], Q[15:0]} entrelazadas canal 0..n_ch-1, canal mas
 * rapido que bin -- el mismo orden que el payload de `ray` del contrato.
 * Devuelve false si no pudo quedarse con el rayo (cuenta como sink_drops). */
typedef bool (*DrxRay_Sink)(const DrxRayHeader *header, const uint32_t *iq,
                            uint32_t n_words, void *user);

/* Arranca el driver del canal S2MM, construye el anillo de descriptores y
 * engancha la interrupcion de fin de descriptor. Una vez, al arrancar.
 * Devuelve false y lo explica por UART si el DMA no esta donde el XSA dice, si
 * el canal S2MM no esta compilado en el bitstream, o si el anillo no cabe. */
bool DrxRay_Init(void);

/* Instala el sumidero. NULL deja los rayos en el contador y los descarta, que
 * es el estado util para el bring-up: lo que se quiere medir entonces es que
 * los rayos LLEGAN, no a donde van. */
void DrxRay_SetSink(DrxRay_Sink sink, void *user);

/* `ray_index` del ultimo rayo entregado, 0 si todavia no hubo ninguno. Lo usa
 * la actuacion AFC para decidir si un `apply_at_seq` ya paso (Z4.5). */
uint32_t DrxRay_LastIndex(void);

/* Crea la tarea que vacia la cola que llena la interrupcion. Hay que crearla:
 * el manejador no toca el sumidero (ver drx_ray.c sobre por que). */
void DrxRayTask_Create(void);

void DrxRay_GetStatus(DrxRayStatus *out);

/* Ultimo rayo entregado, para quien quiera volver a mirarlo. `iq` apunta al
 * buffer de la DDR SIN el metadato en banda y vale mientras ese buffer no se
 * rearme -- con `DrxRay_Freeze()` eso es indefinido. Devuelve false si todavia
 * no llego ninguno. */
bool DrxRay_GetLast(DrxRayHeader *header, const uint32_t **iq, uint32_t *n_words);

/* Comprobacion de bring-up: espera `ms` milisegundos y confirma que llegaron
 * rayos y que `STATUS (overrun)`/`GATE_TRUNCATED` quedaron limpios.
 *
 * Los dos criterios juntos, no por separado: que lleguen rayos con overrun
 * disparado significaria que el DMA no sigue el ritmo y que lo que llega son
 * rayos pisados, que es peor que no recibir ninguno porque parece exito. */
bool DrxRay_SelfTest(uint32_t ms);

/* Congela el proximo rayo completo: su buffer deja de rearmarse, asi que el
 * contenido se queda quieto en DDR y se puede leer entero por JTAG (`mrd`) sin
 * que el DMA lo pise a mitad de lectura.
 *
 * Es lo que hace util a `tools/dump_ray.py`: sin congelar, el buffer cuyo
 * cabecera se acaba de imprimir se reescribe unos 18 ms despues, asi que lo
 * que la lectura por JTAG trae es OTRO rayo -- y, si llega a mitad de
 * escritura, medio de cada uno. Los otros DRX_RAY_BUFFERS-1 buffers siguen
 * rotando, asi que el flujo no se para.
 *
 * Devuelve false si ya hay uno congelado. `DrxRay_Thaw()` lo devuelve al
 * anillo. */
bool DrxRay_Freeze(void);
void DrxRay_Thaw(void);

/* Vuelca un rayo por UART en hexadecimal, para compararlo contra el modelo sin
 * necesidad de Ethernet. Vuelca `n_words` palabras como mucho; con 0 no vuelca
 * datos y solo imprime la cabecera y la direccion del buffer en DDR, que es lo
 * que `tools/dump_ray.py` necesita para leerlo entero por JTAG con `mrd`. */
void DrxRay_DumpLast(uint32_t n_words);

#endif /* DRX_RAY_H */
