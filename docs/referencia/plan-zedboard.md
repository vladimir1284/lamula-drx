!!! note "Documento de referencia — se conserva íntegro"
    Este es el plan de implementación y testing sobre ZedBoard tal como se escribió, sin editar. Las
    páginas de [Alcance](../alcance/contexto.md), [Plataforma](../plataforma/zedboard.md),
    [Implementación](../implementacion/fases.md), [Verificación](../pruebas/plan-testing.md) y
    [Portabilidad](../portabilidad/registro-delta.md) derivan de él y **mandan sobre él** cuando
    discrepan. Se conserva aquí para poder auditar de dónde sale cada decisión.

# LAMULA DRx — Plan de implementación y testing sobre ZedBoard

**Plataforma:** Digilent ZedBoard (Xilinx XC7Z020-CLG484-1)
**Rol:** plataforma de desarrollo primaria mientras no exista hardware ZU9 + FMC213
**Horizonte propuesto:** 28 semanas (Z0–Z5), en paralelo al plan original de 34 semanas
**Fecha:** 30 de agosto de 2026

---

## 0. Supuestos y advertencia de entorno

Este plan se escribe sin acceso a tu repositorio, a tu instalación de Vivado ni a la placa. Todo número de recursos, de temporización o de ancho de banda que aparece marcado como *estimación* es una inferencia mía a partir de las hojas de datos y debe verificarse en banco antes de comprometerse a él.

Supuestos que asumo y que hay que confirmar:

| # | Supuesto | Cómo verificarlo |
|---|---|---|
| A1 | ZedBoard rev. D o posterior, XC7Z020-CLG484-**1**, 512 MB DDR3 | Serigrafía de la placa |
| A2 | Vivado/Vitis con licencia para DDS/CIC/FIR Compiler y AXI DMA | `report_ip_status` sobre un proyecto de prueba |
| A3 | El proyecto DSP aún no ha congelado el contrato DRx↔DSP | Preguntar al equipo DSP |
| A4 | El RTL custom se puede escribir en SystemVerilog (no hay mandato VHDL) | Decisión de equipo — ver §6.1 |
| A5 | La placa/MCU auxiliar para SSI tiene al menos un periférico SPI esclavo o PIO a ≥2 MHz | Hoja de datos del MCU |
| A6 | Hay acceso a un osciloscopio de ≥100 MHz para medir jitter de trigger | Inventario de laboratorio |

**Fact vs. inferencia:** los límites de la ZedBoard (§1) son hechos verificables en la documentación del dispositivo. El plan de fases, los presupuestos de recursos y la estimación de cobertura son inferencias mías.

---

## 1. Frontera dura: lo que la ZedBoard no puede cubrir

El XC7Z020 en empaquetado CLG484 **no expone transceptores gigabit**. Sin MGTs no hay JESD204B en ninguna forma: ni PHY, ni establecimiento de link, ni alineación de lanes, ni SYSREF, ni latencia determinista, ni sincronización multi-dispositivo. Adicionalmente el conector FMC de la ZedBoard es **LPC** y la VadaTech FMC213 requiere HPC con lanes de transceptor, de modo que la mezzanine tampoco es acoplable físicamente.

La consecuencia hay que decirla sin adornos: **el riesgo #1 de tu registro original — bring-up de JESD204B y clocking — recibe cero mitigación con esta placa, y seguirá sin retirarse durante todo el tiempo que la ZU9 no exista.** Ese riesgo no se reduce con trabajo de software; es hardware-bound. Todo lo demás que sigue en este documento es real y valioso, pero no compra ni un punto porcentual de ese riesgo concreto.

Tampoco quedan cubiertos: la tasa de 250 MSPS, el IF analógico real de 60 MHz, el DAC AD9129, el loopback DAC→ADC como oráculo de a bordo, y la capa física RS-422 de los encoders.

---

## 2. Cobertura alcanzable

Del §4.4 del plan original (13 componentes), la ZedBoard permite construir y validar 10 completos y 2 parciales. Estimación: **~70 % de las líneas del WBS**, con la salvedad de que el 30 % excluido contiene el elemento de mayor riesgo.

