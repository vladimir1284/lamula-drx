# CLAUDE.md — LAMULA DRx

Punto de entrada para un agente o una persona que se incorpora en frío. Esta página dice **dónde
está el proyecto ahora**; las reglas de ingeniería están en `AGENTS.md` y no se repiten aquí.

## Qué es

Receptor digital FPGA del sistema LAMULA. Digitaliza el IF del radar, hace conversión a banda base y
diezmado en la lógica programable, ensambla los rayos con sus metadatos bajo FreeRTOS y los entrega
al LAMULA DSP por 1GbE contra el contrato DRx↔DSP. Su única interfaz externa es DRx↔DSP: no habla
con el RCP ni con ORPG.

- **Plataforma objetivo:** Zynq UltraScale+ ZU9 + 2× VadaTech FMC213 (ADC: 2× TI ADS42JB69, dual
  16 bits, 250 MSPS, JESD204B). **Aún no comprada.**
- **Plataforma de desarrollo actual:** Digilent ZedBoard, XC7Z020-CLG484-1.

## Estado, a 26 de septiembre de 2026

**Z0 — substrato: cerrada.** `make check` sigue en verde (108 tests hoy, Verilator + gcc + NumPy +
lint). Detalle en el tutorial de `docs/tutorial/` e inventario en `docs/implementacion/substrato.md`.
El runner de CI con Vivado (`[self-hosted, vivado]`) **se montó el 21-sep-2026** — la propia máquina
de desarrollo, registrada como runner, `HAS_VIVADO_RUNNER=true`. El job `gateware` ya corre de verdad
en CI, no solo a mano: `substrato` y la síntesis+bitstream de `zedboard` cierran verdes (WNS = 2,489
ns). El bloqueador que dejaba ZM0 sin cumplir —`fsbl.elf`/`drx_app.elf` inexistentes— se cerró a
mano el 26-sep-2026 (BSP/FSBL vía Vitis, detalle más abajo). **ZM0 tal como lo define
`docs/implementacion/fases.md`** («`git push` produce un `BOOT.BIN` byte a byte sin intervención
humana») **quedó confirmado el 26-sep-2026**: el push del propio commit de docs de Z2 (`8b3302a`)
disparó el job `ci` en el runner `[self-hosted, vivado]` (run 36262739882, 26m49s) y las cinco etapas
corrieron solas de punta a punta — síntesis+implementación, exportar XSA, BSP/FSBL/app vía Vitis,
verificación de `BOOT.BIN` reproducible y `upload-artifact` (`gateware-zedboard`) — todas verdes, sin
tocar la máquina. Ya no falta ninguna verificación para ZM0; lo que sigue (firmware real de Z4,
puente para ZU9) es trabajo nuevo, no cierre de este hito. De paso se encontraron y
corrigieron tres bugs reales de infraestructura que nadie había ejercitado antes (lint de HDL
desincronizado del Makefile, DRC de bitstream bloqueando `debug_probe`, nombre de archivo equivocado
en `make_boot.sh`) y se sacó `zu9` de la matriz de CI: este Vivado no tiene el device pack de Zynq
UltraScale+ instalado. Ver A7/A8/A11 en `docs/alcance/pendientes.md` y `fases.md#z1`, entrada del
21-sep (más tarde) y del 26-sep.

**Z1 — DDC + range gating: en curso, avanzada, no cerrada.** `rtl/drx_ddc_top.sv` existe, corre
contra IP real de Xilinx (DDS Compiler, CIC Compiler, FIR Compiler ×2) y está verificado con la
matriz completa de L1 (8 casos × {fine, coarse} = 16 corridas contra xsim real, con tolerancia
D-12). **`rtl/drx_top.sv` dejó de ser el diseño vacío de Z0**: instancia de verdad `vector_source`
(nuevo) → `drx_ddc_quad_top` → `drx_range_gate_quad_top`, `N_CH=3`, y tiene un P&R real (no solo
simulación) que cierra temporización. Estado de cada entregable de Z1, `docs/implementacion/
fases.md#z1` es la fuente viva:

