# Pendientes y hallazgos abiertos

Documento vivo. Cada entrada tiene un dueño y una condición de cierre; nada se cierra sin
evidencia. Los hallazgos marcados como **inferencia** salen del análisis del plan original y están
pendientes de confirmación por los especialistas de dominio.

## Hallazgos que hay que resolver antes de comprar hardware

Estos dos afectan a **qué hardware hay que comprar**. Ninguno cuesta más de una tarde de análisis
ahora, y los dos cuestan mucho después.

### P-01 · Tolerancia del tamaño de celda { #p-01 }

**Estado:** abierto · **Dueño:** especialistas de dominio · **Bloquea:** cierre de
[D-04](decisiones.md#d-04) y la arquitectura del DDC.

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
ADR nuevo que sustituya a D-04.

**Brief de investigación:** `research/p-01-orpg-gate-spacing.md` (en el repositorio, no publicado en
este sitio) descompone la pregunta en cuatro sub-preguntas respondibles desde el código de ORPG y
del legacy `RDA_Backend_Py`, y corrige la cuantificación del error: lo que decide no es el error por
celda (0,29 m) sino el **acumulado a 460 km, ~1,1 km**.

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