| Componente (§4.4 original) | Cobertura | Sustituto en ZedBoard |
|---|---|---|
| Clocking & SYSREF | **Ninguna** | — |
| JESD204B RX | **Ninguna** | Reproductor de vectores desde DDR/BRAM |
| Cadena DDC | Completa | Idéntica; solo cambia el reloj |
| Range Gating | Completa | Idéntica, tiempo dilatado |
| Motor de timing/trigger | Completa | Idéntica, tiempo dilatado |
| Lectores SSI | Alta (lógica sí, PHY no) | Emulador en fabric + MCU vía Pmod LVCMOS |
| Camino AXI DMA | Completa | Mismo IP, mismo flujo |
| Ray Assembler (PS) | Alta | FreeRTOS sobre A9 en lugar de R5 |
| Transporte DRx↔DSP | Completa | GEM0 + lwIP, 1GbE real |
| Control/Config Handler | Completa | Portable línea por línea |
| Camino DAC / Tx-reference | Parcial | Síntesis NCO sí; interfaz AD9129 no |
| Status & BITE | Completa | Con catálogo de fallos adaptado |
| Diagnósticos (captura raw) | Completa | Idéntica |

---

## 3. Las tres decisiones de arquitectura que hay que tomar antes de escribir RTL

### 3.1 Capa de abstracción de fuente de muestras (SSA)

Sin esto, el trabajo en ZedBoard es desechable. Con esto, es transferible.

Se define un único interfaz AXI4-Stream de muestras con backpressure:

```
sample_stream: TDATA[N*16-1:0] (N canales entrelazados o N streams paralelos)
               TVALID / TREADY
               TUSER = {channel_id, sample_valid_mask, source_tag}
               TLAST = fin de ventana de captura
```

Del que existen **dos implementaciones intercambiables**:

- `jesd204b_source` — solo en ZU9. IP Xilinx + GTH.
- `vector_source` — reproductor. Es la implementación que existe hoy y la que sobrevive en la placa real como inyector de vectores digitales.

Todo lo que está aguas abajo (DDC, gating, DMA, PS) se desarrolla y se valida contra la SSA, nunca contra la fuente concreta. Esto convierte la inyección de vectores digitales en ciudadano de primera clase en lugar de un hack de bring-up, lo cual también es correcto para la placa final.

### 3.2 Dilatación temporal uniforme mediante un único parámetro `FS_HZ`

El reloj de fabric objetivo en ZedBoard es **100 MHz** (grado -1; 250 MHz no cierra con un datapath DSP no trivial).

La regla es: **se dilata todo por igual, nunca solo una parte**. Un solo genérico/paquete de parámetros define `FS_HZ`, y todos los divisores, anchos de contador, palabras de fase del NCO, factores de diezmado y valores de registro se derivan de él o se mantienen literalmente idénticos.

Preservando la frecuencia normalizada del IF (60/250 = **0,24**):

| Parámetro | ZU9 (real) | ZedBoard | Relación |
|---|---|---|---|
| Reloj de fabric / fs | 250 MHz | 100 MHz | ÷2,5 |
| IF de entrada | 60 MHz | 24 MHz | ÷2,5 |
| IF normalizado | 0,24 | 0,24 | **idéntico** |
| Palabra de fase del NCO | X | X | **idéntica** |
| Factor de diezmado | R | R | **idéntico** |
| Coeficientes FIR | C[] | C[] | **idénticos** |
| Valor de registro de PRF | P | P | **idéntico** |
| PRF en tiempo de pared | 200–1200 Hz | 80–480 Hz | ÷2,5 |
| Ancho de pulso (registro) | 200 clk | 200 clk | **idéntico** |
| Ancho de pulso real | 0,8 µs | 2,0 µs | ×2,5 |

El resultado es que **los testbenches, los vectores de estímulo y los valores esperados son bit a bit los mismos en ambas plataformas**. La migración a la ZU9 consiste en cambiar `FS_HZ` y volver a cerrar timing.

Plan de contingencia: si el 7Z020-1 no cierra a 100 MHz con 4 canales, se baja a 62,5 MHz (dilatación 4×) o se reduce a 2 canales. Numéricamente sigue siendo idéntico.

**Lo que la dilatación rompe:** los ensayos de throughput ya no son representativos (§7.4). Hay que tratarlos como una campaña aparte.

### 3.3 Modelo dorado en Python como oráculo principal

La ZedBoard no tiene loopback DAC→ADC, que era el oráculo del plan original. El sustituto es mejor en precisión y peor en realismo: un **modelo de referencia en NumPy** de toda la cadena DDC (NCO → mixer → CIC → FIR → gating), bit-exacto en aritmética de punto fijo.

Sustitución de oráculos:

| Oráculo del plan original | Sustituto en ZedBoard | Qué se pierde |
|---|---|---|
| Loopback DAC→ADC | Modelo NumPy + inyección de vectores | Realismo analógico, ruido, no linealidades |
| IF real de 60 MHz | Vectores sintéticos con ruido, offset DC, clipping y desbalance I/Q inyectados a propósito | Comportamiento del frontal real |
| Encoders reales | Emulador SSI en fabric + MCU independiente | Capa física RS-422, dinámica de antena |
| DSP como par de red | Stub consumidor + simulador de señal del DSP | Semántica real de consumo |

---

## 4. Hallazgos técnicos del plan original que hay que resolver ahora

Estos son problemas del plan de la ZU9 que la ZedBoard permite descubrir y cerrar barato, antes de comprar hardware. Los marco como inferencia mía, pendientes de confirmación por los especialistas de dominio.

### 4.1 Los factores de diezmado no son enteros para 125 m / 250 m a 250 MSPS

A 250 MSPS, cada muestra cubre `c/2 × 4 ns = 0,5996 m` de rango.

- 125 m → 208,48 muestras → R = 208 da **124,71 m**, R = 209 da **125,31 m**
- 250 m → 416,95 muestras → R = 417 da **250,03 m**

No existe un R entero que dé exactamente 125 m ni 250 m, y además **R(250 m) ≠ 2 × R(125 m)** si se busca el más cercano en cada caso (208 vs 417). Esto importa porque la arquitectura natural es una cadena CIC/FIR donde el modo de 250 m añade una etapa ÷2 sobre el de 125 m.

Recomendación: **R₁ = 208, R₂ = 416** → celdas de 124,71 m y 249,41 m (error −0,24 %, unos 0,6 m en la celda grande). Esto mantiene R₂ = 2·R₁ y una sola cadena con etapa conmutable.

Consecuencia sobre el conteo de bins: 460 km / 249,41 m = **1844 bins** (el plan dice 1840) y 460 km / 124,71 m = **3689 bins** (el plan dice 3680). La diferencia proviene de asumir celdas exactas.

**Decisión requerida de los especialistas:** ¿el producto ORPG admite un error de celda del 0,24 %, o exige 125/250 m exactos? Si exige exactitud hay que ir a remuestreo fraccionario (Farrow) o a otra fs, y eso cambia el presupuesto de DSPs y la arquitectura. Es mucho más barato descubrirlo ahora en ZedBoard que en la ZU9.

### 4.2 El rango máximo y la PRF están acoplados, y el plan no lo dice

El rango no ambiguo es `c / (2·PRF)`:

| PRF | Rango máximo no ambiguo |
|---|---|
| 200 Hz | 749,5 km |
| 326 Hz | **460 km** ← límite para el modo de reflectividad |
| 651 Hz | 230 km |
| 999 Hz | 150 km |
| 1200 Hz | 124,9 km |

Es decir: **460 km @ 1200 Hz es físicamente imposible**. El plan enumera "PRF 200–1200 Hz" y "alcance hasta 460 km" como si fueran independientes. No lo son.

Esto genera un requisito que no está en el plan original: **el manejador de configuración debe validar y rechazar combinaciones ilegales de PRF × extensión de rango**, y reportarlo por el plano de status/BITE. Es un caso de prueba de aceptación y una entrada en el contrato DRx↔DSP (código de error de configuración rechazada). Se implementa y se prueba entero en ZedBoard.

### 4.3 El presupuesto de 1GbE se confirma, pero solo bajo un supuesto

Con R = 208, 4 canales Rx, I/Q de 16+16 bits:

```
tasa por canal  = 250e6 / 208 = 1,2019 MSPS complejas
bytes por canal = 1,2019e6 × 4 B = 4,81 MB/s
4 canales       = 19,23 MB/s = 153,8 Mbps
+ overhead Ethernet (MTU 1500, ~2,8 %) ≈ 158 Mbps
```

Encaja con holgura 6× en 1GbE, y coincide con el «~20 MB/s» del plan. Pero ese número asume ciclo de trabajo del ~100 % en el gating, que es exactamente el peor caso cuando la PRF se lleva al límite del rango (§4.2). Así que 19,23 MB/s es el **techo**, no un promedio. El plan puede afirmarlo con confianza.

### 4.4 El plan no especifica la capa física de los encoders SSI

El §12 dice que «los dos encoders SSI son accesibles» pero nunca dice a través de qué. SSI en instrumentación industrial es habitualmente **RS-422 diferencial**, no LVCMOS. Si la portadora ZU9 no lleva transceptores RS-422, falta hardware. Hay que resolverlo antes de comprar.

