# P-01 — barrido de re-derivación de rango en el resto del árbol de ORPG

**Para:** quien tenga montado el árbol `rpg_b24_0r1_20_pub_src` (paquete CODE del ROC, build 24) —
persona o agente.
**Origen:** [`p-01-RESULTADO.md`](p-01-RESULTADO.md), sección «Qué falta para cerrar P-01».
**Coste estimado:** una tarde. Es el único trabajo pendiente que puede **tumbar** la recomendación
de R₂ = 417, así que va antes que seguir buscando `RDA_Backend_Py`.

Todo lo de abajo es lectura de código. No hace falta compilar ni ejecutar nada de ORPG.

```sh
# Ajusta esto una vez y el resto de los comandos funciona tal cual.
export ORPG=".../CODERPG Build 24.0/20260715033855/rpg_b24_0r1_20_pub_src"
cd "$ORPG"
```

---

## Tarea 0 — reverificar las cuatro citas decisivas (10 minutos)

El resultado de agosto se escribió en una máquina que ya no tiene el árbol. Antes de usarlo para
mover D-04, comprueba que estas cuatro líneas dicen lo que el documento afirma. Si alguna no
coincide, **para y avisa**: el resto del documento queda en cuarentena.

```sh
sed -n '198,204p'   include/generic_basedata.h    # short bin_size, en metros
sed -n '1010,1020p' include/basedata.h            # MAX_BASEDATA_REF_SIZE 1840, REF_SIZE 460, RHO 1200
sed -n '2925,2942p' src/cpc102/tsk033/pbd.c       # SNR_build_range_corr_table, literal 0.25
sed -n '3115,3130p' src/cpc102/tsk033/pbd.c       # el gate es != 1000, no == 250
```

Los números de línea pueden haberse desplazado si la copia no es exactamente la misma build; en ese
caso localiza por contenido, no por línea, y **anota los números reales** en el informe:

```sh
grep -n "bin_size" include/generic_basedata.h
grep -n "SNR_build_range_corr_table" src/cpc102/tsk033/pbd.c
grep -rn "MAX_BASEDATA_REF_SIZE\|BASEDATA_REF_SIZE\|BASEDATA_RHO_SIZE" include/basedata.h
```

## Tarea 1 — el barrido (lo importante)

La pregunta es una sola: **¿hay en el resto del árbol alguna expresión que calcule un rango o una
distancia a partir de un índice de bin sin usar el campo de espaciado declarado?** Una sola en la
cadena de composición o en el remuestreo a rejilla Level-III cambia la conclusión de P-01.

El patrón sano es `range = first_gate_range + i * bin_size`. El patrón que rompe todo es cualquier
variante de `range = i * 250` — o `* 0.25`, o `* 1000.0`, o una macro que valga eso.

### 1a — gates de igualdad sobre el espaciado

```sh
grep -rn --include=*.c --include=*.h \
  -e 'surv_bin_size *[=!]=' \
  -e 'dop_bin_size *[=!]=' \
  -e 'bin_size *[=!]=' \
  src/ | grep -v 'cpc102/tsk033' | tee /tmp/p01-gates.txt
```

Por cada resultado, anota: fichero, línea, contra qué valor compara, y **qué pasa en la rama
`else`**. El hallazgo de `pbd.c` no fue la comparación en sí, fue que la rama que no era 1000 usaba
una tabla calculada para 250.

### 1b — literales de 250 m y de 1 km mezclados con índices de bin

```sh
grep -rn --include=*.c --include=*.h \
  -e '0\.25 *\* *(\?\(float\)\? *[a-z_]*i' \
  -e '\* *0\.25' -e '0\.25 *\*' \
  -e '\* *0\.125' -e '0\.125 *\+' \
  -e '\* *250\b' -e '\b250 *\*' \
  -e '\* *1000\.0\?\b' \
  src/ | grep -v 'cpc102/tsk033' | tee /tmp/p01-literales.txt
```

Esto va a dar mucho ruido (conversiones de unidades legítimas, escalados de producto). El filtro
mental es: **¿el otro operando es un índice de bin o de gate?** Si sí, es hallazgo. Si es una
conversión de metros a kilómetros sobre una magnitud ya calculada, no lo es.

### 1c — declaraciones de arreglo dimensionadas a la rejilla