- **Bit-exactitud del NCO:** resuelta y CUMPLIDA. [D-12](docs/alcance/decisiones.md#d-12) acepta el
  residuo medido (≤5 LSB) como techo del bloque; `sim/tb_sv/drx_l1_checker.sv` ya tiene
  `TOLERANCE_LSB` y la matriz completa de 16 combinaciones corrió contra xsim real bajo ese
  comparador — **16/16 "PASS", confirmado con reverificación limpia** (2 de las 16 dieron
  falso-fallo en la primera pasada por un directorio de build de xsim reutilizado de antes de D-12
  — kernel con `TOLERANCE_LSB=0` por defecto, detectado por timestamp; corregido borrando el build
  y regenerando vectores, ver `pendientes.md`#p-09). [P-11](docs/alcance/pendientes.md#p-11)
  cerrado, confirmado que el techo de Taylor (~−88/−92 dBc) alcanza.
- **Top-level de 3 canales heterogéneos (Config A Tx+H+V / Config B Tx+nominal+atenuado):**
  resuelto — `rtl/drx_ddc_quad_top.sv` y `rtl/drx_range_gate_quad_top.sv` son genéricos en `N_CH`,
  `N_CH=3` ya es ese top-level, verificado contra xsim real (`tb_l1_ddc_tri.sv`,
  `tb_l1_ddc_range_tri.sv`). Ver [P-12](docs/alcance/pendientes.md#p-12).
- **`vector_source` (BRAM-loop):** escrito (`rtl/vector_source.sv`), el primer ítem de Z1 que no
  existía como RTL sintetizable hasta el 19-sep-2026. Solo modo BRAM-loop; RT y Throttled (DDR)
  siguen sin implementar.
- **P&R real del datapath completo, 19-sep-2026:** primera vez que se mide temporización de la
  cadena real (antes, el único WNS medido era del diseño vacío del latido). A 100 MHz **no
  cerraba** (WNS = −1,209 ns, camino crítico FIR Compiler droop → BRAM de range-gate) — la
  contingencia que ya preveía `docs/plataforma/dilatacion-temporal.md` resultó necesaria de
  verdad. **`fs_hz` de zedboard bajó de 100 a 62,5 MHz** (`config/params.toml`, dilatación
  numérica pura, D-02 — no toca `R₁`/`R₂`/`fs` de la ZU9). A 62,5 MHz: **WNS = +2,770 ns, cierra**.
  Dos hallazgos de síntesis real en `drx_range_gate.sv` (RTL ya verificado por xsim, no código
  nuevo) tuvieron que corregirse en el camino — ver `fases.md#z1`, entrada del 19-sep — sin cambiar
  su comportamiento (reverificado bit a bit / D-12 contra xsim tras cada uno).
- **Mapa de registros AXI-Lite:** v2, `rtl/drx_axil_regs.sv` + `config/registers.toml`
  (fuente única, codegen con `tools/gen_registers.py`, mismo patrón que el contrato DRx↔DSP).
  VERSION (RO), CTRL (RW, `mode_coarse`, sustituye el `localparam` fijo que tenía `drx_top`),
  STATUS (write-1-to-clear, `overrun` por canal de range-gate) y OVERFLOW (write-1-to-clear,
  overflow de saturación del DDC por canal, añadido 20-sep-2026). Detalle en
  `docs/implementacion/registros.md`. Verificado con L0 real (80/80 en `make check`) **y con xsim
  real**: la matriz completa de D-12 (16 combinaciones, `tb_l1_ddc.sv`) se reconfirmó tras añadir
  el puerto `overflow` — **16/16 PASS** — y `tb_l1_ddc_range_tri.sv` (fine/coarse, 3 canales cada
  uno) tras el puerto `clear` de `drx_range_gate` — **6/6 PASS**, TLAST bit a bit incluido (ver
  `docs/implementacion/fases.md#z1`, entrada del 20-sep). **P&R ya re-cerrado también** (ver el
  punto siguiente).
- **Puente PS7↔AXI, 20-sep-2026 (más tarde):** el mapa de registros ya es alcanzable desde un PS7
  de verdad — `tcl/gen_zynq_bd.tcl` (block design: `processing_system7` con preset de MIO/DDR del
  board file de Digilent, `axi_interconnect` + `axi_protocol_converter` AXI4→AXI4-Lite) +
  `rtl/drx_zynq_top.sv` (nuevo). `rtl/drx_top.sv` volvió a ser un slave AXI-Lite pass-through puro;
  el flujo sin PS7 sigue igual vía `rtl/drx_top_tieoff.sv` (nuevo). P&R de `-top zynq` cierra: **WNS
  = 1,712 ns, WHS = 0,033 ns**, primer PS7 real de este repo. Detalle completo, incluidos los
  hallazgos de esta sesión (module-reference no admite SystemVerilog, `axi_interconnect` no
  downgradea protocolo por puerto), en `docs/implementacion/registros.md` y `fases.md#z1`.
- **P&R re-cerrado con el AXI-Lite integrado, 20-sep-2026:** `-step impl` — **WNS = 2,528 ns,
  WHS = 0,017 ns** ("All user specified timing constraints are met"). Post-route: LUT 7,61 %
  (4049/53200), registros 8,33 % (8865/106400), BRAM Tile 21,07 % (29,5/140), **DSP48 111/220
  (50,45 %) — cifra correcta para presupuesto de recursos, ya explicada** (20-sep, más tarde): el
  153/220 del 19-sep era una medición de post-síntesis, no de post-rutamiento (se generó a mano,
  fuera del flujo de `tcl/build.tcl`); dentro de la misma corrida del 20-sep, post-síntesis también
  mide 153/220 y cae a 111/220 recién al rutar, toda la caída dentro de las seis instancias de
  `fir_compiler_halfband` — ver `fases.md#z1`, entrada del 20-sep más tarde. El propio gate de
  `tcl/build.tcl` solo comprueba WNS de setup, no de hold (el hold pasó brevemente a negativo en un
  reporte intermedio antes de resolverse solo).
- **Conmutación en caliente fino/grueso:** cerrada como no-requisito, 21-sep-2026 — no como trabajo
  diferido. Confirmado por vladimir: la resolución de celda solo cambia entre rayos distintos,
  nunca a mitad de uno, así que no hace falta continuidad de fase. El mux estático que ya existe en
  `rtl/drx_ddc_top.sv`/`rtl/drx_range_gate.sv` cubre el caso de uso real. Detalle en
  `fases.md#z1`, entrada del 21-sep.
- Nuevo hallazgo abierto, no bloqueante: [P-14](docs/alcance/pendientes.md#p-14) — falta evaluar la
  varianza de los estimadores de momento bajo el residuo aceptado por D-12, contra Doviak & Zrnic
  cap. 6. Deuda de validación sobre una decisión ya tomada, no una condición de cierre de Z1.

**Z2 — motor de timing, triggers y PRF: cerrada, 25-sep-2026.** Las seis piezas de la lista de
trabajo de Z2 (`docs/implementacion/fases.md#z2`) resueltas y verificadas: generador de 4 triggers
configurables (`rtl/drx_trigger_gen.sv`), secuenciador de 2 lotes de PRF/ancho de pulso por radial —
Batch mode de NEXRAD, no *pie-slice* — (`rtl/drx_prf_batch_seq.sv`,
[D-13](docs/alcance/decisiones.md#d-13), cierra P-04), validador PRF × rango no ambiguo completo en
fabric (`rtl/drx_timing_config_valid.sv`, [D-09](docs/alcance/decisiones.md#d-09)), sincronización
determinista trigger↔gating (`ray_start`, [D-14](docs/alcance/decisiones.md#d-14)), conteo de bins
de range-gate por lote configurable en runtime ([D-15](docs/alcance/decisiones.md#d-15)) y BITE de
tiempo muerto (`ray_truncated`, mapa de registros v6). Instrumentación de jitter en fabric cerrada
como no-requisito, mismo criterio que la conmutación fino/grueso de Z1 — el camino de `trig_out`
(pines XDC reales sobre Pmod JA) + osciloscopio ya cubre lo que pide ZM2. P&R re-confirmado en cada
paso; la última cifra, con los pines de `trig_out` ya fijados, es **WNS = 1,295 ns** (`-top zynq`) —
bajando de forma sostenida desde los 2,528 ns previos a Z2 (cada pieza nueva se apila sobre el mismo
camino crítico PS7↔interconnect↔`drx_axil_regs`), vale la pena vigilar antes de seguir sumando
registros o pines a este mapa. Lo único que le falta al hito ZM2 tal como está escrito es la medida
«en placa» con osciloscopio — trabajo físico sobre hardware real, fuera de lo que un agente puede
hacer sin acceso a la placa.

**Z4 — camino de datos, firmware y contrato: en curso, empezó 26-sep-2026.** Planeado antes de
escribir código (fases Z4.0–Z4.6, orden fijado con vladimir el 26-sep-2026, memoria del agente
`z4-firmware-plan-order`) para no depender de hardware que no hay (solo ZedBoard) y para que cada
paso cierre algo probable antes del siguiente. **Z4.0 cerrada** el mismo día: las salidas de
`drx_range_gate_quad_top` tienen por fin un consumidor real —
`rtl/drx_ray_packer.sv` (nuevo, entrelaza N_CH canales en un único AXI4-Stream de 32 bits, verificado
3/3 en L0/cocotb) hacia un AXI DMA S2MM real (scatter-gather, `tcl/gen_zynq_bd.tcl`: `S_AXI_HP0` +
interrupción de fabric, ambos deshabilitados hasta ahora). P&R de `-top zynq` cierra con todo esto
integrado: **WNS = 1,706 ns** (sube desde 1,295 ns, la ruta crítica sigue siendo
PS7↔interconnect↔`drx_axil_regs`, sin tocar por este cambio). Detalle completo, con los dos hallazgos
reales de Vivado que hicieron falta corregir (pin de reloj del stream de entrada del DMA, `HAS_TLAST`
del puerto AXI4-Stream externo), en `fases.md#z4`, entrada del 26-sep. **Z4.1 cerrada** el mismo
día: mapa de registros **v7**, registro `TRIG_COUNT` (RO, contador libre de 32 bits que incrementa
con el mismo `pulse_trig` de `drx_timing_engine` que ya dispara `ray_start`, D-14) — el "contador de
trigger" que `fases.md#z4` ya listaba como metadato de rayo para el firmware de ensamblado (Z4.4).
Sin P&R nuevo (mismo criterio que v5/v6: lógica de bajo costo dentro de un módulo ya cerrado).
**Z4.2, mismo día (más tarde): `drx_app.elf` deja de ser el *Hello World* de Vitis.**
`tcl/gen_bsp.tcl` genera ahora dos dominios (antes uno solo): `standalone_domain` para `fsbl` (sin
cambios — el FSBL de Xilinx no admite FreeRTOS) y un `freertos_domain` nuevo
(`-os freertos10_xilinx` + librería `lwip211`) para `drx_app`, arrancado desde la plantilla de Vitis
"FreeRTOS lwIP Echo Server". `fw/src/app/` (nuevo, versionado — no dentro de `build/`) trae el
firmware real: `drx_regs_hw.c` (primer driver sobre el mapa de registros v7, `Xil_In32`/`Xil_Out32`
sobre `XPAR_M_AXI_REGS_BASEADDR`) y `drx_status_task.c` (tarea de FreeRTOS que confirma `VERSION`
contra `DRX_REGS_VERSION` y sondea/limpia los diagnósticos sticky por UART, arrancada antes de
`lwip_init()` — no depende de que el enlace Ethernet esté arriba), más `main.c` (adaptado de la
plantilla con ese único cambio). Hallazgo real: `app create -template` no aplica los parámetros de
librería del `.mss` de referencia de la plantilla (`api_mode`, `lwip_dhcp`, etc.) — confirmado
corriendo `bsp listparams -lib lwip211` (`api_mode` por defecto es `RAW_API`, no `SOCKET_API`, y
`echo.c` no habría compilado); `tcl/gen_bsp.tcl` los fija a mano con `bsp config`. Verificado con una
recompilación real de punta a punta: el XSA existente era de antes de Z4.1 (`TRIG_COUNT`), así que se
re-corrió `-top zynq -step xsa` completo primero (**WNS = 1,711 ns**), y con ese XSA fresco
`tools/build_vitis.sh` + `tools/make_boot.sh` corrieron limpios — `drx_app.elf` compila y enlaza sin
símbolos sin resolver, `BOOT.BIN` reproducible byte a byte (mismo aviso de solapamiento de `bootgen`
ya conocido, no una regresión), `make check` sigue en 109/109. **Lo que esto NO demuestra: nada
corrió en una ZedBoard física** — sin UART ni Ethernet conectados no hay forma de confirmar el
"primer bring-up físico" que Z4.2 promete; ese paso sigue pendiente de alguien con acceso a la placa.
Detalle completo en `fases.md#z4`, entrada del 26-sep (más tarde).

**Bring-up físico y motor de timing en silicio, 1-oct-2026.** La escalera de `bringup/` (5 escalones
desechables, solo JTAG) cerró de punta a punta y con ella el «bring-up físico pendiente» que Z4.2
dejó abierto. De paso salió la causa raíz de la DDR de esta placa: el board file de Digilent no fija
`PCW_UIPARAM_DDR_USE_INTERNAL_VREF`, así que el parámetro caía al default del IP (VREF externo) y la
DDR3 devolvía basura aunque el controlador reportara «normal operation» — corregido en
`tcl/gen_zynq_bd.tcl` y verificado aislándolo hasta `DDRIOB_DDR_CTRL` (`0xF8000B6C`). **Todo
artefacto de `build/` anterior al 1-oct-2026 es defectuoso.** Después, el firmware pasó a escribir de
verdad la configuración del motor de timing (`fw/src/app/drx_timing_cfg.c`, nuevo): `TIMING_STATUS`
baja de `0x6` (los dos lotes inválidos por D-09 con los registros en su valor de reset) a `0x1`
(`radial_done` solo), y `TRIG_COUNT` avanza a 223,7 pulsos/s medidos contra los 223,47 predichos.
Eso cubre la medida «en placa» que le faltaba a ZM2 salvo el osciloscopio en los pines de `trig_out`.
`tools/make_boot.sh` empaquetaba además el bitstream equivocado (`drx_top_tieoff.bin`, sin PS7, con
el AXI-Lite inerte) — corregido el mismo día. `STATUS (overrun)` y `GATE_TRUNCATED` siguen en `0x7`
a propósito: nadie programa descriptores del AXI DMA todavía, eso es Z4.4. Detalle completo en
`bringup/README.md` y en `fases.md#z4`, entrada del 1-oct.

**Z4.3 cerrada, 1-oct-2026.** Contrato **v0.5** (`test_stimulus_select`, enumeración
`stimulus_vector` con el catálogo de ocho vectores, errores `vector_unknown`/`unimplemented`),
framer y plano de control reales en C (`fw/src/app/drx_contract_io.c`, `drx_control.c` — sin
dependencias de Xilinx, compilados también para host y contrastados contra la implementación de
Python generada del mismo esquema), `rtl/vector_source.sv` con el modo **Throttled(DDR)** y su
primer L0, mapa de registros **v8** (`CTRL` bit 1 `vector_source_ddr`) y **AXI DMA MM2S** en el
block design. El vector de estímulo deja de quedar fijado en síntesis: barrer el catálogo costaba
ocho corridas de Vivado, ahora cuesta ocho mensajes. P&R cierra en **WNS = 1,634 ns**. Verificado en
placa por JTAG — el DMA completa pasadas enteras con 0 errores, y eso prueba que los bytes llegaron
a la PL porque el stream tiene backpressure y el único que levanta `tready` es `vector_source` en
ese modo. **Lo que NO prueba** es que el dato llegue correcto a la salida del DDC: el A/B contra el
vector de +6 dBFS dio `OVERFLOW = 0` en los dos casos y no discriminó; eso se mide en Z4.4, cuando
haya camino de vuelta para leer un rayo. Deuda anotada: `DRX_STIMULUS_N_CH` en
`fw/include/drx_stimulus.h` tiene que coincidir a mano con el `N_CH` de `rtl/drx_top.sv`, que no
vive en `config/params.toml`. Detalle en `fases.md#z4`, entrada del 1-oct (más tarde).

**Z4.4 cerrada, 1-oct-2026 (noche).** El camino de vuelta existe y está medido. `STATUS (overrun)`
y `GATE_TRUNCATED` **bajan de `0x7` a `0x0`** y llegan **231 rayos en 1000 ms** sin un solo error:
`dma_errors`, `bad_magic`, `bad_n_ch`, `short`, `trig_gaps` y `ray_gaps` todos en 0 — un rayo por
disparo de PRF, sin perder ninguno. **Y por fin se midió el dato**, que es lo que Z4.3 dejó abierto:
un rayo completo del lote bajo congelado en DDR, leído por JTAG con `tools/dump_ray.py` y
contrastado contra `model/drx_model` con el mismo estímulo — pico en continua en los tres canales,
**−9,02 dBFS medidos contra −9,02 dBFS del modelo**. La comparación es espectral y no muestra a
muestra a propósito: el rayo empieza en un punto arbitrario del vector en bucle y 4000 no es
múltiplo de 208. Piezas: contrato **v0.6** (`config` de 2 lotes y bandera `batch_high`, cierra
**P-15**), metadato de rayo **en banda** puesto por `drx_ray_packer` (leer `TRIG_COUNT` desde la
interrupción llega tarde y atribuiría mal el lote en el borde del radial), `fw/src/app/drx_ray.c`
(anillo S2MM + interrupción de fin de descriptor), `drx_ray_frame.c` (framer del mensaje `ray`,
compilado también para host y comparado byte a byte contra el Python generado) y `drx_control_boot.c`
(el plano de control ejercitado en silicio con una trama sintética: `PRF_DIV_LOW 767312 -> 800000`).
P&R cierra en **WNS = 2,045 ns, WHS = 0,016 ns**. Dos hallazgos de placa que costaron una corrida
cada uno: **el PRI tiene que ser múltiplo de R₁** o `ray_truncated` se dispara en cada pulso sin
haber perdido ningún rayo, y **el `overrun` del arranque** no es de régimen permanente (el
range-gate lleva llenando bancos que nadie vaciaba desde antes de que el consumidor existiera).
Hallazgo nuevo: **P-16**, Throttled(DDR) y el motor de timing no pueden correr a la vez — resuelto en RTL el 3-oct-2026, ver más abajo.
**Lo que NO hay: transporte.** El framer y el plano de control están, pero nadie abre un socket; el
DSP real es Z4.6. Detalle en `fases.md#z4`, entrada del 1-oct (noche).

**Z4.5 — actuación AFC y status/BITE: cerrada, 2-oct-2026.** El NCO por fin se
puede retunear en tiempo de ejecución: la IP del DDS Compiler se regeneró con `Phase_Increment
{Programmable}` (antes `{Fixed}`, sin ningún puerto por el que cambiar el incremento de fase),
mapa de registros **v9** (`NCO_PINC`, `0x58`, RW, reset = `NCO_PHASE_INC`), contrato **v0.7**
(`afc_out_of_range`, porque `nco_phase_inc` viaja como u64 y este receptor tiene 32 bits — truncar
en silencio convertiría una corrección equivocada en una frecuencia de mezcla equivocada sin
síntoma), y firmware nuevo con el reparto de siempre: `fw/src/app/drx_afc.c` y `drx_status_frame.c`
sin dependencias de Xilinx, compilados también para host y contrastados contra el Python generado
(`fw/tests/test_afc.py`, `fw/tests/test_status_frame.py`); `drx_afc_app.c` escribe el registro.
`apply_at_seq` se aplica **entre rayos**, en el enganche de `drx_ray.c`. De paso salió un bug real
de infraestructura: `tcl/gen_ip.tcl` no era idempotente — `create_ip` con la IP ya presente creaba
`ip/<core>_1/` en silencio y dejaba el XCI versionado intacto; corregido con `ensure_ip`.
**La matriz de 16 corridas de D-12 contra xsim real cerró 16/16 PASS** — el gate de verdad del
cambio de IP, corrido entero antes de commitear: el arranque del Phase Generator no se movió y
`NCO_LUT_OFFSET_K = 655` sigue cancelando. **El retune también está verificado contra el modelo
dorado**, que es lo que de verdad faltaba: que NCO_PINC cambie es un registro, que el NCO mezcle a
la frecuencia nueva es otra cosa — el caso L1 `afc_retune__{fine,coarse}` pasa bit a bit (315
muestras en fino, 157 en grueso, dentro de tolerancia D-12) con la palabra de fase escrita tras
soltar el reset. DSP48 sigue en 159/220: el canal `S_AXIS_CONFIG` no cuesta multiplicadores.

**El bring-up en placa cerró Z4.5 esa misma noche, y encontró un bug que ninguna simulación podía
ver.** En silicio: `mapa de registros v9 confirmado por AXI-Lite`, `drx_afc: actuacion AFC OK`, 231
rayos en 1000 ms con `overrun=0x0 truncated=0x0`, y la línea de BITE con `BITE=0x40`
(`CONFIG_REJECTED`) y `last_error=12` (`afc_out_of_range`) — la palabra fuera de rango de la
autoprueba recorriendo entera la cadena hasta la trama `status`. Pero el A/B espectral dio el pico
en continua con la palabra de retune puesta: **el NCO iba una escritura por detrás**. Causa en
`rtl/drx_axil_regs.sv`: `nco_pinc_we` era combinacional sobre `write_commit`, así que estaba en alto
el mismo ciclo en que `nco_pinc_r` todavía valía lo viejo, y `drx_ddc_top` latchea el dato con el
strobe. Confirmado con una predicción falsable —escribir la nominal aplicó el `0` anterior y la
salida se fue a cero exacto, `|max| = 0`— y corregido registrando el strobe un ciclo. **Ni la matriz
16/16 de D-12 ni el caso `afc_retune` lo vieron porque `tb_l1_ddc.sv` deja `nco_pinc` estable antes
de pulsar el strobe**: verificaban el DDC, no el traspaso registro→DDC; y el L0 comprobaba registro
y pulso por separado, que es justo lo que el bug respetaba. El test de ahora muestrea `nco_pinc` en
los ciclos en que el strobe está alto, y se comprobó que falla contra el RTL anterior. **Con la
corrección el A/B cierra: lado A (nominal) pico en continua a −9,02 dBFS; lado B
(`NCO_PINC = 1025629931`) pico en −0,25000 de fs_dec a −9,01 dBFS, contra −0,24950 y −9,02 dBFS del
modelo** — los dos lados del mismo arranque, vía `DrxAfcApp_RetuneAB`. Y el P&R **mejora** al sacar
un camino combinacional del crítico: **WNS = 2,304 ns, WHS = 0,022 ns** (venía de 1,626 ns).

Dos hallazgos de método de esa noche, los dos medidos: `tcl/sim_l1.tcl` y `tcl/build.tcl` escriben
en el mismo `ip/<core>/` y **no pueden correr a la vez** —el síntoma miente, `synth_ip` termina bien
y la elaboración falla después con `module '<core>' not found`—; y **los `overrun` que aparecen en
una sesión de JTAG son del JTAG**: `xsct` para el Cortex-A9 en cada `mrd` (23 s de reloj de pared
contra 16 s de `uptime` de FreeRTOS durante una ráfaga), la ISR del S2MM no recicla buffers y el
range-gate desborda. 0 eventos en 600 s ociosos contra 2-3 eventos por cada 300 lecturas, y también
leyendo DDR sin relación con el DMA. Cualquier BITE leído durante una sesión de `tools/dump_ray.py`
está contaminado; las cifras de Z4.4 no lo están porque salen de `DrxRay_SelfTest`, anterior a la
primera lectura por JTAG. Detalle en `fases.md#z4`, entradas del 2-oct.

**Z4.6 — transporte TCP y cliente DSP de mentira: en curso, empezó 2-oct-2026 (noche). El camino
completo ya corre en placa.** Por fin hay un socket: `fw/src/app/drx_transport.c` (nuevo) sustituye
al servidor de eco de la plantilla de Vitis, el DRx **escucha** en el puerto 9470 y el DSP conecta
([D-16](docs/alcance/decisiones.md#d-16)); contrato **v0.8**, que añade `tcp_port` al propio esquema
para que las dos puntas no lo dupliquen a mano. `tools/mock_dsp.py` (nuevo) es la otra punta, y no
reimplementa el contrato: todo lo que empaqueta sale de `contract/generated/drx_dsp_v0_1.py`.
**Medido contra la ZedBoard:** 2239 rayos en 10 s (**223,8 rayos/s** contra 223,47 predichos),
36,20 MB a 28,9 Mbps, **0 huecos de `seq`**, ping 0 % de pérdida a 0,147 ms. **Y el lazo de control
cierra sobre el mismo socket, sin JTAG:** un `afc` enviado por la red mueve el pico del espectro de
continua a **−0,24950 de fs_dec, −10,45 dBFS**, exactamente las cifras del modelo dorado, medido
sobre el I/Q que llega por el cable (`--spectrum`); y un `afc` fuera de rango vuelve como
`last_error=afc_out_of_range` con `bite=config_rejected` latcheado. **Soak de cuatro corridas esa
misma noche: 3,2 millones de rayos, 52 GB, 223,4 rayos/s sostenidos**, con el espectro del último
rayo de cada corrida todavía en continua a −9,02 dBFS contra el modelo dorado — el dato no se
degrada con las horas. Aparecieron ~4 descartes por millón, y atribuirlos costó tres pasadas de
instrumentación que refutaron dos hipótesis antes de dar con
[P-18](docs/alcance/pendientes.md#p-18), hallazgo nuevo: en la frontera entre los dos lotes de PRF
de un radial, un rayo puede llevar la cabecera de un lote y la carga útil del otro
(`bins=1002` con `n_words=11067 = 3689 × 3`). **No llega dato malo al DSP** — `DrxRayFrame_Encode`
se niega a enmarcarlo, que es exactamente para lo que esa comprobación existe — pero cuesta un rayo
cada media hora. Dos bloqueos reales en el
camino, los dos del mismo tipo que el VREF de la DDR: (1) el preset de Digilent deja
`PCW_ENET0_GRP_MDIO_IO` en `EMIO`, o sea saca el MDIO del PHY por la fábrica, donde no hay nada —
sin MDIO no hay autonegociación, y el mensaje que engaña (`unable to determine type of EMAC`) ni
siquiera era el error: es ruido de un `switch` sin `break` en el port de lwIP de Xilinx, que lo
imprime también cuando todo ha ido bien; (2) la tarea de diagnóstico se crea antes que el
transporte, así que llamaba a `DrxTransport_Send` con el mutex sin crear y reventaba el
`configASSERT` de FreeRTOS. **La corrida larga que faltaba ya está medida, 3-oct-2026, y
cierra dos cosas.** El sumidero de rayos llamaba a `lwip_send` DENTRO de la tarea de rayos:
mientras el socket bloqueaba nadie reciclaba el anillo S2MM y el range-gate desbordaba — no era un
problema de red, era bloquearse en ella. Con el pool de 4 tramas y la tarea `drx_tx` dedicada, en
**3 085 111 rayos y 3 h 50 min**: `dma_overruns=0 trig_gaps=0 ray_gaps=0`, contra ~18 overruns y 20
ráfagas de `trig_gaps` en 2 h antes del arreglo. **Y [P-18](docs/alcance/pendientes.md#p-18)
desapareció con ellos** (`cortos=0 largos=0 enc_fail=0`; cabía esperar ~7,7 eventos, p ~ 4,5e-4):
el desajuste de metadato en el borde de lote era efecto secundario de la parada, no un fallo
independiente. Cerrado por consecuencia, no por ILA. Lo que sí se mueve ahora es `cola` (pool sin
hueco), y es la contrapresión haciendo su trabajo: el rayo que no cabe cuesta un rayo, no una
ráfaga de once. [P-19](docs/alcance/pendientes.md#p-19) nació y murió el mismo
día: 124 ppm durante una tormenta de WiFi del host, 25 ppm con el host sano y **0 en 201 032
rayos** con un cliente que solo hace `recv_into` sobre un buffer fijo. Era el reensamblado en
Python de `tools/mock_dsp.py`, no la placa. **El barrido del catálogo de estímulos contra rayos
reales —lo último que le faltaba a ZM4— cerró el 4-oct-2026 en 8/8** con el estímulo cargado en
BRAM (ver más abajo). Detalle en `fases.md#z4`, entradas del 2-oct (noche), del 3-oct y del
4-oct.

**P-16 resuelto en RTL, 3-oct-2026 — por una tercera vía que el hallazgo no contemplaba.** P-16
daba dos salidas, las dos caras: ensanchar el stream del MM2S (tres cambios simultáneos, y
`N_CH × 16 = 48` bits no es potencia de dos, así que 64 con un carril muerto) o renunciar al
catálogo elegible en caliente con el motor de timing en marcha. El problema real no era que el
DMA fuera lento: era que **las dos mitades miden el tiempo con reglas distintas** —
`drx_prf_batch_seq` cuenta ciclos de reloj, la cadena del DDC avanza solo con `valid`—, y con la
fuente a una muestra por ciclo eso no se nota. Ahora el motor puede contar **avances de muestra**:
`rtl/drx_sample_pacer.sv` (nuevo, define qué cuenta como un avance y lleva toda la lógica nueva),
un puerto `advance` en `drx_prf_batch_seq`/`drx_trigger_one_shot`, paso a través en el resto, y
mapa de registros **v10** (`TIMING_CTRL` bit 1, `timing_paced`, reset 0 — con el bit en 0 la
netlist es la de v9). Verificado comparando la traza paceada contra la del mismo motor sin pacear,
1804 avances muestra a muestra, **y con RTL mutado**: quitar `advance` del `assign` de
`pulse_trig` da «10 pulsos con el motor parado», quitarlo de los `always_ff` hace divergir la
traza en el avance 134. P&R cierra en **WNS = 2,394 ns, WHS = 0,013 ns**, mejor que los 2,304 ns de Z4.5.
**La medida en placa, el mismo día, dice que el pacing era necesario pero NO suficiente, y
P-16 sigue abierto.** Lo que sí quedó: `GATE_TRUNCATED` baja a `0x0` con el motor corriendo en
modo DDR —la firma de P-16 desaparece, los rayos se completan enteros— y el camino de tiempo
real no se mueve (BRAM-loop con `timing_paced = 0` sigue dando −9,03 dBFS contra −9,03 del
modelo, o sea la equivalencia con v9 está comprobada en silicio). Lo que falta es el DATO: hay
una **tercera base de tiempo** que el análisis no miró — el DDS Compiler avanza un paso de fase
por ciclo de reloj, sin `TREADY` y sin clock enable (`rtl/drx_ddc_mixer.sv:99`,
`tcl/gen_ip.tcl:238`), así que con la fuente a 1 de cada 4 ciclos el DDC mezcla a ~4× el IF y la
salida cae al suelo de ruido: **−87,3 dBFS medidos contra −9,02 del modelo**. El arreglo es
simétrico (regenerar la IP con `Has_ACLKEN {true}` y cablear `aclken = advance`) y su gate es la
matriz de 16 corridas de D-12, 2-3 h. Y el barrido destapó además
[P-21](docs/alcance/pendientes.md#p-21), independiente: el MM2S se atasca tras unas pocas
selecciones encadenadas. Y esto NO convierte Throttled(DDR) en fuente
de tiempo real: no valida nada dependiente de la tasa.

**El estímulo se carga en BRAM en tiempo de ejecución y el MM2S sale del diseño, 4-oct-2026.**
Cambio de arquitectura, no un arreglo: en vez de regenerar la IP del DDS con `Has_ACLKEN {true}`
—que cuesta la matriz de 16 corridas de D-12 y toca un núcleo ya verificado— se elimina la fuente
con huecos. **BRAM-loop, que siempre entregó una muestra por ciclo, pasa a ser cargable en tiempo
de ejecución**, y Throttled(DDR) sale del RTL y del block design. Mapa de registros **v11**:
`CTRL` bit 2 `vector_load` más `VEC_ADDR`/`VEC_DATA`/`VEC_LEN`, un par dirección-dato con
autoincremento y difusión a los N_CH bancos — una ventana de memoria direccionable no cabe en los
128 B de `addr_width = 7` y un `axi_bram_ctrl` habría pedido un maestro más en el interconnect.
`CTRL` bit 1 vuelve a reservado y **no se reutiliza**. Dimensionado medido antes de elegir: 8192
muestras/canal × 3 = **12 BRAM Tile** sobre los 140 del xc7z020 (2048 muestras de 16 bits por
tile), partiendo de 31,5/140 reales — el 29,5/21,07 % que repetía este fichero era de antes de
Z4.4. `VECTOR_BRAM_DEPTH` (8192, capacidad) y `VECTOR_LOOP_LEN` (4000, lo que suena y valor de
reset de `VEC_LEN`) son dos números distintos porque la longitud tiene que ser múltiplo de
`IF_NORM_DEN` = 25 y 8192 no lo es; los dos viven en `config/params.toml` con gate en
`gen_params.py`, comprobado por mutación. Con `VEC_LEN` reseteando a 4000 y el mismo `$readmemh`
detrás, **un arranque en frío reproduce exactamente el bucle de v10**, así que los −9,03 dBFS
medidos siguen siendo la regresión. El strobe de escritura va registrado junto con dirección,
banco y dato, y la dirección que ve la BRAM es la de ANTES de incrementar — la cicatriz de
`nco_pinc_we` aplicada antes de que mordiera, con las dos mutaciones comprobadas. Firmware:
`drx_stimulus.c` reescrito entero contra la ventana, sin DMA, sin descriptores, sin buffer en DDR
y sin la tarea de rearme — con ella desaparece el mecanismo donde vivía P-21; `repeat != 0` pasa a
`unimplemented` y el contrato NO cambia de versión. **Dos cosas que esto NO hace:** no cierra
P-16 (el DDS sigue sin `aclken` y vuelve a romper con cualquier fuente con huecos futura; se
**rebaja**, no se cierra) y no cierra P-21 (el bug no está arreglado ni entendido, está
inalcanzable). **Y una que se pierde:** nada en el diseño ejercita ya el camino DMA PS→PL.
`make check` en verde con 160 tests, y **P&R `-top zynq` cierra: WNS = 1,618 ns, WHS = 0,014 ns,
Block RAM Tile 38,5/140 (27,50 %) desde 31,5/140** — o sea la BRAM se infirió como BRAM y no cayó
a LUTRAM, que era el riesgo principal. El WNS baja 0,776 ns desde los 2,394 ns del 3-oct y **no
por el camino nuevo**: el crítico medido es el FIFO del FIR Compiler → `overflow_sticky_r` de
`drx_axil_regs`, 12 niveles, un camino que ya existía; lo que cambió es la colocación.
`XPAR_FABRIC_DMA_S2MM_INTROUT_INTR` sigue en 61, así que `drx_ray.c` no se toca. `BOOT.BIN`
reproducible. **Medido en placa el mismo día, y cierra ZM4:** mapa v11 confirmado por AXI-Lite,
la ventana de carga releída (`VEC_LEN=4000`), **219 rayos en 1000 ms con `overrun=0x0
truncated=0x0`** y la autoprueba cargando vectores a la vez que se capturan rayos —imposible hasta
v10—, el espectro del rayo por el cable en **−9,03 dBFS en los tres canales** (la misma cifra de
antes del cambio, y ahora con el vector cargado por la ventana, no solo precargado) a 222,6
rayos/s sin huecos de `seq`, y **`tools/sweep_catalogo.py --settle 1` en 8/8, código 0**, contra
el 0/8 del 3-oct. La primera pasada dio 7/8 y el fallo era de la herramienta: exigía
`ddc_overflow` en `tono_sobre_escala` por su nombre, y el modelo dorado dice overflow=0 para los
ocho vectores — la entrada a +6 dBFS la recorta el ADC antes del DDC y la ganancia de Z1 deja la
salida 3,9 dB bajo el fondo. Corregido comparando la bandera contra el modelo.
[P-22](docs/alcance/pendientes.md#p-22) **cerrado el 5-oct-2026 como inalcanzable por estímulo**:
la salida máxima posible del DDC con cualquier entrada de 16 bits es 0,927 fs (fino) y 0,832 fs
(grueso), así que no existe vector que sature (`tools/bound_ddc_overflow.py`). El cableado
`overflow` → sticky → trama `ray` queda sin ver en placa, solo cubierto por L0.

**Soak del catálogo esa noche: 267 pasadas, 2136 selecciones encadenadas, ningún atasco** — que
era lo que el cambio dejaba implícito al sacar el MM2S y no estaba medido. `dma_overruns=0`,
`ray_gaps=0`, `BITE=0x0`, 223,2 rayos/s sostenidos. Dos cosas salieron de ahí. Una, que **el 8/8
de la pasada suelta fue en parte suerte**: 27 de las 201 primeras pasadas dieron 7/8, siempre
`dos_tonos` y siempre con el pico en el bin espejo, porque son dos tonos simétricos respecto al IF
y el modelo da los dos bins **bit a bit iguales** (`4657187.1` en +156 y en −156) — comparar el
`argmax` entre dos valores idénticos no puede ser determinista. Corregido en `dump_ray.spectrum`
(`peak_ambiguo`, compara `|bin|`), y con eso 66/66 pasadas limpias. Dos,
[P-23](docs/alcance/pendientes.md#p-23): **cargar un vector cuesta un rayo**, 1,05–1,12
`trig_gaps` por selección, porque `vector_load` congela la fuente pero el motor de timing cuenta
ciclos y no se entera; los rayos de esa frontera los rechaza `DrxRayFrame_Encode`, así que no
llega dato malo al DSP. **Cerrado como coste aceptado, 5-oct-2026**: nadie necesita el barrido sin
pérdida, y retener el motor sin más empalmaría un rayo en silencio. Detalle en `fases.md#z4`, entradas del 4-oct.

**Infraestructura de medida, 3-oct-2026.** `tools/net_drx_link.sh` deja el enlace cableado al DRx
con perfil persistente (192.168.1.1/24 estática, `never-default`): el perfil por defecto de
NetworkManager pedía DHCP en un enlace punto a punto y purgaba la dirección cada 45 s. Y
`tools/soak.sh` guarda UART y log del cliente en `build/soak/<fecha>/`, no en `/tmp` — un reinicio
de la máquina se llevó el soak 5 entero, y solo se recuperó porque la placa siguió encendida y los
contadores vivían en su RAM.

Lo que sí está hecho y verificado, además de lo de arriba:

- El sitio de documentación se construye y se despliega solo a
  <https://lamula-drx-docs.pages.dev> en cada push a `main` que toque `docs/`. Detalles,
  credenciales y deuda conocida del CI en `docs/implementacion/infraestructura.md`.
- El plan de 28 semanas (Z0–Z5), doce decisiones congeladas, el plan de verificación y el registro
  delta de portabilidad están escritos y publicados.
- P-01 (tolerancia de celda) cerró el 7-sep-2026: exactitud requerida, confirmado también en modo
  fino. P-05 (`RDA_Backend_Py`) sigue abierto, sin localizar.

## Orden de lectura

1. `docs/alcance/contexto.md` — qué es y qué no es, y la relación con los proyectos DSP y RCP.
2. `docs/alcance/decisiones.md` — las doce decisiones congeladas (D-01…D-12). Ninguna se revierte
   sin discutirlo.
3. `docs/alcance/pendientes.md` — hallazgos (P-01…P-23), supuestos de entorno a verificar y
   riesgos de la estrategia ZedBoard.
4. `docs/implementacion/fases.md` — el plan de trabajo.
5. `AGENTS.md` — las reglas que no se negocian, antes de escribir la primera línea de código.

`docs/referencia/` conserva íntegros los dos documentos de los que deriva todo lo anterior: el plan
de ZedBoard y el project plan original de 34 semanas para la ZU9.

## Lo primero que hay que hacer

1. Puente equivalente para la ZU9 (`zynq_ultra_ps_e`, IP distinta de `processing_system7`) — sin
   diseñar, se hace cuando haga falta. Cuando se retome: este Vivado 2022.2 tampoco tiene el device
   pack de Zynq UltraScale+ instalado (ver A11 en `pendientes.md`), así que instalarlo es requisito
   previo a cualquier síntesis contra `xczu9eg-ffvb1156-2-e`, no solo al diseño del puente.

**Confirmar ZM0 con un `git push` real** ya **no** está en esta lista: confirmado el 26-sep-2026. El
push de `8b3302a` disparó el job `ci` en el runner `[self-hosted, vivado]` y las cinco etapas del
camino completo (síntesis+impl → XSA → BSP/FSBL/app vía Vitis → `BOOT.BIN` reproducible →
`upload-artifact`) corrieron solas y en verde (run 36262739882, 26m49s). Detalle en la sección de
Z0 más arriba.

**BSP/FSBL vía Vitis** ya **no** está en esta lista: cerrado a mano el 26-sep-2026.
`tcl/gen_bsp.tcl` + `tools/build_vitis.sh` (nuevos) generan BSP/FSBL/`drx_app` con `xsct` desde el
XSA de `-top zynq -step xsa`; `tools/make_boot.sh` ya no falla y `BOOT.BIN` salió reproducible byte a
byte (mismo SHA-256 en dos corridas de `bootgen`). `drx_app.elf` es la plantilla *Hello World* de
Vitis, un placeholder deliberado — no lee ni un registro del mapa AXI-Lite, no corre FreeRTOS; el
firmware real (FreeRTOS, ensamblado de rayos, lwIP) sigue siendo el resto de Z4, sin empezar, y nada
de esto se probó en una ZedBoard física. Dos bloqueos de entorno nuevos en esta máquina, mismo patrón
que el Pi-hole del 21-sep (de sistema, no arquitectónicos): `xsct` necesita `Xvfb` y, aparte,
`libtinfo.so.5` (Ubuntu 22.04 solo trae `libtinfo6`; el paquete `libtinfo5` vive en `universe`) —
ninguno estaba instalado, los dos resueltos con `apt-get install`. El aviso de solapamiento de rangos que `bootgen` emite entre
`fsbl.elf`/`drx_top.bin`/`drx_app.elf` quedó **cerrado como falso positivo el 1-oct-2026**, con
datos: `bootgen -arch zynq -read BOOT.BIN` da `load_addr` `0x0` para el FSBL (longitud `0x18008`),
`0x0` para el bitstream y `0x00100000` para `drx_app.elf` — el FSBL termina muy por debajo de
`0x100000`, y el único solapamiento es contra el `0x0` del bitstream, que no es una dirección de
memoria (se carga por PCAP). Ya no es deuda abierta. Detalle completo en `fases.md#z1`, entrada del 26-sep.

**Montar el runner de CI `[self-hosted, vivado]`** ya **no** está en esta lista: cerrado el
21-sep-2026. El bloqueo de `gh auth login` era de credenciales (necesitaba `--web` o un PAT, no
disponible interactivamente en esta sesión), no arquitectónico — un self-hosted runner puede ser
esta misma máquina de desarrollo, y el token de registro se generó desde la web de GitHub sin
depender de `gh` autenticado aquí. `HAS_VIVADO_RUNNER=true`, runner instalado como servicio systemd.
De paso salieron tres bugs reales en código que nunca se había ejecutado de punta a punta (lint de
HDL de CI desincronizado de `make lint-hdl`, DRC de `write_bitstream` bloqueando `debug_probe`,
nombre de archivo equivocado en `tools/make_boot.sh`) y un hallazgo nuevo (`zu9` sin device pack de
UltraScale+, sacado de la matriz de CI por ahora). Detalle completo en `fases.md#z1`, entrada del
21-sep (más tarde), y A7/A8/A11 en `pendientes.md`.

**Conmutación en caliente fino/grueso** ya **no** está en esta lista: cerrada como no-requisito el
21-sep-2026, no diferida. Se preguntó para qué serviría cambiar de celda a mitad de rayo antes de
diseñar el modelo de referencia que hacía falta para verificarlo — ningún documento del repo
explicaba el motivo, solo que estaba diferido. Confirmado por vladimir: no tiene sentido, la
resolución de celda solo cambia entre rayos distintos, nunca dentro de uno. El mux estático que ya
existe en `rtl/drx_ddc_top.sv`/`rtl/drx_range_gate.sv` (`mode_coarse` fijo durante una corrida, ya
escribible en tiempo de ejecución) cubre el caso de uso real sin necesitar continuidad de fase.
Detalle en `fases.md#z1`, entrada del 21-sep.

**Puente PS7↔AXI para el mapa de registros** ya **no** está en esta lista: cerrado el 20-sep-2026
(más tarde), override explícito del usuario de "no diseñar por adelantado" tras ver el alcance real
del cambio. `tcl/gen_zynq_bd.tcl` (PS7 + interconnect + `axi_protocol_converter` hacia AXI4-Lite) +
`rtl/drx_zynq_top.sv` (nuevo, PS7 no puede vivir dentro del BD como referencia de módulo SystemVerilog
en Vivado 2022.2, confirmado) + `tcl/build.tcl -top zynq -step xsa`. P&R real cierra: **WNS = 1,712
ns, WHS = 0,033 ns**. El flujo de siempre sin PS7 sigue igual (`-top drx_top`, ahora vía
`rtl/drx_top_tieoff.sv`). Vitis instalado esta noche específicamente para esto
(`/home/orlando/tools/Xilinx_Vitis/`). Detalle completo en `fases.md#z1` y `registros.md`.

«Medir `report_utilization`/timing real de Config A específicamente» ya **no** está en esta lista:
cerrado el 20-sep-2026 sin correr ninguna síntesis nueva — Config A (Tx+H+V) y Config B (Tx+nominal+
atenuado) no tienen, hoy, ninguna diferencia sintetizable (mismo `generate` de `N_CH=3`, mismo
`INIT_FILE` replicado en los tres bancos de `vector_source.sv`). El P&R de `N_CH=3` ya corrido es a
la vez el de A y el de B. Detalle en `fases.md#z1`, entrada del 20-sep más tarde.

La discrepancia de DSP48 entre el P&R del 19-sep (153/220) y el del 20-sep (111/220) ya **no** está
en esta lista: quedó explicada el 20-sep más tarde — era una comparación entre post-síntesis y
post-rutamiento, no entre dos builds. **111/220 es la cifra correcta** para presupuesto de recursos.
Detalle en `fases.md#z1`.

`sim/tb_sv/drx_l1_checker.sv` ya tiene tolerancia (`TOLERANCE_LSB`, D-12) y la matriz de 16 corrió
16/16 «PASS» contra xsim real, confirmado — ese punto ya está cerrado, no solo decidido. La misma
matriz se volvió a correr completa el 20-sep-2026 tras añadir el puerto `overflow` a
`drx_ddc_top.sv`/`drx_ddc_quad_top.sv` (mapa de registros v2): **16/16 PASS** de nuevo.
`tb_l1_ddc_range_tri.sv` (fine/coarse, 3 canales cada uno) también se reconfirmó el mismo día tras
el puerto `clear` de `drx_range_gate`: **6/6 PASS**, TLAST bit a bit incluido.

Y no toques `R₁`/`R₂` ni `fs` en `config/params.toml` hasta que haya ADR: P-08 sigue abierto (P-01
ya cerró — exactitud requerida). Cuando lo haya, el cambio es de dos líneas más
`python3 tools/gen_params.py`.

P-08 ya no espera ningún dato externo: el rate mínimo del ADS42JB69 es de 60 MSPS en modo 10x, así
que los 143,9 MHz propuestos están en spec. Lo que falta es escribir el ADR que sustituya a D-04.

## Lo que está bloqueado, y por quién

| Bloqueante | Bloquea | Dueño |
|---|---|---|
| P-14 — varianza de los estimadores de momento (Doviak & Zrnic cap. 6) bajo el residuo aceptado por D-12 | No bloquea Z1 hoy, pero sí la confianza en D-12 a largo plazo | Especialistas de dominio |
| P-05 — `RDA_Backend_Py` sin localizar | Cerrar del todo P-01 con evidencia empírica de ORPG real (P-01 ya cerró por decisión, esto es la verificación que faltó) | vladimir |
| P-02 — capa física de los encoders SSI | La especificación de la portadora ZU9. Si es RS-422 y la portadora no lleva transceptores, falta hardware | Compra + especialistas |
| P-03 — plataforma de spike para JESD204B | El riesgo número uno del proyecto, que la ZedBoard no mitiga en absoluto | Dirección técnica |

El brief de `research/` para P-01/P-05 sigue listo para lanzarse en cuanto aparezca
`RDA_Backend_Py`; sin esa fuente el agente solo puede leer especificación, y ya hay precedente
documentado en `lamula-rcp/spike-fase0/RESULTADO-rda-orpg.md` de que eso no basta.

## Comandos

```sh
# sitio de documentación
uvx --with 'mkdocs-material==9.*' mkdocs serve
uvx --with 'mkdocs-material==9.*' mkdocs build --strict   # tiene que pasar limpio antes de commitear

# substrato
make venv          # crea .venv con requirements-dev.txt (pinado)
make check         # todos los gates del CI que corren sin Vivado
make gen           # regenera parámetros, coeficientes y contrato
make sim           # solo la suite L0 sobre Verilator

# gateware: ejecutado a mano, máquina de desarrollo con Vivado 2022.2; el
# runner de CI con Vivado todavía no existe (A7). `-step impl` (P&R real, sin
# bitstream: sin AXI-Lite/DMA las salidas de range-gate no tienen destino
# físico) cierra a 62,5 MHz desde el 19-sep-2026 (WNS = +2,770 ns)
python3 tools/gen_vector_source_init.py   # antes de sintetizar: $readmemh de vector_source lo necesita
vivado -mode batch -source tcl/build.tcl -tclargs -platform zedboard -step impl
vivado -mode batch -source tcl/build.tcl -tclargs -platform zedboard -step bitstream
vivado -mode batch -source tcl/sim_l1.tcl -tclargs -platform zedboard -case tono_if__fine
tools/make_boot.sh zedboard
```

## Advertencia que hay que repetir

Esta plataforma **no valida** JESD204B, el árbol de clocking y SYSREF, la sincronización
multi-dispositivo, los 250 MSPS, el frontal analógico real, la interfaz del DAC AD9129 ni la capa
física RS-422. El riesgo número uno del proyecto es hardware-bound y no se reduce con trabajo de
software. **No escribas «validado» donde corresponde «validado en ZedBoard».**