---

## 5. Corrección al orden de prioridades

Ordenaste: DDC+gating → timing → SSI → camino de datos → CI. Acepto los cuatro primeros. **El quinto está mal colocado, y hay una parte del cuarto que también.**

**CI y flujo Tcl no van los últimos: son precondición.** El §7.2 de tu propio plan hace del modelo de entrega acelerado por agentes el argumento central de viabilidad para un equipo de tres personas. Ese modelo no funciona si el diseño vive en un proyecto GUI de Vivado: los agentes no pueden operar sobre él, las builds no son reproducibles y la regresión no existe. Cuesta unas dos semanas hacerlo bien al principio; cuesta un mes de reconstrucción hacerlo al final. Va en Z0.

**El congelado del esquema DRx↔DSP tampoco va cuarto.** Hay que separar dos cosas que el plan mezcla: *definir el esquema* (semana 1–2, coste bajo, dependencia externa alta) e *implementar el transporte* (más tarde, coste medio, dependencia nula). El esquema es un punto de sincronización entre proyectos; cuanto más tarde se congele, más caro es el rebote. Si el equipo DSP no está listo, se congela unilateralmente una v0.1 versionada y se negocia sobre algo concreto en lugar de sobre nada.

El resto de tu orden queda intacto.

---

## 6. Stack técnico en ZedBoard

### 6.1 Decisión de lenguaje y simulador (bloqueante para Z0)

El plan original dice «VHDL/Verilog» y «Verilator + cocotb». **Verilator no soporta VHDL.** Hay que elegir:

| Opción | Ventaja | Coste |
|---|---|---|
| **SystemVerilog + Verilator + cocotb** (recomendada) | Simulación gratis, rápida, sin licencia en el runner de CI | El equipo debe estar cómodo en SV |
| VHDL + GHDL + cocotb | Gratis, sin licencia | GHDL con cocotb vía VPI es más frágil; menos soporte |
| Cualquiera + Vivado xsim | Un solo toolchain | Requiere licencia en el runner de CI; lento |

Recomendación: **SystemVerilog para el RTL custom**, con Verilator para las unidades (motor de timing, SSI, gating, framing, reproductor de vectores) y **xsim para la integración con IP de Xilinx**, porque los cores del DDC son cajas negras que Verilator no puede elaborar. Dos niveles de simulación, dos herramientas, con un único runner cocotb por encima.

### 6.2 Reproductor de vectores: tres modos

El ancho de banda de DDR3 de la ZedBoard (32 bits @ 533 MT/s ≈ 2133 MB/s de pico, estimo ~1400 MB/s sostenidos) limita lo que se puede reproducir en tiempo real dilatado.

| Modo | Fuente | Canales | Tasa | Uso |
|---|---|---|---|---|
| **RT** | DDR vía MM2S DMA | 1–2 | 100 MSPS (≈200–400 MB/s) | Fidelidad temporal, señales largas |
| **BRAM-loop** | BRAM, forma de onda repetitiva | 4 | 100 MSPS | Ensayos de tasa sostenida y de timing |
| **Throttled** | DDR con backpressure AXIS | 4 | < tiempo real | Corrección funcional, bit-exacta |

BRAM disponible: 4,9 Mb ≈ 613 KB. A 16 bits × 4 canales → ~76 k muestras/canal → 766 µs de señal a 100 MSPS. Suficiente para varias PRIs a PRF alta.

El modo *Throttled* produce salida **bit a bit idéntica** al modo RT; solo tarda más. Es el modo de referencia para corrección.

### 6.3 Presupuesto de recursos (estimación, ±40 %)

Para 4 canales de DDC + gating + timing + SSI + DMA sobre XC7Z020:

| Bloque | DSP48 | LUT | BRAM36 |
|---|---|---|---|
| DDS ×4 (NCO 16 bit) | 8 | 1 200 | 4 |
| Mixer complejo ×4 | 16 | 800 | 0 |
| CIC ×8 (N=5, R=52) | 0 | 4 000 | 0 |
| FIR compensador + final (time-shared, 8 streams) | 10 | 2 500 | 4 |
| Range gating + framing | 0 | 2 000 | 4 |
| Reproductor de vectores + infra AXIS | 0 | 1 500 | 6 |
| AXI DMA SG + interconnect | 0 | 2 500 | 4 |
| Motor de timing | 0 | 800 | 0 |
| SSI ×2 + emulador | 0 | 600 | 0 |
| **Total estimado** | **~34** | **~16 000** | **~22** |
| **Disponible en 7Z020** | 220 | 53 200 | 140 |
| **Ocupación** | 15 % | 30 % | 16 % |