Un arreglo de 460, 1840 ó 1200 elementos indexado por gate es una asunción de rejilla cableada,
igual que `Bintbl`.

```sh
grep -rn --include=*.c --include=*.h \
  -e '\[ *460 *\]' -e '\[ *920 *\]' -e '\[ *1200 *\]' -e '\[ *1840 *\]' \
  src/ | grep -v 'cpc102/tsk033' | tee /tmp/p01-arreglos.txt
```

### 1d — dónde mirar primero, si no da tiempo a todo

Por orden de daño si la asunción está cableada:

1. **Remuestreo a rejilla de producto Level-III.** Los productos viven en rejillas fijas de 1 km y
   0,25 km. Si el remuestreo interpola desde el rango declarado, un error sub-bin es inocuo; si
   asume correspondencia directa índice-a-índice, el error se propaga entero.
2. **Composición y mosaico** — combinan radiales de barridos y de radares distintos.
3. **Acumulación de precipitación** (los productos de lluvia integran sobre el rango).
4. **Dealiasing dual-PRF, VAD/VWP, ecos de tierra.**
5. **Cálculos de altura y de elevación** — la corrección por curvatura terrestre y refracción usa
   el rango.

```sh
ls src/                      # localizar los cpc0xx de producto
grep -rln "n_surv_bins\|surv_bin_size\|first_gate_range" src/ | cut -d/ -f1-2 | sort -u
```

Ese último comando da la lista corta de tareas que tocan geometría de base data. Es por donde
empezar.

## Tarea 2 — resolver el riesgo de lectura fuera de arreglo

Quedó en «plausible, no demostrado». Dos preguntas concretas sobre `src/cpc102/tsk033/pbd.c:2570-2584`:

1. **¿`rpg_hd->n_surv_bins` en el bucle es el conteo crudo de gates del Message 31, o un conteo ya
   remuestreado a 1 km?** Seguir el campo desde donde se asigna en `pbd_process_header.c` hasta ese
   bucle.
2. **¿La ruta AVSET se ejecuta con datos de alta resolución, o está condicionada a algo que la
   apague?** Buscar el llamador de esa función y sus guardas.

```sh
grep -rn "n_surv_bins" src/cpc102/tsk033/ | head -40
grep -rn "Bintbl\|Bintbl_sr\|Area_low_refl" src/cpc102/tsk033/
```

Si `n_surv_bins` puede valer más de 460 cuando `surv_bin_size != 250`, el hallazgo se confirma y
sube de «tabla mal alineada» a «lectura fuera de límites». Si no puede, se cae y hay que borrarlo
del resultado — la recomendación no cambia, pero el documento no puede quedarse con una afirmación
falsa dentro.

## Tarea 3 — de paso, si el árbol está montado

Dos preguntas baratas que el resultado dejó abiertas y que se contestan en el mismo sitio:

- **¿Valida ORPG el espaciado declarado contra una lista de valores esperados en algún punto de
  entrada?** Si existe una lista blanca, declarar 249 podría no ser «ruta mal alineada» sino
  rechazo. Buscar validación en el parser de Message 31, no solo en `pbd`.
- **¿Cuál es el tope de gates de velocidad y de dual-pol en la práctica?** `BASEDATA_RHO_SIZE 1200`
  a 250 m son 300 km. Confirmar que el modo de 250 m de LAMULA no excede eso en Doppler, que es un
  tope distinto y más bajo que el de reflectividad.

---

## Qué devolver

Un fichero para `research/`, con el mismo formato que `p-01-RESULTADO.md`:

- **Por cada afirmación, la cita `fichero:línea`.** Sin cita es hipótesis, no hallazgo.
- **Qué se revisó y qué no**, explícito. La crítica al resultado anterior fue exactamente esa: dijo
  «confirmado» sobre un subdirectorio de unos 35.
- **Separar hallazgo de inferencia.** Si algo es plausible pero no demostrado, decirlo así.
- **El veredicto binario:** ¿aparece o no aparece alguna re-derivación de rango cableada fuera de
  `cpc102/tsk033`? Si aparece, en qué cadena y con qué consecuencia para un espaciado declarado de
  250 frente a uno de 249.

Con eso, más `RDA_Backend_Py` si aparece, P-01 se puede cerrar y D-04 se sustituye por un ADR.
