# Brief de investigación — P-01: ¿qué tamaño de celda acepta realmente ORPG?

**Para:** agente de investigación con acceso al código de ORPG y al legacy `RDA_Backend_Py`.
**Origen:** `lamula-drx/docs/alcance/pendientes.md#p-01`, decisión provisional
`lamula-drx/docs/alcance/decisiones.md#d-04` (R₁ = 208, R₂ = 416).
**Salida esperada:** un documento con una recomendación y, por cada afirmación, la cita
`fichero:línea` que la sustenta. Sin cita no es un hallazgo, es una hipótesis.

---

## 1. Reformulación: la pregunta original está mal planteada

El pendiente pregunta «¿ORPG admite un error de celda del 0,24 %?». Formulada así no es
respondible desde código, porque nadie escribe una tolerancia en un `#define`. Hay que partirla en
cuatro preguntas que sí tienen respuesta en el árbol de fuentes, y que además son independientes:

**Q1 — ¿El espaciado de celda es un campo transmitido o una constante en el consumidor?**
Si ORPG lee el espaciado de cada radial desde el mensaje, no hay error geométrico: se declara la
verdad y ya. Si en algún punto lo asume, el error es real y acumulativo.

**Q2 — ¿Con qué cuantización se puede declarar?**
Esta es la pregunta que probablemente decide el asunto, y no está en el pendiente. Si el campo de
espaciado tiene resolución de 1 m, entonces **124,71 m no es declarable**: se declara 125 m y el
error vuelve a aparecer entero. Ver §2.

**Q3 — ¿Dónde re-deriva ORPG el rango a partir del índice de bin en lugar de usar el campo?**
Un solo `range = i * CONSTANTE` en una cadena de producto anula la respuesta de Q1.

**Q4 — ¿Cuál es el número máximo de gates por radial que ORPG acepta?**
Si hay un tope, el modo de 125 m con 3689 bins puede no ser representable **en absoluto**, y eso es
un hallazgo mucho más grande que el 0,24 %. Ver §5.

---

## 2. Corrección numérica que hay que llevar a la investigación

El pendiente cuantifica el error como «−0,24 %, unos 0,6 m en la celda grande». Ese es el error
**por celda**, y es la forma engañosa de decirlo. El número que decide es el **error acumulado en el
extremo del rango**:

```
modo 125 m:  3689 bins × (125    − 124,71) m ≈ 1 070 m
modo 250 m:  1844 bins × (250    − 249,41) m ≈ 1 088 m
```

Es decir, **~1,1 km de error de posición en el bin más lejano a 460 km** — no 0,6 m. Comparado con
un producto Level-III de 1 km de resolución, eso es un bin completo desplazado. Esa es la magnitud
contra la que hay que evaluar cualquier tolerancia que se encuentre en el código.

Y el punto clave: **ese error existe solo si el espaciado se declara mal.** Si el espaciado real
(124,71 m) es declarable y ORPG lo usa, el error es cero. De ahí que Q2 sea la pregunta central.

**Inferencia mía, a verificar:** ningún campo de espaciado en punto fijo con cuantización de 1 m
puede expresar 124,71 m. Para que el error acumulado a 460 km baje de 100 m se necesita una
resolución de espaciado del orden de 0,03 m. Si la cuantización del campo resulta ser de 1 m o
peor, la conclusión no es «hay que tolerar 0,24 %» sino **«hay que elegir R de modo que el tamaño de
celda caiga sobre la rejilla de cuantización del campo»**, que es un requisito distinto y más
fuerte.

**Consecuencia arquitectónica que conviene tener en la cabeza al leer el código** (análisis propio,
no hallazgo): con fs = 250 MSPS la celda es `R × 0,5995849 m`. Para R = 417 la celda sale
**250,026 m**, error del 0,01 % y acumulado de ~48 m a 460 km — casi perfecto. El problema es que
417 es impar, así que no se puede obtener el modo de 125 m con una etapa ÷2 sobre él. La disyuntiva
real, entonces, no es «0,24 % sí o no», sino:

- **una sola cadena con etapa ÷2 conmutable** (R₁ = 208, R₂ = 416), 0,24 % de error en los dos
  modos; o