Veredicto: cabe con holgura. Queda margen para 8 canales o para instrumentación en fabric. El cuello de botella no será área sino **cierre de timing a 100 MHz en grado -1** y ancho de banda de DDR.

---

## 7. Plan de fases

### Z0 — Substrato (semanas 1–2)

**Objetivo:** que exista un repositorio del que CI produzca un bitstream y un ejecutable de forma determinista, y un banco de simulación en verde. Nada de funcionalidad.

Trabajo:
- Estructura de repo: `rtl/`, `ip/` (XCI versionados), `tcl/`, `fw/`, `sim/`, `model/`, `contract/`, `docs/`.
- Flujo Vivado no-project en Tcl: `create_project -in_memory`, `read_verilog`, `read_xdc`, `create_ip`/`generate_target`, `synth_design`, `opt/place/route`, `write_bitstream`. Cero clicks.
- Paquete de parámetros único con `FS_HZ`, `IF_NORM`, `R1`, `R2`, `N_CH`, anchos de bus. Fuente única de verdad.
- Runner cocotb con doble backend (Verilator + xsim).
- Modelo dorado NumPy de la cadena DDC, con aritmética de punto fijo bit-exacta y un generador de vectores.
- **Congelado del esquema DRx↔DSP v0.1** con codegen para C (lado DRx) y para el lenguaje del DSP.
- Gates de CI: lint HDL, regresión de simulación, build de firmware, ensamblado de BOOT.BIN, tests de contrato.
- Decisión §6.1 tomada y documentada.

**Hito Z0:** CI verde sobre un diseño vacío. Un `git push` produce `BOOT.BIN` reproducible byte a byte.

### Z1 — DDC + range gating (semanas 3–8) — *tu prioridad 1*

Trabajo:
- Interfaz SSA definido y `vector_source` implementado en sus tres modos (§6.2).
- Cadena DDC: DDS Compiler + mixer complejo + CIC Compiler (N=5, R=52) + FIR Compiler (compensador de droop CIC + diezmado final ÷4).
- Conmutación de modo 125/250 m mediante etapa ÷2 adicional.
- Escalado de ganancia y saturación con reporte de overflow.
- Range gating: ensamblado de bins hasta 3689 (125 m) / 1844 (250 m), ping-pong, `TLAST` por rayo.
- Mapa de registros AXI-Lite (congelado en este punto).
- Resolución del hallazgo §4.1 con los especialistas.

**Hito ZM1 (fin S8):** vector de IF conocido inyectado → I/Q diezmada en salida que coincide **bit a bit** con el modelo NumPy, en los cuatro canales y en ambos tamaños de celda. Equivalente en ZedBoard del M1 original, menos JESD y menos DMA.

### Z2 — Motor de timing, triggers y PRF (semanas 9–13) — *tu prioridad 2*

Trabajo:
- Generador de 4 triggers configurables con retardo y ancho independientes.
- PRF programable en todo el rango (valores de registro idénticos a la ZU9).
- Selección de ancho de pulso 0,8 / 1,66 / 3,3 µs (200 / 415 / 825 ciclos a 250 MHz).
- Manejo de modos de pulso y encuadre por PRI.
- **Validador de configuración PRF × rango** (§4.2) con código de error hacia el contrato.
- Sincronización determinista trigger ↔ inicio de gating.
- Instrumentación en fabric: contador libre en un dominio de reloj distinto para auto-medir jitter y periodo.
- Salida de los 4 triggers a Pmod para medida con osciloscopio.

**Hito ZM2 (fin S13):** matriz completa PRF × ancho de pulso × modo × 4 triggers verde en simulación y en placa; jitter medido y caracterizado; combinaciones ilegales rechazadas con el código correcto.

### Z3 — Lectores SSI + tagging az/el (semanas 14–18) — *tu prioridad 3*

Estrategia de tres capas, porque una sola no da confianza:

1. **Modelo cocotb** del encoder (Gray, longitudes de palabra 13/25 bits, monoflop, timeout, errores de trama).
2. **Emulador SSI en fabric** en la propia ZedBoard, cableado físicamente Pmod JA → Pmod JB. Valida I/O real, niveles y temporización.
3. **MCU externo** como implementación independiente. Su valor no es la cobertura sino la **independencia**: detecta errores de interpretación compartida que un emulador escrito por la misma persona que el lector nunca detectaría.

