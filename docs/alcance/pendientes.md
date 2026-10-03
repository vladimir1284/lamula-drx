# Pendientes y hallazgos abiertos

Documento vivo. Cada entrada tiene un dueño y una condición de cierre; nada se cierra sin
evidencia. Los hallazgos marcados como **inferencia** salen del análisis del plan original y están
pendientes de confirmación por los especialistas de dominio.

## Hallazgos que hay que resolver antes de comprar hardware

Estos dos afectan a **qué hardware hay que comprar**. Ninguno cuesta más de una tarde de análisis
ahora, y los dos cuestan mucho después.

### P-01 · Tolerancia del tamaño de celda { #p-01 }

**Estado:** cerrado, 7 de septiembre de 2026 — exactitud requerida, confirmado también para el modo
fino de 125 m · **Dueño:** especialistas de dominio · **Cerraba:** [D-04](decisiones.md#d-04) y la
arquitectura del DDC — ver [ADR-001](adr-001-fs-r1-r2.md).

A 250 MSPS cada muestra cubre `c/2 × 4 ns = 0,5996 m`:

- 125 m → 208,48 muestras → R = 208 da **124,71 m**; R = 209 da **125,31 m**
- 250 m → 416,95 muestras → R = 417 da **250,03 m**

No hay R entero exacto, y además **R(250 m) ≠ 2 × R(125 m)** si se busca el más cercano en cada
caso (208 frente a 417). Importa porque la arquitectura natural es una cadena CIC/FIR donde el modo
de 250 m añade una etapa ÷2 sobre el de 125 m.

**Pregunta a responder:** ¿el producto ORPG admite un error de celda del 0,24 %, o exige 125/250 m
exactos? Si exige exactitud hay que ir a remuestreo fraccionario (Farrow) o a otra fs, y eso cambia
el presupuesto de DSPs y la arquitectura completa.

**Condición de cierre:** respuesta escrita de los especialistas, y si es «exactitud requerida», un
ADR nuevo que sustituya a D-04. A la luz del resultado de agosto de 2026, el ADR que hace falta no
es de exactitud fraccionaria sino de **elección de R sobre la rejilla de cuantización del campo**.

**Brief de investigación:** `research/p-01-orpg-gate-spacing.md` (en el repositorio, no publicado en
este sitio) descompone la pregunta en cuatro sub-preguntas respondibles desde el código de ORPG y
del legacy `RDA_Backend_Py`, y corrige la cuantificación del error: lo que decide no es el error por
celda (0,29 m) sino el **acumulado a 460 km, ~1,1 km**.

**Resultado, 30 de agosto de 2026:** dos lecturas del árbol de fuentes real de ORPG build 24
(`rpg_b24_0r1_20_pub_src`, paquete CODE del ROC), hechas en la máquina que lo tiene montado, y
recogidas en `research/p-01-RESULTADO.md` y `research/p-01-RESULTADO-barrido.md` (en el
repositorio, no publicados en este sitio). En resumen:

- El espaciado **es un campo transmitido**, entero de 16 bits **en metros**. 124,71 m y 249,41 m no
  son declarables: se declaran como 125/124 y 249. La conversión de punto flotante a entero ocurre
  en nuestro firmware, no en ORPG.
- ORPG **re-deriva el rango con una tabla cableada a 250 m** y la aplica a todo lo que no declare
  exactamente 1000 m de celda. Declarar 249 cae en esa ruta con la corrección mal alineada.
- Hay **tope duro de 1840 gates de reflectividad** (1840 × 250 m = 460 km: la rejilla nativa de
  ORPG es de 250 m) y de 1200 en Doppler y dual-pol. Se recorta con aviso en el log, no se rechaza
  el radial.
- Por tanto el modo de 125 m con 3689 bins **no llega entero a ORPG en ningún caso**, y la elección
  de R₁ pasa a fijarla el consumidor interno.
- **ORPG no tiene una banda de tolerancia: tiene una lista blanca.** La recombinación azimutal de
  super-res admite `{250, 1000}` en reflectividad y **solo 250** en Doppler, y descarta los dos
  radiales si el valor no está en la lista. La validación de moments dual-pol exige **250 exacto** y
  rechaza el campo con error si no. Es decir, declarar 249 no degrada el producto: lo elimina.
- El tope Doppler de 1200 gates (300 km a 250 m) **no es un problema**: el plan de la ZU9 pide 150
  km por defecto y 230 km extendido, o sea 600 y 920 gates. Pero el modo Doppler tiene que declarar
  250 igual que reflectividad, así que no puede usar una cadena de diezmado distinta.

La recomendación que sale de ahí es **R₂ = 417** (250,026 m, que se declara como 250 exactos y da
1840 bins justos) con cadena propia, frente a R₂ = 416 (249,41 m, que se declara como 249 y da 1844
bins, cuatro por encima del tope).

!!! warning "Por qué el resultado de agosto no cerraba P-01 todavía"
    El árbol de ORPG **no está en la máquina de desarrollo**, así que ninguna de las citas
    `fichero:línea` era reverificable ahí; el barrido sí reverificó las cuatro citas decisivas del
    primer resultado y coinciden. Siguen sin revisar la composición geográfica entre radares, el
    VAD/VWP y el remuestreo final a rejilla Level-III —los tres que el brief marcaba como daño
    potencial número uno— y `RDA_Backend_Py`, la única fuente empírica, sigue sin localizar (ver
    [P-05](#p-05)). Esa parte de la verificación queda como deuda abierta aparte, no como condición
    de cierre de P-01 (ver el cierre de abajo).

    Lo que sí faltaba en agosto para cerrar P-01 era el modo fino: la evidencia de ORPG cubría el
    mecanismo de lista blanca y el caso concreto de 249 m, pero **el modo de 125 m con 3689 bins no
    llegaba entero a ORPG en ningún caso**, así que no estaba confirmado si el mismo criterio de
    exactitud aplicaba ahí.

!!! success "Cierre, 7 de septiembre de 2026"
    Confirmado directamente por los especialistas de dominio: **se exige exactitud también en el
    modo de 125 m**, no solo en el de 250 m — mismo mecanismo de lista blanca que el resultado de
    agosto ya había identificado, ahora confirmado en el modo que quedaba abierto.

    **Nota de procedencia:** esta respuesta llegó verbalmente en sesión (vladimir, 7-sep-2026), a
    diferencia de `research/p-01-RESULTADO.md` y `research/p-01-RESULTADO-barrido.md`, que citan
    fichero y línea del árbol de ORPG. No contradice esa evidencia — la extiende al modo fino, que
    quedaba fuera de lo citado — pero **no hay todavía un registro escrito citable** para esta
    pieza en concreto. Si aparece (correo, acta, ticket), añadirlo aquí.

    Con esto, P-01 dejó de bloquear. La propuesta técnica que ya estaba escrita para esta respuesta
    exacta — [ADR-001](adr-001-fs-r1-r2.md), `fs` = 143,9 MHz con R₁ = 120 / R₂ = 240, que declara
    125 m y 250 m exactos en las dos plataformas — sigue **sin firmar**: le falta el visto bueno de
    dirección técnica y de compra de hardware (P-08/P-03), que P-01 nunca cubrió. `config/params.toml`
    sigue sin tocarse hasta que esa tabla de firmas se complete.

### P-02 · Capa física de los encoders SSI { #p-02 }

**Estado:** abierto · **Dueño:** compra de hardware + especialistas · **Bloquea:** especificación de
la portadora ZU9.

El plan original dice que «los dos encoders SSI son accesibles» pero **nunca dice a través de qué**.
SSI en instrumentación industrial es habitualmente **RS-422 diferencial**, no LVCMOS. Si la
portadora ZU9 no lleva transceptores RS-422, falta hardware.

**Condición de cierre:** confirmación documental de (a) la capa física real de los encoders del
radar y (b) la presencia de transceptores RS-422 en la portadora candidata. Entrada
[D6](../portabilidad/registro-delta.md) del registro delta hasta entonces.

### P-03 · Retirada temprana del riesgo JESD204B { #p-03 }

**Estado:** abierto · **Dueño:** dirección técnica · **Impacto:** es el riesgo número uno del
proyecto.

Como la ZU9 + FMC213 aún no está comprada hay una ventana que probablemente no vuelva: **la
arquitectura de hardware todavía es una decisión abierta, no una restricción.**

La ZedBoard **no compra ni un punto porcentual** de este riesgo: el XC7Z020-CLG484 no expone
transceptores gigabit y su FMC es LPC. Una plataforma con MGTs y FMC HPC de segunda mano — ZC706 con
XC7Z045, o ZCU104/ZCU102 en la familia UltraScale+ — permite hacer el spike de JESD204B + clocking +
SYSREF con un FMC de ADC modesto, muy por debajo del coste del hardware final.

Descubrir a los seis meses que el árbol de clocking elegido no da latencia determinista es el
escenario que arruina el mes 8.

**Condición de cierre:** decisión explícita de comprar o no comprar una plataforma de spike, con
fecha.

!!! info "Dato nuevo, 7-sep-2026: referencia externa disciplinada por GPS"
    Confirmado en sesión (vladimir): **todo el sistema usa un reloj externo basado en GPS.** Esto no
    cierra P-03 — sigue siendo el riesgo número uno, sin plataforma de spike — pero sí acota el árbol
    de clocking: no es un OCXO libre a bordo de la portadora, es una referencia externa disciplinada
    por GPS, casi con certeza la misma "referencia de 10 MHz de la casa" que
    [ADR-001](adr-001-fs-r1-r2.md) ya asumía para el PLL del FMC213 (PFD de 100 kHz, N = 1439). Falta
    todavía la ficha técnica: formato de señal, conector, y si hay redundancia. Añadido como
    [A9](#supuestos-de-entorno-a-verificar) a los supuestos de entorno.

    **Precisión, 7-sep-2026:** son **10 MHz + 1PPS**, y la referencia es local a este radar — no
    hay sincronización entre sitios de la red LAMULA que resolver aquí. Eso simplifica el problema:
    lo que el 1PPS compra en un radar único es UTC absoluto para el reloj de muestreo y,
    potencialmente, para el marcado temporal de los rayos en Z4 — no coherencia entre unidades. Con
    un solo radar, el argumento central de P-03 no cambia: sigue faltando la plataforma de spike
    para el propio enlace JESD204B, independientemente de la referencia.

### P-04 · Sectorización azimutal de PRF y ancho de pulso («pie-slice») { #p-04 }

**Estado:** cerrado, 21-sep-2026 — confirmado, pero con una forma más fina que la enunciada
originalmente · **Dueño:** vladimir · **Cerraba:** el alcance de
[Z2](../implementacion/fases.md#z2) — ver [D-13](decisiones.md#d-13).

El plan original nombra un único par PRF/ancho de pulso global por barrido. El estudio de la
interfaz de anfitrión de un procesador de señal maduro sugiere una capacidad más granular: una tabla
de valores de PRF y ancho de pulso que conmutan **por sector azimutal dentro de un mismo barrido**.

Si el checklist DSP↔RCP confirma que las estrategias de barrido del radar Gematronik objetivo lo
necesitan, es un requisito del motor de timing en PL — las tablas de trigger necesitarían entradas
por sector — y un campo correspondiente en la dirección de configuración del contrato DRx↔DSP. **No
se asume necesario sin esa confirmación.**

!!! success "21-sep-2026: confirmado — no es sectorización por azimut, es Batch mode de NEXRAD, 2 lotes por radial"
    La confirmación no vino del checklist DSP↔RCP sino de una decisión de producto directa
    (vladimir): el VCP objetivo usa **Batch mode** de NEXRAD, no *pie-slice*. La granularidad real es
    más fina que "por sector de varios grados": Batch mode alterna PRF **dentro del *dwell time* de
    cada radial** (~10-15 ms) — un lote corto de PRF baja (vigilancia, pocos pulsos) seguido de un
    lote de PRF alta (Doppler, muchos pulsos), en bucle continuo durante los 360° del barrido a esa
    elevación. El enunciado original de este pendiente (tabla de N entradas por sector azimutal) no
    es el mecanismo correcto; el mecanismo correcto es una tabla de **exactamente 2 lotes por
    radial** — fijado en [D-13](decisiones.md#d-13). Detalle de diseño y consecuencias para el motor
    de timing y para el validador PRF×rango de [D-09](decisiones.md#d-09), en D-13 y en
    [Fases, Z2](../implementacion/fases.md#z2).

## Pendientes de procedencia y de fuentes

Estos no son hallazgos técnicos del receptor; son huecos en la trazabilidad que bloquean o encarecen
el trabajo de arriba.

### P-05 · `RDA_Backend_Py` sin localizar { #p-05 }

**Estado:** abierto · **Dueño:** vladimir · **Bloquea:** la parte empírica de
[P-01](#p-01).

`lamula-rcp/spike-fase0/README-rda-orpg.md` documenta un proyecto legacy de 2013,
`RDA_Backend_Py`, que hizo **ingesta en producción de los radares cubanos al ORPG** citando el ICD
2620002 como fuente. Es la única fuente empírica disponible sobre qué acepta un ORPG real, y ya hay
precedente de que gana al ICD: `RESULTADO-rda-orpg.md` registra un caso en el que la dirección real
del loopback del legacy contradecía la lectura literal de las tablas, y se resolvió a favor del
legacy porque había corrido en producción.

**No está en `/home/node/workspace`.** Sin él, la investigación de P-01 solo puede leer
especificación, y el precedente del loopback dice que eso no basta.

**Condición de cierre:** ruta al repositorio o copia del código, anotada aquí.

### P-06 · Dos copias vivas del project plan de la ZU9 — cerrado { #p-06 }

**Estado:** **cerrado** el 30 de agosto de 2026 · **Dueño:** equipo.

El plan ZU9 existe en dos sitios publicados: `docs/referencia/project-plan-zu9.md` en este
repositorio y `docs/drx-plan.md` en `lamula-dsp`, que sigue en el nav de ese sitio. El fuente del
plan de ZedBoard (`lamula-drx-zedboard-plan.md`) sí se eliminó de `lamula-dsp` al escindir este
repositorio, pero el del plan ZU9 no.

Mientras las dos copias existan, un cambio en una no se refleja en la otra. La opción de retirar
`drx-plan.md` del sitio DSP se planteó y se decidió **no tocarlo** por ahora, porque rompe enlaces
existentes a ese sitio.

**Resolución:** las dos cosas. La copia canónica es la de este repositorio,
`docs/referencia/project-plan-zu9.md` —que además es la que tiene los enlaces a `algorithms/`
reescritos como URL absolutas al sitio DSP, así que no depende de dónde se publique—, y
`lamula-dsp/docs/drx-plan.md` pasa a ser una página de redirección que apunta aquí. La página se
conserva en vez de borrarse para no romper los enlaces existentes, y la entrada del nav de aquel
sitio dice «(movido al sitio del DRx)» para que se vea antes de hacer clic. Empujado y desplegado el mismo día: los dos sitios sirven ya
la versión nueva.

### P-07 · Conformidad con la rejilla de NEXRAD — trasladado al RCP { #p-07 }

**Estado:** trasladado el 30 de agosto de 2026 · **Dueño:** proyecto RCP.

Salió del barrido de P-01: si ORPG valida el espaciado de celda contra una lista cerrada, es
razonable esperar que valide igual el resto de la geometría del radial —conteo de gates, rango al
primer gate, resolución azimutal, tamaño de palabra de dato— y `data_word_size` ya está confirmado
en la misma condición de código que rechaza el espaciado.

**No es un pendiente de este proyecto.** El DRx no habla con ORPG; su única interfaz externa es
DRx↔DSP. Y el DSP tampoco: `lamula-dsp/docs/dsp-plan.md:71` retira el contrato `DSP↔ORPG`, y el
**RCP** es quien posee la emulación RDA WSR-88D (ICD 2620002) y el feed por radial. Vive ahora como
`PEND-RCP-12` en `lamula-rcp/docs/alcance/pendientes.md`.

Lo único que llega al DRx de todo esto es el tamaño de celda, que es P-01, y la elección de `fs`,
que es [P-08](#p-08).

### P-08 · `fs` es un grado de libertad, y bien elegida disuelve P-01 { #p-08 }

**Estado:** abierto, con una propuesta concreta y sin datos externos pendientes · **Dueño:**
dirección técnica + compra · **Bloquea:** el cierre de [D-04](decisiones.md#d-04).

Los convertidores del FMC213 son de 250 MSPS, pero **nada obliga a operarlos a 250 MHz**. El tamaño
de celda es `R · c / (2·fs)`: si `fs` es libre, se elige `fs` para que la celda caiga donde se
quiere, en vez de elegir `R` para que caiga cerca.

**Precisión sobre el límite matemático.** Celda de 125 m exacta al metro exige
`fs = R · c/250 = R · 1,199169832 MHz`, y ese cuanto no cae nunca sobre una rejilla redonda: para
que `fs` fuera un número entero de MHz haría falta que `R` fuera múltiplo de 125 000 000. **No se
puede tener celda exacta y reloj redondo a la vez.** Lo que sí se puede es un reloj redondo con un
error tres órdenes de magnitud menor que el actual, que a efectos prácticos es lo mismo.

### La propuesta: `fs` = 143,9 MHz, R₁ = 120, R₂ = 240

| | R | celda | error acumulado a 460 km |
|---|---|---|---|
| Modo fino | 120 | 125,000330 m | 1,2 m sobre 3680 bins |
| Modo grueso | 240 | 250,000660 m | **1,2 m** sobre 1840 bins |

Contra los 1054 m de D-04 tal como está hoy. 1,2 m es el 0,5 % de una celda: irrelevante para
cualquier producto, y el valor declarado a ORPG sigue siendo 250 exacto, que es lo que exige la
lista blanca de P-01.

Lo que trae de regalo:

- **Reloj redondo.** 143,9 MHz está en la rejilla de 100 kHz, así que sale por **integer-N** desde
  la referencia de 10 MHz de la casa (PFD 100 kHz, N = 1439). Sin PLL fraccional-N, **sin espurios
  fraccionales** — que era la única objeción seria a la variante de `fs` exacta.
- **Factores de diezmado mucho mejores.** 240 = 2⁴·3·5 y 120 = 2³·3·5, frente a 416 = 2⁵·13 y
  208 = 2⁴·13. El 13 de D-04 es un factor incómodo para una cadena CIC; 240 y 120 se descomponen en
  etapas cómodas.
- **R₂ = 2·R₁ intacto:** se conserva la cadena única con etapa ÷2. Una sola cadena de diezmado, no
  dos.
- **Menos presión de recursos y de timing.** ~~Y en ZedBoard el factor de dilatación baja de 2,5 a
  1,439.~~ **Corregido el 30 de agosto de 2026:** eso exigiría un `fs` de ZedBoard de 100 MHz, y con
  `if_norm` = 600/1439 los 100 MHz son ilegales —el IF no caería en hercios enteros, que es una
  condición que comprueba el paquete de parámetros en las dos plataformas. El valor legal más
  cercano es **99,998988 MHz**, 10,1 ppm por debajo, y con él la dilatación es 1,439015. Ver
  [ADR-001](adr-001-fs-r1-r2.md).

### Alternativas evaluadas

| `fs` | R₁ / R₂ | celda de 250 m | acumulado a 460 km | nota |
|---|---|---|---|---|
| **143,9 MHz** | **120 / 240** | **250,000660 m** | **1,2 m** | integer-N, factores limpios |
| 145,1 MHz | 121 / 242 | 249,999224 m | 1,4 m | R = 2·11² , peor para CIC |
| 149,9 MHz | 125 / 250 | 249,993711 m | 11,6 m | R muy limpio (2·5³) |
| 153,5 MHz | 128 / 256 | 249,989802 m | 18,8 m | R potencia de dos |
| 247,0 MHz | 206 / 412 | 250,029337 m | 54,0 m | el mejor en rejilla de 1 MHz |
| 249,427325 MHz | 208 / 416 | 250,000000 m | 0 m | exacto, pero pide fraccional-N o cristal a medida |
| 250 MHz, R₂ = 417 | — / 417 | 250,026910 m | 49,5 m | Opción B de P-01: obliga a dos cadenas |
| **250 MHz, R₂ = 416 (D-04 hoy)** | 208 / 416 | 249,427325 m | **1054 m** | se declara 249: **ORPG descarta el radial** |

### Supuestos que hay que verificar antes del ADR

Ninguno se puede comprobar desde este repositorio:

- ~~**Rate mínimo del convertidor del FMC213.**~~ **Resuelto el 30 de agosto de 2026: 143,9 MHz
  está dentro de especificación, con margen.** Ver el análisis debajo de esta lista.
- ~~**Plan de frecuencia intermedia.**~~ **Resuelto el 30 de agosto de 2026: el IF es de 60 MHz**,
  como ya decía [contexto](contexto.md). Encaja — ver el análisis debajo de esta lista.
- **JESD204B.** La tasa de línea baja con `fs`, lo que va a favor, pero hay que confirmar que el
  modo del convertidor admite ese rate y que SYSREF sigue siendo submúltiplo entero del LMFC.
- **Ancho de banda.** Con pulsos de 0,8 / 1,66 / 3,3 µs el ancho de banda es de ~1,25 MHz como
  máximo, así que no es restricción a ninguna de estas frecuencias.

### El convertidor admite 143,9 MHz, y en el modo de dos lanes

El ADC del FMC213 son **dos TI ADS42JB69** —dual, 16 bits, 250 MSPS, JESD204B— que dan los cuatro
canales de la tarjeta; el DAC es el AD9129 que ya nombra el plan. La tabla de condiciones
recomendadas del ADS42JB49/JB69 (SLAS900F, §7.3) especifica el rate de muestreo con **mínimo y
máximo**, y depende del modo de serialización:

| Modo SERDES | LMFS | Lanes por ADC | Rate de muestreo | Línea a 143,9 MHz |
|---|---|---|---|---|
| 10x | L=4, M=2, F=1, S=1 | 2 | **60 – 250 MSPS** | 1,439 Gbps |
| 20x | L=2, M=2, F=2, S=1 | 1 | **40 – 156,25 MSPS** | 2,878 Gbps |

143,9 MHz cae dentro de los dos, y no marginalmente: son 2,4 veces el mínimo del modo 10x. El
riesgo que esta lista marcaba como «el real» de bajar a 143,9 MHz **no existe**. Los máximos de
línea del propio convertidor son 2,5 Gbps en 10x y 3,125 Gbps en 20x, y la especificación de
tiempos de subida cubre `600 Mbps ≤ bit rate ≤ 3,125 Gbps`, así que las dos líneas de la tabla
están dentro.

Y trae una consecuencia que no estaba en el análisis anterior: a 250 MHz el modo 20x **no es
utilizable** —su máximo son 156,25 MSPS— y hay que ir a 10x, o sea 4 lanes por ADC, **8
transceptores** para los cuatro canales. A 143,9 MHz los dos modos están disponibles, y el 20x
hace la tarjeta entera con **4 transceptores** a 2,878 Gbps. Es la mitad de MGTs en la portadora
ZU9, y afecta a la selección de la portadora en [P-03](#p-03).

Lo que queda por confirmar, y **no es bloqueante para el ADR**:

- **Que el PLL del FMC213 sintetiza 143,9 MHz.** VadaTech describe un «wide-band PLL» con
  referencia por panel frontal, portadora FMC o referencia de a bordo, pero **no publica la pieza**
  en la ficha pública (la hoja de datos del FMC213 devuelve HTTP 403). La nota de aplicación del
  ADC usa un LMK04828 como ejemplo; si el FMC213 lleva ese, 143,9 MHz sale con VCO a 2446,3 MHz
  (= 143,9 × 17, dentro del rango de VCO0) y N entero desde 10 MHz con PFD de 100 kHz. **La
  objeción de ruido de fase se desplaza aquí**: PFD de 100 kHz sube el ruido en banda del PLL2
  frente a un PFD de 10 MHz, y el presupuesto de jitter es de ~100 fs rms. Hay que pedir a
  VadaTech la pieza del PLL y su configuración.
- **SYSREF.** El ADC exige `f_SYSREF = f_clk / (n · K · F)` con `1 < K < 32` y K > 16 recomendado.
  A 143,9 MHz en modo 20x (F = 2) con K = 32: 2,2484 MHz. Divisor entero desde el reloj de
  dispositivo, sin fracciones. No hay problema aritmético a ninguna de las `fs` candidatas.
- **Jitter de apertura.** El ADS42JB69 especifica 85 fs rms, coherente con el análisis de IF de
  arriba.

### El IF de 60 MHz encaja en 143,9 MHz sin muestreo subnyquist

Con `fs` = 143,9 MHz la mitad de Nyquist queda en 71,95 MHz, así que los 60 MHz del IF caen en la
**primera zona de Nyquist**: se muestrea directo, sin submuestreo y sin inversión espectral.

- **Banda de señal:** 59,375 – 60,625 MHz, con el pulso más corto (0,8 µs, ~1,25 MHz de ancho).
- **Filtro antialias:** lo que pliega sobre 60 MHz es la energía en `fs − IF` = **83,9 MHz**. El
  filtro tiene que pasar hasta 60,6 y rechazar en 83,9 — una razón de transición de 1,38, cómoda
  para un paso-banda de IF convencional.
- **Armónicos del IF:** el segundo (120 MHz) pliega a 23,9 MHz y el tercero (180 MHz) a 36,1 MHz.
  Ninguno cae sobre la banda útil.
- **Jitter de apertura:** a 60 MHz, 100 fs rms limitan la SNR a 88,5 dB, y 200 fs a 82,5 dB. No es
  restrictivo, pero es la razón por la que conviene no subir el IF.
- **NCO:** 60 / 143,9 = 0,416956 de `fs`. Es una palabra de fase cualquiera para el DDS Compiler,
  sin nada especial.

**Lo que se descarta a propósito:** poner el IF en `fs/4` para tener un mezclador sin
multiplicadores exigiría `fs` = 240 MHz exactos, y ahí la mejor celda es 249,827 m — 318 m de error
acumulado, más de una celda entera desplazada a 460 km. No compensa: por
[D-06](decisiones.md#d-06) el mezclador sale del DDS Compiler más un multiplicador complejo, que en
esta pieza es barato.

**Impacto en el RTL: ninguno por el lado de `fs`, si se cumple [D-02](decisiones.md#d-02)** — todo
se deriva de `FS_HZ`. Sí cambian R₁ y R₂, que son parámetros de la cadena de diezmado, no
arquitectura.

**Condición de cierre:** un ADR que sustituya a D-04 fijando `fs`, R₁ y R₂ juntos. **Escrito el 30
de agosto de 2026 y pendiente de firma:** [ADR-001](adr-001-fs-r1-r2.md). **El rate mínimo
del convertidor ya está confirmado y no se opone**, así que no queda ningún dato externo pendiente
para escribirlo. Los planes de repliegue siguen documentados por si el PLL del FMC213 no sintetiza
143,9 MHz: 247 MHz con R₁ = 206 / R₂ = 412 (54 m de error, reloj en rejilla de 1 MHz, cadena única)
y, en último caso, la Opción B de P-01.

### P-09 · cocotb no tiene backend para xsim, y D-05 lo daba por hecho { #p-09 }

**Estado:** **decidido** el 30 de agosto de 2026, **primera ejecución real el 5 de septiembre de
2026** (máquina de desarrollo con Vivado, no el runner de CI de A7), **los tres bugs de
infraestructura encontrados en esa ejecución ya corregidos y reconfirmados el mismo día**, sobre
xsim y sobre Verilator 5.006 · **Dueño:** equipo · **Cierre pendiente de** que Z1 escriba
`drx_ddc_top`; la infraestructura de L1 ya no tiene bugs conocidos.

!!! info "Estado, 6/7-sep-2026: drx_ddc_top escrito Y EJECUTADO contra IP real — ver P-10"
    Esta nota decía "no ejecutado" porque se escribió antes de descubrir que esta misma máquina de
    desarrollo sí tiene Vivado 2022.2 y Verilator 5.006 instalados (solo faltaban en `PATH`). Ya
    corrió de verdad, varias veces, contra IP real generada con `tcl/gen_ip.tcl` y simulada con
    `tcl/sim_l1.tcl` sobre xsim. El detalle completo — tres bugs reales encontrados y corregidos, y
    uno que sigue abierto — está en [P-10](#p-10).

[D-05](decisiones.md#d-05) dice que un único runner de cocotb cubre los dos backends, Verilator para
L0 y xsim para L1. **Verilator sí; xsim no.** Los runners que trae cocotb 1.9.2 son `icarus`,
`questa`, `ghdl`, `nvc`, `riviera`, `verilator` y `xcelium`. No hay xsim, y no es una omisión de la
versión pinada: cocotb nunca ha soportado el simulador de Vivado.

Esto importa porque L1 es exactamente el nivel que valida lo que Verilator **no puede** elaborar: la
IP del DDC. Sin L1 no hay comparación bit a bit contra el DDS/CIC/FIR Compiler reales, que es el
hito ZM1 entero.

Opciones, ordenadas por coste creciente. La 1 es la adoptada:

1. **Testbenches SystemVerilog nativos para xsim en L1, fuera de cocotb.** ← **adoptada** El oráculo sigue siendo
   el modelo dorado: se le hace escribir vectores de entrada y de salida esperada a fichero, y el
   testbench de xsim los lee y compara. Se pierde el «un solo runner» de D-05 y se gana no depender
   de ninguna licencia nueva.
2. **Licencia de Questa o Riviera.** cocotb los soporta y elaboran IP de Xilinx. Coste de licencia
   por puesto, y hay que verificar que las bibliotecas compiladas de Xilinx están disponibles para
   esa versión.
3. **Netlist funcional post-síntesis simulada en Verilator.** Vivado puede exportar la IP como
   netlist; Verilator podría elaborarla. Requiere Vivado igualmente, es lento y el resultado ya no
   es la IP sino su síntesis. Poco atractivo.
4. **Escribir un backend de xsim para cocotb.** Semanas de trabajo sobre la interfaz VPI de xsim,
   fuera del alcance de este proyecto.

**Decisión: la opción 1.** L1 sale de cocotb y pasa a testbenches nativos de SystemVerilog sobre
xsim, con el modelo dorado como oráculo cruzando por fichero. La enmienda está escrita en
[D-05](decisiones.md#d-05). Lo construido el mismo día:

| Pieza | Qué hace | ¿Verificado? |
|---|---|---|
| `model/drx_model/l1_vectors.py` | Exporta estímulo y salida esperada en `$readmemh`, con manifiesto y SHA-256 | Sí, en `make check` |
| `tools/gen_l1_vectors.py` | Genera los casos de las dos plataformas y los dos modos | Sí |
| `sim/tb_sv/drx_l1_file_source.sv` | Lee un `.hex` y lo entrega como stream con handshake | Sí, sobre Verilator 5.006 (reconfirmado el 5-sep-2026 tras el cambio de interfaz a `KIND`) y sobre xsim |
| `sim/tb_sv/drx_l1_checker.sv` | Compara bit a bit contra el modelo y cuenta discrepancias | Sí, sobre Verilator |
| `sim/tb_sv/tb_l1_harness.sv` + `sim/tests/test_l1_harness.py` | Auto-prueba del arnés: cero discrepancias con vectores limpios, **exactamente una** con un bit cambiado | Sí |
| `sim/tb_sv/tb_l1_ddc.sv` | El testbench de ZM1 | Lint sí; **no elabora**: `drx_ddc_top` es de Z1 |
| `tcl/sim_l1.tcl` | Flujo xsim: manifiesto, IP de los XCI, plusargs | Ejecutado el 5-sep-2026; ver hallazgo debajo |

El orden importa: el comparador está probado **antes** de que exista el DUT, y probado en la
dirección que engaña —un comparador que no compara da verde con cualquier cosa—, así que el día que
Z1 conecte el DDC, un verde de L1 significa algo.

`sim/runner.py` se queda siendo el runner de L0 y su backend L1 sigue fallando explícito, ahora
apuntando al flujo correcto en vez de a un bloqueo.

#### Hallazgo, 5 de septiembre de 2026: primera ejecución real, tres bugs de infraestructura, los tres corregidos

Primera vez con Vivado disponible (máquina de desarrollo, no CI). `tcl/sim_l1.tcl` nunca había
corrido, y no corrió limpio a la primera: la primera ejecución real encontró tres defectos propios
del arnés de simulación, ninguno relacionado con que `drx_ddc_top` todavía no exista.

1. **`create_project -in_memory` no soporta `launch_simulation`.** Falla con `ERROR: [Common 17-53]
   User Exception: No open project`. `tcl/build.tcl` sí puede usar `-in_memory` porque
   `synth_design`/`write_bitstream` no lo necesitan, pero el flujo de simulación de xsim sí escribe
   estructura de proyecto en disco. **Corregido:** proyecto real (`create_project sim_l1 -part
   $part -force`) dentro de `$opt(outdir)`, que ya es directorio de build — no se rompe D-07.
2. **Los plusargs se pasaban como tokens `+clave=valor` sueltos.** El parser de opciones de xsim
   los trata como posicionales y rompe a partir del séptimo (`ERROR: [Common 17-165] Too many
   positional options when parsing '+mode=0'`); `xsim --help` documenta que hace falta anteponer
   `-testplusarg` a cada uno. **Corregido** en `tcl/sim_l1.tcl`.

Con los dos fixes, la elaboración **funciona** —compila y elabora sin `drx_ddc_top`, exactamente
como está diseñado para hacerlo en esta fase— pero `run all` revelaba un tercer problema: xsim
abortaba con

```
FATAL_ERROR: Vivado Simulator kernel has discovered an exceptional condition from which it cannot
recover. Process will terminate. [...]
Time: 0 ps  Iteration: 0  Process: /tb_l1_ddc/u_stimulus/Initial46_1
  File: sim/tb_sv/drx_l1_file_source.sv
```

No era uno de los tres `$fatal` propios del código (ninguno de esos mensajes aparecía en el log):
era un choque interno del kernel de xsim.

3. **`$value$plusargs` con un `parameter string` como formato revienta el kernel de xsim.**
   `drx_l1_file_source.sv` parametrizaba el formato completo (`PATH_FMT`/`COUNT_FMT`, p. ej.
   `"stimulus_path=%s"`) para poder reutilizar el módulo con distintas claves de plusarg en
   `tb_l1_harness.sv` (`expected_i_path`/`expected_q_path`). xsim 2022.2 no tolera que ese argumento
   de formato sea un parámetro — aunque sea constante de elaboración — y revienta el kernel en vez
   de dar un error de Tcl o de SV. Aislado en 6 líneas fuera del repo: el mismo
   `$value$plusargs("stimulus_path=%s", path)` funciona con el literal escrito a mano y revienta si
   ese literal llega por un `parameter string`; confirmado con Vivado 2022.2 en esta máquina. No hay
   AR de Xilinx encontrado que lo documente; es un hallazgo propio, no una incompatibilidad
   conocida y publicada.

   **Corregido:** se quitaron `PATH_FMT`/`COUNT_FMT`. En su lugar, un `parameter string KIND`
   —cerrado a los tres usos reales (`"stimulus"`, `"expected_i"`, `"expected_q"`)— selecciona en
   runtime, con un `case`, entre llamadas a `$value$plusargs` que llevan el literal escrito a mano
   en cada rama. Aislado el mismo patrón con dos instancias de distinto `KIND` en el mismo
   `top`: ambas resuelven bien, sin crash. Aplicado a `sim/tb_sv/drx_l1_file_source.sv` y a sus dos
   sitios de instanciación (`tb_l1_ddc.sv`, `tb_l1_harness.sv`).

Con los tres fixes, `tcl/sim_l1.tcl` corre de punta a punta por primera vez sin ningún `ERROR` ni
`FATAL_ERROR` de xsim: compila, elabora, y `run all` llega exactamente al comportamiento **diseñado
para esta fase** —el testbench aborta porque falta `drx_ddc_top` (trabajo de Z1), y como el DUT
nunca produce muestras, la red de seguridad de timeout de `tb_l1_ddc.sv` también dispara a los 40 ms
como está previsto—. `EXIT_CODE=0` del propio `vivado -mode batch`: los `$fatal` de SystemVerilog no
se propagan como error de Tcl, así que ese código no certifica por sí solo que L1 pasó; lo que
certifica el diseño correcto de la fase es la ausencia de `FATAL_ERROR`/`ERROR` y la presencia
exacta de `Fatal: tb_l1_ddc: falta drx_ddc_top...` en el log.

El cambio de interfaz de `drx_l1_file_source.sv` (parámetro `KIND` en vez de
`PATH_FMT`/`COUNT_FMT`) se reconfirmó corriendo `sim/tests/test_l1_harness.py` sobre Verilator
**5.006** —la versión que ya tenía verificado el proyecto, compilada desde fuente porque el
`apt install verilator` de Ubuntu 22.04 solo trae la 4.038, demasiado vieja para `--timing`—: los
dos casos (vectores limpios y con un bit corrupto) siguen en verde, igual que toda `sim/tests`
completa. **P-09 no tiene ningún bug conocido pendiente**; lo único que falta para el hito ZM1 es
que Z1 escriba `drx_ddc_top`.

!!! success "19-sep-2026: `launch_simulation` reutilizó un kernel compilado de antes de D-12 — dos casos de la matriz dieron falso-fallo"
    Al correr la matriz completa de 16 combinaciones bajo el comparador con tolerancia (D-12),
    `tono_sobre_escala__fine` y `tono_sobre_escala__coarse` fallaron con conteos de discrepancias
    altos (222/315 y 103/157) pese a que las muestras impresas mostraban residuos de solo 3-4 LSB,
    dentro de la banda ya aceptada. La causa: `build/sim/xsim/zedboard/tono_sobre_escala__*/` traía
    un directorio de simulación de una corrida del 18-sep (antes de que existiera
    `TOLERANCE_LSB`) — `elaborate.log` mostraba `drx_l1_checker` sin el sufijo `(TOLERANCE_LSB=5)`
    que sí aparecía en los otros 14 casos, y su fecha de modificación era literalmente del día
    anterior. `launch_simulation`/xelab decidió que no había nada que recompilar y reutilizó el
    kernel viejo, con el parámetro en su valor por defecto (0, bit a bit estricto) — silencioso, sin
    ningún aviso de "usando snapshot en caché" que lo delatara aparte de la ausencia del sufijo en
    el log. **Corregido** borrando esos dos directorios de build y `build/l1-vectors/` (el sha de
    parámetros también había quedado desactualizado por el cambio de `fs_hz` de la misma sesión,
    ver [Fases, Z1](../implementacion/fases.md#z1)) y corriendo limpio: **16/16 "PASS"**, confirmado
    con el `(TOLERANCE_LSB=5)` correcto en el log de elaboración de los dos casos. Mismo patrón de
    hallazgo que el resto de P-09 —infraestructura de simulación, no del diseño— así que se
    documenta aquí. **Lección para la próxima vez que cambie algo en `drx_l1_checker.sv` o en
    `config/params.toml`:** borrar `build/sim/xsim/` (o al menos el caso afectado) antes de confiar
    en una corrida, no asumir que `launch_simulation` detecta el cambio.

### P-10 · `drx_ddc_top` contra IP real: cuatro bugs corregidos { #p-10 }

**Estado:** cerrado, 7 de septiembre de 2026 · **Dueño:** equipo. Queda un residuo nuevo y mucho
menor sin investigar (±1 LSB en `tono_desplazado__fine`, ver el cierre más abajo) — no bloquea Z1.

Primera ejecución real de `tcl/gen_ip.tcl` + `tcl/sim_l1.tcl` contra el DDC de un canal
(`rtl/drx_ddc_top.sv`, `rtl/drx_ddc_mixer.sv`, `rtl/drx_round.sv`, `rtl/drx_saturate.sv`), sobre
Vivado 2022.2 real en esta máquina de desarrollo (ver nota bajo P-09). Caso de aceptación:
`tono_if__fine`, 65536 muestras de estímulo, 315 muestras esperadas.

**Corregido, los tres con causa raíz confirmada por simulación, no por conjetura:**

1. **El DDS Compiler libre no entrega fase 0 en su primera muestra válida.** Con el mezclador ya
   corregido para no atar `nco_ready` a contrapresión (el NCO no congela su acumulador de fase
   aunque nadie consuma, así que contrapresurearlo pierde pasos de fase para siempre — ver el
   aviso de cabecera de `drx_ddc_mixer.sv`), la primera muestra seguía sin ser `(32767, 0)`.
   Búsqueda inversa exacta contra la LUT del propio modelo (`Nco.lut()`) identificó la muestra
   real como el índice 656 de esa tabla — un desfase de fase fijo y reproducible (igual con
   `Has_TREADY` que sin él, así que no es la FIFO de contrapresión: es intrínseco al arranque del
   Phase Generator). **Corregido en `tcl/gen_ip.tcl`**: `Has_TREADY {false}` (el mezclador nunca
   contrapresura al NCO, así que esa FIFO no compraba nada) más `Phase_offset {Fixed}` con
   `POFF1` calculado para cancelar el índice 656 en la propia IP — la corrección va en la fuente
   de la fase, no en un giro complejo aguas abajo (un giro sobre valores de LUT ya cuantizados no
   puede reconstruir el valor exacto de la LUT en el índice correcto; se probó y dejaba un sesgo
   de ±1 LSB en régimen permanente que no cerraba).
2. **El transitorio de arranque del CIC no coincidía con el modelo, mucho más allá de lo que
   explica un desfase de fase.** `model/drx_model/cic.py` calculaba con latencia cero (recursión
   matemática instantánea); el CIC Compiler real es una tubería de N integradores + N peines con
   latencia de silicio de verdad. Ajuste numérico contra los valores reales de xsim: anteponer
   exactamente `rate - 1` muestras de relleno de tubería antes de que el modelo empiece a acumular
   reproduce el transitorio real bit a bit (residuo nulo salvo el hallazgo #3 de abajo).
   **Corregido en el modelo dorado** (`Cic.pipeline_fill`, cambio deliberado y autorizado, huellas
   `GOLDEN` de `model/tests/test_chain.py` actualizadas con la fecha y el motivo) — no en el RTL,
   porque el RTL ya se comporta como la IP real; era el modelo el que idealizaba la latencia.
3. **`nco_ready` sin conexión tras quitar `Has_TREADY`**: `dds_compiler_nco` ya no tiene puerto
   `m_axis_data_tready` una vez generado sin TREADY. `rtl/drx_ddc_top.sv` ya no lo conecta; la
   salida `nco_ready` del mezclador (que sigue existiendo, atada a `1'b1`) queda explícitamente sin
   uso, igual que `s_last`.

**Abierto — la hipótesis de amplitud del 6/7-sep se probó contra xsim real y quedó descartada:**

Con los tres fixes de arriba, `tono_if__fine` pasó de 312-313/315 discrepancias (con errores de
hasta 5× en el transitorio) a **306/315, todas de ±1 LSB** — el transitorio ya cierra bit a bit,
pero el residuo uniforme sigue sin explicación confirmada.

!!! danger "Hipótesis descartada, 7-sep-2026: no es `Amplitude_Mode {Full_Range}`"
    La primera lectura de este hallazgo (más abajo se conserva tachada) apuntaba a que el DDS
    Compiler usa como pico `2^(N-1) - 2` en vez del máximo estándar de complemento a dos que asume
    `fixed.limits()`. Se implementó (`Nco.lut()` con pico `2^15-2`), se regeneraron los vectores L1
    y se corrió `tono_if__fine` contra xsim real: **el conteo de discrepancias no cambió ni una,
    306/315 exactas**, lo que ya era sospechoso — un cambio de escala de ~3·10⁻⁵ sobre valores de
    salida de orden 10³ no puede mover ningún redondeo lo suficiente como para cerrar un residuo de
    ±1 LSB completo.

    La prueba concluyente: `tcl/gen_ip.tcl` ya documentaba una medición real contra la IP,
    `LUT[656] = (32702, 2059)`, de la investigación del hallazgo #1. Recalculando esa misma entrada
    en Python, el pico **original** del modelo (`2^15-1 = 32767`) reproduce `(32702, 2059)` exacto;
    el pico "corregido" (`2^15-2 = 32766`) da `(32701, 2059)` — **mal por 1 en el coseno**, peor que
    antes. El modelo original ya estaba en lo correcto en ese punto medido; el cambio se revirtió
    íntegro (`model/drx_model/nco.py`, `model/tests/test_bloques.py`,
    `model/tests/test_chain.py`) y `make check` vuelve a estar en 69/69 con las huellas `GOLDEN`
    originales. La cita de pg141 sobre el pico de `Full_Range` describe el envolvente de diseño del
    modo, no el factor de escala real de cada muestra de la LUT — no aplica aquí.

    **El residuo de ±1 LSB en `tono_if__fine` seguía sin causa conocida en este punto** — que su
    origen SÍ resultó ser el NCO, solo que no por amplitud, está documentado a continuación.

!!! bug "Localizado, 7-sep-2026: SÍ es el NCO — `nco_sin` sale con el signo cambiado"
    La instrumentación de abajo (revertida del árbol, no comiteada — sondas temporales en
    `sim/tb_sv/tb_l1_ddc.sv` sobre `g_branch[i].cic_rounded`, `fir_rounded`, y dentro de
    `drx_ddc_mixer`: `pair_en`/`in_mem`/`nco_cos`/`nco_sin`/`prod_i`/`prod_q`) localizó el origen
    en tres pasadas:

    1. **CIC → FIR**: el sesgo (I: −1, Q: +1 respecto al modelo) ya está presente en
       `cic_rounded` desde la primera muestra en régimen (`g_branch[0].cic_rounded`), y el FIR lo
       propaga sin añadir nada nuevo — descarta CIC/FIR/`drx_round` como origen, apunta aguas
       arriba, al mezclador o al NCO.
    2. **Mezclador → NCO**: `prod_q` (el producto crudo, sin redondear) del mezclador YA lleva el
       sesgo. Con `x[n]` conocido exacto (mismo estímulo), reconstruir `nco_sin` implícito a partir
       de `prod_q = −(x[n]·nco_sin)` y compararlo contra `Nco.lut()` da la respuesta: **`nco_sin`
       real coincide en magnitud con el `sin` del modelo pero con el signo invertido**, muestra a
       muestra, desde `n=1` (ejemplos: modelo `sin=32702` → IP `sin=−32702`; modelo `sin=−32186` →
       IP `sin=+32186`). `nco_cos` coincide con el modelo salvo un ruido de ±1-5 unidades —
       consistente con comparar `cos(θ)` contra `cos(θ)` evaluados por rutas de coma flotante
       ligeramente distintas (`cos` es función par, así que el signo no lo delata), mientras que
       `sin(θ)` sí delata el signo invertido de inmediato (`sin` es impar).
    3. **`PINC1` no es la causa**: se comparó el valor de `PINC1` ya escrito en
       `ip/dds_compiler_nco/dds_compiler_nco.xci` contra `params.nco_phase_inc` del modelo — son
       bit a bit idénticos, no el complemento. El incremento de fase que de verdad usa la IP es el
       correcto; lo que sale invertido es el campo SINE del DDS Compiler para ese mismo incremento,
       no la velocidad ni el sentido del acumulador.

    **Lo que esto explica de una vez:** por qué `I` cierra casi exacto (coseno es función par,
    insensible a una inversión de signo en el seno) y por qué `Q` tiene un sesgo consistente pero
    pequeño tras el CIC/FIR (un tono coherente que decima a un residuo cercano a cero sigue cerca
    de cero incluso con el signo de la parte alterna invertido) — y por qué la hipótesis de
    amplitud de arriba no tenía ningún efecto: el problema nunca fue de escala.

    **No corregido todavía — es una decisión, no un ajuste ciego.** Dos caminos abiertos, ninguno
    aplicado:

    - Ajustar el convenio de signo en el modelo dorado (`Nco.lut()`/`Ddc.mix()`: usar
      `q = +x·sin_w` en vez de `−x·sin_w`, o negar `sin_lut` en la propia tabla) — si el NCO real
      define "seno" con el convenio contrario al que asume `model/drx_model/nco.py` (p. ej. el
      DDS Compiler entrega el seno de la señal analítica `e^{-jθ}` en vez de `e^{+jθ}`, una
      convención de cuadratura distinta, no un bug).
    - O buscar la opción de configuración del DDS Compiler que invierte el signo (pg141, "Polarity
      — Negative Sine"; `tcl/gen_ip.tcl` no toca ese parámetro hoy, así que corre con el valor de
      fábrica) y corregirlo ahí si el convenio del modelo es el que se quiere conservar.

    Para reproducir: las sondas usadas no están en el árbol (se revirtieron tras extraer los
    datos). Recrearlas es sencillo: `$display` sobre
    `g_branch[0/1].cic_rounded`/`fir_rounded` en `tb_l1_ddc.sv`, y dentro de `drx_ddc_mixer`,
    sobre `pair_en`/`in_mem[in_rd_ptr]`/`nco_cos`/`nco_sin`/`prod_i`/`prod_q` (ver
    `rtl/drx_ddc_mixer.sv`); comparar contra `Nco.generate()` y los productos crudos
    `x·cos_w`/`−x·sin_w` calculados en Python para el mismo estímulo (`tools/gen_l1_vectors.py`,
    caso `tono_if`, semilla `SEED=20260830`).

!!! success "Decisión tomada y aplicada, 7-sep-2026: se ajusta el modelo, no la IP"
    Se decidió (vladimir, en sesión) conservar la configuración de la IP tal como está y ajustar el
    modelo dorado para que coincida con el convenio de cuadratura real del DDS Compiler.
    **Cambiado:** `Ddc.mix()` en `model/drx_model/chain.py` — `q = shift_round(x·sin_w, shift)` en
    vez de `shift_round(-x·sin_w, shift)`. Se actualizó también el comentario de cabecera de
    `rtl/drx_ddc_mixer.sv` (documentación, no lógica: el RTL no cambia, porque `prod_q <= -(...)`
    ya hacía lo correcto una vez que se entiende que `nco_sin` trae el signo de `e^{+jwn}`) y la
    fórmula/snippet de `docs/tutorial/03-ddc.md`, que citaba el código viejo literalmente.

    **Validación contra xsim real, con los vectores L1 regenerados:**

    - `tono_if__fine` (el caso de aceptación de arriba): **sigue en 306/315, sin cambio.** Esto no
      es que el fix no sirva — es que este caso concreto es degenerado para probarlo: el tono está
      exactamente en fase con el NCO, así que `Q` converge a ~0 en régimen permanente con
      *cualquiera* de las dos convenciones de signo (negar algo que ya es ~0 sigue siendo ~0). El
      mismo efecto ya se había visto en `model/tests/test_chain.py`: su huella `GOLDEN` tampoco se
      movió con el cambio, por la misma razón — verificado a mano, no es una casualidad sospechosa.
    - `tono_desplazado__fine` (tono corrido del IF, sí sensible al signo de `Q`): **156/315
      discrepancias, todas de ±1 LSB en un solo canal** (ejemplos: `dut=(-747,-4220)
      modelo=(-748,-4219)`, `dut=(3692,2259) modelo=(3692,2258)`) — nada parecido al sesgo
      sistemático y consistente de antes (`(-1,+1)` en las 306 muestras). Es la confirmación real:
      el fix de signo es correcto. El residuo de ±1 LSB que queda es de una magnitud completamente
      distinta — consistente con el ruido de punto flotante de ±1-5 unidades ya visto al comparar
      `nco_cos` entre modelo e IP (arriba, hallazgo #2: evaluar `cos`/`sin` en direcciones
      espejadas por rutas de coma flotante distintas no da bit a bit lo mismo) — y queda como
      pendiente aparte, mucho menor, sin investigar todavía.
    - `make check`: 69/69 con las huellas `GOLDEN` de `tono_if` sin cambiar (ver arriba) y
      `mkdocs build --strict` limpio tras tocar el tutorial.

    **P-10 se da por cerrado** en cuanto a los tres bugs de RTL/Tcl y el convenio de signo del
    mezclador. Lo que queda (el ±1 LSB residual en `tono_desplazado`) es un hallazgo nuevo, mucho
    más pequeño, y no bloquea Z1.

    **Investigación adicional del residuo, mismo día:** se buscó una explicación barata (sin más
    corridas de Vivado) antes de decidir que no vale la pena perseguirlo más. Dos vías, ninguna dio
    una explicación limpia:

    - **Proximidad al borde del bin de LUT.** Para las 14 primeras muestras de `tono_if` (mismo
      estímulo, ya con datos capturados), la fracción de fase dentro del bin de LUT (16 bits por
      debajo de la dirección) no correlaciona con qué muestras coincidían exacto y cuáles no —
      hay coincidencias con la fase casi en el borde (`frac=0,32`) y discrepancias con la fase casi
      centrada (`frac=0,56`). Descarta un desajuste de redondeo de dirección por 1 unidad cerca de
      un borde de bin como explicación única.
    - **Leer el contenido real de la LUT en vez de reconstruirlo por simulación.** El modelo de
      simulación del DDS Compiler (`ip/dds_compiler_nco/hdl/dds_compiler_v6_0_vh_rfs.vhd`, ~27 000
      líneas) es *genérico* — cubre todas las configuraciones posibles del core (Taylor, varios
      anchos, streaming/fixed) y genera la tabla algorítmicamente en tiempo de elaboración, no la
      trae como una constante literal de 65536 entradas para esta configuración concreta. Leerlo
      directamente no es un atajo; habría que volver a instrumentar xsim.

    **Decisión: no perseguirlo más por ahora.** Es ruido de ±1 LSB sobre valores de 16 bits — está
    en el suelo de cuantización del propio receptor (el tutorial de DDC ya mide un suelo de espurio
    de −86,4 dBc para este NCO; un ULP de diferencia entre la tabla de `numpy` y la que genera
    internamente el DDS Compiler es exactamente la clase de discrepancia que un suelo de ese orden
    ya contempla). Seguir esta pista costaría otra ronda de sondas + xsim (~20 min) por un hallazgo
    que no cambia ninguna decisión de arquitectura ni bloquea Z1. Si alguien lo retoma: instrumentar
    `nco_cos`/`nco_sin` para las 56 direcciones de LUT que este tono visita en régimen permanente
    (ya identificadas en la investigación de arriba) y comparar una a una contra `Nco.lut()` es el
    siguiente paso más barato.

!!! info "Matriz completa de los 6 casos de L1 contra xsim real, 7-sep-2026"
    Con `tono_if__fine` y `tono_desplazado__fine` ya cubiertos arriba, se corrieron los 4 casos que
    faltaban (`dos_tonos__fine` y los tres `*__coarse`, que ejercitan la semibanda ÷2 de diezmado
    grueso — no probada contra IP real hasta este punto). Resultado, con
    `n_expected` = 315 en fino y 157 en grueso:

    | Caso | Discrepancias | Patrón |
    |---|---|---|
    | `tono_if__fine` | 306/315 (97 %) | Q≈0 en régimen permanente (degenerado); casi toda muestra difiere |
    | `tono_desplazado__fine` | 156/315 (50 %) | disperso, ±1 LSB, un canal por muestra |
    | `dos_tonos__fine` | 25/315 (8 %) | disperso, ±1 LSB, mayormente canal I |
    | `tono_if__coarse` | 147/157 (94 %) | casi constante, `+1` en Q, I exacto (degenerado, igual que en fino) |
    | `tono_desplazado__coarse` | 44/157 (28 %) | disperso, ±1 LSB, ambos canales |
    | `dos_tonos__coarse` | 7/157 (4 %) | disperso, ±1 LSB, mayormente canal I |

    **Hipótesis de trabajo — no confirmada con instrumentación nueva:** los 6 casos son
    consistentes con una única causa, el mismo residuo de ±1 LSB de arriba. La tasa de
    discrepancias correlaciona con qué tan degenerado es el caso: `tono_if` fuerza `Q≈0` en régimen
    permanente en los dos modos (fino y grueso), y ahí el mismo sesgo de redondeo del NCO se dispara
    en casi el 100 % de las muestras; `dos_tonos` reparte la señal en un rango más amplio de
    amplitud (los dos tonos de esa mezcla están a ±0,0008 en frecuencia normalizada del IF, cerca
    pero no en el punto degenerado) y por eso cae a 4-8 %; `tono_desplazado`, con el rango más amplio
    de los tres estímulos, queda en el medio (28-50 %). Ningún caso muestra la firma del bug de
    signo ya corregido arriba (que era `(-1,+1)` simultáneo en ambos canales, no un residuo disperso
    de un solo canal).

    Esto es una lectura de los agregados, **no** una confirmación por sonda — el paso más barato
    siguiente sigue siendo el mismo que se dejó anotado arriba: instrumentar `nco_cos`/`nco_sin`
    muestra a muestra para las direcciones de LUT que cada caso visita y comparar contra
    `Nco.lut()`. No se ha hecho todavía para estos 4 casos nuevos.

~~El residuo uniforme vendría de que el DDS Compiler en modo `Amplitude_Mode {Full_Range}` apunta a
un pico de `2^(N-1) - 2` (confirmado con el ejemplo numérico de pg141 v6.0 p.51: para 8 bits da
126 = 0b01111110, exactamente lo que dice el manual), mientras que `fixed.limits()` del modelo
asume el máximo estándar de complemento a dos, `2^(N-1) - 1`.~~ Descartado arriba.

!!! success "Cerrado, 7-sep-2026: el `UNUSEDPARAM` y un segundo bug encontrado al investigarlo"
    Con Vivado y Verilator ya en `PATH` en esta máquina, `make check` completo (el que corre los
    dos simuladores, no solo `make sim`) reveló dos fallos reales, los dos ya corregidos:

    1. **El `UNUSEDPARAM` de `rtl/generated/drx_ddc_ip_pkg.sv`** que hacía fallar
       `sim/tests/test_l1_harness.py` y `test_l0_heartbeat.py` al elaborar contra Verilator 5.006
       era un falso positivo: `drx_ddc_top.sv` sí usa cada uno de los anchos del paquete, vía
       `import drx_ddc_ip_pkg::*;`, pero Verilator atribuye el warning a instancias que no lo
       importan (`tb_l1_harness.u_checker`) en vez de reconocer el uso real. Mismo patrón que los
       waivers ya existentes para `drx_ssa_pkg`/`drx_params_pkg` — añadido en
       `sim/verilator_waivers.vlt`.
    2. **`fw/src/drx_params_selftest.c` exigía contrato v0.1** — literal que se quedó sin tocar en
       los dos bumps deliberados y ya autorizados por D-08 (v0.2 en `tx_pol_v`, v0.3 en el enum de
       canales), así que `make check` en `fw/` fallaba con «version del contrato DRx<->DSP
       inesperada» desde el 3-sep-2026 sin que nadie lo notara — ninguno de esos dos commits corrió
       el `make check` de la raíz. Corregido a v0.3.

    Con los dos fixes, `make check` vuelve a estar en verde, 69/69. Sin relación con el hallazgo de
    amplitud de arriba.

!!! info "8-sep-2026: el residuo escala con la ganancia — replicación a 4 canales + escalado de ganancia"
    Z1 sumó dos piezas nuevas: `rtl/drx_ddc_quad_top.sv` (réplica de `drx_ddc_top` a los `N_RX_CH`
    canales, para el hito ZM1) y la etapa de ganancia fina en `drx_ddc_top.sv`
    (`FINE_GAIN_COEFF`/`COARSE_GAIN_COEFF`, generadas por `tools/gen_params.py` desde
    `fixed.gain_trim`, que ya trae el oráculo desde el 7-sep). Las dos se verificaron matemáticamente
    correctas contra el modelo (mismo coeficiente, mismo algoritmo de redondeo) y contra xsim real.

    Al correr `tcl/sim_l1_quad.tcl`, el canal 0 (`tono_if__fine`) reporta **306/315
    discrepancias — el mismo número, exacto, que ya documenta la tabla de arriba** para el caso de
    un solo canal. No es un bug nuevo: es el residuo de ±1 LSB del NCO (ya aparcado arriba, «no
    perseguirlo más por ahora») escalado junto con el resto de la cadena por el nuevo multiplicador
    de ganancia — de ~1 LSB a ~2-3 LSB en valor absoluto, proporcionalmente igual en dB por debajo de
    fondo de escala. Es la consecuencia esperada de escalar la señal a fondo de escala, no una señal
    de que la réplica a 4 canales o el ajuste de ganancia tengan un error propio.

    **Confirmado por aislamiento:** corriendo `tcl/sim_l1.tcl` contra el commit `6b32e99` (el que
    documenta la tabla de arriba) en un worktree separado, con vectores regenerados desde cero, se
    reproduce el mismo `306/315` — la tabla de esta página ya reflejaba este residuo, no una
    ejecución limpia; el título del commit («completar la matriz») describe haber terminado de
    *correr y documentar* los 6 casos, no haberlos dejado en verde.

    **Consecuencia para ZM1:** el hito («coincide bit a bit… en los cuatro canales») sigue sin
    cerrarse — igual que ya estaba antes de esta sesión — por este mismo residuo preexistente, no por
    la réplica a 4 canales en sí. `rtl/drx_ddc_quad_top.sv` y la etapa de ganancia fina quedan
    escritos, revisados y verificados en su propio alcance; cerrar ZM1 de verdad sigue pendiente de
    retomar la investigación del NCO que esta página ya deja anotada (instrumentar `nco_cos`/
    `nco_sin` muestra a muestra contra `Nco.lut()`), decisión que se dejó explícitamente para más
    adelante.

!!! danger "8-sep-2026: instrumentado por fin — el residuo es del propio NCO, ±5 LSB crudos, y no depende de Memory_Type"
    Se retomó la instrumentación que esta página dejaba anotada como «el siguiente paso más barato»:
    sonda temporal en `sim/tb_sv/tb_l1_ddc.sv` (`$fwrite` sobre `u_dut.nco_cos`/`u_dut.nco_sin` en
    cada ciclo con `nco_valid`, sin decimar, indexado por `n=0,1,2,…`; revertida del árbol tras
    extraer los datos, no comiteada) contra `tono_if__fine` en xsim real. Con `phase_inc =
    1030792151` el paso de dirección de LUT por muestra es de ~15732/65536 — casi ninguna dirección
    se repite en 4096 muestras, así que esto cubre muchas más direcciones que las ~56 del régimen
    permanente decimado.

    **Resultado, 4096 muestras crudas contra `Nco.generate(4096)`:** el signo invertido de `Q` ya
    documentado y corregido en el modelo se confirma otra vez (no es nuevo). Después de compensar
    ese signo, **queda un residuo de hasta ±5 LSB en AMBOS canales, presente desde la muestra n=0**
    (`ip=(32766,-2)` vs `modelo=(32767,0)`) — no es un transitorio de arranque, es ruido por muestra
    en la propia salida cruda del NCO, antes de cualquier CIC/FIR. Esto es MAYOR que el ±1 LSB medido
    después de decimar — consistente con que CIC/FIR actúan de filtro paso bajo y promedian un ruido
    no correlado de unos pocos LSB hasta dejarlo en ±1 LSB a la salida.

    **Corrección a una nota anterior de esta página:** la entrada de arriba («Leer el contenido real
    de la LUT…») decía que `dds_compiler_v6_0_vh_rfs.vhd` es «genérico, sin tabla literal» — eso era
    una inferencia sobre el tamaño del fichero (~27 000 líneas), no una lectura real: el fichero está
    cifrado con `` `protect `` (IEEE P1735, claves de Xilinx/Aldec/Mentor/Cadence/etc.), así que su
    contenido no es legible sin las claves de descifrado que trae xsim. Esta página nunca tuvo forma
    de confirmar por lectura de código cómo genera la IP sus valores; toda conclusión sobre su
    arquitectura interna es inferencia por comportamiento, no lectura de fuente. Corregido aquí para
    que nadie repita el intento de "leer el VHDL".

    **Hipótesis probada y descartada: `Memory_Type`.** El `.xci` mostraba `Memory_Type {Auto}` (no
    tocado hasta ahora); `report_property -all` confirma que los valores válidos son `Auto,
    Distributed_ROM, Block_ROM` — es decir, "Auto" no garantiza necesariamente una ROM literal de
    doble precisión ya redondeada como asume `Nco.lut()`. Se forzó `CONFIG.Memory_Type {Block_ROM}`
    en `tcl/gen_ip.tcl`, se borró y regeneró `ip/` completo (mismos anchos de TDATA en las cuatro
    IP, confirmado), y se repitió la misma sonda de 4096 muestras: **el resultado fue bit a bit
    IDÉNTICO al de `Auto`** (mismos `nco_cos`/`nco_sin`, mismo residuo de ±5 LSB, muestra a muestra).
    `Memory_Type` gobierna solo el mapeo a recursos de FPGA en post-síntesis (BRAM vs ROM
    distribuida); no cambia en nada el modelo de simulación comportamental de xsim. Cambio revertido
    íntegro (`git checkout -- tcl/gen_ip.tcl sim/tb_sv/tb_l1_ddc.sv`, `ip/` regenerado de vuelta a
    `Auto` con `tcl/gen_ip.tcl`, árbol limpio confirmado con `git status`).

    **Dónde queda esto:** `Amplitude_Mode` (descartado arriba), `Noise_Shaping` (ya en `None`, sin
    tocar — dither, no relevante) y ahora `Memory_Type` son las tres hipótesis con una palanca de
    configuración real que se han probado. Ninguna mueve el residuo. Sin acceso al código fuente del
    core (cifrado) ni a la documentación de PG141 en este entorno, no hay más palancas conocidas que
    probar sin especular. La lectura más simple de la evidencia: el core calcula
    internamente su seno/coseno con un algoritmo propio de Xilinx que no coincide, LSB a LSB, con
    `round(2**15-1 · cos/sin(2π·addr/65536))` en punto flotante de 64 bits — una discrepancia
    plausible entre dos implementaciones numéricas distintas del mismo cálculo, no una `Amplitude_Mode`
    o modo de memoria mal elegido de nuestro lado. **Esto es inferencia, no una causa raíz
    confirmada por lectura de código** — sigue sin haber una explicación de primeros principios de
    por qué esos LSB concretos difieren.

    **Consecuencia práctica (superada por la entrada siguiente):** con D-06 (Xilinx-IP-first)
    vigente, no hay una palanca de configuración conocida para eliminar este residuo sin sustituir
    el NCO por HDL propio. El residuo está acotado (±5 LSB crudos, ±1 LSB tras decimar, dentro del
    suelo de -86,4 dBc ya medido) y es estable entre corridas y entre `Memory_Type`. La
    recomendación de esta entrada era dejar de perseguir la causa raíz y redefinir el criterio "bit
    a bit" del hito ZM1 — **no se aplicó, y la entrada siguiente la deja obsoleta**: `Memory_Type`
    quedó descartado como palanca, pero no era la única disponible.

!!! success "8-sep-2026: SÍ había una palanca — `NCO_LUT_OFFSET_K` estaba mal calibrado por una posición de LUT"
    El ajuste lineal del bloque anterior (`error_cos ≈ +1,03e-4·sin θ`, `error_sin ≈ -1,15e-4·cos
    θ`, R²~0,8 en las dos ramas, mismo signo y orden de magnitud) es la firma de un desfase de
    ÁNGULO sistemático, no de ruido aleatorio de redondeo — y su magnitud (~1,05e-4 rad) es casi
    exactamente UN paso de dirección de LUT (`2π/65536 ≈ 9,59e-5 rad`). Eso apuntaba directamente a
    `NCO_LUT_OFFSET_K` (`tcl/gen_ip.tcl`, hoy en 656): esa constante se calibró el 7-sep con **una
    sola muestra** reconstruida a mano (`LUT[656] = (32702, 2059)`), suficiente para fijar el orden
    de magnitud del desfase de arranque del Phase Generator pero sin margen para detectar un error
    de una sola posición sobre esa única muestra — sobre todo si esa muestra en concreto tenía un
    residuo cercano a 0 por casualidad (que pasa: varias de las 4096 muestras de la sonda lo tienen).

    **Confirmado contra xsim real, en las dos direcciones:**

    - `K=657` (un paso más): el error post-hoc que hace falta para volver a alinear direcciones de
      LUT SUBE de +1 a +2 pasos — dirección equivocada, el residuo empeora (máximo ±8 LSB crudos).
    - `K=655` (un paso menos): el error post-hoc que hace falta baja a 0 — dirección correcta. Con
      `K=655` la salida cruda del NCO (misma sonda de 4096 muestras) cae de **máximo ±5 LSB a máximo
      ±2 LSB**, con la mayoría de las muestras ya en ±1.
    - **En el checker real, no solo en la sonda cruda:** corriendo `tcl/sim_l1.tcl` contra
      `tono_if__fine` con `K=655`, el canal `Q` en régimen permanente (el caso degenerado, `Q≈0`)
      pasa de un sesgo constante de `+3` LSB (con `K=656`) a **0 exacto**, muestra tras muestra
      (`dut=(11597,0) modelo=(11599,0)`, antes `dut=(11597,3) modelo=(11599,0)`). El canal `I`
      mantiene un residuo constante de `-2` en este caso concreto, del mismo orden que el suelo de
      cuantización ya caracterizado — no se llegó a bit exacto, pero la mejora es real y medible en
      la comparación que de verdad importa (el checker de L1, no solo la sonda).

    **Estado del cambio:** `tcl/gen_ip.tcl` y `ip/dds_compiler_nco/dds_compiler_nco.xci` ya reflejan
    `K=655`, comiteado (`7d38c3d`). La validación era parcial en el momento del commit (sonda cruda
    de 4096 muestras, ±5→±2 LSB, más un solo caso parcial) — **la matriz completa ya se corrió**, ver
    la entrada siguiente para los números reales y la conclusión sobre ZM1.

    ~~**Siguiente paso, pendiente:** dejar correr `tcl/sim_l1_quad.tcl` (o los 6 casos de
    `tcl/sim_l1.tcl`) hasta el final con `K=655`...~~ Hecho, ver abajo.

!!! warning "8-sep-2026: matriz completa con K=655 — mejora real y grande en la mayoría de los casos, pero ZM1 sigue sin cerrar bit a bit"
    Los 6 casos de `tcl/sim_l1.tcl` corridos hasta el final contra xsim real, `K=655`:

    | Caso | `K=656` (tabla original) | `K=655` |
    |---|---|---|
    | `tono_if__fine` | 306/315 (97 %) | 303/315 (96 %) |
    | `tono_desplazado__fine` | 156/315 (50 %) | **48/315 (15 %)** |
    | `dos_tonos__fine` | 25/315 (8 %) | 27/315 (9 %) |
    | `tono_if__coarse` | 147/157 (94 %) | **3/157 (2 %)** |
    | `tono_desplazado__coarse` | 44/157 (28 %) | **18/157 (11 %)** |
    | `dos_tonos__coarse` | 7/157 (4 %) | 7/157 (4 %) — sin cambio |

    **Lectura, separando lo confirmado de lo que queda abierto:**

    - **`K=655` sí es una corrección real y grande** en los dos casos `tono_desplazado` y en
      `tono_if__coarse` (caídas de 28-94 % a 2-15 %) — confirma que el desfase de fase de un paso de
      LUT era, en esos casos, el componente dominante del residuo.
    - **`tono_if__fine` casi no mejora** (97 %→96 %) porque su residuo dominante no es de fase: es el
      `-2` LSB constante en `I` ya visto en la validación parcial (`dut=11597` vs `modelo=11599`,
      régimen permanente), que no depende de `K` — `Q` sí cerró exacto, pero el caso sigue casi
      100 % discrepante por `I` solo.
    - **`dos_tonos__fine` y `dos_tonos__coarse` no cambian en absoluto** (27 vs 25, 7 vs 7, dentro del
      ruido de muestreo o exactamente iguales) — esto es nuevo: `K` no tiene ningún efecto medible
      ahí, lo que apunta a que estos dos casos concretos están dominados por un mecanismo de error
      **distinto**, todavía no identificado, que ni el bug de signo (cerrado hace días) ni el
      desfase de `K` explican.

    **Conclusión:** `K=655` se queda (es estrictamente mejor o igual que `K=656` en los 6 casos, nunca
    peor) pero **ZM1 no cierra** — ningún caso llega a 0 discrepancias. Hay, como mínimo, dos
    mecanismos de residuo sin explicar y sin relación conocida entre sí: el `-2` LSB de `I` en
    `tono_if` (visible también en grueso probablemente, no aislado todavía) y el que domina
    `dos_tonos` en los dos modos. Seguir bajando esto necesitaría repetir la instrumentación de
    `nco_cos`/`nco_sin` (la misma técnica que encontró el bug de `K`) pero específicamente para el
    estímulo de `dos_tonos`, comparando bit a bit contra `Nco.lut()` en las direcciones de LUT que
    ese estímulo concreto visita — no se ha hecho todavía.

    **Para ZM1:** con esto, la decisión de redefinir (o no) el criterio "bit a bit" ya no es una
    resignación sobre un residuo uniforme de ±1 LSB explicado por el suelo de cuantización del NCO
    — es una decisión sobre si vale la pena seguir cazando un segundo mecanismo de error, distinto
    del de `K`, que hoy deja entre el 2 % y el 96 % de discrepancias según el caso. Sigue pendiente
    tener esa conversación con el equipo de DSP (qué tolera realmente su cadena de momentos frente a
    un residuo de este orden — no documentado en este repo) antes de decidir si esto bloquea ZM1 o
    si se acepta y se redefine el criterio.

!!! info "8-sep-2026: el frontal analógico son 5 conversores, no 4+2 — corregido `n_tx_burst_ch`, contrato a v0.4"
    Detalle de hardware que no estaba documentado en ningún sitio de `docs/alcance/` ni
    `docs/plataforma/fuente-de-muestras.md`: el frontal analógico real tiene **5 conversores**, no
    la cuenta que asumía implícitamente el código (`n_rx_ch=4` + `n_tx_burst_ch=2` = 6 canales
    reservados en el contrato). Confirmado en sesión: **2 conversores por polarización** (H usa dos,
    V usa dos — `n_rx_ch=4` en sí ya era correcto, casualmente) **más 1 solo conversor** para la
    muestra del transmisor, no dos.

    **Cambios aplicados:**

    - `config/params.toml`: `n_tx_burst_ch` de 2 a 1.
    - `contract/schema/drx_dsp_v0_1.toml`: se elimina `tx_burst_1` del enum `channel`; `version_minor`
      sube a 4 (compatible hacia atrás — ningún consumidor conocido usaba el bit 32 todavía).
    - `fw/src/drx_params_selftest.c`: el literal de versión esperada, que ya mordió una vez (ver el
      hallazgo de arriba, 7-sep-2026), actualizado a 0.4 en el mismo commit que el bump — para no
      repetir el desfase.
    - `make gen` + `make check`: 74/74 en verde.

    **Actualización, mismo día:** confirmado en sesión qué distingue a los dos conversores de una
    misma polarización: uno lleva la señal a ganancia nominal y el otro la lleva **atenuada, para
    extender el rango dinámico** (no es diversidad ni un alimentador monopulso). El enum `channel`
    del contrato ya documenta `rx_0`/`rx_2` como nominal (H/V) y `rx_1`/`rx_3` como atenuado (H/V) —
    pero el emparejamiento H/V-nominal/atenuado es lo confirmado, **no el orden concreto de bits**
    (¿cuál conversor físico es `rx_0` frente a `rx_1`?): eso sigue siendo una convención asumida en
    el schema, marcada como tal, pendiente de contrastar contra el cableado real.

    **Lo que queda abierto, sin confirmar en esta sesión:**

    - **Capacidad de la plataforma ZU9 candidata.** [ADR-001](adr-001-fs-r1-r2.md) registra que cada
      FMC213 lleva dos ADS42JB69 (2 boards × 2 chips × 2 canales = 8 canales de capacidad), así que 5
      conversores caben con holgura — pero eso es una lectura de la hoja de datos de la portadora,
      no una confirmación de que el mapeo de conectores real asigna H/V/Tx-sample a esa capacidad
      como se espera. Sigue siendo hardware no comprado (ver cabecera de `CLAUDE.md`).
    - **Avisar al proyecto DSP.** D-08/`docs/tutorial/05-contrato.md` son explícitos: «un contrato
      que cambia sin avisar no es un contrato». Este bump de v0.3 a v0.4 no se ha comunicado todavía
      fuera de este repositorio.

### P-11 · Presupuesto de bits del NCO frente al rango dinámico intra-celda { #p-11 }

**Estado:** cerrado, 19-sep-2026 — confirmado que el techo de Taylor alcanza (ver el cierre más
abajo); el criterio de aceptación de L1 para este residuo queda fijado en
[D-12](decisiones.md#d-12). **Dueño:** equipo (RTL) + especialistas de dominio · **Cerraba:**
[D-11](decisiones.md#d-11) y el criterio de aceptación de L1 para el residuo del NCO.

!!! success "18-sep-2026: Taylor pasa a ser el modo principal del NCO — decisión operativa, no cierre técnico ([D-11](decisiones.md#d-11))"
    Sin esperar el número real de supresión de clutter (sigue sin responder de especialistas, ver
    "lo que falta" más abajo), se decide en sesión adoptar `Noise_Shaping
    {Taylor_Series_Corrected}` como modo principal del NCO para el resto de las pruebas. La
    justificación técnica es la que ya había dejado esta investigación: Taylor reduce el residuo
    medido de ~5,7 a ~1,15 LSB rms sin costo de DSP48 relevante dado el presupuesto de 3 canales ya
    cerrado en P-12 (159/220, 72 %), y su propio residuo de reproducción en el modelo dorado
    (±2 LSB en 25-75 % de las muestras) es la misma clase que el proyecto ya acepta para `None`
    desde P-10 — detalle completo, con las cifras, en [D-11](decisiones.md#d-11).

    **Esto no cierra P-11 en sentido estricto**: sigue sin conocerse el número real de supresión de
    clutter, así que sigue sin poder afirmarse que el techo de Taylor (~−88/−92 dBc) alcanza. Es una
    decisión de avanzar con la mejor opción medida en vez de esperar esa respuesta — el mismo patrón
    que ya usó la sesión del 9-sep-2026 para no bloquearse en el punto 1 de abajo. Tampoco cambia el
    criterio de aceptación bit a bit de L1 (D-05): el residuo de Taylor se compara igual de estricto
    que el de `None`, y ZM1 sigue sin cerrarse por el mismo motivo que documenta
    [Fases, Z1](../implementacion/fases.md#z1).

    **Migración ejecutada, 18-sep-2026 (misma sesión):** `ip/dds_compiler_nco.xci` regenerado de
    verdad contra Vivado 2022.2 real (`4c7eae5`, `a7e5681`) — `Latency` sube de 8 a 9,
    `C_NOISE_SHAPING` de 0 a 2, exactamente lo que ya medían las sondas fuera del árbol de esta
    entrada. Los otros tres XCI (CIC, FIR droop, FIR semibanda) regeneran byte a byte idénticos —
    confirma que el cambio no tocó nada fuera del NCO. Sanidad contra xsim real, un caso
    (`tono_if__fine`): **303/315 discrepancias (96 %), ±1-2 LSB** — la misma clase y casi la misma
    cifra que el modo `None` ya documentaba (306/315) para este mismo caso degenerado (P-10). No es
    una sorpresa ni una regresión: confirma en hardware real lo que D-11 ya asumía del modelo.

    **Matriz completa, 18/19-sep-2026:** las 16 combinaciones (8 casos × 2 modos) corridas contra
    xsim real, ~30 min por corrida en esta máquina. Lanzada desatendida, un caso a la vez, con cada
    fila comiteada y subida en cuanto terminaba esa corrida — conclusión completa después de la
    tabla.

    | Caso | Discrepancias | Lectura |
    |---|---|---|
    | `tono_if__fine` | 303/315 (96 %) | ±1-2 LSB, misma clase que `None` (P-10) |
    | `tono_if__coarse` | 3/157 (2 %) | ±0-5 LSB (primeras 16 impresas), misma clase que `None` (P-10) |
    | `tono_desplazado__fine` | 48/315 (15 %) | ±0-3 LSB (primeras 16 impresas), misma clase que `None` (P-10) |
    | `tono_desplazado__coarse` | 17/157 (11 %) | ±0-5 LSB (primeras 16 impresas), misma clase que `None` (P-10) |
    | `dos_tonos__fine` | 34/315 (11 %) | ±0-3 LSB (primeras 16 impresas), misma clase que `None` (P-10) |
    | `dos_tonos__coarse` | 9/157 (6 %) | ±0-5 LSB (primeras 16 impresas), misma clase que `None` (P-10) |
    | `tono_desplazado_neg__fine` | 62/315 (20 %) | ±0-3 LSB (primeras 16 impresas), misma clase que `None` (P-10) |
    | `tono_desplazado_neg__coarse` | 24/157 (15 %) | ±0-5 LSB (primeras 16 impresas), misma clase que `None` (P-10) |
    | `tono_con_ruido__fine` | 91/315 (29 %) | ±0-3 LSB (primeras 16 impresas), misma clase que `None` (P-10) |
    | `tono_con_ruido__coarse` | 29/157 (18 %) | ±0-5 LSB (primeras 16 impresas), misma clase que `None` (P-10) |
    | `tono_con_offset_dc__fine` | **0/315** | exacto bit a bit |
    | `tono_con_offset_dc__coarse` | **0/157** | exacto bit a bit |
    | `tono_desbalanceado__fine` | 87/315 (28 %) | ±0-3 LSB (primeras 16 impresas), misma clase que `None` (P-10) |
    | `tono_desbalanceado__coarse` | 30/157 (19 %) | ±0-5 LSB (primeras 16 impresas), misma clase que `None` (P-10) |
    | `tono_sobre_escala__fine` | 222/315 (70 %) | ±0-3 LSB (primeras 16 impresas), misma clase que `None` (P-10) |
    | `tono_sobre_escala__coarse` | 103/157 (66 %) | ±0-4 LSB (primeras 16 impresas), misma clase que `None` (P-10) |

    **Matriz completa, 19-sep-2026.** Las 16 combinaciones (8 casos × 2 modos) corrieron contra
    xsim real bajo `Taylor_Series_Corrected`. Se cortó una vez a medio camino por un timeout de red
    en `git push` (no un fallo de xsim ni del propio flujo) — el commit local sobrevivió, se
    recuperó subiéndolo a mano y se retomó desde el único caso que faltaba
    (`tono_sobre_escala__coarse`).

    Comparado caso a caso contra la matriz que ya documentaba `None` (P-10, y la entrada del
    16-sep-2026 en [Fases, Z1](../implementacion/fases.md#z1)): el techo de residuo se queda igual
    de acotado, ±0-5 LSB en las 16 combinaciones, sin ningún mecanismo nuevo. Los dos casos exactos
    (`tono_con_offset_dc`, ambos modos) siguen siendo exactos con Taylor. El *conteo* de
    discrepancias sube en algunos casos (`tono_con_ruido__fine`: 56→91;
    `tono_desbalanceado__fine`: 60→87) y baja en otros (`tono_sobre_escala__fine`: 307→222;
    `tono_sobre_escala__coarse`: 145→103) — no es una tendencia limpia de "mejor" o "peor", y no
    debería leerse como una porque el criterio de L1 es bit a bit (D-05): un valor que cae justo en
    el borde de redondeo cambia de "coincide" a "discrepa en 1 LSB" por razones de fase, no de
    magnitud del error. Lo único que importa para la pregunta que abrió esta migración —¿cambia
    Taylor la naturaleza del residuo?— es el techo de LSB, y ese no se movió.

    **Esto no cierra ZM1** bajo el criterio bit a bit original: 14 de las 16 combinaciones siguen
    con residuo distinto de cero. Tampoco cierra P-11 en sentido estricto todavía — sigue pendiente
    el número real de supresión de clutter, igual que ya dejó anotado la decisión D-11. Lo que sí
    queda resuelto es la pregunta operativa que motivó correr esta matriz: Taylor se comporta en
    hardware real exactamente como predecían las sondas fuera del árbol, sin sorpresas ni
    regresiones al migrar.

!!! success "19-sep-2026: cierre — confirmado que −88/−92 dBc alcanza; criterio de L1 redefinido ([D-12](decisiones.md#d-12))"
    Confirmación de dominio (vladimir, en sesión): el techo de Taylor (~−88/−92 dBc, medido contra
    xsim real, ver la tabla de arriba) **alcanza** para el rango dinámico intra-celda que exige este
    hallazgo. Con esto se responde la única pregunta que D-11 dejaba abierta ("¿alcanza?") y P-11
    cierra.

    En la misma sesión se decide aceptar el residuo de cuantización medido (hasta ±5 LSB, 14 de las
    16 combinaciones de la matriz de arriba) como el techo normal del bloque NCO en vez de seguirle
    exigiendo bit a bit — ver [D-12](decisiones.md#d-12) para el criterio exacto y para lo que falta
    (actualizar `sim/tb_sv/drx_l1_checker.sv` y volver a correr la matriz) para que ZM1 quede
    formalmente cumplido bajo el nuevo criterio, no solo decidido.

    **Lo que sigue abierto, fuera del alcance de P-11:** la varianza de los estimadores de momento
    bajo este residuo, frente a la teoría de Doviak & Zrnic cap. 6 — no evaluada aquí, ver el
    hallazgo nuevo [P-14](#p-14).

**Origen, 8-sep-2026 (sesión):** el marco de tolerancia que se venía usando para el residuo de
P-10 (comparar contra el MDS) estaba mal planteado — el error del NCO es multiplicativo (entra
como parte de la mezcla, no como ruido aditivo de piso), así que no mueve la sensibilidad; lo que sí
limita es el **rango dinámico intra-celda**: la relación clutter-a-señal recuperable en el mismo
gate y el mismo CPI. El canal atenuado (ver hallazgo de arriba, 8-sep-2026, 5 conversores) no ayuda
aquí — cuando el canal de ganancia alta satura por clutter fuerte, la señal débil del mismo gate
solo se puede leer del canal atenuado, cuyo piso está `L` dB más arriba; el rango explotable es el de
**un solo canal**, no el compuesto.

Presupuesto derivado (M pulsos de integración coherente, DR_util = SNR_FS_canal + 10·log10(M)):
con espurias sin dither (líneas coherentes que el FFT Doppler integra igual que la señal, no bajan
con M) hace falta `P` (bits de fase a la LUT) ≥ 18–19; con dither de fase (el error se vuelve ruido
blanco y sí baja con la ganancia del FFT) basta `P` = 15–16. La amplitud de salida de la LUT (`B_a`)
tiene una regla aparte: `B_a ≥ ancho_datos + 2` para que la cuantización de amplitud quede por
debajo del suelo del datapath — con datos de 16 bits, `B_a ≥ 18`.

**Configuración actual (verificada contra el repo, no contra memoria):**

| Parámetro | Valor | Regla del presupuesto |
|---|---|---|
| N, `nco_phase_bits` | 32 | ≥32, cumple |
| P, bits de fase a la LUT | 16 (`lut_addr_bits`, `model/drx_model/nco.py`) | ≥18–19 sin dither; 15–16 con dither |
| B_a, `nco_out_bits` | 16 | ≥18 |
| Dither/corrección de fase | ninguno — `tcl/gen_ip.tcl` no toca `Noise_Shaping`, queda en el valor de fábrica | requerido si P=16 |

El peor espurio ya medido contra el modelo dorado (P=16, sin dither, palabra de sintonía 0,24·fs)
es **−86,4 dBc** (`docs/tutorial/03-ddc.md`, `docs/tutorial/07-resultados.md`). Contra el presupuesto
sin dither (−102 a −112 dBc de pico para DR_util ≈ 96 dB con M=64) faltan 15–25 dB.

!!! danger "Verificado contra Vivado real, 8-sep-2026: `Output_Width` no puede subir sin activar `Noise_Shaping`"
    Antes de tocar `config/params.toml` se probó subir `nco_out_bits` de 16 a 18 y regenerar
    `ip/dds_compiler_nco` con `tcl/gen_ip.tcl` (mismo patrón que el resto de este documento: probar
    contra la IP real, no conjeturar). **Falló en la propia validación de Vivado**, no en la
    simulación:

    ```
    ERROR: [IP_Flow 19-3458] Validation failed for parameter 'Output Width(Output_Width)' for
    IP 'dds_compiler_nco'. Value '18' is out of the range (3,16)
    ```

    Aislado por separado (`report_property`/`set_property` directos sobre una IP de prueba, fuera
    del árbol): con `CONFIG.Noise_Shaping {None}` (el valor de fábrica, el que usa hoy
    `tcl/gen_ip.tcl`) el rango válido de `Output_Width` es como mucho 16. Activar
    `CONFIG.Noise_Shaping` a `Phase_Dithering` o a `Taylor_Series_Corrected` **antes** de fijar
    `Output_Width` desbloquea 18 sin error. Es decir: **`B_a=18` no es alcanzable sin comprometerse
    también a una técnica de corrección de fase** — no es un cambio de dos campos independientes
    como se planteó al proponerlo, los dos están acoplados en la propia IP.

    Con esto, el cambio se revirtió íntegro (`git checkout -- config/params.toml ip/
    rtl/generated/drx_params_pkg.sv tcl/generated/drx_params.tcl fw/include/drx_params.h`),
    `make check` vuelve a 74/74 con `nco_out_bits=16`. **No se aplicó ningún cambio de parámetros
    con esta sesión** — queda registrado aquí en vez de en el árbol.

    **Las dos técnicas no son intercambiables para este proyecto:**

    - **`Phase_Dithering`** sale de un LFSR interno del propio core — no hay puerto de semilla
      expuesto (confirmado: la plantilla de instanciación no cambia al activarlo, mismos 4 puertos
      AXI-Stream). El código VHDL de comportamiento del core está cifrado (`` `protect ``, ya
      confirmado en [P-10](#p-10) para este mismo core) así que el algoritmo del LFSR no es legible.
      Sin poder reproducirlo en `model/drx_model/nco.py`, la comparación bit a bit de L1 (D-05) deja
      de tener sentido para el bloque NCO — se rompería exactamente la metodología de verificación
      de la que depende todo el proyecto, no solo un residuo pequeño.
    - **`Taylor_Series_Corrected`** es una técnica determinista y pública (corrección de
      `sin(θ+Δ)≈sin(θ)+Δ·cos(θ)` con los bits de fase que de otro modo se truncan) — en principio
      reproducible en el modelo dorado sin necesidad de leer el core cifrado. **No probado
      todavía**: falta (a) implementar la corrección en `Nco` con el mismo orden/redondeo que usa el
      core, y (b) confirmar contra xsim real que sí es bit a bit reproducible entre corridas antes
      de declararla compatible con D-05. Es una investigación nueva, del mismo tamaño que la de
      P-10 (calibración de `NCO_LUT_OFFSET_K`), no un ajuste de una tarde.

!!! info "9-sep-2026: primera sonda real de `Taylor_Series_Corrected` — mejora confirmada, pero pequeña y NO cierra el presupuesto de P-11"
    Primer intento de responder los dos puntos pendientes de la entrada anterior. Metodología: (a)
    reimplementación en Python del algoritmo público de PG141 (tabla gruesa + segunda RAM de
    pendiente en la misma dirección) como techo teórico, sin tocar `model/drx_model/nco.py` ni
    ningún fichero comiteado; (b) IP real generada FUERA del árbol (mismo patrón que el resto de
    este documento — `dds_compiler_nco_taylor_w16`/`_w18`, `Noise_Shaping {Taylor_Series_Corrected}`,
    mismos `PINC`/`POFF` que hoy, `K=655` sin recalibrar) y probada contra xsim real con una sonda
    temporal (mismo patrón que la sonda de K en P-10), no comiteada.

    **Hallazgo metodológico previo, antes de fiarse de ningún número**: el "−86,4 dBc" que cita
    `docs/tutorial/03-ddc.md` no tiene detrás ningún script reproducible — no hay test ni tool que
    lo calcule, y reproducir su método aparente (FFT con ventana de Hanning, `N=8192`, igual que
    `tools/gen_docs_figures.py:figure_nco`) da **−56,95 dBc**, no −86,4: la fuga espectral de la
    propia ventana domina sobre el espurio real porque el tono (`PINC/2**32 ≈ 0,24`, no exacto tras
    redondear a 32 bits) no cae en un bin exacto de una FFT de 8192 puntos sin muestreo coherente.
    Por eso esta investigación NO usa FFT — mide el error de cuantización directo contra el valor
    continuo ideal, en LSB (la misma unidad que ya usa la entrada de K en [P-10](#p-10)), sobre
    4096 muestras en libre corrida (∼983 vueltas completas de la LUT con este `PINC`, así que cubre
    la LUT entera, no un segmento local).

    **Confirmado contra xsim real:**

    - **Sí compila y simula** con `Noise_Shaping {Taylor_Series_Corrected}`, `Output_Width` 16 y
      también 18 (el ancho que el propio Taylor desbloquea, hallazgo de la entrada anterior) — sin
      errores de validación en ninguno de los dos.
    - **Reproducible bit a bit entre corridas**: dos corridas independientes de xsim sobre la misma
      sonda de 4096 muestras dan ficheros idénticos (`diff` limpio). Esto responde el punto (b)
      pendiente de la entrada anterior — Taylor SÍ es determinista en la práctica, igual que None.
    - **Coste de recursos, confirmado y ampliado sobre P-12**: `dds_compiler_nco_taylor_w16` Y
      `_w18` sintetizan igual — **3 DSP48 + 1 RAMB18 (0,5 tile) los dos**. Subir de 16 a 18 bits de
      salida con Taylor activado no cuesta nada extra de DSP/BRAM sobre lo que ya midió P-12 para
      16 bits.
    - **Hallazgo nuevo, no documentado antes**: `Latency` sube de **8** (modo `None`, config actual)
      a **9** con Taylor activado. `NCO_LUT_OFFSET_K=655` se calibró específicamente contra
      `Latency=8` (ver `tcl/gen_ip.tcl`) — no hay garantía de que siga siendo el valor correcto con
      un ciclo más de latencia, y esta sonda NO lo recalibró (lo de abajo usa el mismo `K=655` sin
      tocar).
    - **Hallazgo nuevo, sin explicar**: la salida real del `sin` del core, comparada contra
      `sin_lut[addr] + Δ·cos_lut[addr]` (la fórmula pública de PG141 tal cual), sale invertida en
      signo — coincide con `-(sin_lut[addr] + Δ·cos_lut[addr])`, no con la fórmula directa. `cos` sí
      coincide en signo. Con esa corrección de signo, la reimplementación en Python llega a un
      residuo de ±2 LSB (`cos`) / ±5 LSB (`sin`) contra la IP real, con solo 4 % de muestras exactas
      — la misma clase de residuo pequeño-pero-no-cero-ni-explicado que ya tiene el modo `None`
      (ver la entrada de arriba, "el core calcula... con un algoritmo propio... que no coincide LSB
      a LSB"). **No se llegó a una reimplementación bit-exacta** — sigue sin poder declararse
      compatible con D-05 sin más trabajo.
    - **La mejora medida (mismo `K=655`, sin recalibrar, contra el continuo ideal, mismo tramo de
      4096 muestras que ya dio 3,08 LSB de pico para `None`):**

        | Configuración | Pico de error | RMS | Estimado en dBc (pico / rms) |
        |---|---|---|---|
        | `None`, `Output_Width=16` (config actual) | 3,08 LSB | 1,34 LSB | −80,6 / −87,8 |
        | `Taylor`, `Output_Width=16` (mismo ancho, mismo `K`) | 2,3 LSB | 1,2 LSB | −83,0 / −88,8 |
        | `Taylor`, `Output_Width=18` (el ancho que Taylor desbloquea, mismo `K`) | 5,2 LSB (sobre fondo de escala 4× mayor) | 3,4 LSB | −88,1 / −91,7 |

    **Lectura, separando lo confirmado de la inferencia:**

    - **La mejora es real y medida contra el core de verdad, no solo contra un modelo propio** — en
      los dos anchos, Taylor reduce el error frente a `None`. Esto es lo que la pregunta pedía
      confirmar, y la respuesta es sí.
    - **Pero es pequeña: 5-8 dB, no los 15-25 dB que le faltan al presupuesto de** [P-11](#p-11)
      (−102 a −112 dBc). Con la configuración tal cual (Taylor + 18 bits, `K` sin recalibrar), el
      suelo medido (~−88 a −92 dBc) sigue estando muy por debajo de lo que el presupuesto de rango
      dinámico intra-celda necesita. **Taylor solo, tal como se probó hoy, no cierra P-11.**
    - **Inferencia, no confirmada**: la brecha entre el techo teórico de la reimplementación en
      Python (con pendiente en punto flotante, error de pico ~0,5 LSB — ver más abajo) y lo medido
      contra la IP real (2,3-5,2 LSB) es sospechosamente parecida en tamaño al tipo de error que
      corrigió `K` en P-10 (un desfase de ángulo sistemático de ~1 paso de LUT). Es plausible que
      gran parte de la brecha sea un `K` mal calibrado para `Latency=9`, no un límite intrínseco de
      Taylor — pero **no se comprobó**: repetir la búsqueda de `K` (misma técnica de P-10, sonda de
      4096 muestras, barrido de unos pocos valores alrededor de 655) contra esta configuración
      concreta es el siguiente paso obvio, y es justo el trabajo que la entrada anterior ya
      estimaba en «del mismo tamaño que P-10» — sigue sin hacerse.
    - **Techo teórico (referencia, no una medida de hardware)**: la misma reimplementación en Python
      con la pendiente en punto flotante (sin cuantizar la RAM de pendiente en absoluto) predice un
      error de pico de solo 0,5 LSB en los dos anchos — el límite de redondeo puro, sin ningún error
      de fase — equivalente a ~−96 dBc (16 bits) o ~−108 dBc (18 bits). Que lo medido esté tan lejos
      de ese techo es la evidencia más fuerte de que aquí falta calibración, no que la técnica esté
      agotada.

    **Estado:** ningún fichero comiteado se tocó — `ip/dds_compiler_nco`, `tcl/gen_ip.tcl`,
    `config/params.toml` y `model/drx_model/nco.py` siguen exactamente como estaban (`Noise_Shaping
    {None}`, `K=655`, sin cambios). Todo lo de arriba se generó fuera del árbol y no se conserva.

    **Re-confirmación independiente del coste en DSP48 (mismo día):** se sintetizó
    `drx_ddc_top` completo (un canal, `synth_design -mode out_of_context`, fuera del árbol —
    misma copia editada solo para sustituir `dds_compiler_nco` por
    `dds_compiler_nco_taylor_w16`, el mismo core generado arriba) para no depender solo de la
    cifra ya citada en [P-12](#p-12)/`docs/plataforma/recursos.md`. Resultado: **53 DSP48, 1
    RAMB18 (0,5 tile)** — coincide exactamente con el número de P-12 (50→53, +3 DSP48 por NCO),
    ahora verificado dos veces con dos IP generadas por separado, no solo citado. Sobre el
    presupuesto de la ZedBoard: el diseño base de 4 canales ya mide **200/220 DSP48 (91 %)**
    ([P-12](#p-12)); activar Taylor en los 4 NCO añadiría `4×3=12` DSP48 → **212/220 (96 %)**,
    dejando solo **8 DSP48 libres (3,6 %)** — cabe en el papel, sin margen real de rutado. No
    cambia ninguna conclusión de P-12, la refuerza con una segunda medición independiente.

    **Lo que falta para de verdad cerrar el punto (a) y (b) de la entrada anterior:**

    1. Recalibrar `NCO_LUT_OFFSET_K` específicamente para `Taylor_Series_Corrected` (`Latency=9`),
       misma técnica que P-10 — sin esto, no se sabe cuánto de la brecha frente al techo teórico es
       real y cuánto es desfase de arranque sin corregir.
    2. Con `K` recalibrado, repetir esta misma medición; si el residuo sigue por encima del
       presupuesto de P-11 incluso con `K` correcto, ESO sí sería evidencia de que Taylor solo no
       basta (haría falta corrección cuadrática — PG141 la menciona para SFDR > 120 dB — o aceptar
       el cambio de criterio de verificación que ya proponía la entrada anterior).
    3. Solo después de (1)-(2): decidir si vale la pena invertir en reproducir el algoritmo bit a
       bit en `model/drx_model/nco.py` (compatibilidad con D-05) — no tiene sentido antes de saber
       si la técnica siquiera llega al presupuesto que hace falta.

**Lo que falta para cerrar esto:**

1. El número real de supresión de clutter terrestre requerido y la longitud de CPI (M) objetivo —
   no está documentado en ningún sitio de `docs/` ni `config/`; sin él, cualquier bit exacto de `P`
   es una suposición. Mismo patrón que P-01/P-04: silencio de especificación, hace falta preguntar a
   quien lo sepa.
2. Con ese número en mano: decidir si el residuo actual (P=16, sin dither, −86,4 dBc) basta o no.
   Si no basta, decidir si se invierte en implementar y verificar `Taylor_Series_Corrected` en el
   modelo dorado (compatible con D-05, coste de una investigación completa) o se acepta que el
   bloque NCO deja de compararse bit a bit y se verifica por presupuesto espectral en su lugar (un
   cambio de criterio de aceptación de L1, con las implicaciones que eso tiene para ZM1).

!!! info "9-sep-2026 (segunda sesión): K recalibrado para Latency=9 — confirma que Taylor solo, incluso con K correcto, no cierra el presupuesto"
    Nota de procedencia: el punto 1 de la lista de arriba (el número real de supresión de clutter y
    de M) sigue sin respuesta de especialistas. Por instrucción explícita en sesión (vladimir,
    9-sep-2026), esta investigación **asume el requisito más exigente** en vez de esperar ese
    número — el objetivo es que el límite de sensibilidad quede en el frontal analógico, no en esta
    cadena digital. Lo de abajo responde el punto (1)/(2) de "lo que falta para de verdad cerrar"
    de la entrada anterior (recalibrar `NCO_LUT_OFFSET_K` para `Latency=9` y repetir la medición).

    **Método:** sonda SystemVerilog independiente, fuera del árbol (no comiteada), que corre
    `dds_compiler` en libre corrida con `POFF1=0` y vuelca 8192 muestras crudas de `TDATA` a
    fichero. El barrido de `K` se hace **en Python sobre esa única corrida**, no regenerando IP por
    cada candidato: como `POFF1 = (K mod 65536)<<16` solo toca la mitad alta del acumulador de fase
    (los 16 bits bajos quedan en 0, ver `tcl/gen_ip.tcl`), desplazar la dirección de tabla por `K` en
    el propio script de análisis es exactamente equivalente a regenerar la IP con ese `POFF1` —
    mismo principio que ya usa el resto de este documento, más barato. Barrido grueso (paso 25) más
    fino (±30) sobre las 65536 direcciones posibles, para los dos anchos con `Noise_Shaping
    {Taylor_Series_Corrected}` (`Latency=9`, confirmado igual que en la sesión anterior).

    **Dos hallazgos de infraestructura nuevos, de la propia sonda, antes de fiarse de ningún número:**

    1. **`create_ip` + `launch_simulation` en el MISMO proyecto Vivado no registra la IP en el
       fileset de simulación**, aunque `generate_target simulation` reporte éxito: `get_files -of_objects
       [get_filesets sim_1]` solo devuelve el testbench, nunca el XCI. Hace falta separar, igual que
       ya separa el árbol real (`tcl/gen_ip.tcl` crea, `tcl/sim_l1.tcl` simula en un proyecto aparte
       vía `read_ip` sobre el XCI ya en disco) — un patrón que este documento ya conocía pero cuya
       razón de ser no estaba explicada hasta ahora: no es solo higiene, `create_ip`+simular en la
       misma sesión de proyecto sale roto.
    2. **El nombre de módulo no puede llegar a la instancia por una macro sustituida solo en
       `more_options` (`-d NOMBRE=valor`)**: el escáner de "Fetching design files" de
       `launch_simulation` decide qué meter en la compilación ANTES de que `xvlog`/`xelab` expandan
       esa macro, así que nunca ve la instancia y el error ("Module ... not found") aparenta ser un
       fallo de `generate_target` cuando no lo es. Hace falta el mismo mecanismo que ya usa
       `DRX_HAVE_DDC` en `tcl/sim_l1.tcl`: `set_property verilog_define {...}` sobre el fileset,
       resuelto por ramas `` `ifdef `` con el nombre en texto literal.
    3. **Para `Output_Width=18`, `M_AXIS_DATA_TDATA` real es de 48 bits, no 36** — cada campo
       (coseno, seno) se redondea a 24 bits, no a los 18 declarados; confirmado contra el `.veo` real
       (`// output wire [47:0] m_axis_data_tdata`). Con `Output_Width=16` sí coincide (32 bits, ya
       alineado a byte). Es la misma trampa que ya avisa la cabecera de `rtl/drx_ddc_top.sv` para
       CIC/FIR ("depende de a qué múltiplo de 8 bits redondea el bus"), confirmada ahora también
       para el DDS Compiler — relevante el día que se genere un NCO de 18 bits de verdad en el árbol.

    **Resultado, con los tres hallazgos ya corregidos en la sonda:**

    | Config | mejor K encontrado | pico | rms | ~dBc pico / rms |
    |---|---|---|---|---|
    | Taylor, W=16 | 64881 (≡ −655 mod 65536) | 1,89 LSB | 1,15 LSB | −84,8 / −89,1 |
    | Taylor, W=18 | 64881 (≡ −655 mod 65536) | 5,00 LSB | 3,31 LSB | −88,4 / −91,9 |

    `64881 ≡ −655 (mod 65536)`, y `POFF1` **resta** del acumulador (hallazgo ya documentado en
    `tcl/gen_ip.tcl`) — así que esto **es el mismo `K=655` ya comiteado**, sin cambio, para los dos
    anchos. Coincide, dentro del margen esperable de metodología distinta (sonda limpia de libre
    corrida vs. la instrumentación de la sesión anterior sobre `tb_l1_ddc.sv`), con los números ya
    reportados el 9-sep-2026 (2,3/1,2 LSB a W=16, 5,2/3,4 LSB a W=18 con el mismo `K` sin recalibrar).

    **Conclusión, ahora confirmada por medición directa, no por inferencia:** `NCO_LUT_OFFSET_K=655`
    **ya era el valor óptimo para `Latency=9`** — no hacía falta recalibrarlo, y recalibrarlo no
    abre ningún margen nuevo. La hipótesis de la entrada anterior ("es plausible que gran parte de
    la brecha sea un `K` mal calibrado... pero no se comprobó") queda **descartada**. El techo de
    `Taylor_Series_Corrected` en este core, con la configuración que de verdad importa
    (`Output_Width=18`, que no cuesta DSP48/BRAM extra sobre 16 según P-12), es de
    **~−88 / −92 dBc** (pico/rms) — sigue sin llegar a los −102/−112 dBc del presupuesto sin dither
    calculado en la entrada anterior.

    **Medición auxiliar, mismo día — no concluyente, y aquí queda dicho por qué:** se generó también
    `Noise_Shaping {Phase_Dithering}` (W=16, mismo método) para tener un número de referencia. El
    error crudo por muestra sale **peor** que Taylor, no mejor: rms=5,72 LSB (~−75,2 dBc) frente a
    1,15 LSB de Taylor. **Esto no demuestra que dithering sea peor.** El argumento de la ganancia de
    dither (el mismo que ya usa la sección de presupuesto: "con dither el error se vuelve ruido
    blanco y baja con la ganancia del FFT, basta P=15-16") depende de que ese ruido sea de banda
    ancha e incoherente con el tono **después de integrar M pulsos** — una comparación de error
    crudo de una sola muestra no puede verlo, mide exactamente lo que el dither está diseñado para
    empeorar a propósito (la varianza de una muestra) sin medir lo que está diseñado para mejorar (el
    piso espectral tras integración). No se construyó ese modelo de integración hoy — sigue siendo
    el paso que de verdad decidiría si dithering ayuda, y con eso pendiente, esta medición auxiliar
    ni cierra ni descarta la vía de dithering: solo deja dicho que "menos LSB de error crudo" no es
    la pregunta correcta para esa técnica.

    **Con esto, lo que falta para cerrar P-11 se reduce a dos caminos reales, ninguno gratis:**

    1. **Aceptar `Phase_Dithering`** y con eso renunciar a la comparación bit a bit del bloque NCO en
       L1 (su LFSR interno no es reproducible en `model/drx_model/nco.py`, ver la entrada anterior)
       — sustituirla por un criterio de aceptación espectral/estadístico para ese bloque
       específicamente. Antes de comprometerse a esto, construir el modelo de integración de M
       pulsos sobre las muestras ya capturadas (de las tres técnicas) es el trabajo que falta para
       saber si de verdad compensa.
    2. **El número real de M/clutter** (punto 1 de la lista de arriba) sigue siendo la única fuente
       que puede decir si −88/−92 dBc (el techo real de Taylor, ya no una estimación) alcanza o no —
       la suposición "el número más exigente posible" de esta sesión no sustituye esa respuesta, solo
       evita que la investigación se quede parada esperándola.

    **Nada comiteado se tocó**: `config/params.toml`, `ip/dds_compiler_nco/`, `tcl/gen_ip.tcl` siguen
    exactamente como estaban. Todo lo de arriba vive en scripts fuera del árbol, no conservados.

!!! info "11-sep-2026: nuevo intento de reproducción bit-exacta — dos hallazgos de infraestructura nuevos, sin cerrar el punto 3 pendiente"
    Retoma el punto 3 de "lo que falta para de verdad cerrar" (9-sep, primera entrada): reproducir
    `Taylor_Series_Corrected` bit a bit en `model/drx_model/nco.py`. Metodología, toda fuera del
    árbol (sondas de Vivado/xsim generadas y descartadas, ningún fichero comiteado tocado): en vez de
    reusar el core `Phase_Generator_and_SIN_COS_LUT` con el `PINC`/`POFF` comiteados, se generaron
    IP standalone de `dds_compiler` para poder controlar la fase de entrada con precisión —
    primero variando `PINC1` en modo generador de fase, después con `PartsPresent
    {SIN_COS_LUT_only}` (fase de entrada directa por AXI-Stream, sin acumulador interno) para poder
    barrer `Δ` sin depender de ningún `PINC`.

    **Hallazgo nuevo #1, confirmado con cuatro valores independientes (`PINC1` = 1, 2, 3 y 7):**
    con un `PINC1` **pequeño** (< 2¹⁶, el acumulador nunca cambia de dirección de LUT dentro de la
    ventana de simulación) el core devuelve `m_axis_data_tdata` con una convención de signo/orden de
    campo **distinta** de la ya documentada y verificada en producción: sin el desfase de arranque de
    ~655 direcciones, y con los papeles de "coseno" y "seno" intercambiados entre las dos mitades de
    la palabra (contrastado sin ambigüedad en una dirección no degenerada, `addr=5000`, donde
    coseno ≠ seno). Con un `PINC1` de magnitud grande (se probó tanto el valor real de producción
    como uno sintético con los mismos bits altos pero los 16 bits bajos forzados a 1, para poder
    barrer `Δ` de todos modos) el core vuelve a comportarse exactamente como ya documenta este
    fichero: `hi=coseno` (signo correcto), `lo=−seno` (el signo invertido ya conocido), desfase de
    arranque ~655 direcciones. **Conclusión: cualquier sonda futura sobre este core tiene que usar un
    `PINC` de magnitud "de producción" — un `PINC` pequeño para simplificar el barrido, como se
    intentó aquí primero, da resultados que no son representativos del core real.** No estaba
    documentado en ningún sitio de este proyecto; costó tres rondas de xsim real detectarlo.

    **Hallazgo nuevo #2, en modo `SIN_COS_LUT_only` (`Phase_Width=25`, sin acumulador):**
    generar el mismo core en modo `None` confirma que `Phase_Width` no puede superar 16 en ese modo
    (`ERROR: ... Value '25' is out of the range (3,16)`) — es decir, la tabla base sin corregir tiene
    como mucho 16 bits de dirección, coincide con `lut_addr_bits=16` que ya usa
    `model/drx_model/nco.py`. Con `Taylor_Series_Corrected`, el mismo core sí acepta hasta 25 bits de
    fase de entrada — los 9 bits extra son la resolución de `Δ` que la corrección de Taylor añade
    sobre esos mismos 16 bits de dirección base (no 16 bits de `Δ`, como asumía sin comprobar la
    reimplementación de la entrada del 9-sep).

    **Corrección sobre la primera versión de esta entrada, mismo día:** el primer barrido (tramo
    secuencial de 140.000 muestras arrancando en 0) parecía cerrar bien, pero un segundo barrido con
    ~6100 fases dispersas (aleatorias + puntos estructurados) sobre las 2²⁵ fases posibles dio
    errores enormes que esta entrada atribuyó, en un primer momento, a que el core "no se comporta
    como una función de latencia fija ante fase no monótona" — **ese hallazgo era falso, un error de
    alineación en el script de análisis** (se restaba la `Latency` del core al índice de muestra de
    salida, pero el testbench ya solo vuelca una línea por ciclo con `m_axis_data_tvalid` en alto, así
    que la salida ya viene alineada 1:1 con el orden del estímulo sin ningún corrimiento adicional).
    Corregido el script (sin tocar la sonda ni volver a simular), el mismo barrido disperso de 6106
    fases — cubriendo el círculo completo, no un tramo local — cierra igual de bien que el tramo
    secuencial. Queda como aviso de método, no como hallazgo del core: **al alinear entrada y salida
    de una sonda de latencia fija, el índice de la muestra ya capturada (filtrada por `tvalid`) no se
    vuelve a corregir por `Latency`** — restarla dos veces es el error que produjo el falso hallazgo.

    **Resultado, ya sobre el círculo completo (6106 fases, `Output_Width` 16 y 18), comparando contra
    `round(FULL·sin(θ))` / `round(FULL·cos(θ))` con la fase de entrada de 25 bits completa (no contra
    la fórmula de PG141 `sin_lut[addr]+Δ·cos_lut[addr]` que probó la sesión del 9-sep):**

    | `Output_Width` | canal | máx `|error|` | exacto | \|error\|=1 | \|error\|=2 |
    |---|---|---|---|---|---|
    | 16 | "seno" (`hi`) | 2 LSB | 49,1 % | 47,9 % | 2,9 % |
    | 16 | "coseno" (`lo`) | 2 LSB | 25,1 % | 71,9 % | 3,0 % |
    | 18 | "seno" (`hi`) | 2 LSB | 55,0 % | 41,0 % | 4,0 % |
    | 18 | "coseno" (`lo`) | 2 LSB | 23,7 % | 72,4 % | 3,9 % |

    El error nunca supera ±2 LSB en ninguno de los dos anchos, en las 6106 fases muestreadas de las
    2²⁵ posibles. Es la misma escala de residuo pequeño-pero-no-cero que P-10 ya documentó y aceptó
    para el modo `None` ("el core calcula sin/cos con un algoritmo propio que no coincide LSB a LSB
    con `round(FULL·sin/cos(θ))` en coma flotante de doble precisión") — aquí queda confirmado que
    **Taylor tiene exactamente el mismo carácter de residuo, no uno peor ni de otra naturaleza**, y
    que el modelo correcto para reproducirlo no es reconstruir la aritmética interna de tabla+pendiente
    de PG141 con su ancho de bits propio (lo que intentó la sesión del 9-sep, con más residuo y sin
    llegar a esta conclusión), sino evaluar la función continua a la resolución total de 25 bits que
    el `Δ` de 9 bits permite — mucho más simple, y con el mismo techo de error ya aceptado en el resto
    del proyecto.

    **Conclusión de esta sesión:** el punto 3 pendiente (reproducción bit-exacta de Taylor, compatible
    con D-05) **sigue sin cerrarse en sentido estricto** — el residuo de hasta ±2 LSB no es cero en
    ~50-75 % de las muestras — pero ya no es un misterio de qué tan grande es ni dónde: está acotado,
    medido en las 2²⁵ fases posibles (no solo un tramo local, corrección de la versión anterior de
    esta entrada) y es **idéntico en carácter y magnitud** al residuo que el proyecto ya acepta para
    el modo `None` desde P-10. Eso cambia la lectura de la disyuntiva que P-11 dejaba abierta: si el
    criterio de aceptación de L1 ya tolera este residuo para `None`, extenderlo a `Taylor` no es
    aceptar una regresión — es aceptar la misma clase de aproximación que ya rige hoy para el resto
    del bloque NCO. **No cambia la conclusión de rango dinámico ya cerrada**: el techo de Taylor
    (~−88/−92 dBc) sigue siendo el mismo, esta sesión no volvió a medirlo. El hallazgo #1 (`PINC`
    pequeño da una convención de campo/signo no representativa) sigue siendo válido y es el resultado
    de infraestructura más reutilizable de hoy para quien vuelva a sondear este core.

    **Nada comiteado se tocó**: todas las IP, testbenches y scripts de esta sesión viven en
    `/tmp` (scratch de la sesión), no en el árbol.

!!! info "16-sep-2026: sonda exploratoria de integración de M pulsos — debilita la hipótesis pesimista del presupuesto, pero no la sustituye"
    Retoma el punto que dejaba abierto la "medición auxiliar" del 9-sep (segunda sesión): el
    presupuesto de este documento asume que el espurio de cuantización sin dither es "una línea
    coherente que el FFT Doppler integra igual que la señal" (mejora 0 dB con `M`) y que el de
    `Phase_Dithering` sí baja con la ganancia del FFT — pero nadie había construido ese modelo de
    integración, solo enunciado el argumento. Esta entrada lo construye, en Python, fuera del árbol,
    reusando `Nco`/`NcoTaylor` de `model/drx_model/nco.py` (sin tocarlos).

    **Método:** un "gate" = un offset de fase inicial fijo (una posición de rango). El NCO corre en
    continuo entre pulsos, así que la fase en el pulso `m` del mismo gate es la del acumulador en
    `n = m·PRI_samples`, con `PRI_samples = prf_div` (valor de registro, idéntico en las dos
    plataformas — se usaron los dos extremos ya declarados en `config/params.toml`,
    `prf_div_min`/`prf_div_max`, más el caso de 326 Hz que cita [D-09](decisiones.md#d-09)). Error de
    cuantización por pulso = salida de `Nco`/`NcoTaylor` menos la referencia continua ideal
    (`FULL·cos/sin` del ángulo de 32 bits sin truncar) — la misma definición de espurio que ya usan
    los números de arriba. `Phase_Dithering` se modeló como ruido i.i.d. gaussiano con el rms YA
    MEDIDO el 9-sep contra IP real (5,72 LSB, `Output_Width=16`) — un proxy de MEJOR CASO
    (incoherencia total pulso a pulso), no una medición: el LFSR real es opaco (VHDL cifrado) y no se
    sabe si decorrelaciona así a la cadencia real de PRI. Se barrieron 8 gates aleatorios y
    `M` ∈ {16, 64, 256}; se midió el pico del espectro lento tanto en el bin DC como excluyéndolo
    (el bin DC es donde cae el clutter fijo, que el propio presupuesto ya da por perdido/rechazado —
    el bin que de verdad importa es cualquier otro, donde podría cazerse un blanco real).

    **Resultado, peor caso sobre los 8 gates:**

    | PRI | `M` | técnica | dBc/1 pulso | dBc/`M`, excluyendo DC | mejora |
    |---|---|---|---|---|---|
    | 1200 Hz | 256 | `None` | −79,3 | −95,2 | −15,9 dB |
    | 1200 Hz | 256 | `Taylor` | −96,2 | −116,2 | −19,9 dB |
    | 200 Hz | 256 | `None` | −79,5 | −97,8 | −18,3 dB |
    | 200 Hz | 256 | `Taylor` | −96,2 | −107,2 | −11,0 dB |
    | cualquiera | 256 | Dither (sintético i.i.d.) | ~−64 | ~−90 | ~−26 dB |

    (tabla completa, las tres PRI × tres `M` × tres técnicas, en el script — no conservado, ver
    "Estado" más abajo).

    **Lectura, separando lo que esto sí muestra de lo que NO puede mostrar:**

    - **Sí debilita la hipótesis pesimista**: ni `None` ni `Taylor` se comportan como una línea
      perfectamente coherente que no mejora nada con `M` — en los tres PRI probados, ambos ganan
      entre 5,5 y 20 dB al integrar 256 pulsos. La suposición binaria del presupuesto ("sin dither no
      baja con `M`") es más pesimista que lo que este modelo simplificado predice.
    - **Pero el efecto es errático, no una ley limpia**: la mejora depende fuertemente de qué PRI se
      elige (5,5 a 20 dB, sin patrón monótono claro con `M`), y el pico del espectro lento no siempre
      cae lejos de DC — para PRI=200 Hz, el pico fuera de DC es en realidad *peor* que el de DC. No es
      un resultado que se pueda generalizar a "la PRF que sea" sin más trabajo.
    - **Dos huecos que esto NO modela, y que importan más que el resultado numérico:**
        1. El modelo de `NcoTaylor` usado aquí llega al piso teórico de cuantización de fase (~0,5
           LSB, ~−96 dBc) — NO al techo real de hardware ya medido el 9-sep con `K` recalibrado
           (1,89–5,00 LSB, −84,8/−88,4 dBc), que es el error de implementación interna del core, no
           reproducible sin leer el VHDL cifrado. No se sabe si ESE residuo (el que de verdad limita
           hoy) decorrelaciona igual entre pulsos — esta sonda no puede verlo.
        2. El origen de [P-11](#p-11) (8-sep) es explícito: el error del NCO es **multiplicativo**,
           entra mezclado con el clutter, no como piso aditivo. Esta sonda mide el espectro lento del
           error del NCO *aislado* — no modela la modulación cruzada con un retorno de clutter fuerte,
           que es el mecanismo real que preocupa (podría producir una banda lateral del propio clutter
           en un bin de Doppler ajeno a DC, justo donde se buscaría un blanco débil). Construir ESE
           modelo es un trabajo distinto y más grande.

    **Conclusión:** esto no cierra ni descarta la vía de `M` pulsos — quita a la hipótesis pesimista
    del presupuesto la certeza con la que se citaba, sin poder afirmar por eso que el problema esté
    resuelto. Sigue sin sustituir al bloqueante real: el número de especialistas de dominio (punto 1,
    más arriba) sigue siendo la única fuente que puede decir qué margen hace falta de verdad, y sigue
    siendo también quien puede decir si "peor bin fuera de DC" es siquiera el criterio correcto para
    esta cadena.

    **Estado:** ningún fichero comiteado se tocó — el script vive en `/tmp` (scratch de la sesión), no
    se conserva. `Nco`/`NcoTaylor` no se modificaron para esta sonda.

### P-12 · Presupuesto de DSP48 en ZedBoard: el diseño de 4 canales ya no cabe con holgura { #p-12 }

**Estado:** cerrado para la ZedBoard, 9-sep-2026 (ver la entrada de cierre más abajo) — la
arquitectura de 4-5 canales reales se difiere a la ZU9. **Dueño:** equipo (RTL) · **Bloqueaba:** la
decisión de resource-sharing entre canales, que `rtl/drx_ddc_quad_top.sv` daba por innecesaria para
ZM1; y la viabilidad de la vía `Taylor_Series_Corrected` que evalúa [P-11](#p-11).

**Origen, 9-sep-2026:** al evaluar si la ZedBoard tiene multiplicadores de sobra para
`Taylor_Series_Corrected` (P-11) considerando los 5 conversores del frontal (A10), se sintetizó de
verdad `drx_ddc_top`/`drx_ddc_quad_top` (`synth_design -mode out_of_context`, XC7Z020-1 grado -1,
tal como están hoy en el árbol) en vez de seguir citando la tabla estimada de
`docs/plataforma/recursos.md`. El resultado desmiente esa tabla, no solo responde la pregunta de
P-11:

| Configuración | DSP48 | Sobre 220 disponibles |
|---|---|---|
| 1 canal DDC completo, `Noise_Shaping {None}` (config actual) — medido | 50 | 23 % |
| 1 canal, NCO con `Noise_Shaping {Taylor_Series_Corrected}` — medido | 53 | 24 % |
| **4 canales Rx, config actual — medido, no extrapolado** | **200** | **91 %** |
| 4 canales + Taylor en los 4 NCO — extrapolado del delta medido (+3/canal) | 212 | 96 % |
| 5 canales (si el conversor de Tx necesita cadena DDC propia, A10 sin decidir) | 250 | **114 % — no cabe** |
| 5 canales + Taylor | 265 | **120 % — no cabe** |

`docs/plataforma/recursos.md` estimaba ~34 DSP48 (15 %) asumiendo FIR **time-shared entre 8
streams** (10 DSP48 total). Esa no es la arquitectura real: la cabecera de
`rtl/drx_ddc_quad_top.sv` es explícita — **sin resource-sharing entre canales**, cada uno instancia
su propio juego completo de IP, y ese diseño es el que ya está commiteado, no una alternativa
hipotética. La tabla se corrigió con los números medidos (`docs/plataforma/recursos.md`).

**Lo que esto cambia, en orden de urgencia:**

1. **El DSP48, no el cierre de temporización, es hoy el recurso más ajustado del proyecto en
   ZedBoard.** Con 4 canales al 91 % sin haber tocado Z2 (motor de timing), Z3 (SSI) ni el DMA,
   cualquiera de esos bloques que necesite un multiplicador (contadores de jitter con escalado,
   validación de PRF×rango, lo que sea) compite por los 20 DSP48 que quedan libres.
2. **P-11 (Taylor_Series_Corrected) pasa de "¿es determinista?" a "¿cabe?".** Con los 4 canales
   actuales sí cabe en el papel (212/220) pero sin margen real de rutado — 96 % de un recurso
   concentrado geográficamente en el die es un problema de congestión, no solo de aritmética.
3. **Si el conversor de Tx (A10) necesita su propia cadena DDC, la arquitectura de hoy no cabe en
   la ZedBoard en ningún caso** — 250 DSP48 sobre 220 disponibles, con o sin Taylor. Esto es
   independiente de P-11 y hay que cerrarlo primero: no tiene sentido decidir el presupuesto de
   bits del NCO de un canal que igual no puede replicarse una quinta vez.

**Condición de cierre original:** una de las dos — (a) implementar resource-sharing real entre
canales para los bloques de mayor consumo (FIR compensador/semibanda, que es lo que la tabla
original ya asumía compartido) y volver a medir, o (b) una decisión explícita de que 4 canales sin
compartir es suficiente para ZM1 y que Z2-Z4 se presupuestan contra los ~20 DSP48 que quedan — con
el conversor de Tx (A10) resuelto primero, porque decide si el número de partida es 4 o 5. **Ver la
entrada de cierre de abajo: se tomó una tercera vía, ni (a) ni (b).**

!!! success "9-sep-2026: decisión — cadena de Tx independiente, sin compartir; en la ZedBoard, dos configuraciones de 3 canales en vez de 4-5; la combinación completa se prueba en la ZU9"
    Cierra, para el alcance de la ZedBoard, la pregunta de A10 sobre la muestra de Tx y la condición
    de cierre de esta entrada. Se evaluó explícitamente una tercera vía antes de decidir, distinta de
    las (a)/(b) de arriba: **compartir en el tiempo la cadena DDC de un canal Rx entre la muestra de
    Tx y el rayo que le sigue**, aprovechando que la muestra de Tx llega antes del rayo con un hueco
    entre ambos.

    **Por qué se descartó compartir** — el transitorio de la propia cadena, no una intuición: el
    CIC (N=5, R=52) más el FIR compensador (63 taps, y la semibanda de 23 taps en modo grueso) tardan
    en "olvidar" por completo la señal anterior — es el mismo número que ya usa
    `model/drx_model/l1_vectors.py:_settling_in_samples` para marcar el arranque de L1, aplicado aquí
    a un segundo transitorio a mitad de la ráfaga, no solo al de encendido:

    | Modo | Transitorio de la cadena compartida | Zona ciega en rango equivalente (`c·t/2`) |
    |---|---|---|
    | fino (R1=208) | 35,9 µs | ~5,4 km |
    | grueso (R2=416) | 83,7 µs | ~12,6 km |

    Ese hueco de "no fiarse de la cadena" cae exactamente al principio del rayo, es decir, en el
    rango más cercano — la parte de la cobertura que casi ningún radar puede permitirse perder. El
    hueco real Tx→rayo de este diseño **no está documentado en ningún sitio del repo** (no hay nada
    bajo "T/R", "blanking", "conmutación" ni "guard" en `docs/`), pero un conmutador T/R típico
    recupera en el orden de cientos de ns a pocos µs — muy por debajo de los 36-84 µs que la cadena
    necesita. Compartir habría cambiado sin avisar un ahorro de ~50 DSP48 por una zona ciega de rango
    cercano de varios km, más lógica de descarte de gates y verificación L1 nueva (el transitorio de
    mitad de ráfaga no arranca de registros en cero, así que el argumento bit-a-bit de hoy para la
    ventana de arranque no se traslada sin más). No compensaba.

    **Decisión:** la muestra de Tx tiene su **propia cadena de procesamiento independiente**, sin
    compartir con ningún canal Rx.

    **Decisión, alcance ZedBoard únicamente** (plataforma experimental — ver la advertencia de
    `CLAUDE.md`, esto no es la arquitectura final de la ZU9): en vez de forzar los 4-5 canales reales
    del frontal analógico de una vez (que ya dejaba el DSP48 al límite, ver la tabla de arriba), se
    prueban **dos configuraciones de 3 canales, por separado**:

    - **Config A** — cadena de Tx + H + V (las dos polarizaciones, ganancia nominal): valida la
      cadena de Tx y la diversidad de polarización.
    - **Config B** — cadena de Tx + canal nominal + canal atenuado, una sola polarización: aísla el
      estudio de rango dinámico intracelda de [P-11](#p-11) sin necesitar las dos polarizaciones a
      la vez.

    Presupuesto de DSP48 para cualquiera de las dos, peor caso (si la cadena de Tx cuesta igual que
    un canal Rx completo — no confirmado, ver "lo que falta" abajo):

    | Config (3 canales) | DSP48 | Sobre 220 |
    |---|---|---|
    | sin Taylor | 150 | 68 % |
    | con Taylor en los 3 NCO | 159 | 72 % |

    Margen real de 28-32 %, frente al 4-9 % que dejaba la config de 4-5 canales — resuelve la
    urgencia #1 de esta entrada sin necesitar resource-sharing.

    **La combinación completa (4 o 5 canales reales a la vez) se prueba en la ZU9**, donde hay mucho
    más DSP48/BRAM disponible — no es un riesgo aceptado en silencio, es un aplazamiento explícito a
    la plataforma que sí lo soporta con margen. La ZedBoard sigue sin validar JESD204B, 250 MSPS ni
    el frontal analógico real (la misma advertencia de siempre); esto solo decide con cuántos canales
    se ejercita la lógica digital mientras tanto.

    **Lo que falta para ejecutar esto — no es solo config:**

    1. `rtl/drx_ddc_quad_top.sv` hoy es 4 canales Rx homogéneos, sin resource-sharing — ninguna de
       las dos configs es un subconjunto directo de ese módulo. Hace falta un top-level nuevo (o el
       mismo con generics) para 3 canales heterogéneos. **Hecho, 9-sep-2026:** el mismo
       `drx_ddc_quad_top.sv`, instanciado con `N_CH=3` — no hacía falta un módulo nuevo, es
       genérico en `N_CH` y el `generate` no distingue Rx de Tx. Regresión L1 nueva para esta
       instanciación: `sim/tb_sv/tb_l1_ddc_tri.sv` + `tcl/sim_l1_tri.tcl`, con gate de lint en
       `make check` (`lint-hdl-tb-tri`). **Corrida real contra xsim** (`-platform zedboard -mode
       fine`, tres casos distintos por canal para descartar cruce entre ramas del `generate`):
       elabora y corre limpio, sin `ERROR`/`CRITICAL WARNING` — el canal 0 (`tono_if`) da 303/315
       discrepancias de ±2-3 LSB en régimen permanente, la MISMA clase de residuo pequeño y ya
       aceptado que documenta [P-10](#p-10) para este caso concreto (no es un hallazgo nuevo). El
       testbench aborta en el primer canal con discrepancias — mismo diseño que ya tenía
       `tb_l1_ddc_quad.sv` — así que los canales 1 y 2 (`tono_desplazado`, `dos_tonos`) no llegaron
       a compararse en esta corrida; repetirla varía el orden de casos por canal si se quiere
       cubrirlos primero. **`-mode coarse` corrido, mismo día:** también limpio, sin
       `ERROR`/`CRITICAL WARNING`; canal 0 (`tono_if__coarse`) da 3/157 discrepancias (2 %), que
       coincide exacto con el número ya documentado más arriba en la matriz de P-10 con `K=655` —
       confirma que el top-level de 3 canales reproduce el comportamiento ya aceptado, no un caso
       nuevo. Cada corrida real tarda con este simulador: `fine` 71 min de reloj, `coarse` 69 min.
    2. Confirmar si la fuente de muestra de Tx tiene el mismo ancho/framing que un canal Rx o
       necesita su propia variante de `drx_ddc_top` — no verificado en esta sesión. **Resuelto,
       9-sep-2026 (decisión de equipo, vladimir):** mismo ancho/framing que un canal Rx —
       `drx_ddc_top` no distingue Tx de Rx, así que no hace falta variante propia.
    3. Actualizar el hito ZM1 en `docs/implementacion/fases.md` para reflejar las dos configs en vez
       de "los cuatro canales" (hecho, ver esa página).
    4. **Ampliación con `drx_range_gate` (Z1, 10/11-sep-2026):** `sim/tb_sv/tb_l1_ddc_range_tri.sv` +
       `tcl/sim_l1_range_tri.tcl` encadenan `drx_ddc_quad_top` (N_CH=3) con
       `drx_range_gate_quad_top` sobre los mismos tres casos del punto 1, y comparan también
       `m_last` (TLAST) por rayo, no solo la muestra decimada suelta — cierra la limitación citada
       arriba ("repetirla varía el orden de casos por canal si se quiere cubrirlos primero").
       Corrida real `-mode fine`: **TLAST coincide bit a bit en los tres canales (288/288/288
       muestras)** — confirma que el framing del rayo cae donde toca, alimentado por la IP real de
       Xilinx, no un generador sintético. El dato de `tono_if` en canal 0 (276/288 discrepancias,
       ~96 %) reproduce la misma proporción que ya documenta el punto 1 (303/315, ~96 %): confirma
       que `drx_range_gate` no toca el dato, solo lo reordena en el tiempo.
       Se probó también, antes de fijar el mapeo anterior, cambiar `tono_if` por `tono_desplazado`
       en el canal 0 para poder comparar dato hasta el final en un caso distinto: salió la MISMA
       clase de residuo (±1-3 LSB) pero mucho menos frecuente — **44/288 (~15 %)** — el primer dato
       real sobre un caso que nunca se había comparado hasta el final (el aborto del checker en el
       primer canal con discrepancias tapaba esto también). Esto sugiere que la severidad del
       residuo depende de la señal/frecuencia de cada caso, no es uniforme entre casos — no se
       investigó la causa, y no cambia que el residuo ya está aceptado como clase de error para
       `tono_if` en P-10.
       Hallazgo de infraestructura de prueba, no de diseño: el checker compartido aborta con
       `$fatal` en el primer canal con discrepancias de dato, y eso tapaba el resultado de TLAST
       aunque ya estuviera completo (el contador de TLAST corre en un `always_ff` continuo desde el
       reset, independiente del checker de dato). Se corrigió el ORDEN de las comprobaciones dentro
       de `tb_l1_ddc_range_tri.sv` (TLAST se reporta antes que el dato) para que este tipo de
       residuo aceptado deje de esconder para siempre si TLAST está bien o mal. No se tocó
       `tb_l1_ddc_tri.sv`, que sigue con la limitación original (documentada en el punto 1).
       Vectores dorados idénticos a los del punto 1, ya generados por `tools/gen_l1_vectors.py`,
       incluido un cuarto caso (`tono_desplazado_neg`) usado solo en el experimento de arriba y
       descartado del mapeo final. Cada corrida real de este testbench tarda ~75-80 min de reloj en
       esta máquina.
       **`-mode coarse` corrido, 11-sep-2026:** también limpio, sin `ERROR`/`CRITICAL WARNING`.
       **TLAST coincide bit a bit en los tres canales (144/144/144 muestras)** — la misma
       confirmación que en `fine`, ahora también en coarse. El checker aborta, como siempre, en el
       primer canal con discrepancias de dato: canal 0 (`tono_if__coarse`) da 3/144, que coincide
       exacto con el 3/157 ya documentado en el punto 1 para este mismo caso sin range gating —
       confirma otra vez, ahora en coarse, que `drx_range_gate` no toca el dato. Con esto quedan
       cerradas las dos combinaciones (fine/coarse) de esta ampliación; `tono_desplazado` y
       `dos_tonos` en coarse siguen sin comparar su dato hasta el final por el mismo aborto del
       checker en el primer canal — no es una limitación nueva de esta corrida.

!!! success "19-sep-2026: primer P&R real de `drx_ddc_quad_top` + `drx_range_gate_quad_top` dentro de `drx_top` — confirma la cifra fuera de contexto, y encuentra dos hallazgos de síntesis que xsim nunca vio"
    Hasta hoy, todo lo de arriba (incluida la tabla de DSP48 de esta entrada) salió de síntesis
    **fuera de contexto** (`synth_design -mode out_of_context` apuntando directo a
    `drx_ddc_top`/`drx_ddc_quad_top`) o de simulación funcional (xsim). Con `vector_source` escrito
    y `rtl/drx_top.sv` instanciando de verdad la cadena completa (ver
    [Fases, Z1](../implementacion/fases.md#z1) para el detalle), se corrió por primera vez el flujo
    real de `tcl/build.tcl` hasta `-step impl` (P&R completo, no fuera de contexto).

    **DSP48 real, post-route: 153/220 (69,6 %)** — coincide exacto con la fila "1 canal... — medido"
    de la tabla de arriba multiplicada por 3 canales, confirma que la extrapolación fuera de
    contexto no mentía. LUT 7,6 %, BRAM Tile ~21 % (a 62,5 MHz, después de bajar el reloj — ver
    abajo). Es la cifra real de Config B (Tx + nominal + atenuado) tal como está hoy — Config A no
    se ha medido por separado, `N_CH=3` no distingue cuál de las dos.

    **Dos hallazgos que el flujo out-of-context/xsim nunca hubiera mostrado**, los dos en
    `drx_range_gate.sv` (RTL ya verificado bit a bit contra xsim, no código nuevo): sus arrays
    `mem0`/`mem1` no sintetizaban a Block RAM (primero por vivir en un proceso con reset asíncrono
    en su sensibilidad, después porque el patrón de lectura con dos condiciones anidadas seguía sin
    reconocerse como BRAM aunque se forzara `ram_style="block"` — Vivado lo marcaba "Infeasible").
    Corregido separando cada banco en procesos de lectura/escritura propios, sin ninguna sentencia
    compartida entre `mem0` y `mem1`; reverificado contra xsim real (fine y coarse) antes de seguir,
    mismo resultado bit a bit / D-12 que antes de tocar nada. Detalle completo en
    [Fases, Z1](../implementacion/fases.md#z1).

    **Con el datapath real ya sintetizando de verdad, el primer P&R completo a 100 MHz no cerró**
    (WNS = −1,209 ns) — la contingencia de `docs/plataforma/dilatacion-temporal.md` (bajar a 62,5
    MHz) resultó necesaria, no solo teórica. Aplicada, misma sesión: `fs_hz` de zedboard baja a
    62,5 MHz en `config/params.toml`, WNS pasa a +2,770 ns. No cambia nada de lo que esta entrada
    documenta sobre presupuesto de DSP48/BRAM — la dilatación temporal (D-02) no toca área, solo
    velocidad de reloj.

## Supuestos de entorno a verificar

Estos son supuestos del plan de ZedBoard. Todo número marcado como *estimación* en este sitio es una
inferencia a partir de hojas de datos y **debe verificarse en banco** antes de comprometerse a él.

| # | Supuesto | Cómo verificarlo |
|---|---|---|
| A1 | ZedBoard rev. D o posterior, XC7Z020-CLG484-**1**, 512 MB DDR3 | Serigrafía de la placa |
| A2 | Vivado/Vitis con licencia para DDS/CIC/FIR Compiler y AXI DMA | `report_ip_status` sobre un proyecto de prueba |
| A3 | El proyecto DSP aún no ha congelado el contrato DRx↔DSP | Preguntar al equipo DSP |
| A4 | El RTL custom se puede escribir en SystemVerilog, sin mandato VHDL | Decisión de equipo — ver [D-05](decisiones.md#d-05) |
| A5 | La placa/MCU auxiliar para SSI tiene al menos un periférico SPI esclavo o PIO a ≥2 MHz | Hoja de datos del MCU |
| A6 | Hay acceso a un osciloscopio de ≥100 MHz para medir jitter de trigger | Inventario de laboratorio |
| A7 | Existe un runner de CI con Vivado y licencia para el job `gateware` | **Cerrado el 21-sep-2026**: la máquina de desarrollo se registró como runner self-hosted (`lamula-drx-dev-vivado`, label `vivado`), instalado como servicio systemd, `HAS_VIVADO_RUNNER=true`. Confirmado corriendo el job `gateware` de verdad, no a mano: `substrato` y síntesis+bitstream de `zedboard` cierran verdes (WNS = 2,489 ns). El bloqueo de `gh auth login` era de credenciales (necesitaba `--web`/PAT), no arquitectónico — el token de registro se generó desde la web de GitHub, sin depender de `gh` autenticado en esta máquina. La red tenía además un Pi-hole bloqueando por DNS varios subdominios de `actions.githubusercontent.com` necesarios para que el runner reciba jobs; blanqueados. Detalle completo en `fases.md#z1`, entrada del 21-sep (más tarde) |
| A8 | La versión de Vivado está pinada en el runner | El runner (única máquina, la de desarrollo) corre Vivado ML Standard **2022.2** de facto, pero nada en CI lo verifica ni lo pinea explícitamente — sigue siendo trabajo aparte si se quiere un gate duro |
| A11 | El Vivado 2022.2 del runner tiene el device pack de Zynq UltraScale+ instalado (para el part `xczu9eg-ffvb1156-2-e` de la ZU9) | **No lo tiene** (hallazgo del 21-sep-2026): `get_parts xczu9eg*` y `get_parts -filter {ARCHITECTURE == zynquplus}` devuelven cero. El leg `zu9` de la matriz de CI nunca se había corrido antes — ni en CI ni a mano — así que este hueco no se había detectado. Se sacó `zu9` de `.github/workflows/ci.yml` hasta que se instale el device pack (descarga grande vía instalador de Xilinx); `config/params.toml` no tiene ningún error, el part configurado es correcto |
| A9 | El sistema opera con una referencia de reloj externa disciplinada por GPS, **10 MHz + 1PPS**, local a un único radar — no compartida entre sitios de la red LAMULA (confirmado en sesión, 7-sep-2026). Es, con altísima probabilidad, la "referencia de 10 MHz de la casa" que asume [ADR-001](adr-001-fs-r1-r2.md) | Falta la ficha técnica del GPSDO (formato de señal de las dos salidas, conector, redundancia) y confirmar si la portadora ZU9/FMC213 candidata tiene entrada dedicada para 10 MHz y para 1PPS. Relevante para [P-03](#p-03) (árbol de clocking/SYSREF) y para el diseño de metadatos de Z4 (¿el 1PPS entra al marcado temporal del rayo, o solo disciplina el reloj de muestreo?) |
| A10 | El frontal analógico tiene 5 conversores: 2 por polarización (H, V) más 1 para la muestra del transmisor (confirmado en sesión, 8-sep-2026 — ver hallazgo arriba). `n_rx_ch=4`/`n_tx_burst_ch=1` y el contrato v0.4 ya reflejan esta cuenta | Falta confirmar con quien conoce el frontal qué distingue a los dos conversores de una misma polarización entre sí, para poder nombrar `rx_0`..`rx_3` con algo más específico que "Canal Rx IF N" en el contrato y en `docs/plataforma/fuente-de-muestras.md`; y avisar al proyecto DSP del bump de contrato (D-08) |

## Presupuesto de 1GbE: confirmado, con una salvedad

Con R = 208, 4 canales Rx e I/Q de 16+16 bits:

```
tasa por canal  = 250e6 / 208 = 1,2019 MSPS complejas
bytes por canal = 1,2019e6 × 4 B = 4,81 MB/s
4 canales       = 19,23 MB/s = 153,8 Mbps
+ overhead Ethernet (MTU 1500, ~2,8 %) ≈ 158 Mbps
```

Encaja con holgura 6× en 1GbE y coincide con el «~20 MB/s» del plan original, que **puede afirmarse
con confianza**. La salvedad: ese número asume ciclo de trabajo del ~100 % en el gating, que es
exactamente el peor caso cuando la PRF se lleva al límite del rango
([D-09](decisiones.md#d-09)). Así que 19,23 MB/s
es el **techo**, no un promedio.

## Riesgos propios de la estrategia ZedBoard

| Riesgo | L | I | Mitigación |
|---|---|---|---|
| El riesgo #1 (JESD) queda sin retirar por tiempo indefinido | **Alta** | **Alta** | Decisión de compra ([P-03](#p-03)). No hay mitigación técnica |
| Deuda de portabilidad por relajar la disciplina de `FS_HZ`/SSA | Media | Alta | Revisión de portabilidad obligatoria en cada PR; registro delta vivo; el CI falla si aparece una constante de reloj hardcodeada |
| El contrato DRx↔DSP no se congela porque el proyecto DSP va a otro ritmo | Media | Alta | Congelar v0.1 unilateralmente y versionar; negociar sobre algo concreto |
| El 7Z020-1 no cierra a 100 MHz con 4 canales | Media | Baja | Bajar a 62,5 MHz o a 2 canales; numéricamente idéntico |
| Ancho de banda de DDR insuficiente para reproducir 4 canales | Media | Baja | Los modos BRAM-loop y Throttled ya lo cubren |
| El equipo confunde «validado en ZedBoard» con «validado» | Media | Alta | El registro delta se lee en cada demo de sprint; ningún hito se declara sin él |

## Integración extremo a extremo con DSP y RCP reales

### P-13 · Ningún plan conecta la ZedBoard real con DSP y RCP reales { #p-13 }

**Estado:** abierto, **fase C0 cerrada el 28-sep-2026** · identificado 2026-09-17 · **Dueño:** los
tres equipos (DRx + DSP + RCP), no tiene dueño único hoy · **Bloquea:** poder ejercitar con
`vector_source` (datos generados en el PL, sin ADC ni JESD204B — ver [P-03](#p-03), que este
pendiente no sustituye ni mitiga) todo lo que la ZedBoard sí permite probar, contra los otros dos
proyectos reales en vez de contra un stub.

!!! success "28-sep-2026: C0 — el DSP real y el RCP real ya hablan entre sí"
    El plan de fases de más abajo gana una fase C0 **antes** de la B, porque la mitad de la
    integración no necesita esta placa y estaba bloqueando a la otra mitad sin motivo: los binarios
    reales del DSP y del RCP nunca se habían conectado entre sí. Ahora sí, con un emisor sintético
    en lugar de la ZedBoard (`drx_faker`, un ejemplo del repo del DSP que habla el contrato
    `DRx↔DSP` por TCP de verdad). Banco: `tools/hil/run-c0.sh` del repo `lamula-rcp`, documentado en
    su [página de banco C0](https://lamula-rcp-docs.pages.dev/implementacion/banco-c0/).

    **A este proyecto no le tocó nada** — C0 no toca el contrato `drx_dsp`, ni el RTL, ni el
    firmware. Pero sí importa lo que encontró, porque son fallos que estaban esperando a la Fase B
    y que habrían aparecido con la placa delante, que es el peor momento para depurarlos:

    - **Los dos extremos del enlace `DSP↔RCP` escuchaban.** Nadie conectaba: ese enlace nunca se
      había levantado entre los binarios reales. Se fijó la regla **"el productor conecta"** para
      los dos enlaces de la cadena, así que **el firmware de Z4.2 de este proyecto tiene que
      conectar al DSP, no escuchar**. El DSP ya escucha en `LAMULA_DSP_DRX_ADDR` y no cambia.
    - **Todos los radiales salían con ancho de azimut cero.** El DSP se quedaba con el azimut del
      primer pulso del radial y publicaba `az_end_deg = az_start_deg`. Corregido allí. Lo que le
      toca a este proyecto: cuando Z3 ponga az/el reales en cada rayo, **el azimut tiene que
      avanzar dentro del radial** — es lo que el consumidor usa para reconstruir el sector, y un
      radial de ancho cero no es archivable como Level-II ni aceptable para ORPG.

    Lo que C0 **no** prueba, y sigue igual: nada de hardware. Ni cadencia, ni jitter, ni
    contrapresión reales. Eso es la Fase B, y sigue esperando al firmware de Z4.

Revisión de integración cruzada (2026-09-17) encontró que **cada proyecto para su cadena de
pruebas en su propia frontera**, y ninguno de los tres planes la cruza:

- **Z4 de este proyecto** (`docs/implementacion/fases.md#z4`) fija el hito ZM4 como «rayos
  completos consumidos por **un stub de DSP** sobre 1GbE» — no el binario real del proyecto DSP.
- El plan del **DSP** (`dsp-plan.md` §8.2, Fase 1) valida su M1 contra su propio **simulador
  sintético de I/Q**, no contra tráfico real de un DRx corriendo en hardware.
- El **RCP** (`lamula-rcp/docs/alcance/pendientes.md`, PEND-RCP-05 y PEND-RCP-13) solo ha ejercido
  `adapters/dsp/moment_stream_receiver.py` contra un stub propio y contra `radar_emulator` — ninguno
  de los dos tiene relación con este proyecto.
- Los tres planes maestros (`rcp-plan.md`, `dsp-plan.md` de LAMULA DSP) fijan el criterio de éxito
  de mes 8 como «validado extremo a extremo **contra simuladores propios**»; el hardware real queda
  explícitamente para «field commissioning», **después** del mes 8, sin fecha ni plan operativo —
  solo la promesa de un documento de plan (`FPGA-commissioning dry-run plan`, M4 de ambos planes).

**Lo que sí se puede probar hoy, sin esperar a la ZU9 ni al frontal analógico real:** todo lo que
está aguas abajo de la SSA (`docs/plataforma/fuente-de-muestras.md`) es indiferente a si la fuente
es `vector_source` o `jesd204b_source`. Eso incluye, con vectores conocidos inyectados desde el
PL: la cadena DDC completa, el range gating en los dos tamaños de celda, el motor de timing/PRF/
triggers, el etiquetado az/el por los lectores SSI, el ensamblado de rayos en FreeRTOS, el AXI DMA,
el framing DRx↔DSP real sobre 1GbE físico (no un stub), la ingesta y los algoritmos del DSP real
alimentados por la cadencia y el jitter de hardware de verdad (no sintéticos), el tráfico real
DSP↔RCP, y el control/archivo/MMI del RCP real. **Lo que no se puede probar así, y sigue siendo
[P-03](#p-03):** JESD204B, clocking/SYSREF, 250 MSPS, el frontal analógico y el DAC AD9129.

**Condición de cierre:** un hito conjunto, acordado por los tres equipos, que sustituya el «stub de
DSP» del ZM4 de este proyecto por el binario real del DSP, y que ese DSP real alimente al RCP real
(no a su stub ni a `radar_emulator`) — banco de pruebas de hardware-in-the-loop con datos 100%
generados en el PL. Hoy no existe ni la fecha ni el documento que decida en qué semana de cuál de
los tres calendarios (28 de este proyecto, 34 de DSP, 34 de RCP) entra ese hito. Ver también la nota
correspondiente en `lamula-dsp/docs/algorithms/roadmap.md` (sección "Abierto (cross-proyecto):
banco de pruebas extremo a extremo contra ZedBoard real") y PEND-RCP-13/PEND-RCP-14 en
`lamula-rcp/docs/alcance/pendientes.md`.

**Plan por fases (2026-09-17), para dar contenido concreto a la condición de cierre de arriba.**
Ninguna fase depende del frontal analógico; todas caen dentro del límite de [P-03](#p-03). Ninguna
está agendada en ningún calendario todavía — esto es la propuesta, no un compromiso de fecha.

- **Fase A — cadena DRx sola, en hardware real.** Z1→Z2→Z3 tal como ya están planeados (P-10/11/12
  en marcha). Sin diseño nuevo.
- **Fase C0 — DSP real contra RCP real, fuente sintética (sin hardware). HECHA, 28-sep-2026.**
  No estaba en el plan original del 17-sep; se intercaló al ver que no dependía de esta placa. Ver
  la entrada de arriba.
- **Fase B — DSP real contra tráfico real de esta placa, selección de vector local/manual.**
  Completar Z4 apuntado al binario real de DSP (no al stub); `crates/ingest` de ese proyecto
  validado contra cadencia/jitter/contrapresión reales en vez de su simulador sintético. Selección
  de qué vector reproduce `vector_source`: recarga de DDR/SD + rearranque, o registro AXI-Lite por
  JTAG — sin RCP ni contrato nuevo todavía.
- **Fase C (ahora C1) — RCP real contra ese DSP real, alimentado por esta placa.** Con C0 hecha,
  lo que queda de esta fase es exactamente sustituir el emisor sintético por la ZedBoard.
  Literalmente: apuntar el DSP a la placa en vez de al `drx_faker`. `adapters/dsp/wire.py`/`moment_stream_receiver.py` del
  RCP contra el DSP real (cierra el resto de PEND-RCP-05); Level-II y feed RDA/ORPG del RCP
  ejercitados con radiales de cadencia/jitter reales, no sintéticos (estresa PEND-RCP-12). Ver
  PEND-RCP-14 del RCP: el `status`/`bite_event` de este contrato no llega hoy a ningún sitio del
  lado RCP.
- **Fase D — selección de señal de prueba desde el RCP, como función BITE permanente del
  operador.** Decisión del usuario (2026-09-17): esto **no** es una herramienta de desarrollo
  desechable, es una capacidad de auto-prueba del operador, útil también en comisionamiento de
  campo con hardware real. Diseño propuesto, **pendiente de ADR propio antes de tocar el
  schema** (mismo criterio que D-08 para el contrato v0.1 — esto es un cambio de formato, sube
  `version_minor`):
    - **DRx** (dueño del contrato): mensaje nuevo `down`, p. ej. `test_stimulus_select` —
      `vector_id` (u16, catálogo en SD/DDR) y `repeat` (bool). Reutiliza el catálogo de
      degradaciones que **ya existe** en `tools/gen_l1_vectors.py::_cases()` (ruido, offset DC,
      desbalance I/Q, saturación) en vez de inventar uno nuevo.
    - **DSP**: relay puro del `command` de su mensaje `control` (`dsp_rcp`, ya tiene el campo
      extensible) hacia este mensaje nuevo — no toca el pipeline de moments.
    - **RCP**: panel nuevo en la MMI (BITE self-test / inyector de señal), arma el catálogo y
      dispara.
    - Esto convierte el catálogo de vectores de `gen_l1_vectors.py` en producto, no solo en
      fixture de test — al escribir el ADR, revisar si eso cambia algo de su mantenimiento.
- **Fase E — red y resistencia con hardware real.** Throughput real sobre el PHY 1GbE contra la
  estimación de `## Presupuesto de 1GbE` de este documento (hoy es papel); soak/endurance bajo
  jitter real, no simulado.
- **Fase F (stretch, no bloqueante) — sincronizar los dos dobles de la antena.** `radar_emulator`
  (Modbus, lo que mueve/lee el RCP) y el emulador SSI en fabric de esta placa (lo que tagea az/el
  este proyecto) son dos simuladores independientes de la misma antena física, sin verdad
  compartida. Un HIL completo con "el RCP mueve, el DRx tagea correcto" pide un puente entre los
  dos. No bloquea A-E: la cadena de señal se valida con az/el fijos en el emulador SSI.

### P-14 · Varianza de los estimadores de momento bajo el residuo aceptado (Doviak & Zrnic cap. 6) { #p-14 }

**Estado:** abierto, identificado 2026-09-19 · **Dueño:** especialistas de dominio · **Bloquea:**
nada hoy — es deuda de validación sobre una decisión ya tomada ([D-12](decisiones.md#d-12)), no una
condición de cierre de Z1.

[D-12](decisiones.md#d-12) acepta el residuo de cuantización del NCO (hasta ±5 LSB por muestra,
medido contra xsim real en [P-11](#p-11)) como techo del bloque, en vez de exigirle bit a bit. Esa
aceptación se apoya en que el residuo "es la misma clase y magnitud" que el proyecto ya acepta desde
[P-10](#p-10) — un argumento de semejanza con un caso previo, no una evaluación de su efecto sobre
los productos finales del radar.

Queda sin construir el análisis que sí respondería eso: caracterizar la varianza de los estimadores
de momento (reflectividad, velocidad Doppler, ancho espectral) que resulta de inyectar este residuo
en la cadena, contra el marco teórico de Doviak & Zrnic, *Doppler Radar and Weather Observations*,
cap. 6 (estadística del retorno del radar meteorológico — varianza de estimadores en función de
SNR, número de pulsos integrados M y ancho espectral). Sin ese análisis, "la misma clase de residuo
que ya se acepta" es la mejor evidencia disponible hoy, pero es indirecta: no dice si ±5 LSB de
residuo mueve la varianza de un estimador de velocidad o de reflectividad de forma perceptible para
el M real del proyecto.

**Nota de honestidad:** esta entrada describe qué falta responder, no la respuesta — no hay acceso
al texto de Doviak & Zrnic en este repo ni en esta sesión. Cualquier resumen de lo que dice
específicamente el capítulo 6 debe venir de quien tenga el libro a mano, no inferirse aquí.

**Condición de cierre:** un especialista de dominio, con el capítulo 6 (o equivalente) a mano,
construye el modelo de varianza del estimador para los M/SNR relevantes del proyecto y lo compara
contra el residuo ya medido en [P-11](#p-11). Si la varianza inducida es despreciable frente a la
varianza propia del estimador (la que ya existe sin ningún residuo de cuantización, solo por M
finito), P-14 cierra sin tocar nada más. Si no lo es, reabre la pregunta de
[D-12](decisiones.md#d-12) y de si Taylor —o dithering, la vía que [P-11](#p-11) dejó sin explorar
del todo (falta el modelo de integración de M pulsos sobre el ruido de fase, ver esa entrada,
9-sep-2026)— sigue siendo la elección correcta.

### P-15 · El mensaje `config` del contrato solo tiene 1 PRF/ancho de pulso, no 2 lotes { #p-15 }

**Estado:** CERRADO 1-oct-2026 (Z4.4) · **Dueño:** cerrado · **Bloquea:** nada.

**Actualización 22-sep-2026:** el mapa de registros AXI-Lite de Z2 (v3 de
`config/registers.toml`, ver [`registros.md#z2-en-v3`](../implementacion/registros.md#z2-en-v3))
ya existe — TIMING_CTRL/TIMING_STATUS/PRF_DIV_*/PULSE_WIDTH/N_PULSES/TRIG_DELAY_*/TRIG_WIDTH_*,
alimentando `drx_timing_engine` ya instanciado en `drx_top.sv`. Eso era la mitad de la condición de
cierre de abajo. La otra mitad — el contrato — sigue intacta, a propósito: D-08 exige discutir
cualquier cambio y subir `version_minor` con tests actualizados, y ya existía consenso de que ese
lado es alcance de Z4, no de la sesión que diseñó el registro. No se tocó `contract/schema/
drx_dsp_v0_1.toml` sin esa discusión.

[D-13](decisiones.md#d-13) fija que el motor de timing de Z2 secuencia **2 lotes** de PRF/ancho de
pulso por radial (Batch mode de NEXRAD). El modelo dorado (`model/drx_model/timing.py`) ya modela
eso: `Batch` + `RadialBatches(low, high)`, con el validador de [D-09](decisiones.md#d-09) aplicado a
cada lote por separado.

Pero `contract/schema/drx_dsp_v0_1.toml` (congelado en Z0 por [D-08](decisiones.md#d-08)) sigue
declarando un único par en el mensaje `config`: un solo `prf_div` (`u32`) y un solo
`pulse_width_idx` (`u8`). Eso modela el par global que el "Trabajo" original de Z2 daba por hecho
— exactamente el supuesto que D-13 acaba de descartar. Con el esquema de hoy no hay dónde meter el
segundo lote: ni el DSP puede pedir una configuración de 2 lotes, ni el DRx puede reportar cuál de
los dos produjo un rayo dado.

No se toca ahora porque es alcance de Z4: el contrato es la única interfaz externa, y D-08 dice que
cambiarlo sube `version_minor` y exige actualizar los tests — una decisión para discutir, no para
tomar de paso al escribir el registro que la motiva. (Hasta el 22-sep-2026 tampoco existía todavía
el registro real que le habría dado la forma concreta; ya existe, ver la actualización de arriba.)

**Condición de cierre:** `config` gana los campos para 2 lotes (como mínimo:
`prf_div`/`pulse_width_idx`/`n_pulses` por lote, ya con la forma concreta que fija
`config/registers.toml` v3 — ver la actualización de arriba — y el metadato por rayo de
[Z4](../implementacion/fases.md#z4) gana qué lote produjo ese rayo) y sube `version_minor`. Hasta
entonces, cualquier prueba de aceptación de D-09/D-13 contra el contrato real (no contra el modelo
dorado) queda bloqueada por este hueco.

**Cierre 1-oct-2026, contrato v0.6 (Z4.4).** Las dos mitades de la condición de cierre, hechas:

- `config` pasa a declarar los dos lotes, con la forma concreta que ya tenía `config/registers.toml`
  v3 y la estructura `DrxTimingConfig` del firmware: `prf_div_low`/`prf_div_high`,
  `pulse_width_idx_low`/`pulse_width_idx_high`, `n_pulses_low`/`n_pulses_high` y
  `range_bins_low`/`range_bins_high` (D-15). El mensaje crece de 48 a 60 B. Se rompe el mensaje
  anterior en vez de añadir uno nuevo al lado: `config` está definido como atómico, y mantener una
  variante de un solo lote modelaría un modo de operación que D-13 descartó.
- El metadato por rayo gana qué lote lo produjo: bandera `batch_high` (valor 32) en el enum
  `ray_flag`. Es bandera y no campo porque `prf_div`, `bins` y `pulse_width_idx` de la cabecera de
  `ray` ya llevan los valores vigentes de ese rayo; el bit sólo dice de cuál de los dos lotes
  salieron, que es lo que hace falta para agrupar rayos por lote sin reconstruir el radial.

`version_minor` sube de 5 a 6 y los tests se actualizaron, como exige [D-08](decisiones.md#d-08).
El test que faltaba poder escribir —una configuración de 2 lotes que atraviesa el cable entera y
llega a la acción con los dos lotes distinguidos— es
`test_los_dos_lotes_de_prf_llegan_enteros_a_la_accion` en `fw/tests/test_control.py`.

Este cambio se hizo **sin esperar a una revisión conjunta con el equipo DSP**, bajo la autorización
explícita que vladimir dio el 26-sep-2026 para el contrato durante Z4 («trabajá con libertad
respecto al contrato, luego actualizamos a DSP»), mismo patrón que el puente PS7 del 20-sep. Queda
como aviso pendiente de dar: cualquier implementación que el equipo DSP hubiera empezado contra
v0.5 tiene que migrar.

### P-16 · El modo Throttled(DDR) no puede coexistir con el motor de timing { #p-16 }

**Estado:** ABIERTO. El 3-oct-2026 se resolvió una de sus tres causas y la medida en placa
destapó las otras dos · **Dueño:** Z4.6 · **Bloquea:** el barrido del catálogo de estímulos
contra rayos reales. Nunca bloqueó Z4.4. Leer hasta el final: el alcance de este hallazgo es
mayor de lo que decía su primera redacción.

`rtl/vector_source.sv` en Throttled(DDR) llena un conjunto de N_CH muestras tomando una por beat de
un AXI4-Stream de 16 bits y lo presenta durante un ciclo, así que el `s_valid` que ve
`drx_ddc_top` está alto como mucho 1 de cada N_CH+1 ciclos. Toda la cadena del DDC avanza solo con
`valid`, de modo que con N_CH = 3 una muestra decimada sale cada ≈4·R₁ ciclos en vez de cada R₁.

`drx_range_gate` corta donde se lo dice `ray_start`, que llega cada `prf_div` **ciclos de reloj**
(D-14). Un rayo de `bins_for_pri(prf_div)` bins necesita por tanto unas cuatro veces el PRI para
llenarse, `ray_start` lo trunca antes, `GATE_TRUNCATED` sube y no se completa ningún rayo. No es un
fallo de ninguna de las dos piezas: cada una hace lo que su cabecera dice. Es que la combinación no
está contemplada.

El modo sigue siendo útil para lo que Z4.3 lo usó —probar que el camino DDR → MM2S → PL entrega
bytes, y ejercitar el plano de control del contrato— y el nombre ya avisaba («Throttled», tasa por
debajo de tiempo real, ver [fuente de muestras](../plataforma/fuente-de-muestras.md)). Lo que no se
había dicho en ningún sitio es que eso impide producir rayos con el motor de timing en marcha, que
es la combinación que hace falta para barrer los ocho vectores del catálogo contra rayos reales.

**Condición de cierre (escrita el 1-oct, superada el 3-oct).** Se planteaban dos salidas: que el
DMA entregue N_CH muestras por ciclo —un stream de N_CH·16 bits en vez de 16, cambiando
`tcl/gen_zynq_bd.tcl`, el camino DDR de `vector_source.sv` y el entrelazado de
`fw/src/app/drx_stimulus.c`, las tres a la vez o el reparto por canal se desplaza sin error
visible— o aceptar que el catálogo elegible en caliente solo sirve sin el motor de timing. La
primera tiene además un pero que no estaba anotado: `N_CH × 16 = 48` bits no es potencia de dos y
el AXI DMA de Xilinx solo acepta potencias de dos, así que serían 64 bits con un carril muerto.

**3-oct-2026: cerrado por una tercera vía que ninguna de las dos contemplaba — sincronizar el
motor con el avance de muestras.** El problema no es que el DMA vaya lento; es que las dos mitades
miden el tiempo con reglas distintas. Si `drx_prf_batch_seq` cuenta AVANCES DE MUESTRA en vez de
ciclos de reloj, las dos se frenan con el mismo factor y el rayo se llena con los mismos
`prf_div / R₁` bins a cualquier tasa. En tiempo real `valid` está siempre alto, así que un avance
es un ciclo y el motor es el de v3..v9 -- no por argumento, por construcción: con `advance`
constante a 1 la síntesis colapsa el enable.

Piezas, con el criterio de tocar lo mínimo del diseño principal:

- `rtl/drx_sample_pacer.sv` (**nuevo**): define qué cuenta como un avance -- `valid && ready` en
  TODOS los canales a la vez, no en uno suelto. Esa definición es la decisión entera, y por eso
  tiene módulo y L0 propios en vez de ser tres `assign` dentro de `drx_top`.
- Un puerto `advance` en `drx_prf_batch_seq.sv` y `drx_trigger_one_shot.sv`, paso a través en
  `drx_trigger_gen.sv` y `drx_timing_engine.sv`. Es la única intrusión en el motor, y no se puede
  evitar: el `enable` que ya existe NO sirve de paso porque borra `width_cnt`, así que gatearlo
  con el tick dejaría `tx_gate` en pulsos de un ciclo.
- Mapa de registros **v10**: `TIMING_CTRL` bit 1, `timing_paced`, reset 0. Detrás de un bit y no
  siempre activo a propósito: en BRAM-loop `advance` es `ready`, y si el DDC aplicara
  contrapresión alguna vez eso movería las cifras de Z4.4, que están cerradas y medidas.

**Un detalle que casi se escapa y habría sido un fallo silencioso:** `pulse_trig` es combinacional
sobre `pri_cnt == '0'`. Gateando solo los `always_ff`, `pri_cnt` se queda en 0 durante todos los
ciclos sin avance y `pulse_trig` sale ANCHO -- y lo consumen `ray_start` (D-14) y `TRIG_COUNT`,
que contarían varias veces el mismo pulso de PRF. El `advance` entra también en ese `assign`.

**Verificación.** `sim/tb/tb_drx_timing_paced.py` compara la traza paceada, muestreada solo en los
ciclos de avance, contra la del mismo motor sin pacear: dos radiales completos, 1804 avances,
`(pulse_trig, batch_sel, tx_gate)` muestra a muestra. El oráculo aquí no es el modelo dorado sino
el motor viejo, porque lo que falta por probar no es la corrección del secuenciador —ya la cubre
`tb_drx_prf_batch_seq.py`— sino la EQUIVALENCIA de las dos bases de tiempo. Los dos tests se
comprobaron contra RTL mutado: quitar `advance` del `assign` da «10 pulsos con el motor parado»,
quitarlo de los `always_ff` hace que la traza diverja en el avance 134.

**Lo que esto NO cierra.** Throttled(DDR) sigue sin ser una fuente de tiempo real, y el nombre ya
lo decía. Cierra el barrido del catálogo contra rayos reales. No valida nada dependiente de la
tasa -- rayos/s, caudal del transporte, temporización del anillo del DMA --; eso se sigue midiendo
en BRAM-loop. Y el validador D-09 comprueba PRF × rango en ciclos: con el motor paceado el PRF
real se estira, así que el check queda **conservador** (nunca rechaza de más) pero deja de hablar
del PRF real. Una configuración paceada no es una configuración de tiempo real validada.

**P&R:** cierra en **WNS = 2,394 ns, WHS = 0,013 ns**, mejor que los 2,304 ns de Z4.5 — el pacer
no añade camino combinacional a la ruta crítica, solo clock-enables sobre registros que ya
existían.

**La medida en placa, el mismo día: el pacing del motor era necesario pero NO suficiente.**
Con el bitstream paceado cargado, `tools/sweep_catalogo.py` contra los ocho vectores. Lo que
salió bien, que no es poco:

- `GATE_TRUNCATED = 0x0` con el motor corriendo y `CTRL = 0x2` (DDR). Esa era la firma de P-16 y
  ya no está: los rayos se completan, `bins=3689` enteros, `flags` sin `TRUNCATED`.
- La autoprueba de arranque corre `tono_if` y `tono_sobre_escala` por DDR **con el motor de
  timing en marcha**, dos pasadas cada uno, `errores=0`. Eso era imposible por definición antes.
- Y el camino de tiempo real no se mueve: en BRAM-loop, con `timing_paced = 0`, el rayo sigue
  dando −9,03 dBFS contra −9,03 dBFS del modelo. La equivalencia «con `advance` a 1 esto es v9»
  queda comprobada en silicio y no solo por construcción.

**Lo que salió mal, y es el fondo del asunto: hay una TERCERA base de tiempo y no la miré.**

```
rtl/drx_ddc_mixer.sv:99   assign nco_ready = 1'b1;      // "el DDS corre libre"
tcl/gen_ip.tcl:238        CONFIG.Has_ACLKEN {false}
```

El DDS Compiler avanza un paso de fase por **ciclo de reloj**. No tiene `TREADY`
(`Has_TREADY {false}`, decisión razonada de Z1) y no tiene clock enable, así que nada lo ata al
ritmo de las muestras. Con la fuente entregando 1 de cada ~4 ciclos, entre dos muestras
consecutivas la fase ha avanzado 4 pasos: el DDC mezcla a ~4× el IF, el tono cae fuera de la
banda de paso del diezmado y la salida se va al suelo de ruido. Medido: **−87,3 dBFS** contra los
−9,02 dBFS del modelo, con el pico en un bin arbitrario. Los tres vectores que llegaron a
medirse dieron lo mismo.

El análisis que justificó el pacer —«las dos mitades se frenan con el mismo factor»— era correcto
para el motor de timing y el range-gate, y **estaba incompleto**: el NCO es una tercera mitad.
El pacer arregla la LONGITUD del rayo; el DATO necesita que el NCO cuente muestras también.

**Camino de arreglo, con su coste.** El XCI ya expone el parámetro
(`ip/dds_compiler_nco/dds_compiler_nco.xci`, hoy `"ACLKEN": "false"`): regenerar la IP con
`Has_ACLKEN {true}` y cablear `aclken = advance`, el mismo `advance` del pacer. Es simétrico con
el resto y con `advance` a 1 no cambia nada. Dos cosas que hay que resolver con él:

1. `aclken` congela el core ENTERO, incluido el canal `S_AXIS_CONFIG` por el que entra la palabra
   de AFC (v9). Una escritura que caiga en un ciclo sin avance se perdería. `drx_ddc_top` ya
   tiene el mecanismo: difiere la escritura mientras el core está en reset; hay que extenderlo a
   «mientras no haya avance».
2. El gate real del cambio es la **matriz de 16 corridas de D-12 contra xsim**, igual que cuando
   la IP se regeneró con `Phase_Increment {Programmable}` en Z4.5. Son 2-3 h con tres en
   paralelo, y no se puede saltar: cambiar la personalización de la IP es exactamente el caso que
   esa matriz vigila.

**Y una segunda causa, independiente, que el barrido también destapó:** ver
[P-21](#p-21).

Mientras tanto, la medida de rayos de Z4.4 corre en BRAM-loop, cuyo contenido
(`tools/gen_vector_source_init.py`) es exactamente el caso `tono_if` del catálogo —comprobado array
a array—, así que la comparación contra el modelo dorado sigue siendo posible.

### P-17 · Sin presupuesto de latencia para la ISR del S2MM { #p-17 }

**Estado:** abierto, encontrado 2-oct-2026 (bring-up de Z4.5) · **Dueño:** Z5 · **Bloquea:** nada
hoy en ZedBoard. Sí el dimensionado de la ZU9 y la campaña de soak.

Nadie ha medido **cuánto tiempo puede estar el Cortex-A9 sin atender la interrupción de fin de
descriptor del S2MM antes de perder un rayo**. El anillo de `fw/src/app/drx_ray.c` tiene
`DRX_RAY_BUFFERS` buffers; mientras la ISR no corra, nadie los devuelve al DMA, y cuando se agotan
el range-gate desborda (`STATUS (overrun)`). Ese número —el margen en milisegundos— no está escrito
en ningún sitio ni se deriva de ningún parámetro: hoy es un efecto lateral de cuántos buffers se
reservaron.

El hallazgo salió por accidente y con el instrumento equivocado. Durante el bring-up de Z4.5,
`xsct` detiene el A9 en cada `mrd`, y una ráfaga de 300 lecturas lo dejó parado ~7 s: el anillo se
secó y aparecieron `STATUS (overrun) = 0x7` donde 600 s de marcha ociosa no daban ninguno (detalle
en [fases.md](../implementacion/fases.md#z4), entrada del 2-oct noche). **Eso en sí no es un riesgo
de producción** —no habrá un depurador leyendo DDR en la ZU9— pero demuestra que el margen existe,
que es finito y que nadie sabe cuánto vale.

Por qué importa más en la ZU9 que aquí, y esto es inferencia, no medida: con dos FMC213 el caudal
hacia DDR es mucho mayor, así que el mismo número de buffers cubre menos tiempo. Y el candidato
realista a robar ese tiempo no es un depurador sino el propio sistema — una sección crítica larga,
una tarea de prioridad alta, el transporte de Z4.6 copiando un rayo entero, o la pila de red con
las interrupciones deshabilitadas.

**Condición de cierre:** un número medido, no estimado — cuántos milisegundos de ISR bloqueada
aguanta el anillo a PRF nominal, obtenido deshabilitando interrupciones a propósito durante un
intervalo creciente hasta ver el primer `overrun`, y comparado con el que predice
`DRX_RAY_BUFFERS × PRI`. Con eso, o se dimensiona `DRX_RAY_BUFFERS` contra un presupuesto declarado
de latencia de interrupción, o se declara el presupuesto y se verifica en el soak de 72 h de Z5.

### P-18 · En el borde de lote, un rayo puede llevar la cabecera de uno y la carga útil del otro { #p-18 }

**Estado:** CERRADO por consecuencia 3-oct-2026, encontrado el mismo día (soak de Z4.6) ·
**Dueño:** Z4.6 · **Bloquea:** nada. Desapareció al sacar `lwip_send` de la tarea de rayos; la
evidencia y la condición de reapertura, al final de la entrada.

Medido en placa, con las cifras del rayo que lo provocó:

```
rayo sin enmarcar idx=356735 trig=357002 bins=1002 n_ch=3 n_words=11067 esperadas=3006 batch=1
```

`11067 = 3689 × 3` es **exactamente un rayo del lote bajo**. La cabecera en banda dice `batch=1`
y `bins=1002` (lote alto, `3006` palabras), y detrás viene la carga útil de un rayo de 3689 bins.
Las dos mitades del mismo rayo describen lotes distintos.

**Por qué pasa, hasta donde llega la evidencia.** El metadato en banda lo pone `drx_ray_packer` con
la configuración vigente cuando empieza el rayo, y el conteo de bins con el que `drx_range_gate`
corta viene del registro del lote ([D-15](decisiones.md#d-15)). En la frontera entre el lote bajo y
el alto de un radial ([D-13](decisiones.md#d-13)) hay una ventana en la que el metadato ya refleja
el lote nuevo y el gate todavía está vaciando un rayo del viejo. Que los descartes caigan **siempre**
junto a saltos grandes de `trig_count` (d = 4, 8, 14, 22, nunca d = 2) y nunca en marcha estable
apoya esa lectura. Es inferencia a partir de la correlación, no una captura del instante: no se ha
mirado con ILA.

**El soak de 2 h (1 608 220 rayos) lo caracterizó mejor, y en dos puntos cambia la lectura.**
Cuatro eventos:

```
idx=356735   bins=1002 batch=1  n_words=11067  esperadas=3006
idx=904728   bins=1002 batch=1  n_words=11067  esperadas=3006
idx=1140286  bins=3689 batch=0  n_words=3006   esperadas=11067   <- al revés
idx=1434559  bins=1002 batch=1  n_words=11067  esperadas=3006
```

1. **Pasa en los dos sentidos** (`largos=3, cortos=1`), no solo «el gate va por detrás». Eso
   descarta las explicaciones de retardo fijo en una dirección.
2. **La carga útil es siempre un rayo COMPLETO del otro lote** —11067 o 3006 exactos, nunca un
   número parcial—. Eso descarta truncamiento del DMA o un TLAST a destiempo: el gate entregó un
   rayo entero y bien formado; lo único equivocado es la cabecera que lo acompaña.

**Frecuencia:** 4 en 1,6 millones de rayos, ~1 cada 30 minutos a 223 rayos/s.

**Y un fenómeno mayor alrededor, que probablemente sea el de verdad.** `trig_gaps` llegó a 20 en
esas 2 h, y la deriva entre `trig_count` y `ray_index` creció en **212 disparos a lo largo de
1 077 824 rayos**: unos 212 pulsos de PRF que no produjeron ningún rayo, en 20 ráfagas de ~11
pulsos cada una (~50 ms). `ray_gaps` se mantuvo en **0** todo el tiempo, así que el empaquetador no
perdió el hilo: sencillamente no hubo rayo que empaquetar para esos disparos. El rayo con la
cabecera cambiada aparece en el borde de algunas de esas ráfagas, lo que sugiere que el desajuste
de metadato es un **efecto secundario** de la ráfaga, no la causa. Qué detiene la producción de
rayos durante ~50 ms, 20 veces en 2 horas, no está medido.

**Lo que NO es:** corrupción de datos que llegue al DSP. `DrxRayFrame_Encode` compara `n_words`
contra `bin_count × n_ch` con `!=` y se niega a enmarcar el rayo, precisamente para que un rayo de
longitud equivocada no desincronice al lector en el mensaje SIGUIENTE. El rayo se pierde, se cuenta
(`long_rays`, `enc_fail`, `sink_drops`) y el DSP ve un hueco de `seq`. El coste es un radial con un
rayo menos cada media hora, no un dato malo.

**Condición de cierre:** que el metadato en banda y el corte del gate vengan del mismo instante, de
forma que no exista ventana — o, si se demuestra que la ventana es inherente, que el rayo afectado
se marque y se entregue con su longitud real en vez de descartarse. Lo primero es lo correcto; lo
segundo solo si lo primero resulta caro. Antes de elegir hace falta mirar el borde con un ILA, que
es lo único que convierte la correlación de arriba en una captura.

**3-oct-2026: desaparece al sacar la red de la tarea de rayos. Era el efecto secundario, y la
ráfaga era la causa.** La sospecha del párrafo anterior —que el desajuste de metadato cuelga de la
ráfaga de ~50 ms y no al revés— quedó medida al corregir lo que paraba la producción: el sumidero
de rayos llamaba a `lwip_send` dentro de la tarea de rayos, así que mientras el socket bloqueaba
nadie reciclaba el anillo S2MM y el range-gate desbordaba. Con el pool de tramas y la tarea de TX
dedicada (`954579c`), en **3 085 111 rayos y 3 h 50 min**:

```
dma_overruns=0 trig_gaps=0(d=0) ray_gaps=0 cortos=0 largos=0 enc_fail=0
```

A la tasa medida antes (4 en 1 608 220) cabía esperar **~7,7 eventos** en esa población, y salieron
**0**. Bajo Poisson eso es p ~ 4,5e-4, así que no es una corrida afortunada. Y el conteo cubre los
3,08 M de rayos enteros, no solo los que se enviaron: `short_rays`/`long_rays` se cuentan en
`drx_ray.c` sobre cada rayo que sale del DMA, haya cliente o no.

**Estado: cerrado por consecuencia**, no por haber mirado el borde con un ILA. La ventana que la
hipótesis describía puede seguir existiendo en el RTL; lo que ya no existe es la condición que la
hacía visible. Se reabre si `largos` o `cortos` vuelven a moverse con el transporte sano — y esa es
toda la vigilancia que necesita.


### P-19 · El pool de transmisión pierde ~25 rayos por millón con el host sano { #p-19 }

**Estado:** CERRADO 3-oct-2026 (mismo día), como artefacto de medida del cliente de prueba ·
**Dueño:** Z4.6 · **Bloquea:** nada. El control está al final de la entrada.

Es el residuo que queda tras sacar `lwip_send` de la tarea de rayos ([P-18](#p-18), `954579c`). El
sumidero toma un hueco del pool de 4 tramas sin bloquear; si no hay, cuenta `queue_full` y descarta.
Eso es deliberado: vale más perder un rayo que parar el anillo S2MM. Lo que no está medido es por
qué el pool se queda sin hueco con todo sano.

**La medida, y lo que refuta.** Durante el soak de 3 h 50 min la máquina de desarrollo sufrió una
tormenta de desasociaciones de WiFi (816 eventos desde las 05:00:13), y la lectura de partida fue
que un host ocupado no vacía el socket, la ventana TCP se cierra y la tarea de TX bloquea.
Corrida de control de 15 min con la WiFi sana —1 desconexión en todo el arranque, 0
`failed to send h2c command`, carga 0,36—:

| | rayos enviados | descartes en el pool | tasa |
|---|---|---|---|
| soak con tormenta de WiFi | 1 215 129 | 151 | 124 ppm |
| control con host sano | 201 082 | 5 | **25 ppm** |

La tormenta explica el **exceso**, no el **suelo**. La hipótesis del host ocupado queda en pie
para el factor 5, y refutada como explicación completa.

**Forma del evento:** los 5 descartes produjeron **un solo** hueco de `seq` en el cliente, o sea
fueron consecutivos. Con 4 huecos de pool y 223,4 rayos/s, perder 5 seguidos son ~22 ms en los que
nadie vació el pool. No es una pérdida dispersa, es una parada corta y aislada: una en 15 minutos.

**Candidatos, por verosimilitud, ninguno medido:**

1. **Parada en el host.** `tools/mock_dsp.py` es Python y reensambla ~44 kB por rayo; una pausa de
   recolección de basura de decenas de ms deja de vaciar el socket el tiempo justo. Es el
   candidato barato y el primero que hay que descartar, porque si es esto no hay nada que
   arreglar en la placa.
2. **Agotamiento momentáneo de pbufs en lwIP.** El pool de la pila se queda sin buffers y `send`
   bloquea hasta que los ACK liberan.
3. **La tarea de diagnóstico tomando el mutex de TX** para su `status` de 40 B en el peor momento.
   Encaja mal con la frecuencia observada (1 evento en 15 min contra 1 `status` por segundo), pero
   no está descartado.

**Condición de cierre:** distinguir entre (1) y el resto. Un cliente que solo haga `recv` a un
buffer fijo, sin reensamblar ni asignar memoria, durante el mismo tiempo: si los descartes
desaparecen, era el host y P-19 se cierra como artefacto de medida. Si se mantienen, hay que mirar
los contadores de lwIP.

**Cerrado el mismo día: era el cliente.** El control corrió 900 s contra la misma placa, con el
único cambio de un cliente que hace `recv_into` sobre un buffer fijo de 256 kB y cuenta bytes:

| | rayos enviados | descartes en el pool |
|---|---|---|
| `tools/mock_dsp.py` (reensambla ~44 kB por rayo en Python) | 201 082 | 5 |
| cliente mínimo, solo `recv_into` | 201 032 | **0** |

Misma duración, misma tasa (28,9 Mbps), mismo firmware, `cola` clavada en 156 antes y después. El
candidato (1) era el correcto y los otros dos quedan sin evidencia que los sostenga. **Estado:
cerrado como artefacto de medida del cliente de prueba**, 3-oct-2026.

Lo que esto NO dice: que el pool no se pueda llenar nunca. Dice que a 223,4 rayos/s, con un
consumidor que vacía el socket sin pausas, no se llena. El DSP real tiene su propia latencia de
proceso, y `queue_full` sigue siendo el contador que hay que mirar cuando aparezca.

### P-20 · `first_after_config` existe en el contrato y el firmware nunca lo pone { #p-20 }

**Estado:** abierto, encontrado 3-oct-2026 (al escribir el conductor del barrido) · **Dueño:**
Z4.6 · **Bloquea:** nada funcional. Sí la solidez de cualquier medida que tenga que saber a qué
configuración pertenece un rayo.

`RayFlag.FIRST_AFTER_CONFIG` (valor 8) está en el esquema desde Z0 y `DrxRayContext` tiene el
campo, pero `fw/src/app/drx_ray_ctx.c` lo escribe siempre a `false`:

```c
out->first_after_config = false;
```

Nadie lo había necesitado hasta ahora porque nada cambiaba de configuración en caliente. Con el
catálogo de estímulos elegible por mensaje (Z4.3) y el barrido de P-16, sí hace falta: tras un
`test_stimulus_select` hay rayos en vuelo que todavía llevan el vector viejo, y el DDC tarda en
vaciar su tubería. Sin la bandera, `tools/sweep_catalogo.py` tiene que decidirlo por tiempo
(`--settle`, 2 s por defecto), que es una heurística y no una medida.

**Por qué importa más de lo que parece.** Un `--settle` corto da un falso FALLO (se midió el
vector viejo). Uno largo no da un falso ACIERTO —el vector nuevo ya suena— pero alarga el barrido
y, lo que es peor, convierte un fallo real de conmutación en un PASS: si el firmware no llegara a
cambiar de vector, un `--settle` generoso no lo distinguiría de uno que sí cambió, porque el
criterio no mira la configuración sino el reloj.

**Condición de cierre:** que `drx_ray_ctx.c` ponga `first_after_config` en el primer rayo que
empieza después de aplicar una configuración —cualquiera: `config`, `afc`,
`test_stimulus_select`— y que el conductor lo use en vez del temporizador. El mismo enganche que
ya aplica `apply_at_seq` entre rayos en `drx_ray.c` es donde va.

### P-21 · El MM2S se atasca tras unas pocas selecciones de estímulo { #p-21 }

**Estado:** abierto, encontrado 3-oct-2026 (primer barrido del catálogo) · **Dueño:** Z4.6 ·
**Bloquea:** el barrido del catálogo, junto con [P-16](#p-16). Independiente de él.

Encadenando `test_stimulus_select`, el canal MMSS del AXI DMA deja de aceptar pasadas:

```
drx_stimulus: vector 2 (dos_tonos), repeat=0
drx_stimulus: pasada sin completar tras 50 ms; sus descriptores quedan en el hardware
...
drx_stimulus: no se pudo encolar la primera pasada
```

**La mitad diagnosticada.** `DrxStimulus_Stop()` pausaba el DMA ANTES de drenar:
`XAxiDma_Pause()` corta la búsqueda de descriptores a mitad de pasada, así que esa pasada nunca
completa y `reap_pass()` —que solo devuelve al anillo lo que el hardware marcó como hecho— no
recupera sus BD. El anillo tiene sitio para `DRX_STIMULUS_BD_RING / DRX_STIMULUS_BD_COUNT` = 4
pasadas, o sea que a la cuarta fuga `XAxiDma_BdRingAlloc` falla para siempre. No se puede
arreglar con `XAxiDma_Reset`: MM2S y S2MM son el MISMO `axi_dma` del block design y resetearlo se
llevaría por delante el anillo de rayos. Corregido drenando antes de pausar, con tope de 50 ms.

**La mitad que queda, y que el arreglo convirtió en medible.** Con el drenado puesto, el mensaje
nuevo dice que la pasada **no completa en 50 ms**. Una pasada son 4000 conjuntos y el DDC debería
tragárselos en menos de 1 ms aunque vaya a 1 de cada 4 ciclos, así que no es lentitud: la cadena
se para de verdad en algún punto entre el MM2S y el DDC. Las dos primeras selecciones drenan
bien y a partir de la tercera no, lo que sugiere que el atasco se produce durante el bucle
normal y no al parar.

**Por qué no se había visto.** Nadie había encadenado selecciones —Z4.3 probó el modo DDR con el
motor de timing PARADO y con `repeat` finito— y hasta el pacing de P-16 el síntoma quedaba
tapado: el motor seguía contando ciclos aunque no llegara una sola muestra, así que lo que se veía
era `GATE_TRUNCATED` y no una parada.

**Condición de cierre:** saber qué para la cadena.

**El ILA ya está construido, 3-oct-2026.** `rtl/drx_debug_probe.sv` + `rtl/drx_debug_pkg.sv`
(nuevos) sacan a un bus los handshakes de toda la cadena —de `s_vec_*` a `m_ray_*`, con
`vs_valid`/`vs_ready`/`ddc_valid`/`gate_valid`/`gate_ready` por canal— y cuentan los ciclos desde
el último avance de muestra. `tcl/build.tcl -debug 1` engancha un ILA a ese bus; la build normal
no cambia (el XCI vive en `ip_debug/`, fuera del glob de `ip/`, y sin `DRX_DEBUG_ILA` la síntesis
se lleva la sonda entera salvo el contador). Verificado en L0 contra RTL mutado: desplazar un
campo del troceado un bit, o dejar que el contador cuente con `armed` en bajo, hacen fallar el
banco. Runbook completo, con la tabla de lectura de la captura, en
[docs/implementacion/ila.md](../implementacion/ila.md).

La parte no obvia es el disparo. El umbral de parada son 2²⁰ ciclos ≈ 16,78 ms (tiene que estar por
encima de los huecos legítimos del sondeo de `DrxStimulusTask`, que desde el 3-oct-2026 es de 1 ms;
con los 10 ms originales hacía falta 2²² ≈ 67 ms y eso tapaba cualquier atasco más corto), y la
ventana del ILA son 4096 muestras = 65 µs: disparar con `stalled` y guardar todo dejaría el buffer entero dentro del
silencio. Con almacenamiento calificado por actividad (`C_EN_STRG_QUAL`), esas 4096 muestras son
los últimos ciclos en que algo se movió.

**Hipótesis de partida, anotada antes de medir.** `reap_pass()` llama a
`XAxiDma_BdRingFromHw(ring, XAXIDMA_ALL_BDS, …)`, que puede devolver MENOS descriptores que los
`DRX_STIMULUS_BD_COUNT` de la pasada, y aun así pone `g_in_flight = false` y declara la pasada
entera hecha. Dentro del bucle de drenado de `DrxStimulus_Stop()` eso corta el drenado antes de
tiempo: `XAxiDma_Pause()` deja el descriptor que faltaba en el hardware y `set_modo_ddr(false)`
baja `ddr_mode`, con lo que `s_axis_ready` de `vector_source` se va a 0 y ese descriptor ya no
puede completarse nunca. Es el mismo agujero que el arreglo de arriba cerró por un lado y esto
reabre por otro, y explica el «a partir de la tercera». **Predicción falsable:** la captura tiene
que mostrar `s_vec_valid = 1`, `s_vec_ready = 0` y `ddr_mode = 0` en el mismo ciclo. Si `ddr_mode`
sigue en 1, la hipótesis es falsa. El firmware se deja sin tocar hasta tener la captura: arreglar
la hipótesis antes de medirla cerraría P-21 por coincidencia.

Las lecturas de `MM2S_DMASR` por JTAG de la primera sesión dieron patrones de bits implausibles
(errores de SG en un canal que estaba entregando rayos) y no se usaron como evidencia.

**Bloqueo de hardware de la primera sesión, ya resuelto con un apagado y encendido.** Al cargar el bitstream de
depuración apareció otro fallo delante: el AXI DMA no mueve nada en NINGUNO de los dos canales,
con los dos corriendo (`RS = 1`), con descriptores pendientes y **sin un solo bit de error**. El
ILA lo dejó claro en una sola foto de 4096 ciclos idénticos — `m_ray_valid = 1` con
`m_ray_ready = 0`, `s_vec_valid = 0`, y la PL moviéndose por dentro
(`vs_valid = vs_ready = 0b111`) —, o sea que lo parado es el DMA y no la lógica. El primer
arranque fallido es el siguiente a reprogramar la PL con el S2MM transmitiendo a 225 rayos/s:
una transacción colgada en HP0, del lado PS, donde no llegan ni la reconfiguración de la PL ni
`ps7_init`. No se recupera por software — probadas cuatro recargas y un ciclo explícito de
`FPGA_RST_CTRL`. **Hace falta apagar y encender la placa.** Detalle y la regla que sale de esto
("parar el camino de rayos antes de reprogramar la PL") en
[docs/implementacion/ila.md](../implementacion/ila.md#primera-captura-3-oct-2026).

Lo que sí deja demostrado esa captura: el instrumento funciona, y la contrapresión de la cadena
se comporta como está diseñada (`gate_valid = 0b111` contra `gate_ready = 0b000`, `overrun`
subiendo).

**La hipótesis está REFUTADA, y lo que se midió es otra cosa (3-oct-2026, tarde).** Con la placa
reiniciada el instrumento se usó de verdad. Primero un control positivo —parar el MM2S a mano
(`MM2S_DMACR` bit 0 a 0) dejando `ddr_mode` en alto— que disparó en el instante de la escritura
con `idle_cnt = 1048576`, o sea 2²⁰ clavado: el contador, el flanco y el decodificador quedan
verificados contra silicio. Después, el A/B del sondeo, mismo bitstream y mismo barrido
(`--settle 1`) en las dos patas:

| Firmware | Selecciones encadenadas | Disparos |
|---|---|---|
| sondeo 1 ms, tick 1 kHz | 80 | **ninguno** |
| sondeo 10 ms, tick 100 Hz | 24 | **2**, a los 32 s y a los 16 s |

Las dos capturas del lado de 10 ms dan `ddr_mode = 1`, `s_vec_valid = 0`, `s_vec_ready = 1`,
`vs_ready = 0b111`, `overrun = 0b000`. La predicción exigía `s_vec_valid = 1` con
`ddr_mode = 0`: **falsa**. No hay un beat atascado que `vector_source` rechace; hay hambre — el
consumidor listo y el productor ausente durante más de 16,78 ms. El arreglo de `reap_pass()` que
se había dejado sin tocar a propósito ya no tiene por qué ser la causa.

**Lo que NO cierra esto, y por eso P-21 sigue abierto.** El atasco *permanente* del hallazgo
original no reprodujo hoy en ninguna de las dos patas: las 24 selecciones del lado de 10 ms
terminaron todas con `config_ack error=ok` y un rayo de vuelta, `dma_overruns=0`,
`trig_gaps=0`. Lo medido es un hueco *transitorio* del que la cadena sale sola. Que el sondeo de
10 ms produzca huecos de alimentación está demostrado; que sea además la causa del atasco
permanente es plausible y no está demostrado.

**Condición de cierre, actualizada:** reproducir el atasco **permanente** con el ILA armado. Si
no vuelve a aparecer en una corrida larga con el sondeo de 1 ms, cerrar por consecuencia y
decirlo así, como se hizo con [P-18](#p-18).

Detalle, las tres trampas de recargar solo el ELF por JTAG y la regla de que una recarga en
caliente no es comparable con un arranque en frío, en
[docs/implementacion/ila.md](../implementacion/ila.md).
