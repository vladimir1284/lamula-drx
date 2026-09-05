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
    este documento. Ese ADR ya está redactado y espera firma: [ADR-001](adr-001-fs-r1-r2.md). Y antes de escribir ese ADR hay que resolver [P-08](#p-08): si `fs` puede
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
| A7 | Existe un runner de CI con Vivado y licencia para el job `gateware` | Hoy **sigue sin existir**: el job está condicionado a la variable `HAS_VIVADO_RUNNER`. Lo que sí cambió el 5-sep-2026: el flujo de `tcl/` (`build.tcl`, `sim_l1.tcl`) y `tools/make_boot.sh` **se ejecutaron manualmente**, con éxito, en una máquina de desarrollo fuera de CI — ver el hallazgo bajo [P-09](#p-09). Falta registrar ese runner `[self-hosted, vivado]` y poner `HAS_VIVADO_RUNNER=true` para que el hito ZM0 quede automatizado por CI, no solo demostrado a mano |
| A8 | La versión de Vivado está pinada en el runner | Sigue sin pinarse porque el runner no existe. La instalación manual de esta sesión fue Vivado ML Standard **2022.2** — candidata obvia a version-pin cuando se monte el runner — pero pinarla en CI es trabajo aparte |

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