Trabajo:
- Lector SSI ×2 (azimut, elevación), reloj configurable 100 kHz–2 MHz, decodificación Gray, detección de timeout y de trama corta/larga.
- Marcado temporal de la lectura y asociación al rayo correcto (esta es la parte sutil: la latencia de la lectura SSI frente al instante del trigger).
- Perfiles de movimiento de antena en el MCU: rotación constante, aceleración, wrap de 360°, parada, glitch.
- Entrada en el registro delta: **capa física LVCMOS 3.3 V vs RS-422** (§4.4).

**Hito ZM3 (fin S18):** cada rayo llega etiquetado con az/el correctos y con error temporal acotado y medido, bajo los cinco perfiles de movimiento, contra dos emuladores independientes.

### Z4 — Camino de datos, firmware y contrato (semanas 19–24) — *tu prioridad 4*

Trabajo:
- AXI DMA scatter-gather S2MM → buffers circulares en DDR del PS.
- FreeRTOS sobre Cortex-A9 (ver delta D4). Ensamblado de rayos: I/Q diezmada + metadatos (az/el, PRF, modo de pulso, ancho, contador de trigger, timestamps, mapeo de canales).
- Framing DRx↔DSP contra el esquema congelado en Z0.
- lwIP raw API sobre GEM0 (PHY Marvell 88E1518, RGMII).
- Plano de control/config completo, incluyendo aplicación de constantes de calibración.
- **Actuación AFC**: retune del NCO a partir de la estimación suministrada, verificado contra el modelo NumPy.
- Encuadre por modo de barrido: Split Cut, Batch Cut, Doppler Cut.
- Status y BITE con el catálogo de fallos adaptado (§8.4).
- Captura raw ventaneada a DDR como diagnóstico.

**Hito ZM4 (fin S24):** rayos completos consumidos por un stub de DSP sobre 1GbE, con configuración íntegra desde el par remoto y lazo AFC cerrado. Equivalente en ZedBoard de M2 + M3.

### Z5 — Endurecimiento y dossier de portabilidad (semanas 25–28)

Trabajo:
- Campañas de inyección de fallos (§8.4) y soak de 72 h.
- Campaña de throughput sintético (§7.4).
- Cierre del **registro delta de portabilidad** (§9) con evidencia por entrada.
- **Dossier de migración**: qué cambia exactamente al pasar a ZU9, fichero por fichero, con la lista de regeneraciones de IP.
- BOOT.BIN + procedimiento de provisionado de placa limpia, probado desde cero.
- Documentación.

**Hito ZM5 (fin S28):** todo lo construible sin JESD está construido, validado y documentado, y existe un plan de migración ejecutable.

### 7.4 La campaña de throughput es un ensayo aparte

Consecuencia incómoda de la dilatación: a 100 MHz la salida es `100e6/208 × 4 B × 4 ch = 7,69 MB/s = 61,5 Mbps`, muy por debajo de los 154 Mbps reales. **Los ensayos de throughput sobre el camino de fabric no son representativos.**

Solución: desacoplarlos. Una campaña específica en la que el PS genera rayos sintéticos a la tasa real de 19,23 MB/s (y a 1,5× y 2× como margen) y los transmite por GEM/lwIP con el framing real. Eso valida lo que hay que validar — pila de red, framing, gestión de buffers, latencia — sin depender del fabric dilatado.

En paralelo, un ensayo de DMA S2MM con un generador de patrones en fabric a la tasa real, para caracterizar el camino AXI-HP → DDR independientemente del DDC.

---

## 8. Plan de testing

### 8.1 Niveles

| Nivel | Qué | Herramienta | Cuándo corre |
|---|---|---|---|
| **L0** | Unidades RTL custom | cocotb + Verilator | Cada push |
| **L1** | Integración con IP de Xilinx | cocotb + xsim | Cada push (nocturno si es lento) |
| **L2** | Hardware-in-the-loop: vector → placa → comparación bit-exacta con NumPy | Runner sobre ZedBoard | Cada merge a main |
| **L3** | Subsistema: matriz de timing, perfiles SSI, throughput | Scripts + osciloscopio | Por hito |
| **L4** | Sistema: rayos end-to-end a stub de DSP | Banco completo | Por hito |

### 8.2 Suite de aceptación del DDC (autoría de los especialistas)

Cada caso se ejecuta en L0/L1 (simulación) y en L2 (placa), y ambos deben coincidir con el modelo NumPy bit a bit.

