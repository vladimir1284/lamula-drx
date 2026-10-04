# P-21 · Evidencia de las tres corridas desatendidas (3 y 4 de octubre de 2026)

Esta carpeta conserva las capturas del ILA de las tres corridas desatendidas que se hicieron para
medir cada cuánto se atasca el MM2S del estímulo. Está aquí, y no en `build/soak/`, porque
`build/` está en `.gitignore` y la evidencia se habría perdido en el primer borrado del árbol de
construcción.

El trabajo quedó **aparcado**, no cerrado: ver [P-21](../../../alcance/pendientes.md#p-21) para el
estado y el razonamiento. Lo que sigue es el dato en bruto y su lectura, para que quien lo retome
no tenga que repetir las noches.

## Cómo se produjo

Las tres corridas usaron el mismo bitstream de depuración, el mismo firmware (sondeo del MM2S a
1 ms, `configTICK_RATE_HZ (1000)`) y el mismo orquestador `tools/noche_p21.sh`, sin un solo cambio
entre ellas. Cada corrida arranca sobre una placa recién encendida con `SW8`: el atasco de P-21 es
permanente por diseño del firmware —`set_modo_ddr(true)` corre antes de `submit_pass()` y la ruta
de fallo no lo baja— así que una corrida equivale exactamente a un atasco, y no hay recuperación
por software.

El conductor es un bucle de `tools/sweep_catalogo.py --settle 1`, que encadena selecciones de
estímulo. Las capturas se leen con `tools/ila_p21_leer.py`.

## Resultado

| | corrida 1 | corrida 2 | corrida 3 |
|---|---|---|---|
| directorio original | `noche-20261003-215159` | `noche-20261004-071308` | `noche-20261004-122254` |
| inicio | 2026-10-03T21:54:27 | 2026-10-04T07:15:54 | 2026-10-04T12:25:39 |
| atasco | 2026-10-03T22:02:09 | 2026-10-04T08:12:12 | 2026-10-04T13:27:53 |
| tiempo hasta el atasco | 7 min 42 s | 56 min 18 s | 62 min 14 s |
| selecciones encadenadas | 323 | 2837 | 3141 |
| pasadas completas del catálogo | 41 | 354 | 392 |
| líneas precursoras (`pasada sin completar tras`) | 7 | 0 | 0 |
| disparos naturales del ILA (flanco de `stalled`) | 4 | 0 | 0 |
| `trig_gaps` al final | 2 (d=2) | 30 (d=2) | 50 (d=2) |
| `snd_fail` al final | 38 | 325 | 364 |

`trig_gaps` y `snd_fail` escalan con la duración de la corrida y son artefactos de la interacción
con el cliente (del orden de 1500 ciclos de conexión y desconexión por corrida). No son
indicadores de salud y no se usan como tales.

## Lo primero que dice el dato: hay dos modos de fallo distintos, no una sola distribución

Las corridas 2 y 3 coinciden entre sí dentro del 10 % en selecciones y en tiempo, y sus capturas
son idénticas columna por columna. La corrida 1 es ocho veces más corta, es la única con líneas
precursoras, la única en la que el ILA disparó solo, y su estado final es el opuesto. Promediar
las tres como si fueran muestras de la misma distribución daría una «cola larga» que el dato no
respalda.

### Modo A — la cadena se queda llena y bloqueada (corrida 1)

Los cuatro disparos naturales (`c1-flanco-1.csv` … `c1-flanco-4.csv`) son idénticos entre sí, y
son la evidencia más valiosa del conjunto porque llevan calificación de almacenamiento sobre
`moved`: de las 4096 muestras, 4095 son los últimos ciclos en que la cadena avanzó una muestra, y
la última es el ciclo del disparo.

En las 4095 muestras con movimiento: `ddr_mode = 0`, `timing_paced = 0`, `moved = 1`,
`idle_cnt = 0`. En la muestra del disparo: `ddr_mode = 1`, `timing_paced = 1`, `moved = 0`,
`stalled = 1`, `idle_cnt = 1048576` exactamente, o sea 2²⁰, el umbral.

El hecho es que en los últimos 4095 avances de muestra antes de cada parada, `ddr_mode` valía 0
todas las veces. La inferencia inmediata, y es fuerte: **en esa corrida la cadena no avanzó ni una
sola muestra con `ddr_mode = 1`**. El camino DDR no entregó nada, nunca, en lugar de entregar unas
cuantas y atascarse después.

El estado congelado (`c1-forzado.csv`, las 4096 muestras constantes) es el de una cadena llena que
nadie vacía: `m_ray_valid = 1` con `m_ray_ready = 0` —el S2MM no acepta—, `gate_valid = 0b111` con
`gate_ready = 0b000`, `s_vec_valid = 0` con `s_vec_ready = 1`, y `idle_cnt` saturado en
`0xffffff`. Los cuatro disparos cayeron a intervalos de 26 a 27 segundos, y el cuarto coincide con
la marca de tiempo del mensaje de atasco.

### Modo B — la cadena se queda vacía y drenada (corridas 2 y 3)

`c2-forzado.csv` y `c3-forzado.csv` son el inverso exacto, y entre sí son indistinguibles. Las
4096 muestras son constantes y consecutivas (`idle_cnt` incrementa de uno en uno, sin calificación
de almacenamiento, porque son capturas forzadas con `-trigger_now`):

```
dbg_s_vec  = 2    s_vec_valid=0 s_vec_ready=1 s_vec_last=0
dbg_m_ray  = 2    m_ray_valid=0 m_ray_ready=1 m_ray_last=0
dbg_ctrl   = 07   ddr_mode=1 timing_enable=1 timing_paced=1 moved=0 pulse_trig=0 stalled=0
vs_valid   = 0b000      vs_ready  = 0b111
ddc_valid  = 0b000      gate_valid = 0b000      gate_ready = 0b000
overrun    = 0b000      truncated  = 0b000
```

Aquí el S2MM sí acepta (`m_ray_ready = 1`) y no hay nada que entregarle. No hay contrapresión
desde el consumidor: simplemente no llega dato desde el MM2S.

## Las dos incógnitas que quedan vivas

**1. `stalled` no dispara en el modo B, y por eso el instrumento no sirve tal como está.** Tres
corridas seguidas, 118 minutos acumulados de cadena parada, y el flanco de `stalled` no subió ni
una vez en las corridas 2 y 3. Sin la foto forzada por el vigía no habría quedado nada. Quien
retome esto tiene que cambiar la condición de disparo antes de volver a correr una noche.

**2. Algo resetea `idle_cnt` periódicamente durante el atasco del modo B, y no se sabe qué.** En la
foto forzada de la corrida 2, `idle_cnt` recorre 11223 → 15318; en la de la corrida 3, 20864 →
24959. Las dos fotos se tomaron entre 45 y 49 segundos **después** del mensaje de atasco. Si nada
reseteara el contador llevaría del orden de 3·10⁹ ciclos y estaría saturado en `0xffffff`, como en
la corrida 1. O sea que el contador se reinicia cada pocas décimas de milisegundo mientras la
cadena está supuestamente muerta.

`drx_debug_probe.sv` solo tiene dos condiciones de reseteo: `!armed` o `moved`, con
`armed = ddr_mode || s_vec_valid`. Dentro de las ventanas capturadas `ddr_mode` vale 1 y `moved`
vale 0 en las 4096 muestras, así que el reseteo ocurre fuera de la ventana. Quedan dos
explicaciones, y el instrumento actual no las distingue:

- el MM2S entrega una muestra suelta de vez en cuando, o sea el atasco es un goteo y no una
  parálisis total — esto explicaría además por qué `idle_cnt` nunca llega a 2²⁰ y `stalled` nunca
  sube;
- `ddr_mode` cae durante algún ciclo.

La primera parece más probable porque explica las dos observaciones a la vez, pero con dos puntos
de dato es una hipótesis, no un hallazgo.

**3. El modo A no reprodujo.** Dos horas de intento entre las corridas 2 y 3, y el estado final de
la corrida 1 no volvió a aparecer. La «inversión de causalidad» —que el S2MM deje de aceptar antes
de que el MM2S se quede sin alimentar— descansa sobre una sola corrida y está contradicha por las
otras dos. No se escribió como hallazgo por eso.

## Lo que no es evidencia

Los volcados de los registros del AXI DMA leídos por JTAG sobre la cadena congelada son basura y
no deben usarse. Los punteros de descriptor de scatter-gather tienen que estar alineados a 64
bytes, y tres de los cuatro leídos no lo están (`MM2S_CURDESC = 0x02345920`,
`MM2S_TAILDESC = 0x02346048`, `S2MM_TAILDESC = 0x02321216`; solo `S2MM_CURDESC = 0x02321600`
cumple). Son valores imposibles, no lecturas con ruido. El mismo veredicto que ya se había
registrado para el `MM2S_DMASR = 0x00086281` de la primera sesión. El ILA es el único instrumento
fiable sobre esta placa con la cadena parada.

## Ficheros

| Fichero | Qué es |
|---|---|
| `c1-flanco-1.csv` … `c1-flanco-4.csv` | corrida 1, los cuatro disparos naturales por flanco de `stalled`, con calificación sobre `moved` |
| `c1-forzado.csv` | corrida 1, estado congelado tras el atasco permanente |
| `c2-forzado.csv`, `c3-forzado.csv` | corridas 2 y 3, estado congelado (no hubo disparos naturales) |
| `c1-disparos.tsv`, `c2-disparos.tsv`, `c3-disparos.tsv` | bitácora de disparos de cada corrida: marca, iteración, estado y modo |

Para leer cualquiera de ellos:

```sh
python3 tools/ila_p21_leer.py docs/implementacion/evidencia/p-21/c3-forzado.csv
```

Conviene recordar que `ila_p21_leer.py` imprime solo dos muestras. En las capturas forzadas todas
las columnas menos `idle_cnt` son constantes, así que esas dos bastan; en las capturas con
calificación de almacenamiento, no — ahí hay que mirar la distribución de las 4096 filas, que es
donde está el dato de `ddr_mode = 0` en todos los avances.
