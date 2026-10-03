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

**Cerrado en RTL, 22-sep-2026 (más tarde, tercera sesión):** `r_max_required_m` se fijó en 460 km
(lote de vigilancia/reflectividad) y 115 km (lote Doppler) — valores estándar WSR-88D/NEXRAD, el
primero ya coincidía con la fila "326 Hz → 460 km" de la tabla de arriba. `rtl/
drx_timing_config_valid.sv` rechaza en fabric las tres condiciones (pulse_width fuera de tabla, no
cabe en su PRI, `prf_div` bajo el piso de rango de su lote), gateando `enable` de
`drx_prf_batch_seq.sv` — ver `docs/implementacion/fases.md#z2`. **Con matiz:** el piso del lote
alto (115 km → `prf_div_min_high=191800`) queda por debajo del techo de PRF ya congelado
(`prf_div_min=208333`, 1200 Hz), así que no rechaza nada con los límites de PRF de hoy — se deja
implementado igual, por si ese techo cambia. Lo que sigue sin decidirse: el código de error del
contrato hacia el DSP (alcance de Z4).

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

## D-12 · El residuo de cuantización del NCO se acepta como techo documentado; L1 deja de exigirle bit a bit { #d-12 }

**Decisión, 19-sep-2026 (vladimir, en sesión):** el residuo que [P-11](pendientes.md#p-11) viene
midiendo contra xsim real bajo `Taylor_Series_Corrected` —hasta ±5 LSB por muestra I/Q, en 14 de
las 16 combinaciones de la matriz `tono_*` × {fine, coarse} del 18/19-sep-2026— se acepta como el
techo normal del bloque NCO, no como un defecto pendiente de corregir. El criterio de aceptación de
L1 para ese residuo concreto deja de ser bit a bit estricto (D-05) y pasa a ser:

> **Discrepancia ≤ 5 LSB por muestra I/Q**, frente al modelo dorado, para el bloque NCO/mezclador
> bajo `Taylor_Series_Corrected`.

Con esto:

- Las 16 combinaciones ya corridas de la matriz de [P-11](pendientes.md#p-11) pasan bajo el nuevo
  criterio: 14 dentro de la banda ±0-5 LSB ya documentada, 2 (`tono_con_offset_dc`, ambos modos)
  exactas bit a bit.
- [ZM1](../implementacion/fases.md#z1) puede darse por cumplido bajo este criterio en cuanto se
  actualice el comparador (ver "lo que falta" abajo) — ni el RTL ni los vectores cambian por esta
  decisión.
- D-05 se mantiene sin cambio para todo lo demás: framing (`TLAST`), range gating y cualquier
  bloque sin cuantización de fase de por medio siguen exigiendo coincidencia bit a bit estricta.
  Esta es una excepción puntual para el residuo del NCO, no un cambio general del criterio de L1.

**Lo que esta decisión NO resuelve:**

- Confirmar que el techo de Taylor (~−88/−92 dBc) alcanza para el rango dinámico intra-celda es un
  dato de dominio aparte, no derivado de aceptar el residuo — ver el cierre de
  [P-11](pendientes.md#p-11) el mismo día.
- La varianza de los estimadores de momento (reflectividad, velocidad, ancho espectral) que resulta
  de este residuo, frente a la teoría de Doviak & Zrnic cap. 6, no se evalúa aquí. Esta decisión fija
  el techo aceptado del bloque NCO; no certifica su efecto en los productos finales del radar — ver
  el hallazgo nuevo [P-14](pendientes.md#p-14).

**Lo que falta para que esto sea más que una decisión de producto:** `sim/tb_sv/drx_l1_checker.sv`
hoy compara bit a bit sin tolerancia ("No hay tolerancia, no hay ventana", cabecera del fichero).
Para que `make check` / `tcl/sim_l1.tcl` apliquen de verdad este criterio hace falta añadirle un
parámetro de tolerancia en LSB (por defecto 0, para no tocar ningún testbench que siga exigiendo
bit a bit) y volver a correr la matriz de 16 combinaciones contra xsim real para confirmar que con
esa tolerancia las 16 dan «pass». **No se ha hecho todavía** — es el trabajo pendiente concreto que
deja esta decisión.

## D-13 · Motor de timing de Z2: 2 lotes de PRF/ancho de pulso por radial (Batch mode de NEXRAD) { #d-13 }

**Decisión, 21-sep-2026 (vladimir, en sesión):** el motor de timing de [Z2](../implementacion/fases.md#z2)
se diseña para soportar **exactamente 2 lotes de PRF/ancho de pulso por radial**, no un único par
global (como decía el "Trabajo" original de Z2) ni una tabla genérica de N entradas por sector
azimutal (como especulaba [P-04](pendientes.md#p-04)).

Esto cierra [P-04](pendientes.md#p-04): el VCP objetivo usa **Batch mode** de NEXRAD, que alterna PRF
**dentro del *dwell time* de cada radial** (~10-15 ms) — un lote corto de PRF baja (vigilancia, pocos
pulsos, ej. 4-6, para reflectividad a rango largo sin ambigüedad) seguido de un lote de PRF alta
(Doppler, muchos pulsos, ej. 30-40, para velocidad/ancho espectral con buen Nyquist pero rango
ambiguo menor) — en bucle continuo durante los 360° de esa elevación. Es más fino que "por sector":
ocurre a la cadencia de un radial, no de varios grados de azimut.

Consecuencias para el diseño de Z2:

- El generador de triggers necesita 2 perfiles de PRF/ancho de pulso configurables por registro, con
  conteo de pulsos por lote, secuenciados de forma **autónoma en fabric** — el RCP no puede comandar
  esto en vivo por 1GbE a la cadencia de un radial (10-15 ms de *dwell*, órdenes de magnitud más
  rápido que la latencia de red razonable).
- El validador PRF×rango de [D-09](#d-09) se aplica **a cada lote por separado**: el rango
  no-ambiguo del lote de PRF baja y el del lote de PRF alta son distintos por diseño — ese es el
  punto de Batch mode — así que un único par PRF/rango por configuración no basta para validar la
  combinación completa.
- El metadato por rayo ya contempla PRF y modo de pulso ([Z4](../implementacion/fases.md#z4)), pero
  si el conteo de bins de range-gate necesita diferir entre lotes dentro del mismo radial, eso es
  alcance nuevo de Z2 a resolver cuando se diseñe esa pieza — no lo resuelve esta decisión.
  **Sí difiere, y se resolvió en [D-15](#d-15), 25-sep-2026: BINS_LOW/BINS_HIGH, un registro por
  lote.**

**Lo que esta decisión NO resuelve:**

- Las PRF exactas y el número de pulsos por lote de cada VCP de Gematronik: son valores de
  configuración en tiempo de ejecución (registro), no constantes de `config/params.toml`.
- El mensaje `config` del contrato DRx↔DSP (congelado en Z0, [D-08](#d-08)) sigue teniendo un solo
  `prf_div`/`pulse_width_idx`, no dos — ver [P-15](pendientes.md#p-15). Se resuelve con el mapa de
  registros de Z2, no aquí.
- Si el range-gate necesita dos configuraciones de bins simultáneas (una por lote) dentro de un
  mismo radial, o si un solo conjunto de bins alcanza para los dos — pendiente de diseño.
  **Resuelto en [D-15](#d-15): sí, dos registros, BINS_LOW/BINS_HIGH.**
- Sincronización entre el cambio de lote del motor de timing y la lectura de azimut/elevación de
  [Z3](../implementacion/fases.md#z3) — cada lote dentro del mismo radial comparte az/el, pero el
  diseño concreto del tagging todavía no existe.

## D-14 · El corte de rayo de range-gate se resincroniza con cada pulso de PRF { #d-14 }

**Decisión, 22-sep-2026 (en sesión):** `drx_range_gate` gana un puerto `ray_start` (pulso de un
ciclo) que fuerza su puntero de escritura a 0. `drx_top` lo conecta a `pulse_trig` de
`drx_timing_engine` (D-13): cada pulso de PRF, de cualquiera de los 2 lotes, arranca un rayo nuevo
en el range-gate, en vez de dejar que el contador libre de bins decida por su cuenta dónde cortar.

Esto resuelve el hueco que dejaba abierto la integración del mapa de registros v3
([P-15](pendientes.md#p-15), Z2): con la entrada del DDC muestreando sin parar y sin ningún
concepto de "tiempo muerto" entre pulsos, `drx_range_gate` free-run trocearía ese hueco como si
fuera parte de un rayo real. De las tres opciones consideradas en sesión (resync por hardware en
cada pulso; alineación solo por configuración, confiando en que `PRF_DIV` sea múltiplo exacto de
`bins`; o un wrapper a nivel `drx_top` que solo adjunta metadatos sin tocar `drx_range_gate`), se
eligió la primera: es la única que fija sin ambigüedad qué significa "bin 0" (el instante del
disparo), las otras dos dejan esa definición implícita o dependiente de un invariante que nada
comprueba.

Un `ray_start` que llega con el puntero de escritura ya a mitad de rayo (tiempo muerto acumulado, o
un PRI configurado más corto que `bins` — D-09 no se valida en RTL, ver la cabecera de
`drx_prf_batch_seq.sv`) **descarta** ese banco en curso sin marcarlo como pendiente: nunca sale
como un rayo corto o corrupto, simplemente no sale. Solo el camino ya existente (alcanzar `bins`
muestras reales) produce un rayo válido; `ray_start` decide únicamente dónde empieza el próximo
intento.

Es un cambio aditivo sobre RTL ya cerrado bajo [D-12](#d-12): con `ray_start` en bajo (el estado de
toda la matriz L1 ya corrida) el comportamiento es bit a bit idéntico al de antes del puerto, así
que no hizo falta modelo dorado nuevo ni vectores nuevos — solo reconfirmar contra xsim real que
`tb_l1_ddc_range_tri.sv` (el único testbench L1 que instancia `drx_range_gate`) sigue en verde con
el puerto añadido y atado a 0. El comportamiento nuevo (`ray_start` en alto) se verifica en L0
(`sim/tb/tb_drx_range_gate.py`), sin equivalente en el modelo dorado: es una característica de
interlock de hardware, no un bloque numérico con oráculo de valores.

**Lo que esta decisión NO resuelve:**

- Si `drx_range_gate` necesita un conteo de bins distinto por lote — ya lo deja abierto
  [D-13](#d-13), sin relación con esta sincronización. **Cerrado por [D-15](#d-15), 25-sep-2026.**
- Si `pulse_trig` debe disparar también algo del lado Tx (`vector_source` u otra fuente) — ese lado
  no existe todavía en este repo.
- Diagnóstico del tiempo muerto descartado: hoy no hay ningún contador ni bit de BITE que distinga
  "PRI bien calibrado, `ray_start` llegó justo cuando tocaba" de "`ray_start` llegó tarde y truncó
  un rayo en curso". **Cerrado, 25-sep-2026 (más tarde): `ray_truncated` por canal (GATE_TRUNCATED,
  mapa v6)** — ver la entrada correspondiente en [`fases.md#z2`](../implementacion/fases.md#z2). Es
  independiente de D-09, que desde [D-15](#d-15) (25-sep-2026) sí se aplica completo en RTL,
  incluido el conteo de bins.

## D-15 · Conteo de bins de range-gate por lote: registro configurable en runtime, no una elección fino/grueso { #d-15 }

**Decisión, 25-sep-2026 (en sesión):** el conteo de bins que `drx_range_gate` usa para cortar cada
rayo deja de ser `BINS_MODE_FINE`/`BINS_MODE_COARSE` (3689/1844, `config/params.toml`) elegidos por
`mode_coarse`, y pasa a ser un **registro por lote** (`BINS_LOW`/`BINS_HIGH`, mapa v5) — el mismo
patrón que ya tienen `PRF_DIV_LOW`/`PRF_DIV_HIGH` y `PULSE_WIDTH`/`N_PULSES` desde D-13.

Confirmado por vladimir: el conteo de bins es configurable, y llega a DRx a través de DSP, que a su
vez lo recibe de RCP — la proporción entre el rango del lote bajo (vigilancia) y el del lote alto
(Doppler) nunca es la misma, y esa proporción la fija el VCP en curso, no un valor congelado del
proyecto. Esto cierra el punto que D-13 dejaba explícitamente abierto ("si el conteo de bins de
range-gate necesita diferir entre lotes dentro del mismo radial, eso es alcance nuevo de Z2") y el
mismo punto que D-14 también dejaba sin resolver.

Consecuencias para el diseño:

- `mode_coarse` (CTRL bit 0) deja de llegar a `drx_range_gate` — sigue existiendo, pero solo para
  `drx_ddc_quad_top` (decimación/tamaño de celda), un eje independiente del conteo de bins.
  `drx_range_gate`/`drx_range_gate_quad_top` ganan un puerto `bin_count` (no `bins`: SystemVerilog
  reserva esa palabra para coverpoints/randomize, Verilator la rechaza como identificador) que lo
  reemplaza por completo en ese módulo.
- El conteo ACTIVO (el del lote que está corriendo en cada instante) lo compone `drx_prf_batch_seq`:
  gana `bins_low`/`bins_high` como entradas y `bin_count` como salida, con el mismo mux combinacional
  que ya usaba para `pulse_width` (seleccionado por `batch_sel`) — no hace falta ningún registro ni
  lógica nueva de "cuál lote está activo", ya existía para otra señal.
- El techo físico (D-09, la profundidad real de la BRAM de `drx_range_gate`, `BINS_MODE_FINE`) SÍ se
  valida en RTL: `drx_timing_config_valid.sv` gana un cuarto check
  (`bin_count >= 1 && bin_count <= BinsMax`), con el mismo gateo de `enable` que ya usan los otros
  tres. A diferencia del piso de rango de D-09 (que sí difiere por lote), el techo es el MISMO
  requisito físico para los dos lotes — una sola BRAM real — así que las dos instancias de
  `drx_timing_config_valid` comparten el mismo `BinsMax` por defecto (`BINS_MODE_FINE`).
- `BinsMax` es un PARÁMETRO, no un registro, mismo argumento que el piso de PRF de D-09: es un
  requisito fijo de hardware (la BRAM no cambia de tamaño en runtime), no algo que el DSP configure
  — por eso el mapa de registros sube a v5 solo por los dos registros nuevos (BINS_LOW/HIGH) y el
  cambio de semántica de CTRL bit 0, no por el techo en sí.

Es un cambio aditivo sobre el comportamiento de `drx_range_gate` cerrado bajo [D-12](#d-12) en el
sentido de que no reordena ni transforma ningún dato — solo cambia de dónde sale el conteo de bins
(de una constante de compilación seleccionada por `mode_coarse`, a un registro de entrada) — pero
**no es bit a bit transparente por defecto** como lo fue D-14 (`ray_start`): con `BINS_MODE_FINE`
como profundidad real de BRAM sin cambios, cualquier `bin_count` igual al valor que antes producía
`mode_coarse` reproduce el mismo comportamiento; verificado reconfirmando `tb_l1_ddc_range_tri.sv`
(xsim real, corrida completa) con `bin_count` derivado del mismo `+mode=` de siempre — fine:
288/288/288 muestras en tolerancia D-12 y TLAST bit a bit en los tres canales; coarse: 144/144/144 —
las mismas cifras que ya medía D-14.

**Lo que esta decisión NO resuelve:**

- Qué código de error del contrato DRx↔DSP reportar cuando `BINS_LOW`/`BINS_HIGH` es inválido — sigue
  siendo alcance de Z4, igual que el resto de D-09 (ver [P-15](pendientes.md#p-15)).
- Diagnóstico de tiempo muerto / BITE que D-14 ya dejaba abierto — sin relación con este cambio.
- P&R real con este cambio — no se corrió en esta sesión (lógica combinacional adicional de bajo
  costo dentro de un módulo ya cerrado; la última cifra medida sigue siendo la de D-09/v4).

## D-16 · El transporte DRx↔DSP es una sola conexión TCP, con el DRx escuchando { #d-16 }

**Decisión, 2-oct-2026 (en sesión):** el contrato DRx↔DSP viaja sobre **una única conexión TCP**
que lleva los dos sentidos. El **DRx escucha** en `tcp_port` (9470, constante del propio esquema) y
el **DSP conecta**. Cierra el hueco que [D-08](#d-08) dejó abierto a propósito al congelar el
esquema sin implementar el transporte.

Hasta hoy no había ninguna decisión escrita: el esquema no menciona TCP, UDP ni puerto, y lo único
dicho en el repo era «GEM 1GbE». Eso bastaba mientras nadie abría un socket; Z4.6 es justo el paso
que lo hace.

**TCP y no UDP.** El framer del DRx (`fw/src/app/drx_contract_io.c`, Z4.3) es incremental, con
buffer de reensamblado: está escrito para un flujo de bytes y no supone que un `recv` traiga un
mensaje entero. Montarlo sobre datagramas obligaría a reescribirlo y a inventar reordenación y
reintento en el contrato, que hoy no los tiene — no hay ventana de recepción, ni ACK de rayo, ni
hueco para retransmitir. El caudal no obliga a lo contrario: 231 rayos/s × 44 KB son ~80 Mbps, con
sitio de sobra en 1GbE. El argumento habitual a favor de UDP en datos de radar —evitar el bloqueo
de cabeza de línea— se aplica cuando llegar tarde es peor que no llegar; aquí el consumidor es un
DSP que integra radiales, y perder uno en silencio es peor que recibirlo con jitter.

**Una conexión, no dos.** Separar control y datos en dos sockets añade un estado de emparejamiento
—qué conexión de control manda sobre qué conexión de datos— sin resolver nada: el contrato ya
distingue sentido y tipo en la cabecera de cada mensaje, y `DrxFrame_IsDownstream` ya existe.

**El DRx escucha.** El receptor no necesita conocer la dirección del DSP, que es una cosa menos que
configurar en placa y una menos que equivocar. También hace el bring-up reproducible: el cliente de
mentira (`tools/mock_dsp.py`) conecta y se va cuantas veces haga falta sin reiniciar la placa. La
alternativa —el DRx conectando hacia un colector— obliga a reconfigurar y rearrancar el receptor
cada vez que cambia el host del DSP.

**El puerto vive en el esquema, no en el firmware.** Es exactamente lo que las dos puntas tienen
que acordar, así que duplicarlo a mano en el C del DRx y en el cliente del DSP es la clase de
desacuerdo que no da ningún síntoma hasta que nadie conecta. Se genera a C, Python y Rust como
`DRX_DSP_TCP_PORT` / `TCP_PORT`. Sube `version_minor` a 8 aunque no cambie ni un byte del formato
de cable: cambia el documento que las dos partes firman.

**Lo que esta decisión NO resuelve, y hay que decirlo:** qué pasa cuando el DSP no lee lo bastante
rápido. Hoy `DrxRay_SetSink` devuelve `false` y el rayo se cuenta en `sink_drops` — descartar el
rayo nuevo, no bloquear la tarea de rayos ni crecer sin límite. Es la única opción que no rompe el
tiempo real, pero significa que una congestión de red se traduce en huecos de radial, y el contrato
no tiene hoy forma de avisar al DSP de cuántos se perdieron. Anotado como trabajo de Z5 junto con
[P-17](pendientes.md#p-17); no bloquea el cierre de ZM4, que es demostrar el camino completo.