- Tono puro en el centro de banda: amplitud, fase y frecuencia de salida dentro de tolerancia.
- Barrido de tono a lo largo de toda la banda de Nyquist, incluyendo bordes y el punto de aliasing.
- Dos tonos: verificación de rechazo de imagen y de productos de intermodulación.
- Respuesta al impulso y respuesta escalón de la cadena completa.
- Verificación de la respuesta de banda de paso y de la atenuación de banda eliminada frente a la plantilla.
- Compensación de droop del CIC dentro de tolerancia.
- Comportamiento en saturación: entrada a fondo de escala, entrada sobre-escala, reporte de overflow.
- Robustez: offset DC, desbalance I/Q inyectado, ruido gaussiano a varios SNR.
- Conmutación 125 ↔ 250 m: continuidad y ausencia de artefactos en el rayo de transición.
- Retune del NCO en caliente (camino AFC): amplitud del transitorio y tiempo de asentamiento.
- Conteo de bins correcto en ambos modos y en todas las extensiones de rango.

### 8.3 Suite de timing

- Producto cartesiano: 4 triggers × 3 anchos de pulso × PRF {200, 326, 500, 651, 999, 1200} × modos de pulso.
- Jitter de trigger medido en fabric y con osciloscopio; ambos deben concordar.
- Estabilidad del periodo sobre 10⁶ PRIs.
- Alineación trigger ↔ primer bin de rango.
- Cambio de PRF en caliente: sin PRI corta ni larga espuria.
- Rechazo de combinaciones ilegales PRF × rango con el código de error correcto.

### 8.4 Catálogo de inyección de fallos (adaptado)

El original lista pérdida de link JESD, que aquí no existe. Sustitutos con la misma forma de fallo:

| Fallo del plan original | Sustituto en ZedBoard | Comportamiento esperado |
|---|---|---|
| Pérdida de link JESD204B | Underrun de la fuente de muestras (SSA) | BITE lo reporta, gating se detiene limpiamente, recuperación sin reset |
| Overrun de DMA | Idéntico: consumidor del PS ralentizado a propósito | Descarte contabilizado, sin corrupción, BITE |
| Glitch de encoder | Timeout SSI, trama corta, salto de Gray | Rayo marcado como az/el inválido, no descartado |
| Pérdida de reloj | Pérdida de lock de MMCM | BITE, parada segura |
| — | Pérdida de link Ethernet y reconexión | Reconexión sin reset de la placa |
| — | Configuración inválida desde el par remoto | Rechazo con código, estado anterior preservado |

### 8.5 Métrica de rigor

Ninguna prueba pasa por «se ve razonable». Toda salida del DDC se compara **bit a bit** con el modelo NumPy. Si hay discrepancia, o el RTL está mal o el modelo está mal; en ambos casos hay un bug real y hay que encontrarlo. Este es el beneficio concreto de sustituir el loopback analógico por un modelo dorado: el oráculo es exacto, no estadístico.

---

## 9. Registro delta de portabilidad (documento vivo desde Z0)

Análogo al «bench-vs-radar delta register» del plan original, pero para el salto ZedBoard → ZU9. Se actualiza en cada PR; nada se cierra sin una entrada aquí.

| # | Delta | Severidad | Compensación |
|---|---|---|---|
| D1 | JESD204B / GTH / SYSREF / latencia determinista / sync multi-dispositivo | **Crítica** | Ninguna posible. Requiere hardware con MGTs |
| D2 | Cierre de timing a 250 MHz vs 100 MHz | Alta | Diseño con margen; ejecutar reportes de timing con `FS_HZ` real en CI aunque no haya placa |
| D3 | Artix-7 vs UltraScale+: DSP48E1 vs E2, BRAM vs URAM, versiones de IP | Media | XCI versionados, regeneración guionizada, revisión de parámetros de IP en el dossier |
| D4 | R5 + TCM vs A9 + OCM: latencia de interrupción, arranque AMP, coherencia | Media | El PS no está en el camino del trigger (principio del plan original). Las latencias medidas en A9 **no** transfieren |
| D5 | AXI HP 64 bits vs 128 bits; sin CCI | Media | Parametrizar anchos de bus; no asumir ancho de banda |
| D6 | SSI: LVCMOS 3,3 V vs RS-422 diferencial | Media | Aislar la capa PHY tras un wrapper; **confirmar transceptores en la portadora ZU9** |
| D7 | Drivers de salida de trigger, skew y jitter reales | Media | Caracterizar en ZedBoard como cota inferior; recaracterizar en ZU9 |
| D8 | Camino DAC AD9129 / referencia Tx | Media | Solo la síntesis NCO es portable; la interfaz del DAC es trabajo nuevo |
| D9 | Frontal analógico: ruido, offset, desbalance I/Q, nivel de IF, clipping | Alta | Inyectar estas degradaciones sintéticamente en los vectores desde Z1 |
| D10 | DDR 512 MB vs varios GB, y ancho de banda | Baja | Dimensionar buffers por parámetro, no por constante |
| D11 | Throughput no representativo por dilatación | Media | Campaña sintética separada (§7.4) |

