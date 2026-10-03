# ILA de depuración (P-21)

Instrumento, no funcionalidad. Existe para contestar **una** pregunta que ningún
otro mecanismo de este repositorio puede contestar hoy: cuando el camino
MM2S → `vector_source` → DDC se para,
[¿dónde se para?](../alcance/pendientes.md#p-21)

No entra en la build de producción. `tcl/build.tcl` sin `-debug 1` no lee el
XCI del ILA, no define `DRX_DEBUG_ILA` y no inserta `dbg_hub`; el netlist es el
de siempre salvo el contador de `drx_debug_probe`, que sí vive en las dos
builds porque cuelga de un puerto real de `drx_top`.

## Por qué hace falta un ILA y no bastan los registros

Las tres formas de mirar que ya existen fallan, cada una por un motivo
distinto:

- **El mapa AXI-Lite** no expone un solo handshake de la cadena. Expone
  resultados (`STATUS`, `OVERFLOW`, `GATE_TRUNCATED`, `TRIG_COUNT`), que es lo
  correcto para un BITE y lo inútil para localizar un atasco.
- **Los registros del AXI DMA leídos por JTAG no son fiables.** `xsct` para el
  Cortex-A9 en cada `mrd` (23 s de reloj de pared contra 16 s de `uptime` de
  FreeRTOS durante una ráfaga, medido el 2-oct-2026), así que el acto de medir
  cambia lo medido. En la corrida del 3-oct `MM2S_DMASR = 0x00086281` decodificaba
  a errores de SG en un canal que estaba entregando 225 rayos/s: un dato que no
  se puede usar para concluir nada.
- **La simulación no reproduce el fallo**, porque el fallo aparece encadenando
  `test_stimulus_select` sobre un firmware real contra un DMA real.

## Las dos piezas

**`rtl/drx_debug_pkg.sv`** fija el orden de los bits del bus, una sola vez.
**`rtl/drx_debug_probe.sv`** empaqueta los handshakes y cuenta ciclos sin
avance de muestra. Los dos extremos —la sonda que escribe el bus y
`rtl/drx_zynq_top.sv`, que lo trocea en probes— usan los mismos nombres del
paquete. Con los números repetidos a mano, un cambio de orden daría una captura
perfectamente legible y equivocada: diría que se para `ddc_valid` donde se para
`vs_ready`.

| Probe | Ancho | Qué lleva |
|---|---|---|
| `probe0` | 3 | `s_vec_valid`, `s_vec_ready`, `s_vec_last` — el beat que entra del MM2S |
| `probe1` | 3 | `m_ray_valid`, `m_ray_ready`, `m_ray_last` — el rayo que sale al S2MM |
| `probe2` | 6 | `ddr_mode`, `timing_enable`, `timing_paced`, `moved`, `pulse_trig`, `stalled` |
| `probe3` | 3 | `vs_valid` por canal — `vector_source` presenta el conjunto |
| `probe4` | 3 | `vs_ready` por canal — el DDC lo acepta |
| `probe5` | 3 | `ddc_valid` por canal |
| `probe6` | 3 | `gate_valid` por canal |
| `probe7` | 3 | `gate_ready` por canal |
| `probe8` | 3 | `overrun` del range-gate por canal |
| `probe9` | 3 | `ray_truncated` por canal |
| `probe10` | 24 | ciclos desde el último avance de muestra |

## El disparo, que es la parte no obvia

El atasco se **detecta** mucho después de empezar. El umbral de
`drx_debug_probe` son 2²⁰ ciclos ≈ 16,78 ms a 62,5 MHz, y no puede bajar sin
límite: `DrxStimulusTask` sondea el anillo del MM2S cada
`DRX_STIMULUS_POLL_MS`, así que entre dos pasadas hay huecos legítimos de ese
orden y un umbral corto dispararía con la cadena sana.

El umbral y el sondeo se bajaron juntos el 3-oct-2026, y no se pueden mover por
separado. El primer umbral fueron 2²² ciclos (67,1 ms) porque el sondeo eran
10 ms; eso dejaba invisible cualquier atasco intermitente más corto que 67 ms,
y P-21 podía perfectamente ser un hueco repetido de 15-20 ms en vez de una
parada definitiva. Bajar el sondeo a 1 ms pedía además subir el tick de
FreeRTOS: `freertos10_xilinx` arranca en `tick_rate 100`, o sea un tick de
10 ms, con lo que `pdMS_TO_TICKS(1)` se redondea a 0 y `vTaskDelay` degenera en
un `taskYIELD`. Con `bsp config tick_rate 1000` (`tcl/gen_bsp.tcl`) el sondeo
es de verdad 1 ms, el hueco legítimo baja a ~1-2 ms y 2²⁰ deja 10× de margen.
Ningún otro retardo del firmware cambia de duración: todos convierten con
`pdMS_TO_TICKS` o dividen por `configTICK_RATE_HZ`.

La ventana del ILA, en cambio, son 4096 muestras = **65 µs**. Disparando con
`stalled` y guardando todas las muestras, el buffer entero caería dentro del
silencio posterior a la parada: 4096 ciclos en los que, por definición, no pasa
nada.

### Cuándo cuenta el contador

No basta con "modo Throttled(DDR)", y esto estuvo mal en el primer diseño de
la sonda. La condición es `ddr_mode || s_vec_valid`.

El motivo es que el atasco que se persigue puede dejar `ddr_mode` en **bajo**
con un descriptor del MM2S todavía en vuelo: `DrxStimulus_Stop()` termina
llamando a `set_modo_ddr(false)`, así que si el drenado salió antes de tiempo
el DMA se queda ofreciendo un beat (`s_vec_valid = 1`) que `vector_source` ya
no puede aceptar, porque `s_axis_ready = ddr_mode && !ddr_presenting`. Con el
contador atado solo a `ddr_mode`, la sonda se desarmaría **justo al entrar en
el estado que hay que capturar** y el ILA no dispararía nunca. El L0 lo cubre
con un caso propio, comprobado contra esa misma mutación.

Un `s_vec_valid` alto durante 16,78 ms seguidos ya es, por sí solo, un fallo:
nadie ofrece un beat tanto tiempo si la cadena funciona.

### El almacenamiento calificado

De ahí `C_EN_STRG_QUAL = 1`. Con la condición de
almacenamiento puesta en "algo se movió", esas 4096 muestras son los últimos
4096 ciclos **con actividad** antes de la parada — que es exactamente la
evidencia que falta. `ALL_PROBE_SAME_MU_CNT = 2` porque el mismo probe
participa en la condición de disparo y en la de almacenamiento, y con una sola
unidad de comparación Vivado rechaza una de las dos.

## Cómo se corre

Una vez, para crear el XCI (ya está versionado; solo hace falta si se cambia la
configuración del core):

```sh
vivado -mode batch -source tcl/gen_ip_debug.tcl -tclargs -platform zedboard
```

La build:

```sh
vivado -mode batch -source tcl/build.tcl -tclargs \
       -platform zedboard -top zynq -debug 1 -step bitstream
```

Sale en `build/gw/zedboard_zynq_dbg/`: `drx_zynq_top.bit` y
`drx_zynq_top.ltx`. **El `.ltx` es obligatorio** — lleva los nombres de los
probes, y sin él el Hardware Manager abre el ILA igual pero con once vectores
anónimos.

No hace falta XSA ni firmware nuevos: el ILA no toca el mapa de direcciones del
PS7, así que el `drx_app.elf` de la build normal vale.

Cargar y arrancar, con el firmware de siempre:

```sh
xsct bringup/tcl/run_jtag.tcl \
     build/gw/zedboard_zynq_dbg/drx_zynq_top.bit \
     build/fw/zedboard/drx_app.elf \
     build/gw/zedboard_zynq/drx_zynq_top.xsa
```

Y después **cerrar `xsct`** antes de abrir el Hardware Manager: los dos hablan
con el mismo `hw_server`, y el ILA se lee sin parar el A9 solo si nadie más
tiene el DAP cogido.

```sh
vivado -mode gui &
# open_hw_manager; connect_hw_server; open_hw_target
# set_property PROBES.FILE build/gw/zedboard_zynq_dbg/drx_zynq_top.ltx [current_hw_device]
# refresh_hw_device [current_hw_device]
```

Armado típico: disparo en `probe2[5]` (`stalled`) con flanco de subida,
posición del disparo al final del buffer, y condición de almacenamiento sobre
`probe2[3]` (`moved`) u `OR` de `probe0[0]`/`probe1[0]`.

## Qué se espera ver, y qué distingue cada hipótesis

La captura discrimina entre las dos mitades del camino de un vistazo:

| Lo que se ve en el último ciclo con actividad | Lectura |
|---|---|
| `s_vec_valid = 1`, `s_vec_ready = 0` | La PL rechaza el beat. `vector_source` no está en modo DDR, o el conjunto presentado no se retira porque falta `vs_ready` de algún canal. |
| `s_vec_valid = 0`, `s_vec_ready = 1` | La PL espera y el DMA no entrega. El problema está aguas arriba: descriptores, SG o el propio firmware. |
| `vs_valid = 0b111`, `vs_ready` con algún bit a 0 | Contrapresión del DDC. Habría que mirar qué etapa de la cadena la origina. |
| `m_ray_valid = 1`, `m_ray_ready = 0` | El S2MM no drena y la contrapresión sube hasta la fuente. |

**Hipótesis de partida, escrita antes de medir para que la medida pueda
refutarla.** `reap_pass()` en `fw/src/app/drx_stimulus.c` llama a
`XAxiDma_BdRingFromHw(ring, XAXIDMA_ALL_BDS, …)`, que devuelve los descriptores
completados y puede devolver **menos de los `DRX_STIMULUS_BD_COUNT` de la
pasada**. Con eso pone `g_in_flight = false` y declara la pasada entera
terminada. Si eso pasa dentro del bucle de drenado de `DrxStimulus_Stop()`, el
drenado sale antes de tiempo, `XAxiDma_Pause()` deja el descriptor que faltaba
en poder del hardware, y `set_modo_ddr(false)` baja `ddr_mode` — con lo que
`s_axis_ready` de `vector_source` se va a 0 y ese descriptor ya no puede
completarse nunca. El anillo aguanta cuatro pasadas: a la cuarta,
`XAxiDma_BdRingAlloc` falla y no se encola nada más. Es el mismo agujero que el
arreglo de "drenar antes de pausar" cerró por un lado y esto reabre por otro.

Si la hipótesis es cierta, la captura tiene que mostrar `s_vec_valid = 1` con
`s_vec_ready = 0` y `ddr_mode = 0` en el mismo ciclo. Si `ddr_mode` sigue en 1,
la hipótesis es falsa y el atasco está en otro sitio.

El firmware se deja **sin tocar** para la captura, a propósito: arreglar la
hipótesis antes de medirla dejaría P-21 cerrado por coincidencia, sin saber si
era eso.


## Primera captura, 3-oct-2026

El instrumento funciona de punta a punta: once probes con nombre en el `.ltx`,
captura por `tools/ila_p21.tcl` y decodificación por `tools/ila_p21_leer.py`.
Pero la primera captura **no es la de P-21**: al recargar la placa apareció
otro fallo delante, y el ILA lo identificó en una sola foto.

4096 ciclos consecutivos, **todos idénticos**:

```
s_vec: valid=0 ready=0 last=0
m_ray: valid=1 ready=0 last=0
ctrl : ddr_mode=0 timing_enable=1 timing_paced=0 moved=1 pulse_trig=0 stalled=0
vs_valid=0b111  vs_ready=0b111  ddc_valid=0b000
gate_valid=0b111  gate_ready=0b000  overrun=0b111  truncated=0b000
```

Se lee de corrido, y en los dos sentidos:

- **Aguas abajo está todo parado en el DMA.** `m_ray_valid = 1` con
  `m_ray_ready = 0` durante 65 µs seguidos: el empaquetador ofrece y el S2MM
  no toma ni un beat. Detrás, `gate_valid = 0b111` con `gate_ready = 0b000` y
  `overrun = 0b111` — la contrapresión sube por la cadena exactamente como
  está diseñada, y el range-gate desborda porque nadie vacía.
- **Aguas arriba tampoco entrega el DMA.** `s_vec_valid = 0`: el MM2S no
  ofrece un solo beat. No es que `vector_source` lo rechace.
- **La PL está sana.** `vs_valid = vs_ready = 0b111` y `moved = 1`: en
  BRAM-loop las muestras siguen avanzando hacia el DDC sin problema, y el
  motor de timing corre (`timing_enable = 1`).

Los dos canales del mismo `axi_dma` parados a la vez, con la PL moviéndose,
señala al DMA y no a la lógica. Los registros lo confirman, leídos con el
A9 parado a propósito (nada estaba fluyendo, así que la contaminación por
`mrd` que documenta `fases.md` no aplica aquí):

```
MM2S_DMACR = 0x00010003   RS=1    MM2S_DMASR = 0x00010008   Halted=0, sin bits de error
S2MM_DMACR = 0x00017003   RS=1    S2MM_DMASR = 0x00010008   Halted=0, sin bits de error
MM2S_CURDESC = 0x0023cb80   MM2S_TAILDESC = 0x0023cbc0
S2MM_CURDESC = 0x00236b00   S2MM_TAILDESC = 0x00236bc0
```

Los dos canales **corriendo**, con descriptores pendientes
(`CURDESC != TAILDESC`), **sin un solo bit de error** y sin avanzar. Un DMA
que no da error y no progresa está esperando en su lado de memoria: la
búsqueda del descriptor por HP0 no vuelve. Y el procesador sí llega a la DDR
—la aplicación corre desde ahí, con UART, lwIP y el motor de timing vivos—,
así que lo que no responde es el puerto AFI/HP0, no la DDR.

*(Nota de lectura: el bit 1 de `DMACR` es reservado, no `Reset`.
`0x00010002` es el valor por defecto limpio del registro.)*

### Cómo se llegó ahí, y la regla que sale de esto

El primer arranque fallido es justo el siguiente a reprogramar la PL **con el
S2MM transmitiendo rayos a 225/s**. Reconfigurar la PL con transacciones AXI
vivas en HP0 deja la transacción colgada en el lado PS, donde ni la
reconfiguración de la PL ni `ps7_init`/`ps7_post_config` llegan.

Comprobado que no se recupera por software: dos recargas completas del
bitstream de producción, dos del de depuración, y un ciclo explícito de
`FPGA_RST_CTRL` (`0xF8000240` a `0xF` y de vuelta a `0x0`, con el SLCR
desbloqueado) — el síntoma no se mueve.

**Regla: parar el camino de rayos antes de reprogramar la PL.** Y si ya
pasó, hace falta un reset del PS — apagar y encender la placa.

No está excluido que la causa sea otra; lo que sí está medido es que el
síntoma sobrevive a todo lo que se puede hacer sin tocar la placa.

## Segunda sesión, 3-oct-2026 (tarde): la medida con la placa reiniciada

Con la placa apagada y encendida, el instrumento se usó de verdad. Tres
resultados, en orden de confianza.

### 1. El instrumento dispara, y está calibrado

Antes de leer nada en la ausencia de un disparo hay que probar que la sonda
**puede** disparar. El control positivo es un atasco provocado a mano:
`MM2S_DMACR` bit 0 (`RS`) a 0 **dejando `CTRL` bit 1 (`vector_source_ddr`) en
alto**, así que `armed` sigue alto y `moved` cae a 0. Es reversible, es una
escritura a un registro y no reprograma la PL.

El ILA disparó en el instante exacto de la escritura, y la muestra del disparo
trae `idle_cnt = 1048576` ciclos — 2²⁰ clavado, el umbral de hoy. El contador,
el flanco de `stalled`, la calificación de almacenamiento y el decodificador de
`tools/ila_p21_leer.py` quedan verificados contra silicio, no contra
simulación.

### 2. Con sondeo de 10 ms el MM2S deja huecos de más de 16,78 ms

Montado como A/B, no como anécdota. Las dos patas corren el **mismo** bitstream
de depuración, el mismo XSA y el mismo barrido
(`tools/sweep_catalogo.py --settle 1`, ocho selecciones encadenadas por vuelta):

| Firmware | Selecciones encadenadas | Disparos del ILA |
|---|---|---|
| sondeo 1 ms, tick 1 kHz | 80 (10 vueltas) | **ninguno** |
| sondeo 10 ms, tick 100 Hz | 24 (3 vueltas) | **2**, a los 32 s y a los 16 s |

Las dos patas no se pueden separar más: `pdMS_TO_TICKS(1)` vale 0 con el tick a
100 Hz, así que «sondeo de 1 ms» y «tick de 1 kHz» son una sola configuración,
no dos variables.

Las dos capturas del lado de 10 ms dicen lo mismo, y refutan la predicción que
se había escrito antes de medir:

```
ctrl : ddr_mode=1 timing_enable=1 timing_paced=1 moved=0 stalled=1
s_vec: valid=0 ready=1
vs_valid=0b000  vs_ready=0b111  overrun=0b000  truncated=0b000
idle_cnt = 1048576 ciclos (16,8 ms)
```

`s_vec_valid = 0` con `s_vec_ready = 1` y `vs_ready = 0b111`: **la PL está
esperando y el MM2S no entrega**. No hay un beat atascado que
`vector_source` rechace — que era la hipótesis — sino hambre. El consumidor
está listo; el productor no aparece. `overrun` y `truncated` en cero: nada se
rompió, nada se perdió.

### 3. Lo que esto NO cierra

**P-21 tal como está escrito no reprodujo hoy en ninguna de las dos patas.**
El hallazgo original es un atasco *permanente* que deja el MM2S sin
recuperarse; lo medido hoy es un hueco *transitorio* de más de 16,78 ms del
que la cadena sale sola — las 24 selecciones del lado de 10 ms terminaron
todas con `config_ack error=ok` y un rayo de vuelta, con `dma_overruns=0` y
`trig_gaps=0`.

Así que lo honesto es: el sondeo de 10 ms **sí** produce huecos de
alimentación medibles, y bajarlo a 1 ms los elimina; que eso sea además la
causa del atasco permanente de P-21 es plausible y no está demostrado. Falta
reproducir el atasco permanente con el instrumento armado.

## Recargar solo el ELF por JTAG: tres trampas, las tres medidas

Las dos patas del A/B se cargaron sin reprogramar la PL (el bitstream no
cambia entre ellas), y ese camino resultó tener problemas propios que cuesta
atribuir si no se conocen.

**1. El AXI DMA sigue escribiendo en DDR con el A9 detenido.** Es un maestro
independiente: `stop` para el núcleo, no el DMA. Lo que escribe cae encima de
la imagen que `dow` acaba de cargar. El síntoma fue
`drx_dma: el XSA no declara el AXI DMA`, o sea `XAxiDma_LookupConfig`
devolviendo NULL — y se descartó que fuera un problema del BSP volcando la
`XAxiDma_ConfigTable` de los dos ELF con `objdump`: **byte a byte idénticas y
correctas** (`DeviceId = 0`, `BaseAddr = 0x40400000`). El fichero estaba bien;
lo corrupto era la copia en DDR. Hay que poner `RS = 0` en los **dos**
`DMACR` antes de `stop`.

**2. Con los canales parados, el firmware nuevo no arranca.** No resetea el
core —no puede: un solo `axi_dma` sirve MM2S y S2MM, así que `XAxiDma_Reset`
se lleva por delante el otro canal—, así que `XAxiDma_BdRingStart` falla y el
arranque dice `no se pudo encolar la primera pasada` / `Select devolvio 9`.
Entre `dow` y `con`, con el A9 todavía detenido, hay que hacer el reset blando
a mano: `MM2S_DMACR` bit 2.

**3. Aun así no equivale a un arranque en frío.** Con las dos correcciones el
firmware arranca y los rayos fluyen (`overrun=0x0 truncated=0x0
dma_errors=0`), pero el lector de rayos cuenta **300 rayos/s contra ~220
disparos/s** y `trig_gaps` sube uno por rayo con `d=0`. Un arranque en frío da
228 y 228, y `trig_gaps = 0`.

De ahí la regla: **una medida tras una recarga en caliente no es comparable
con una de arranque en frío.** Las cifras del lado de 1 ms de la tabla de
arriba son de arranque en frío por eso. El lado de 10 ms es de recarga en
caliente, pero con los indicadores de un arranque limpio (`trig_gaps = 0`,
`dma_overruns = 0`) antes de empezar a medir.
