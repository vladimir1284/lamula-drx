/* Implementacion de fw/include/drx_timing_cfg.h. Copiado por tcl/gen_bsp.tcl
 * al proyecto de Vitis del dominio FreeRTOS, igual que el resto de fw/src/app.
 */
#include "drx_timing_cfg.h"
#include "drx_regs.h"
#include "drx_regs_hw.h"
#include "drx_params.h"

#include "FreeRTOS.h"
#include "task.h"
#include "xil_printf.h"

/* Microsegundos por segundo: constante de unidades, no una frecuencia. El
 * unico numero de reloj que entra en este fichero es DRX_FS_HZ, y entra por
 * fw/include/drx_params.h (D-02). */
#define DRX_US_PER_S 1000000LL /* clock-const-ok: us/s, conversion de unidades */

#define DRX_MAX_U32(a, b) (((a) > (b)) ? (a) : (b))

/* Ciclos de FS_HZ en `us` microsegundos, redondeado hacia abajo. */
#define DRX_CYCLES_US(us) ((uint32_t)((DRX_FS_HZ * (int64_t)(us)) / DRX_US_PER_S))

/* Pulsos por lote. Valores de bring-up arbitrarios, no un VCP real: los elige
 * este fichero solo para que un radial completo (lote bajo + lote alto) dure
 * del orden de 200 ms, lo bastante corto para ver `radial_done` en el primer
 * sondeo de la tarea de estado y lo bastante largo para distinguir los dos
 * lotes en un osciloscopio. El reparto real viene del mensaje `config` del
 * contrato DRx<->DSP, que es Z4.4. */
#define DRX_BRINGUP_N_PULSES_LOW 6u
#define DRX_BRINGUP_N_PULSES_HIGH 41u

/* Ventana de comprobacion tras arrancar el secuenciador. Cubre casi 5 radiales
 * completos con los pulsos de arriba, asi que `radial_done` tiene que haberse
 * puesto varias veces dentro de ella.
 *
 * Por que no basta con medio radial: los pulsos NO estan repartidos de forma
 * uniforme dentro de un radial. El lote bajo da 6 pulsos a ~81 Hz y el alto da
 * 41 a 300 Hz, asi que una ventana corta que arranca justo en el borde del
 * radial cae casi entera en la parte dispersa y cuenta de menos. Medido en
 * placa el 1-oct-2026 con una ventana de 500 ms: 99 pulsos frente a los 111
 * del promedio. Cuanto mas larga la ventana, menos pesa esa fase. */
#define DRX_BRINGUP_CHECK_MS 1000u

/* Banda que se acepta alrededor del promedio, en octavos (12,5 %). Cubre de
 * sobra el error de fase que queda con la ventana de arriba y sigue rechazando
 * un motor que corre a una PRF equivocada -- que es lo que distingue este
 * criterio de un simple "TRIG_COUNT se movio". */
#define DRX_BRINGUP_RATE_TOLERANCE_EIGHTHS 1u

/* Retardo y ancho de cada canal de drx_trigger_gen, en microsegundos. Los 4 se
 * arman con el mismo `pulse_trig` (ver la cabecera de drx_timing_engine.sv),
 * asi que lo unico que los distingue en el osciloscopio es su retardo y su
 * ancho: se escalonan a proposito para que una sola punta de prueba pueda
 * identificar cual es cual. El ultimo flanco cae en 30 + 8 = 38 us, muy por
 * dentro del PRI mas corto de los dos lotes. */
static const uint32_t kTrigDelayUs[DRX_N_TRIGGERS] = {0u, 10u, 20u, 30u};
static const uint32_t kTrigWidthUs[DRX_N_TRIGGERS] = {1u, 2u, 4u, 8u};

/* Bins de range-gate que caben en un PRI de `prf_div` ciclos.
 *
 * Un rayo de N bins ocupa N * R1 ciclos: el DDC entrega una muestra decimada
 * cada R1 ciclos de FS_HZ en modo fino, y drx_range_gate cuenta muestras
 * decimadas, no ciclos. Si N * R1 pasa de prf_div, el siguiente `ray_start`
 * llega con el banco a medias y drx_range_gate_quad_top marca `ray_truncated`
 * (GATE_TRUNCATED, D-14/v6). De ahi el bin de guarda que se descuenta.
 *
 * Esto depende de que CTRL bit 0 (`mode_coarse`) valga 0: en modo grueso la
 * decimacion es R2 = 2 * R1 y estos conteos sobrarian por el doble.
 * DrxTiming_Start() escribe CTRL explicitamente por ese motivo.
 *
 * El techo, ademas del PRI, es BINS_MODE_FINE: la profundidad fisica real de
 * la BRAM de drx_range_gate, que D-09 valida desde v5 (D-15). */
