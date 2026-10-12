/* Configuracion de arranque del motor de timing (Z2: D-13 lotes, D-09
 * validacion, D-15 bins por lote), escrita por el firmware sobre el mapa de
 * registros v7 via drx_regs_hw.c.
 *
 * Por que existe este fichero y por que NO es todavia Z4.4: en reset todos los
 * registros de timing valen 0, y D-09 rechaza esa combinacion -- pulse_width 0
 * no esta en DRX_PULSE_WIDTH_CYCLES y bins 0 esta por debajo del minimo de 1.
 * Con los dos lotes invalidos drx_timing_engine mantiene el secuenciador
 * parado, no sale ningun pulse_trig, y por tanto no hay ray_start: eso es lo
 * que se vio en placa el 1-oct-2026 como TIMING_STATUS = 0x6 y STATUS
 * (overrun) = 0x7 con TRIG_COUNT clavado en 0 (ver bringup/README.md,
 * escalon 5). Esto arranca el motor con una configuracion fija y valida.
 *
 * La configuracion definitiva no vendra de aqui: viene del mensaje `config`
 * del contrato DRx<->DSP, que es Z4.4. Lo de aqui es un valor de arranque de
 * bring-up, elegido para ser valido bajo D-09 y medible con osciloscopio en
 * los 4 pines de `trig_out` del Pmod JA (tcl/xdc/zedboard_zynq.xdc) -- la
 * medida "en placa" que es lo unico que le falta al hito ZM2.
 */
#ifndef DRX_TIMING_CFG_H
#define DRX_TIMING_CFG_H

#include <stdbool.h>
#include <stdint.h>

#include "drx_dsp_v0_1.h"
#include "drx_regs_hw.h"

/* Rellena `cfg` con la configuracion de arranque de bring-up. Todos los
 * valores se derivan de fw/include/drx_params.h (D-02: FS_HZ es la unica
 * fuente de verdad temporal); ninguno es un numero suelto. */
void DrxTiming_DefaultConfig(DrxTimingConfig *cfg);

/* Secuencia completa de arranque, pensada para llamarse una vez al arrancar y
 * antes de DrxStatusTask_Create(), de forma sincrona: si la configuracion
 * llegase despues, la tarea de estado imprimiria el TIMING_STATUS = 0x6 de
 * reset como si fuese un fallo.
 *
 * Pasos, en este orden exacto:
 *   1. parar el secuenciador (los registros solo son seguros de escribir con
 *      el motor parado -- ver la cabecera de drx_prf_batch_seq.sv);
 *   2. escribir la configuracion;
 *   3. releerla por AXI-Lite y comparar, para separar un camino de registros
 *      roto de un rechazo de D-09;
 *   4. limpiar los bits sticky de TIMING_STATUS que vienen del reset;
 *   5. arrancar el secuenciador;
 *   6. esperar y comprobar que TRIG_COUNT avanza y que TIMING_STATUS no vuelve
 *      a marcar ningun lote invalido.
 *
 * Devuelve true solo si los seis pasos salen bien. Imprime por UART lo que
 * vio en cada paso, para que un fallo se pueda atribuir sin depurador. */
bool DrxTiming_Start(void);

/* Aplica el mensaje `config` del contrato (v0.6, 2 lotes -- P-15). Devuelve el
 * codigo con el que contestar el `config_ack`.
 *
 * Atomico, como exige el esquema: TODA la validacion ocurre antes de escribir
 * ni un registro, y si el RTL rechaza la configuracion ya escrita (D-09, que
 * valida cosas que esta funcion no puede comprobar sola) se restaura la
 * ultima configuracion que si entro. Un `config` rechazado no deja el motor
 * parado ni a medio configurar.
 *
 * Lo que comprueba aqui y no en el RTL: que los indices de ancho de pulso
 * esten en la tabla, que `cell_mode` y `scan_mode` esten en rango, que la
 * mascara de canales case con los que el bitstream instancia, que `prf_div`
 * respete PRF_DIV_MIN/MAX (el techo de PRF del sistema, que
 * drx_timing_config_valid.sv NO mira) y que el rayo quepa en el PRI. Lo
 * ultimo es el bin de guarda: D-09 valida `bin_count <= BinsMax`, no que
 * `bin_count * R` entre en `prf_div`. */
drx_dsp_error_t DrxTiming_Apply(const drx_dsp_config_t *config);

/* Vuelve a la configuracion de bring-up: escribe los registros Y el estado que
 * DrxTiming_GetRayMeta lee. Sin lo segundo las cabeceras de rayo declaran la
 * ultima config aplicada aunque el hardware ya corra otra (12-oct-2026: tras
 * DrxControlBoot_SelfTest los rayos decian 800000/300000 y el motor corria
 * 767312/208416). */
void DrxTiming_RestoreDefault(void);

/* Metadato de rayo de la configuracion vigente, para DrxRayCtx_Fill. Antes el
 * rayo se estampaba con los valores de bring-up aunque el DSP hubiera enviado
 * otra config, y el DSP no veia TX_BURST_0 ni la PRF real. */
typedef struct {
    uint32_t prf_div_low;
    uint32_t prf_div_high;
    uint8_t pulse_width_idx_low;
    uint8_t pulse_width_idx_high;
    uint8_t channel_mask;
    bool first_after_config;
} DrxTimingRayMeta;

/* `first_after_config` sale en true una sola vez por cada config aplicada: la
 * llamada lo consume. */
void DrxTiming_GetRayMeta(DrxTimingRayMeta *out);

#endif /* DRX_TIMING_CFG_H */