- **dos cadenas de diezmado independientes** (R₂ = 417 casi exacto, R₁ = 208 o 209 por su cuenta),
  a costa de más área y más verificación.

Si la investigación concluye que el modo de 250 m es el que llega a ORPG y el de 125 m no
(ver §5), la segunda opción se vuelve claramente mejor y el 0,24 % desaparece del camino crítico.

---

## 3. Fuentes, en orden de fuerza probatoria

### Fuente 1 (la más fuerte) — el legacy `RDA_Backend_Py`

`lamula-rcp/spike-fase0/README-rda-orpg.md` documenta que existe un proyecto legacy de 2013,
`RDA_Backend_Py`, que **hizo ingesta en producción de los radares cubanos al ORPG** y que cita el
ICD 2620002 como fuente. `RESULTADO-rda-orpg.md` registra un caso en el que la dirección real del
loopback del legacy contradecía la lectura literal del ICD, y que **ganó el legacy** porque había
corrido en producción.

Eso convierte a `RDA_Backend_Py` en la única fuente empírica disponible: es código que un ORPG real
aceptó. Hay que responder sobre él:

- ¿Qué valor de espaciado de celda declaraba, y en qué campo y unidad?
- ¿Era un campo tomado del radar o una constante en el código?
- ¿Qué tamaño de celda tenía físicamente el radar cubano que alimentaba? Si era un Gematronik de la
  misma familia que el radar objetivo de LAMULA, su tamaño de celda real ya pasó por un ORPG en
  producción, y la pregunta P-01 está contestada empíricamente.
- ¿Cuántos gates por radial mandaba, y en qué modo?

**Este fichero no está en `/home/node/workspace`.** Localizarlo es la primera tarea; pregunta a
vladimir dónde vive. Sin él, todo lo demás es lectura de especificación sin contraste empírico.

### Fuente 2 — el árbol de fuentes de ORPG

Es el que contesta Q3 y Q4, que son las preguntas que ninguna especificación contesta. ORPG se
distribuye como el paquete CODE del ROC (NWS Radar Operations Center); hay que localizar una copia.
Dado que vladimir operó ingesta real al ORPG, es plausible que exista una copia interna — preguntar
antes de buscar fuera.

### Fuente 3 — las tablas del ICD 2620002

Contesta Q1 y Q2 (unidades, escalado, rangos válidos, topes de conteo). Es la fuente más fácil de
leer y la más débil de las tres: el precedente del loopback ya demostró que la lectura literal de
sus tablas puede no describir el comportamiento real.

### Fuente 4 (proxy rápido) — lectores open-source de Level-II

MetPy, Py-ART y wradlib parsean el Message 31 y dan las unidades y el escalado de los campos de
espaciado y de rango al primer gate en minutos. Sirven para acotar Q2 rápido, pero **no** contestan
Q3 ni Q4: son consumidores de Level-II, no son ORPG.

---

## 4. Plan de trabajo concreto sobre el código de ORPG

### Paso 1 — Localizar la estructura de base data y sus campos de geometría

Términos de búsqueda (algunos fallarán; son candidatos, no nombres confirmados):

```
gate_width  gate_size  bin_size  surv_bin_size  dop_bin_size
range_to_first_gate  first_gate  range_first_bin
n_gates  num_gates  number_of_gates  n_surv_bins  n_dop_bins
RANGE_RESOLUTION  GATE_SPACING  SUPER_RES
```

Buscar tanto en cabeceras (`*.h`, definiciones de estructura y `#define`) como en los parsers del
mensaje entrante del RDA.

### Paso 2 — Contestar Q1: ¿campo o constante?

Del parser de base data hacia adelante, seguir el campo de espaciado. La pregunta binaria es: ¿el
valor viaja en la estructura hasta los algoritmos de producto, o se descarta y se sustituye por una
constante en algún punto?

### Paso 3 — Contestar Q3: buscar toda re-derivación de rango

Este es el paso que de verdad importa, y el más laborioso. Buscar toda expresión que calcule un
rango o una distancia a partir de un índice de bin. El patrón sano es:

```c
range = range_to_first_gate + i * gate_width;
```

El patrón que rompe la respuesta de Q1 es cualquier variante de:

