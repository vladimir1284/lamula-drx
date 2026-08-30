# Pendientes y hallazgos abiertos

Documento vivo. Cada entrada tiene un dueño y una condición de cierre; nada se cierra sin
evidencia. Los hallazgos marcados como **inferencia** salen del análisis del plan original y están
pendientes de confirmación por los especialistas de dominio.

## Hallazgos que hay que resolver antes de comprar hardware

Estos dos afectan a **qué hardware hay que comprar**. Ninguno cuesta más de una tarde de análisis
ahora, y los dos cuestan mucho después.

### P-01 · Tolerancia del tamaño de celda { #p-01 }

**Estado:** parcialmente respondido sobre código de ORPG, pendiente de verificación de fuente ·
**Dueño:** especialistas de dominio · **Bloquea:** cierre de [D-04](decisiones.md#d-04) y la
arquitectura del DDC.

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

!!! warning "Por qué esto no cierra P-01 todavía"
    El árbol de ORPG **no está en la máquina de desarrollo**, así que ninguna de las citas
    `fichero:línea` es reverificable aquí; el barrido sí reverificó las cuatro citas decisivas del
    primer resultado y coinciden. Siguen sin revisar la composición geográfica entre radares, el
    VAD/VWP y el remuestreo final a rejilla Level-III —los tres que el brief marcaba como daño
    potencial número uno— y `RDA_Backend_Py`, la única fuente empírica, sigue sin localizar (ver
    [P-05](#p-05)).

    La evidencia ya es suficiente para decir que **R₂ = 416 declarado como 249 es la opción
    equivocada**, pero sustituir D-04 pide un ADR firmado por los especialistas, no una edición de
    este documento. Y antes de escribir ese ADR hay que resolver [P-08](#p-08): si `fs` puede
    moverse a 249,427325 MHz, R₂ = 416 pasa a dar 250 m exactos y el dilema desaparece sin tocar
    los factores de diezmado.

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

### P-04 · Sectorización azimutal de PRF y ancho de pulso («pie-slice») { #p-04 }

**Estado:** abierto · **Dueño:** checklist DSP↔RCP · **Alcance:** no comprometido.

El plan original nombra un único par PRF/ancho de pulso global por barrido. El estudio de la
interfaz de anfitrión de un procesador de señal maduro sugiere una capacidad más granular: una tabla
de valores de PRF y ancho de pulso que conmutan **por sector azimutal dentro de un mismo barrido**.

Si el checklist DSP↔RCP confirma que las estrategias de barrido del radar Gematronik objetivo lo
necesitan, es un requisito del motor de timing en PL — las tablas de trigger necesitarían entradas
por sector — y un campo correspondiente en la dirección de configuración del contrato DRx↔DSP. **No
se asume necesario sin esa confirmación.**

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

### P-06 · Dos copias vivas del project plan de la ZU9 { #p-06 }

**Estado:** abierto · **Dueño:** equipo · **Severidad:** baja, pero divergirá.

El plan ZU9 existe en dos sitios publicados: `docs/referencia/project-plan-zu9.md` en este
repositorio y `docs/drx-plan.md` en `lamula-dsp`, que sigue en el nav de ese sitio. El fuente del
plan de ZedBoard (`lamula-drx-zedboard-plan.md`) sí se eliminó de `lamula-dsp` al escindir este
repositorio, pero el del plan ZU9 no.

Mientras las dos copias existan, un cambio en una no se refleja en la otra. La opción de retirar
`drx-plan.md` del sitio DSP se planteó y se decidió **no tocarlo** por ahora, porque rompe enlaces
existentes a ese sitio.

**Condición de cierre:** o se retira la copia del sitio DSP dejando una redirección, o se declara
explícitamente cuál de las dos es la canónica y se anota en las dos.

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

**Estado:** abierto, con una propuesta concreta · **Dueño:** dirección técnica + compra ·
**Bloquea:** el cierre de [D-04](decisiones.md#d-04).

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
- **Menos presión de recursos y de timing**, y en ZedBoard el factor de dilatación baja de 2,5 a
  1,439, lo que acerca la plataforma de desarrollo a la de destino.

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

- **Rate mínimo del convertidor del FMC213.** Es el riesgo real de bajar a 143,9 MHz: los
  convertidores JESD204B de gama alta tienen frecuencia de muestreo **mínima** especificada, y una
  pieza pensada para 250 MSPS puede quedarse fuera de spec a 143,9. **Hay que leer la hoja de datos
  antes que nada**; si el mínimo lo impide, los candidatos de la tabla por encima de 200 MHz siguen
  en pie.
- **Plan de frecuencia intermedia.** A 143,9 MHz, `fs/2` = 71,95 MHz. Un IF de 30 MHz entra holgado
  en la primera zona de Nyquist; uno de 60 MHz entra pero con menos margen para el filtro
  antialias. Hace falta el IF real del radar, que no está en este repositorio.
- **JESD204B.** La tasa de línea baja con `fs`, lo que va a favor, pero hay que confirmar que el
  modo del convertidor admite ese rate y que SYSREF sigue siendo submúltiplo entero del LMFC.
- **Ancho de banda.** Con pulsos de 0,8 / 1,66 / 3,3 µs el ancho de banda es de ~1,25 MHz como
  máximo, así que no es restricción a ninguna de estas frecuencias.

**Impacto en el RTL: ninguno por el lado de `fs`, si se cumple [D-02](decisiones.md#d-02)** — todo
se deriva de `FS_HZ`. Sí cambian R₁ y R₂, que son parámetros de la cadena de diezmado, no
arquitectura.

**Condición de cierre:** confirmación del rate mínimo del convertidor y del plan de IF, y un ADR que
sustituya a D-04 fijando `fs`, R₁ y R₂ juntos. Si el convertidor no baja a 143,9 MHz, el plan B es
247 MHz con R₁ = 206 / R₂ = 412 (54 m de error, reloj en rejilla de 1 MHz, cadena única); y si
tampoco, la Opción B de P-01.

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