---

## 10. Riesgos propios de esta estrategia

| Riesgo | L | I | Mitigación |
|---|---|---|---|
| El riesgo #1 (JESD) queda sin retirar por tiempo indefinido | **Alta** | **Alta** | Decisión de compra (§11). No hay mitigación técnica |
| Deuda de portabilidad por relajar la disciplina de `FS_HZ`/SSA | Media | Alta | Revisión de portabilidad obligatoria en cada PR; registro delta vivo; CI falla si aparece una constante de reloj hardcodeada |
| El contrato DRx↔DSP no se congela porque el proyecto DSP va a otro ritmo | Media | Alta | Congelar v0.1 unilateralmente y versionar; negociar sobre algo concreto |
| El 7Z020-1 no cierra a 100 MHz con 4 canales | Media | Baja | Bajar a 62,5 MHz o a 2 canales; numéricamente idéntico |
| Ancho de banda de DDR insuficiente para reproducción de 4 canales | Media | Baja | Modos BRAM-loop y Throttled ya lo cubren |
| El equipo confunde «validado en ZedBoard» con «validado» | Media | Alta | El registro delta se lee en cada demo de sprint; ningún hito se declara sin él |

---

## 11. Una observación sobre la compra de hardware

Como la ZU9 + FMC213 aún no está comprada, hay una ventana que probablemente no vuelva: **la arquitectura de hardware todavía es una decisión abierta, no una restricción.** Dos cosas que valdría la pena resolver antes de firmar:

**Retirar el riesgo JESD barato y pronto.** Una plataforma con MGTs y FMC HPC de segunda mano (ZC706 con XC7Z045, o ZCU104/ZCU102 en la familia UltraScale+) permite hacer el spike de JESD204B + clocking + SYSREF de la Fase 0 con un FMC de ADC modesto, muy por debajo del coste del hardware final. Descubrir a los seis meses que el árbol de clocking elegido no da latencia determinista es el escenario que arruina el mes 8. La ZedBoard, por buena que sea para todo lo demás, no compra ni un gramo de esta tranquilidad.

**Confirmar los dos huecos del §4.** El error de celda del 0,24 % (§4.1) y la capa física de los encoders (§4.4) son ambos cuestiones que afectan a qué hardware hay que comprar. Ninguna cuesta más de una tarde de análisis. Las dos cuestan mucho después.

---

## 12. Definición de terminado (semana 28)

El firmware LAMULA DRx, sobre una ZedBoard provisionada desde cero por un BOOT.BIN construido por CI de forma reproducible, reproduce vectores de IF conocidos a través de la capa de abstracción de fuente de muestras, los baja a banda base y los diezma en la PL a I/Q compleja enrejada en rango para ambos tamaños de celda con concordancia bit a bit contra el modelo dorado, genera los cuatro triggers a la PRF y anchos de pulso configurados con jitter caracterizado, rechaza las combinaciones ilegales de PRF y rango, lee dos encoders SSI contra dos emuladores independientes y etiqueta cada rayo con azimut y elevación con error temporal acotado, ensambla los rayos bajo FreeRTOS y los transmite a un consumidor de DSP sobre GEM 1GbE conforme al esquema DRx↔DSP congelado, aplica la corrección AFC suministrada, encuadra los tres modos de barrido, reporta status y BITE bajo todas las inyecciones de fallo del catálogo, sostiene la tasa real de 19,23 MB/s en la campaña sintética de throughput, y sobrevive 72 horas de soak.

Y, explícitamente, **no** valida: el enlace JESD204B, el árbol de clocking y SYSREF, la sincronización multi-dispositivo, la tasa de 250 MSPS, el frontal analógico real, la interfaz del DAC AD9129 ni la capa física RS-422. Esos siete elementos siguen abiertos y son el contenido del trabajo sobre la ZU9.
