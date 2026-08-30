# Resultado — P-01: ¿qué tamaño de celda acepta realmente ORPG?

**Brief de origen:** [`p-01-orpg-gate-spacing.md`](p-01-orpg-gate-spacing.md).
**Fecha:** 30 de agosto de 2026.

## Procedencia de la evidencia

La investigación corrió **en otra máquina**, sobre una copia del paquete CODE del ROC:

```
CODERPG Build 24.0/20260715033855/rpg_b24_0r1_20_pub_src
```

Es árbol de fuentes real de ORPG build 24, no un simulacro. Confirmado por vladimir.

**Consecuencia para quien lea esto desde este repositorio:** el árbol no está en
`/home/node/workspace` ni en ninguna parte de la máquina de desarrollo, así que **las citas
`fichero:línea` de abajo no son reverificables aquí**. Se dan por buenas por procedencia, no por
comprobación local. Antes de que una de ellas tumbe una decisión congelada conviene reabrir el
árbol y releer las cuatro decisivas: `include/generic_basedata.h:202`,
`src/cpc102/tsk033/pbd.c:2934`, `src/cpc102/tsk033/pbd.c:3121`, `include/basedata.h:1015`.

**Fuentes no consultadas:** `RDA_Backend_Py` (Fuente 1 del brief, la única empírica) sigue sin
localizar — ver [P-05](../docs/alcance/pendientes.md#p-05). El ICD 2620002 (Fuente 3) no se leyó
directamente; lo que se sabe de él aquí es inferencia a partir del wire format en el código.

**Cobertura:** dirigida a la cadena `src/cpc102/tsk033` (`pbd.c`, `pbd_process_header.c`,
`pbd_process_data.c`), donde vive el procesamiento de base data. Quedan sin revisar unos 35
subdirectorios `cpc0xx`, incluidos los de composición, dealiasing, VAD/VWP y remuestreo a rejilla
Level-III. **No es un barrido exhaustivo.**

---

## Q1 — ¿campo transmitido o constante?

**Campo transmitido, y ORPG lo usa** para la geometría básica: offset del primer bin y número de
bins.

- `include/generic_basedata.h:200-202` — el moment header del wire format (`Generic_moment_t`)
  trae `first_gate_range` y `bin_size` como campos explícitos.
- `src/cpc102/tsk033/pbd_process_header.c:1959` — `rpg_hd->surv_bin_size = mom->bin_size;`
- `src/cpc102/tsk033/pbd_process_header.c:1978-1980` — el cálculo del offset del primer bin
  (`leading_edge_range`, `first_bin`) usa el campo declarado, no un literal.
- `src/cpc102/tsk033/pbd_process_header.c:2154` — el recorte a 70 000 ft también usa el campo.

Confianza alta para la cadena de ingesta. La excepción grave aparece en Q3.

## Q2 — ¿con qué cuantización se puede declarar el espaciado?

**Entero de 16 bits, unidad de 1 metro. 124,71 m no es declarable: se declara 125 ó 124.**

- `include/generic_basedata.h:202` — `short bin_size; /* Size of each gate for this moment in m. */`
- `include/basedata.h:356-359`, `:496-499`, `:730`, `:754` — la representación interna repite el
  tipo: `short surv_bin_size`, `short dop_bin_size`, ambos en metros.

Esto coincide con lo que declara el ICD 2620002 para el bloque de momento del Message 31 (*Range
Sample Interval* y *Range to center of first gate*, enteros de 16 bits en metros), de modo que la
conclusión no depende de una sola fuente.

Consecuencia aritmética: 124,71 → 125 ó 124; 249,41 → 249; 250,026 → 250. Ningún valor con parte
fraccionaria de metro es representable.

**Dónde ocurre la conversión:** `pbd_process_header.c:1959` es una asignación `short = short`. La
conversión de punto flotante a entero ya pasó antes, en quien construye el Message 31 — es decir,
en el firmware de LAMULA. La decisión de truncar frente a redondear es nuestra, no de ORPG, y **no
está verificada**: hay que mirar el backend de LAMULA, que está fuera de este repositorio.

## Q3 — ¿dónde re-deriva ORPG el rango en vez de usar el campo?

**Sí, y no es un remuestreo inocuo: es una tabla de corrección de rango cableada a 250 m que se
aplica a cualquier dato que no declare exactamente `surv_bin_size == 1000`.**

```c
/* src/cpc102/tsk033/pbd.c:2934-2938 — SNR_build_range_corr_table */
for( i = 0; i < MAX_BASEDATA_REF_SIZE; i++ ){
    r = 0.125 + (0.25* (float) i);        /* 250 m literal, no usa rpg_hd->surv_bin_size */
    Range_corr[i] = PBD_log_range[i] - Syscal + (r*Atmos);
}
```

El comentario de la propia función (`pbd.c:2929`) dice *«First time buffer allocation for the Range
Correction table for 250 m bin size»*: el autor asumió 250 m fijo.

El uso de esa tabla no está condicionado a `== 250`, sino a `!= 1000`:

```c
/* src/cpc102/tsk033/pbd.c:3121 — aplicación del umbral SNR */
if( rpg_hd->surv_bin_size == 1000 ){
    SNR_1km_reflectivity(...);                 /* camino de 1 km */
}
else{
    ...
    if( (z + Range_corr[i]) <= tz[QRTKM] )     /* tabla de 250 m cableada */
```

Cualquier valor que no sea 1000 —209, 249, 251, 416— entra al camino de alta resolución y recibe
una corrección de rango calculada para 250 m exactos, sea cual sea el espaciado declarado.

### Riesgo de lectura fuera de arreglo — plausible, no demostrado

La selección de tabla de área para AVSET sí compara con 250, y las dos tablas tienen tamaños
distintos:

```c
/* src/cpc102/tsk033/pbd.h:275-276 */
float Bintbl[460];
float Bintbl_sr[1840];

/* src/cpc102/tsk033/pbd.c:2570-2584 */
if( rpg_hd->surv_bin_size == 250 )
   lookup = (float *) &Bintbl_sr[0];   /* 1840 elementos */
else
   lookup = (float *) &Bintbl[0];      /* 460 elementos */
...
for( i = 0; i < rpg_hd->n_surv_bins; i++ ){
   if( ref[i] >= Low_refl_thresh ) Area_low_refl += lookup[i];
```

Si un radial declarara `surv_bin_size = 249` con más de 460 gates, el `else` elige `Bintbl` (460
elementos) y el bucle indexaría más allá del final. En ORPG real esto es inalcanzable, porque el
único valor distinto de 250 que llega es 1000 y con 1000 nunca hay más de 460 bins; el arreglo está
dimensionado para esa premisa. Un radial de LAMULA que declare 249 la rompería.

**Esto último no está demostrado.** Falta comprobar que `n_surv_bins` en `pbd.c:2578` es el conteo
crudo de gates y no un conteo ya remuestreado, y que la ruta AVSET se ejecuta en ese caso. Si se
quiere usar este argumento, hay que verificarlo en el árbol. La tabla `Range_corr` mal escalada, que
sí está demostrada, basta por sí sola para la conclusión.

## Q4 — ¿tope máximo de gates por radial?

**Sí, hay tope duro, y confirma la hipótesis fuerte del brief (§5).**

- `include/basedata.h:1015` — `#define MAX_BASEDATA_REF_SIZE 1840`
- `include/basedata.h:1017` — `#define BASEDATA_RHO_SIZE 1200` (Doppler y dual-pol)
- `include/basedata.h:1013` — `#define BASEDATA_REF_SIZE 460` (legado, 1 km × 460 = 460 km)

1840 × 250 m = 460 km exactos: **la rejilla nativa de ORPG es de 250 m**, tal como predecía el
brief.

El enforcement es recorte con aviso, no rechazo:

```c
/* src/cpc102/tsk033/pbd_process_data.c:127-132 */
if( mom->no_of_gates > MAX_BASEDATA_REF_SIZE ){
   LE_send_msg( GL_STATUS | LE_RPG_WARN_STATUS,
                 "Reflectivity Bins >= %d For RDA Cut %d\n",
                 MAX_BASEDATA_REF_SIZE, gbd->base.elev_num );
   mom->no_of_gates = MAX_BASEDATA_REF_SIZE;
}
```

Se repite en `pbd_process_header.c:2151-2166` (recorte a 70 000 ft) y `:2214-2221` (recorte final
con aviso *«Too Many Bins Found In RDA Radial Message»*).

Los 3689 bins del modo de 125 m no caben: a 125 m, 1840 gates son 230 km. La mitad externa del
volumen se descarta con aviso en el log.

## Modo de fallo (Paso 6 del brief)

Todo lo encontrado es recorte más aviso, nunca rechazo del radial, salvo el caso borde de
`pbd_process_header.c:2214`, que devuelve `-1` si tras recortar sigue excediendo el tope. Es decir:
un espaciado o un conteo de gates fuera de lo esperado no tumba el pipeline, pero corrompe en
silencio los cálculos aguas abajo, y solo el log lo delata.

---

## Recomendación

**Opción B del brief: dos cadenas de diezmado independientes, con R₂ = 417 para el modo de 250 m y
R₁ elegido por su cuenta para el de 125 m.** Cuatro argumentos, en orden de fuerza:

1. **Valor fuera de familia.** Un ORPG en producción solo ha visto 250 y 1000. Declarar 249 es un
   valor que nadie ha probado nunca contra ese código. Este argumento no depende de ninguna cita.
2. **Cuantización (Q2) más gates de igualdad (Q3).** 250,026 m se declara como 250 y pasa todos los
   `== 250` encontrados; 249,41 m se declara como 249 y los falla todos, quedándose con una tabla
   de corrección de rango mal alineada.
3. **Tope de conteo (Q4).** Con R₂ = 416 salen 1844 bins y el tope es 1840: se recortan 4 bins con
   aviso. Con R₂ = 417, 460 km / 250,026 m = 1840 bins exactos. R₂ = 417 encaja a la vez en la
   rejilla nativa y en el tope; R₂ = 416 falla en los dos.
4. **Coste nulo del modo de 125 m.** Q4 muestra que ese modo no cabe entero en el camino de
   reflectividad de ORPG en ningún caso (1840 gates frente a 3689). Separar su cadena de diezmado no
   pierde nada frente a ORPG, porque ese modo nunca iba a llegar íntegro.

**Corolario que hay que resolver con el equipo DSP:** si el modo de 125 m no llega a ORPG, la
elección entre R₁ = 208 (124,71 m) y R₁ = 209 (125,31 m) deja de tener una restricción externa y la
fija el consumidor interno — DSP, fichero Level-II propio, webviewer. No se cierra aquí.

## Qué falta para cerrar P-01

- **Fuente 1, `RDA_Backend_Py`** — sigue sin localizar. Es la única evidencia empírica de qué
  aceptó un ORPG real en producción, y hay precedente documentado de que gana al ICD. Ver P-05.
- **Reverificar las cuatro citas decisivas** en el árbol `rpg_b24_0r1_20_pub_src`, que no está en la
  máquina de desarrollo.
- **Repetir el barrido de Q3** (`surv_bin_size ==`, `dop_bin_size ==`, literales `0.25`, `0.125`,
  `1000`) en el resto de `src/cpc0xx/*`: composición, dealiasing, VAD/VWP y remuestreo a rejilla
  Level-III siguen sin revisar.
- **Demostrar o descartar el riesgo de lectura fuera de arreglo** de Q3.
- **Confirmar en el firmware de LAMULA** si la conversión de km en punto flotante a metros enteros
  trunca o redondea, y a qué valor exacto cae cada R candidato.
- **Contrastar con el ICD 2620002** directamente, aunque el wire format en código sea evidencia más
  fuerte que sus tablas.