static uint32_t bins_for_pri(uint32_t prf_div)
{
    uint32_t bins = prf_div / (uint32_t)DRX_R1;

    if (bins > (uint32_t)DRX_BINS_MODE_FINE) {
        bins = (uint32_t)DRX_BINS_MODE_FINE;
    }
    if (bins > 1u) {
        bins -= 1u; /* bin de guarda: el rayo tiene que cerrar antes del siguiente ray_start */
    }
    return bins;
}

void DrxTiming_DefaultConfig(DrxTimingConfig *cfg)
{
    static const uint16_t kPulseWidthCycles[DRX_N_PULSE_WIDTHS] = DRX_PULSE_WIDTH_CYCLES;

    /* prf_div lo mas bajo posible (PRF lo mas alta posible) sin violar ningun
     * piso, que son DOS y no uno:
     *
     *   - el de rango no ambiguo del lote (D-09: 460 km para el bajo, 115 km
     *     para el alto, WSR-88D-NEXRAD), que el RTL si comprueba;
     *   - PRF_DIV_MIN, el techo de PRF del sistema (1200 Hz), que el RTL NO
     *     comprueba -- drx_timing_config_valid.sv no mira ese limite.
     *
     * Para el lote bajo manda el primero (767198 > 208333). Para el alto manda
     * el segundo: PRF_DIV_MIN_HIGH vale 191800, por debajo de PRF_DIV_MIN, y
     * config/params.toml ya avisa de que ese piso es no-vinculante hoy. Tomar
     * el maximo de los dos es lo que mantiene la configuracion dentro del
     * envolvente declarado y no solo dentro de lo que el fabric acepta.
     *
     * Quedarse en el piso exacto del lote bajo no es casualidad: deja la
     * configuracion pegada al limite que el validador comprueba, asi que un
     * comparador invertido en el RTL saldria en este bring-up en vez de pasar
     * por casualidad. */
    cfg->prf_div_low = DRX_MAX_U32((uint32_t)DRX_PRF_DIV_MIN_LOW, (uint32_t)DRX_PRF_DIV_MIN);
    cfg->prf_div_high = DRX_MAX_U32((uint32_t)DRX_PRF_DIV_MIN_HIGH, (uint32_t)DRX_PRF_DIV_MIN);

    /* Pulso largo para el lote de vigilancia, corto para el de Doppler: es el
     * reparto de Batch mode (D-13). Los indices son posiciones de la tabla de
     * config/params.toml, que es la unica lista que D-09 acepta. */
    cfg->pulse_width_low = kPulseWidthCycles[DRX_N_PULSE_WIDTHS - 1u];
    cfg->pulse_width_high = kPulseWidthCycles[0];

    cfg->n_pulses_low = (uint16_t)DRX_BRINGUP_N_PULSES_LOW;
    cfg->n_pulses_high = (uint16_t)DRX_BRINGUP_N_PULSES_HIGH;

    cfg->bins_low = bins_for_pri(cfg->prf_div_low);
    cfg->bins_high = bins_for_pri(cfg->prf_div_high);

    for (unsigned i = 0u; i < DRX_N_TRIGGERS; i++) {
        uint32_t width = DRX_CYCLES_US(kTrigWidthUs[i]);

        /* drx_trigger_one_shot.sv asume width >= 1 y no lo valida en RTL. */
        cfg->trig_delay[i] = DRX_CYCLES_US(kTrigDelayUs[i]);
        cfg->trig_width[i] = (width == 0u) ? 1u : width;
    }
}

/* Pulsos de PRF que caben en la ventana de comprobacion con esta
 * configuracion, en promedio sobre un radial completo. Es el numero contra el
 * que se compara el avance medido de TRIG_COUNT: sin el, "TRIG_COUNT subio" no
 * distingue el motor corriendo a la PRF pedida de un motor corriendo a una PRF
 * equivocada. Es un PROMEDIO, no un conteo exacto -- ver la nota de fase en
 * DRX_BRINGUP_CHECK_MS. Todo en 64 bits: el producto pasa de 2^31 de sobra. */
static uint32_t expected_pulses(const DrxTimingConfig *cfg, uint32_t window_ms)
{
    int64_t radial_cycles = (int64_t)cfg->n_pulses_low * (int64_t)cfg->prf_div_low +
                            (int64_t)cfg->n_pulses_high * (int64_t)cfg->prf_div_high;
    int64_t radial_pulses = (int64_t)cfg->n_pulses_low + (int64_t)cfg->n_pulses_high;
    int64_t window_cycles = (DRX_FS_HZ * (int64_t)window_ms) / 1000;

    if (radial_cycles <= 0) {
        return 0u;
    }
    return (uint32_t)((window_cycles * radial_pulses) / radial_cycles);
}

