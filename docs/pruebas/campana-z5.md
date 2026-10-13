# Campaña de Z5: inyección de fallos, throughput y soak

**Borrador del 8-oct-2026. Nada de esto se ha ejecutado.** Es el plan de la campaña de
[Z5](../implementacion/fases.md#z5) sobre lo que existe hoy, sin escribir scripts que nadie ha
podido probar contra la placa. Parte del catálogo de [inyección de
fallos](plan-testing.md#inyeccion-de-fallos) y dice, fallo por fallo, **qué se puede provocar ya, con
qué, y qué hay que construir antes**.

Los observables son los que el sistema ya emite: la bandera `bite` de la trama `status`
(`SSA_UNDERRUN`, `DMA_OVERRUN`, `SSI_TIMEOUT`, `SSI_FRAME_ERROR`, `MMCM_UNLOCKED`, `LINK_DOWN`,
`CONFIG_REJECTED`), los códigos de error del contrato (`Error`, 0–12) y los contadores de la UART
(`dma_overruns`, `trig_gaps`, `ray_gaps`, `sink_drops`, `snd_fail`, `cola`, `enc_fail`).

## Catálogo

| Fallo | ¿Se puede provocar hoy? | Cómo | Resultado esperado (del plan de testing) |
|---|---|---|---|
| Configuración inválida del par remoto | **Sí, solo con el cliente** | `CONFIG` con PRF fuera de rango, ancho de pulso fuera de tabla o `afc` fuera de rango, por el socket. Ya hay precedente: `afc_out_of_range` vuelve como `last_error=12` con `CONFIG_REJECTED` (Z4.6) | Rechazo con código, **estado anterior preservado**: la tasa de rayos y `TRIG_COUNT` no se alteran. **Ejecutado el 12-oct-2026, pasa 5/5** (`tools/inyectar_fallos.py config`; ver [`fases.md#z5`](../implementacion/fases.md#z5)) |
| Pérdida de enlace Ethernet y reconexión | **Sí, desde el host** | Bajar y subir `enp1s0` (`tools/net_drx_link.sh` ya fija el perfil) o desconectar el cliente y reconectar. | Reconexión **sin reset de la placa**. `drx_transport.c` tiene un bucle de `lwip_accept` con contador `accepts` (línea 286), así que debería reaceptar; *no se había probado una caída real*. **Ejecutado el 12-oct-2026** (`tools/inyectar_fallos.py enlace`): reacepta sin reset, pero tarda hasta decenas de segundos si el cliente no cerró su socket, y `link_down` no se levanta ([P-25](../alcance/pendientes.md#p-25), [P-26](../alcance/pendientes.md#p-26)) |
| Overrun de DMA | **Solo de forma indirecta** | El consumidor lento del lado de la red **no** lo provoca: desde Z4.6 la tarea `drx_tx` desacopla el socket del anillo S2MM, así que un cliente lento sube `sink_drops`/`cola`, no `dma_overruns`. Para `dma_overruns` hay que frenar al PS. Se sabe que `mrd` por JTAG lo hace (para el A9), pero eso contamina cualquier medida | Descarte contabilizado, sin corrupción, BITE `DMA_OVERRUN`. **Ejecutado el 12-oct-2026 deteniendo el A9 por JTAG** (`tools/inyectar_fallos.py overrun`, sin firmware nuevo): pasa 5/5, y el BITE `dma_overrun` queda sticky de por vida ([`fases.md#z5`](../implementacion/fases.md#z5)) |
| Underrun de la fuente de muestras (SSA) | **No** | No hay inyector. `vector_load` congela la fuente (P-23), pero no se ha comprobado que eso levante `SSA_UNDERRUN` | BITE, gating parado limpiamente, recuperación sin reset. **Falta un hook en RTL** |
| Pérdida de lock de MMCM | **No** | Sin hook de RTL ni forma física de provocarlo | BITE `MMCM_UNLOCKED`, parada segura. **Falta un hook** |
| Glitch de encoder SSI | **Desconocido** | Depende de que exista el camino SSI; este borrador no lo ha verificado | Rayo marcado az/el inválido, **no descartado** |

Resumen honesto: **dos de seis** se pueden ejercitar hoy sin tocar RTL ni firmware. Las demás
exigen construir un inyector, y ese trabajo es de diseño, no de scripting.

## Criterios de paso, para todos

1. El BITE correspondiente se levanta y la trama `status` lo transporta.
2. `ray_gaps`, `trig_gaps` y los descartes aumentan **solo** lo que el fallo explica. Un fallo que
   corrompe un rayo sin contabilizarlo es un fallo de la campaña, no un pase.
3. La placa se recupera **sin reset**, salvo donde el catálogo diga «parada segura».
4. No se lee BITE durante una sesión de JTAG: `xsct` ya produce overruns por sí solo y contamina la
   lectura (hallazgo del 2-oct-2026).

## Throughput sintético

Objetivo del plan: el PS genera rayos a **19,23 MB/s** (154 Mbps), a 1,5× y a 2× (≈231 y 308 Mbps),
por GEM/lwIP con el framing real. Hoy el camino real entrega 28,9 Mbps (223 rayos/s medidos), así
que el generador sintético **no existe** y hay que escribirlo en firmware. Dos cosas por decidir
antes de empezar, que no son mías:

- Si el generador reemplaza a la tarea de rayos o corre junto a ella. Junto a ella mide el caso
  real; en su lugar mide solo la pila de red.
- Si 2× (308 Mbps) es un objetivo razonable para un lwIP en un A9 sin copia cero. *No lo sé; no hay
  ninguna medida de ese techo en el repositorio.*

El ensayo 2 del plan (generador de patrones en fabric hacia el S2MM) tampoco existe, y
`rtl/vector_source.sv` ya no tiene camino DDR desde el 4-oct (v11): habría que construirlo.

## Soak de 72 h

En curso desde el 8-oct-2026 19:36: `build/soak/20261008-193558/`. Criterio: `dma_overruns=0`,
`ray_gaps=0`, `BITE=0x0` y huecos de `seq` del cliente iguales a los `trig_gaps`/`ray_gaps` de la
UART. Cualquier hueco del cliente **sin** contador correspondiente en la placa es del host (P-19), no
de la placa.

**Defecto del cliente encontrado durante esta corrida:** `tools/mock_dsp.py` acumulaba todos los
rayos en una lista (~110 MB/h, ~8 GB proyectados a 72 h). Corregido en el repositorio el mismo día;
el proceso que ya corre usa la versión anterior.

## Fuera de esta campaña

JESD204B, clocking/SYSREF, multi-dispositivo, 250 MSPS reales, DAC AD9129 y RS-422 no se ejercitan
aquí: ver el [registro delta](../portabilidad/registro-delta.md).
