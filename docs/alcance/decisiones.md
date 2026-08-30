# Decisiones congeladas

Estas decisiones ya están tomadas. Ninguna se revierte sin discutirlo con el equipo, y cada
reversión obliga a revisar el [registro delta de portabilidad](../portabilidad/registro-delta.md).

## D-01 · Capa de abstracción de fuente de muestras (SSA) { #d-01 }

Todo lo que está aguas abajo del ADC se desarrolla y se valida contra un **único interfaz
AXI4-Stream de muestras con backpressure**, nunca contra la fuente concreta. Existen dos
implementaciones intercambiables: `jesd204b_source` (solo en ZU9) y `vector_source` (reproductor de
vectores).

Sin esto, el trabajo en ZedBoard es desechable. Con esto, es transferible — y la inyección de
vectores digitales pasa a ser ciudadano de primera clase también en la placa final. Detalle en
[Fuente de muestras](../plataforma/fuente-de-muestras.md).

## D-02 · Dilatación temporal uniforme mediante un único parámetro `FS_HZ` { #d-02 }

Un solo paquete de parámetros define `FS_HZ` y de él se derivan todos los divisores, anchos de
contador, palabras de fase del NCO, factores de diezmado y valores de registro. **Se dilata todo por
igual, nunca solo una parte.** El reloj de fabric objetivo en ZedBoard es 100 MHz.

Consecuencia buscada: los testbenches, los vectores de estímulo y los valores esperados son bit a
bit los mismos en ambas plataformas. Detalle y tabla de correspondencia en [Dilatación
temporal](../plataforma/dilatacion-temporal.md).

**El CI falla si aparece una constante de reloj hardcodeada.** No es un lint cosmético: es la única
defensa contra que la deuda de portabilidad se acumule en silencio.

## D-03 · Modelo dorado en Python como oráculo principal { #d-03 }

La ZedBoard no tiene loopback DAC→ADC, que era el oráculo del plan original. El sustituto es un
modelo de referencia en NumPy de toda la cadena DDC, **bit-exacto en aritmética de punto fijo**.

Es mejor en precisión y peor en realismo. Ninguna prueba pasa por «se ve razonable»: toda salida del
DDC se compara bit a bit contra el modelo. Detalle en [Modelo dorado](../pruebas/modelo-dorado.md).

## D-04 · Factores de diezmado R₁ = 208, R₂ = 416 { #d-04 }

A 250 MSPS cada muestra cubre 0,5996 m de rango, y **no existe un R entero que dé exactamente
125 m ni 250 m**. Se adopta R₁ = 208 y R₂ = 416, lo que da celdas de 124,71 m y 249,41 m — error
de −0,24 %, unos 0,6 m en la celda grande — y mantiene R₂ = 2·R₁, es decir una sola cadena con una
etapa ÷2 conmutable.

Conteo de bins resultante: **3689 bins** a 124,71 m y **1844 bins** a 249,41 m, frente a los
3680/1840 del plan original, que asumía celdas exactas.

!!! danger "Congelada provisionalmente, pendiente de los especialistas"
    Esta decisión está congelada para poder escribir RTL, **no** porque el requisito esté
    resuelto. Si el producto ORPG exige 125/250 m exactos hay que ir a remuestreo fraccionario
    (Farrow) o a otra fs, y eso cambia el presupuesto de DSPs y la arquitectura. Ver
    [Pendientes, P-01](pendientes.md#p-01).

## D-05 · SystemVerilog para el RTL custom; Verilator + cocotb para unidades, xsim para integración { #d-05 }

El plan original decía «VHDL/Verilog» y «Verilator + cocotb», y eso es incompatible: **Verilator no
soporta VHDL**.

| Opción | Ventaja | Coste |
|---|---|---|
| **SystemVerilog + Verilator + cocotb** (adoptada) | Simulación gratis, rápida, sin licencia en el runner de CI | El equipo debe estar cómodo en SV |
| VHDL + GHDL + cocotb | Gratis, sin licencia | GHDL con cocotb vía VPI es más frágil; menos soporte |
| Cualquiera + Vivado xsim | Un solo toolchain | Requiere licencia en el runner de CI; lento |

Dos niveles de simulación, dos herramientas, un único runner cocotb por encima: **Verilator** para
las unidades (motor de timing, SSI, gating, framing, reproductor de vectores) y **xsim** para la
integración con IP de Xilinx, porque los cores del DDC son cajas negras que Verilator no puede
elaborar.

## D-06 · Xilinx-IP-first, HDL custom solo donde no hay IP { #d-06 }

JESD204B, DDS/CIC/FIR Compiler, AXI DMA, AXI Timer/GPIO. El HDL custom se reserva para el motor de
timing, los lectores de encoder, el pegamento de framing de rayos y lo que ninguna IP cubra. Esto es
lo que hace el alcance viable para tres personas.

## D-07 · Flujo Vivado no-project en Tcl y CI desde la semana 1 { #d-07 }

Cero clicks. `create_project -in_memory`, `read_verilog`, `read_xdc`, `create_ip`/`generate_target`,
`synth_design`, `opt/place/route`, `write_bitstream`. Los XCI van versionados y la regeneración de
IP está guionizada.

Cuesta unas dos semanas hacerlo bien al principio y cuesta un mes de reconstrucción hacerlo al
final. **Va en Z0**, no al cierre, corrigiendo el orden de prioridades original que lo ponía último.

## D-08 · El esquema DRx↔DSP se congela en Z0, separado de su implementación { #d-08 }

Hay que separar dos cosas: *definir el esquema* (semanas 1–2, coste bajo, dependencia externa alta)
e *implementar el transporte* (más tarde, coste medio, dependencia nula). El esquema es un punto de
sincronización entre proyectos; cuanto más tarde se congele, más caro es el rebote.

Si el equipo DSP no está listo, **se congela unilateralmente una v0.1 versionada** y se negocia
sobre algo concreto en lugar de sobre nada.

## D-09 · Validación de combinaciones PRF × extensión de rango { #d-09 }

El rango no ambiguo es `c / (2·PRF)`. El plan original enumeraba «PRF 200–1200 Hz» y «alcance hasta
460 km» como si fueran independientes, y no lo son:

| PRF | Rango máximo no ambiguo |
|---|---|
| 200 Hz | 749,5 km |
| 326 Hz | **460 km** ← límite para el modo de reflectividad |
| 651 Hz | 230 km |
| 999 Hz | 150 km |
| 1200 Hz | 124,9 km |

Es decir, **460 km a 1200 Hz es físicamente imposible**. De aquí sale un requisito que no estaba en
el plan original: el manejador de configuración **debe validar y rechazar** las combinaciones
ilegales, reportarlo por el plano de status/BITE y devolver un código de error definido en el
contrato DRx↔DSP. Es un caso de prueba de aceptación y se implementa entero en ZedBoard.

## D-10 · La campaña de throughput es un ensayo aparte { #d-10 }

A 100 MHz la salida de fabric es `100e6/208 × 4 B × 4 ch = 7,69 MB/s = 61,5 Mbps`, muy por debajo
de los 154 Mbps reales. Los ensayos de throughput sobre el camino de fabric dilatado **no son
representativos** y hay que desacoplarlos. Ver [Fases, Z5](../implementacion/fases.md#throughput).