static void print_config(const DrxTimingConfig *cfg)
{
    xil_printf("drx_timing: lote bajo  prf_div=%lu pulse_width=%lu bins=%lu n_pulses=%lu\r\n",
               (unsigned long)cfg->prf_div_low, (unsigned long)cfg->pulse_width_low,
               (unsigned long)cfg->bins_low, (unsigned long)cfg->n_pulses_low);
    xil_printf("drx_timing: lote alto  prf_div=%lu pulse_width=%lu bins=%lu n_pulses=%lu\r\n",
               (unsigned long)cfg->prf_div_high, (unsigned long)cfg->pulse_width_high,
               (unsigned long)cfg->bins_high, (unsigned long)cfg->n_pulses_high);

    for (unsigned i = 0u; i < DRX_N_TRIGGERS; i++) {
        xil_printf("drx_timing: trig[%lu] delay=%lu ciclos  width=%lu ciclos\r\n",
                   (unsigned long)i, (unsigned long)cfg->trig_delay[i],
                   (unsigned long)cfg->trig_width[i]);
    }
}

bool DrxTiming_Start(void)
{
    DrxTimingConfig cfg;

    if (!DrxReg_SelfTest()) {
        xil_printf("drx_timing: mapa de registros no coincide, motor sin arrancar\r\n");
        return false;
    }

    /* Modo fino explicito. Es ya el valor de reset de CTRL, pero bins_for_pri()
     * depende de el para no truncar rayos: dejarlo implicito esconderia ese
     * acoplamiento. */
    DrxReg_Write(DRX_REG_CTRL_OFFSET, 0u);

    DrxReg_TimingDisable();

    DrxTiming_DefaultConfig(&cfg);
    DrxReg_WriteTimingConfig(&cfg);
    print_config(&cfg);

    if (!DrxReg_VerifyTimingConfig(&cfg)) {
        xil_printf("drx_timing: la relectura no coincide -- camino AXI-Lite, no D-09\r\n");
        return false;
    }

    /* TIMING_STATUS arranca en 0x6 tras reset: los dos lotes invalidos con los
     * registros a 0. Ahora que la configuracion es valida, se limpian los
     * sticky para que lo que se lea despues sea del motor ya configurado. */
    DrxReg_ClearTimingStatus(DrxReg_ReadTimingStatus());

    DrxReg_TimingEnable();
    if (!DrxReg_TimingEnabled()) {
        xil_printf("drx_timing: TIMING_CTRL no se quedo en 1\r\n");
        return false;
    }

    uint32_t trig_before = DrxReg_TrigCount();
    vTaskDelay(pdMS_TO_TICKS(DRX_BRINGUP_CHECK_MS));
    uint32_t advanced = DrxReg_TrigCount() - trig_before; /* envuelve bien en 32 bits */
    uint32_t expected = expected_pulses(&cfg, DRX_BRINGUP_CHECK_MS);

    uint32_t timing_status = DrxReg_ReadTimingStatus();
    bool invalid_low = (timing_status & (1u << 1)) != 0u;
    bool invalid_high = (timing_status & (1u << 2)) != 0u;
    bool radial_done = (timing_status & (1u << 0)) != 0u;

    xil_printf("drx_timing: en %lu ms TRIG_COUNT avanzo %lu (esperado ~%lu), "
               "TIMING_STATUS = 0x%lx\r\n",
               (unsigned long)DRX_BRINGUP_CHECK_MS, (unsigned long)advanced,
               (unsigned long)expected, (unsigned long)timing_status);

    if (invalid_low || invalid_high) {
        xil_printf("drx_timing: D-09 rechaza el lote %s -- motor parado\r\n",
                   invalid_low ? (invalid_high ? "bajo y el alto" : "bajo") : "alto");
        return false;
    }
    if (advanced == 0u) {
        xil_printf("drx_timing: TRIG_COUNT clavado -- no sale pulse_trig\r\n");
        return false;
    }

    uint32_t tolerance = (expected / 8u) * DRX_BRINGUP_RATE_TOLERANCE_EIGHTHS;
    if (advanced + tolerance < expected || advanced > expected + tolerance) {
        xil_printf("drx_timing: TRIG_COUNT avanza fuera de banda (%lu +/- %lu) -- "
                   "el motor corre, pero no a la PRF pedida\r\n",
                   (unsigned long)expected, (unsigned long)tolerance);
        return false;
    }
    if (!radial_done) {
        xil_printf("drx_timing: sin radial_done en la ventana -- el secuenciador "
                   "corre pero no cierra un radial completo\r\n");
        return false;
    }

    /* El sticky de radial_done ya cumplio su proposito aqui; se limpia para que
     * la tarea de estado lo vea volver a 1 por su cuenta y asi confirme que el
     * motor sigue cerrando radiales, no solo que cerro uno al arrancar. */
    DrxReg_ClearTimingStatus(timing_status);

    xil_printf("drx_timing: motor de timing corriendo, trig_out vivo en Pmod JA\r\n");
    return true;
}
