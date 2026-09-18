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

!!! danger "Propuesta de sustitución sobre la mesa — los dos hallazgos que la motivan ya cerraron"
    [ADR-001](adr-001-fs-r1-r2.md) propone `fs` = 143,9 MHz con R₁ = 120 y R₂ = 240, y está
    pendiente de firma. [P-01](pendientes.md#p-01) y [P-08](pendientes.md#p-08) — los dos
    hallazgos que la motivan — cerraron (P-01 el 7-sep-2026: exactitud requerida también en 125 m,
    no solo en 250 m). Lo que falta ya no es evidencia técnica, es la firma de dirección técnica y
    de compra de hardware en la tabla del propio ADR. Mientras esa tabla no esté completa, esta
    decisión sigue vigente **provisionalmente** y `config/params.toml` no se toca. El resumen es
    que R₂ = 416 declara una celda de 249 m y ORPG descarta el radial en vez de degradarlo.

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

    La lectura del código de ORPG de agosto de 2026 dice que **R₂ = 416 es la opción equivocada**,
    y por una razón más dura que el error del 0,24 %: ORPG no tiene una banda de tolerancia, tiene
    una lista blanca de espaciados. Declarar 249 m no degrada el producto, hace que el radial se
    descarte en la recombinación de super-res y que se rechacen todos los moments dual-pol. La
    sustituta sería **R₂ = 417** con cadena propia.

    Pero hay una salida mejor: **`fs` no está obligada a ser 250 MHz**. Con `fs` = 143,9 MHz,
    R₁ = 120 y R₂ = 240 dan celdas de 125,00033 m y 250,00066 m —1,2 m de error acumulado a 460 km
    frente a los 1054 m de esta decisión—, con la cadena única con etapa ÷2 intacta, un reloj que
    sale por integer-N desde la referencia de 10 MHz, y factores de diezmado sin el 13 incómodo de
    416. Ver [Pendientes, P-08](pendientes.md#p-08); depende del rate mínimo del convertidor y del
    plan de IF.

    **No cambies R₁/R₂ ni `fs` sin cerrar P-01 y P-08 y escribir el ADR que sustituya a esta
    decisión.**

## D-05 · SystemVerilog para el RTL custom; Verilator + cocotb para unidades, xsim para integración { #d-05 }

El plan original decía «VHDL/Verilog» y «Verilator + cocotb», y eso es incompatible: **Verilator no
soporta VHDL**.

| Opción | Ventaja | Coste |
|---|---|---|
| **SystemVerilog + Verilator + cocotb** (adoptada) | Simulación gratis, rápida, sin licencia en el runner de CI | El equipo debe estar cómodo en SV |
| VHDL + GHDL + cocotb | Gratis, sin licencia | GHDL con cocotb vía VPI es más frágil; menos soporte |
| Cualquiera + Vivado xsim | Un solo toolchain | Requiere licencia en el runner de CI; lento |

Dos niveles de simulación y dos herramientas: **Verilator** para las unidades (motor de timing,
SSI, gating, framing, reproductor de vectores) y **xsim** para la integración con IP de Xilinx,
porque los cores del DDC son cajas negras que Verilator no puede elaborar.

!!! warning "Enmienda del 30 de agosto de 2026 — el runner único no existe"
    Esta decisión decía «un único runner cocotb por encima» de los dos backends. **Es falso:**
    cocotb no tiene backend para xsim y nunca lo ha tenido (hallazgo
    [P-09](pendientes.md#p-09)). Lo que se mantiene de D-05 es la elección de herramientas —
    SystemVerilog, Verilator en L0, xsim en L1— y lo que cae es el runner único.

    En su lugar: **L0 sigue en cocotb sobre Verilator; L1 es SystemVerilog nativo sobre xsim**, y
    el oráculo del modelo dorado (D-03, que no se toca) cruza la frontera **por fichero** en vez de
    por VPI. `tools/gen_l1_vectors.py` escribe estímulo y salida esperada en formato `$readmemh`
    con un manifiesto que lleva la huella de `config/params.toml`; `sim/tb_sv/` los lee y compara
    bit a bit; `tcl/sim_l1.tcl` lo lanza.

    Se eligió frente a comprar licencia de Questa o Riviera (que cocotb sí soporta) porque no
    añade dependencia de licencia, y frente a escribir un backend de xsim para cocotb porque eso
    son semanas sobre la interfaz VPI de xsim. El precio es que hay dos estilos de testbench en el
    repositorio, y el mitigante es que el arnés de L1 —lector y comparador— **está verificado hoy
    sobre Verilator** en `sim/tests/test_l1_harness.py`, incluida la prueba de que sabe fallar
    cuando cambia un solo bit.

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

## D-11 · `Noise_Shaping {Taylor_Series_Corrected}` es el modo principal del NCO { #d-11 }

**Decisión, 18-sep-2026 (vladimir, en sesión):** de aquí en adelante, el DDS Compiler del NCO se
genera con `Noise_Shaping {Taylor_Series_Corrected}`, no con el modo `None` que documentaba
[P-10](pendientes.md#p-10) hasta ahora. `Output_Width` se queda en 16 — esta decisión no toca el
ancho de salida, y cambiarlo es un asunto aparte con su propio ripple (`rtl/drx_round.sv`,
`rtl/drx_ddc_mixer.sv`, `rtl/drx_ddc_top.sv`, ver [P-11](pendientes.md#p-11)).

Lo que [P-11](pendientes.md#p-11) ya había medido, contra xsim real, antes de esta decisión:

- Techo de error frente al modo `None`: de ~5,7 LSB rms a **1,15 LSB rms / 1,89 LSB pico**
  (`Output_Width=16`), −84,8/−89,1 dBc.
- `NCO_LUT_OFFSET_K` **no cambia**: 655 ya comitteado sigue siendo el valor correcto con Taylor
  (`64881 ≡ −655 mod 65536`, confirmado contra xsim real el 9-sep-2026, segunda sesión).
- Coste de recursos: +3 DSP48 / +1 RAMB18 (0,5 tile) por canal frente a `None`. Con la config de 3
  canales de ZedBoard ya decidida (ver el cierre de P-12 en `pendientes.md`), el presupuesto queda
  en 159/220 DSP48 (72 %) — margen real, no al límite.
- La reproducción bit-exacta de Taylor en el modelo dorado (`NcoTaylor` en
  `model/drx_model/nco.py`) **no cierra en sentido estricto**: residuo de hasta ±2 LSB en 25-75 %
  de las muestras, contra las 2²⁵ fases posibles del círculo completo. Es, medido, **la misma clase
  y magnitud de residuo** que el proyecto ya acepta para el modo `None` desde P-10 — no una
  regresión nueva.

**Lo que esta decisión NO resuelve**, y sigue abierto exactamente como antes:

- El número real de supresión de clutter / longitud de CPI objetivo, que es lo único que puede
  decir si el techo de Taylor (~−88/−92 dBc) alcanza para el rango dinámico intra-celda que exige
  P-11. Sigue sin responder de especialistas de dominio.
- Por lo mismo, el criterio de aceptación de L1 para el bloque NCO sigue siendo bit a bit estricto
  (D-05, `sim/tb_sv/drx_l1_checker.sv` sin tolerancia) — esta decisión **no** lo cambia a un
  criterio espectral/estadístico. El residuo de Taylor se acepta bajo el mismo argumento que ya
  rige para `None`: no bloquea Z1, pero tampoco cierra ZM1 por sí solo.

**Alcance de la migración:** `model/drx_model/chain.py` (el oráculo pasa de `Nco` a `NcoTaylor`,
huellas `GOLDEN` de `model/tests/test_chain.py` actualizadas con esta fecha) y `tcl/gen_ip.tcl`
(`CONFIG.Noise_Shaping {Taylor_Series_Corrected}` añadido al `dds_compiler_nco`). La matriz L1
completa (8 casos × 2 modos, ver [Fases, Z1](../implementacion/fases.md#z1)) queda pendiente de
volver a correr contra xsim real bajo este modo — es trabajo de Vivado, no de esta entrada.