```c
range = i * 250;        /* o 0.25, o 1000.0, o una macro */
```

Prestar atención especial a:

- **los remuestreadores a rejilla de producto.** Los productos Level-III viven en rejillas fijas
  (1 km, 0,25 km). Si el remuestreo interpola desde las coordenadas de rango declaradas, un error
  de 0,24 % es un desplazamiento sub-bin y probablemente inocuo. Si asume correspondencia directa
  índice-de-bin → índice-de-bin-de-producto, el 1,1 km se propaga entero.
- los cálculos de altura y de ángulo de elevación (la corrección por curvatura terrestre y
  refracción usa el rango).
- cualquier cosa que combine radiales de barridos distintos: composición, dealiasing dual-PRF,
  VAD/VWP, ecos de tierra.
- los umbrales expresados en km (rango máximo de producto, recortes, sectores).

### Paso 4 — Contestar Q2: cuantización real del campo

Del ICD y del parser, extraer para cada campo de geometría: tipo, tamaño en bytes, factor de
escala, unidad y rango válido documentado. Con eso, calcular qué tamaños de celda son exactamente
declarables, y contrastarlo con 124,71 / 249,41 / 250,026 m.

### Paso 5 — Contestar Q4: topes de conteo de gates

Buscar el máximo de gates por radial, tanto en el ICD como en los `#define` y en las declaraciones
de array de ORPG. Comprobar explícitamente si 3689 cabe. Ver §5.

### Paso 6 — Buscar validación de entrada y modo de fallo

¿ORPG valida el espaciado declarado contra un conjunto de valores esperados? ¿Rechaza el radial,
lo recorta, lo acepta en silencio, o registra un aviso? El modo de fallo importa tanto como la
tolerancia: un rechazo silencioso en producción es peor que un error del 0,24 %.

---

## 5. Hipótesis fuerte que hay que verificar o descartar primero

**Inferencia mía, sin verificar, y la más consecuente de este brief:** la super-resolución de
NEXRAD parece estar definida sobre una rejilla de **0,25 km con 1840 gates de reflectividad**
(= 460 km) y unos 1200 gates de velocidad (= 300 km). Si eso es correcto:

1. El **modo de 250 m de LAMULA coincide con la rejilla nativa de ORPG**, y es el modo que de
   verdad importa para esta interfaz. Eso hace que R₂ = 417 (250,026 m, error 0,01 %) sea
   claramente preferible a R₂ = 416 (249,41 m, error 0,24 %).
2. El **modo de 125 m con 3689 bins puede no tener ninguna representación en ORPG**, porque
   excedería el tope de gates por radial. Si es así, P-01 se disuelve para el modo de 125 m: ese
   modo no es un producto ORPG, es un dato interno del sistema, y su tolerancia la fija el consumidor
   interno (DSP, archivo Level-II propio, webviewer), no ORPG.

Verificar esto primero. Si se confirma, cambia la decisión D-04 completa y ahorra el resto de la
investigación.

---

## 6. Formato de entrega

Para cada una de Q1–Q4, una respuesta con:

- **Veredicto** en una frase.
- **Evidencia:** citas `fichero:línea`. Para Q3, la lista completa de re-derivaciones de rango
  encontradas, cada una clasificada como inocua o propagadora del error.
- **Confianza** y qué falta para subirla.

Y al final, una recomendación explícita entre:

- **A** — mantener R₁ = 208 / R₂ = 416, una sola cadena con etapa ÷2. Elegir esto solo si Q1–Q4
  demuestran que el espaciado declarado se respeta en todo el camino de producto.
- **B** — R₂ = 417 con cadena propia para el modo de 250 m (el que va a ORPG), y R₁ independiente
  para el de 125 m.
- **C** — remuestreo fraccionario (Farrow) para dar tamaños de celda exactos. Es la opción cara:
  cambia el presupuesto de DSP48 y la arquitectura del DDC. Recomendarla solo con evidencia de que
  A y B no sirven.

Marcar explícitamente qué parte de la recomendación se apoya en código leído y qué parte en
inferencia. Y decir en voz alta si la respuesta no se puede cerrar con las fuentes disponibles: un
«no se puede determinar sin acceso a X» documentado es un resultado útil; una recomendación
inventada, no.
