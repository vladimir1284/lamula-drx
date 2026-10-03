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
`drx_debug_probe` son 2²² ciclos ≈ 67 ms a 62,5 MHz, y tiene que ser de ese
orden: `DrxStimulusTask` sondea cada 10 ms, así que entre dos pasadas hay
huecos legítimos de milisegundos y un umbral corto dispararía con la cadena
sana.

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

Un `s_vec_valid` alto durante 67 ms seguidos ya es, por sí solo, un fallo:
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
