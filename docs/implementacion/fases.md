# Plan de fases Z0–Z5

**Horizonte:** 28 semanas, en paralelo al plan original de 34 semanas para la ZU9.
Cadencia de dos semanas por sprint. Demos al final de cada sprint a los especialistas, que son
dueños de la aceptación.

| Fase | Semanas | Foco | Hito de salida |
|---|---|---|---|
| [Z0](#z0) | 1–2 | Substrato: repo, CI, flujo Tcl, modelo dorado, contrato v0.1 | ZM0 — CI verde sobre diseño vacío |
| [Z1](#z1) | 3–8 | DDC + range gating | ZM1 — coincidencia bit a bit con el modelo |
| [Z2](#z2) | 9–13 | Motor de timing, triggers y PRF | ZM2 — matriz de timing verde, jitter caracterizado |
| [Z3](#z3) | 14–18 | Lectores SSI + tagging az/el | ZM3 — rayos etiquetados con error temporal acotado |
| [Z4](#z4) | 19–24 | Camino de datos, firmware y contrato | ZM4 — rayos consumidos por el DSP, AFC cerrado |
| [Z5](#z5) | 25–28 | Endurecimiento y dossier de portabilidad | ZM5 — todo lo construible sin JESD, validado |

## Z0 — Substrato (semanas 1–2) { #z0 }

**Objetivo:** que exista un repositorio del que el CI produzca un bitstream y un ejecutable de forma
determinista, y un banco de simulación en verde. **Nada de funcionalidad.**

Trabajo:

- Estructura de repo: `rtl/`, `ip/` (XCI versionados), `tcl/`, `fw/`, `sim/`, `model/`, `contract/`,
  `docs/`. Ver [Estructura del repositorio](estructura-repo.md).
- Flujo Vivado no-project en Tcl: `create_project -in_memory`, `read_verilog`, `read_xdc`,
  `create_ip`/`generate_target`, `synth_design`, `opt/place/route`, `write_bitstream`. Cero clicks.
- Paquete de parámetros único con `FS_HZ`, `IF_NORM`, `R1`, `R2`, `N_CH` y anchos de bus. Fuente
  única de verdad — ver [Dilatación temporal](../plataforma/dilatacion-temporal.md).
- Runner cocotb con doble backend, Verilator y xsim.
- Modelo dorado NumPy de la cadena DDC, con aritmética de punto fijo bit-exacta, y un generador de
  vectores.
- **Congelado del esquema DRx↔DSP v0.1** con codegen para C (lado DRx) y para el lenguaje del DSP.
- Gates de CI: lint HDL, regresión de simulación, build de firmware, ensamblado de `BOOT.BIN`, tests
  de contrato.
- Decisión de lenguaje y simulador tomada y documentada
  ([D-05](../alcance/decisiones.md#d-05)).

**Hito ZM0:** CI verde sobre un diseño vacío. Un `git push` produce un `BOOT.BIN` reproducible byte
a byte.

!!! info "Estado a 5 de septiembre de 2026"
    El flujo completo (`tcl/build.tcl`, `tcl/sim_l1.tcl`, `tools/make_boot.sh`) ya corrió de punta a
    punta, a mano, en una máquina de desarrollo con Vivado 2022.2 — bitstream con WNS = 5,850 ns,
    simulación L1 sin bugs de infraestructura conocidos (ver
    [P-09](../alcance/pendientes.md#p-09)), empaquetado de `BOOT.BIN` fallando exactamente donde
    corresponde por los entregables de Z4 que aún no existen. **El hito tal como está definido
    arriba sigue sin cumplirse**: todavía no hay runner de CI con Vivado (`HAS_VIVADO_RUNNER`, ver
    A7/A8 en `pendientes.md`), así que el `git push` no produce el `BOOT.BIN` — lo produce una
    persona ejecutando el flujo a mano.

!!! info "Por qué el CI va primero y no al final"
    El modelo de entrega acelerado por agentes es el argumento central de viabilidad para un equipo
    de tres personas, y ese modelo no funciona si el diseño vive en un proyecto GUI de Vivado: los
    agentes no pueden operar sobre él, las builds no son reproducibles y la regresión no existe.
    Cuesta unas dos semanas hacerlo bien ahora y un mes de reconstrucción hacerlo al final.

## Z1 — DDC + range gating (semanas 3–8) { #z1 }

Trabajo:

- Interfaz SSA definido y `vector_source` implementado en sus tres modos
  ([Fuente de muestras](../plataforma/fuente-de-muestras.md)).
- Cadena DDC: DDS Compiler + mixer complejo + CIC Compiler (N=5, R=52) + FIR Compiler (compensador
  de droop del CIC + diezmado final ÷4).
- Conmutación de modo 125/250 m mediante una etapa ÷2 adicional.
- Escalado de ganancia y saturación con reporte de overflow.
- Range gating: ensamblado de bins hasta 3689 (125 m) / 1844 (250 m), ping-pong, `TLAST` por rayo.
- Mapa de registros AXI-Lite, **congelado en este punto**.
- Resolución del hallazgo del tamaño de celda con los especialistas
  ([P-01](../alcance/pendientes.md#p-01)).
- Publicación de los números reales de `report_utilization`, sustituyendo la estimación de
  [Presupuesto de recursos](../plataforma/recursos.md).
- Inyección deliberada de degradaciones analógicas en los vectores — ruido, offset DC, desbalance
  I/Q, clipping — desde esta fase, para no descubrirlas en la ZU9
  ([D9](../portabilidad/registro-delta.md)).

**Hito ZM1 (fin S8):** un vector de IF conocido inyectado produce I/Q diezmada en salida que coincide
**bit a bit** con el modelo NumPy, en ambos tamaños de celda. Es el equivalente en ZedBoard del M1
original, menos JESD y menos DMA.

!!! success "9-sep-2026: dos configuraciones de 3 canales en vez de 4, en la ZedBoard"
    El presupuesto de DSP48 medido contra Vivado real ([P-12](../alcance/pendientes.md#p-12)) deja 4
    canales sin compartir al 91 % (200/220), sin margen para Z2/Z3/DMA. Decisión, ver la entrada de
    cierre de P-12: la muestra de Tx tiene su propia cadena independiente (no compartida con un canal
    Rx — el transitorio del CIC+FIR compartido crearía una zona ciega de rango cercano de varios km),
    y en la ZedBoard (plataforma experimental, no la portadora real) ZM1 se demuestra sobre **dos
    configuraciones de 3 canales**, no sobre los 4-5 canales reales del frontal a la vez:

    - **Config A** — Tx + H + V.
    - **Config B** — Tx + canal nominal + canal atenuado, una sola polarización.

    La combinación completa (4-5 canales reales simultáneos) se prueba en la ZU9, donde el margen de
    DSP48/BRAM es mucho mayor.

    **Corrección, mismo día (esta entrada quedó obsoleta en cuestión de horas):** lo de abajo decía
    que hacía falta un top-level nuevo para las dos configs de 3 canales heterogéneos. Es falso —
    quedó resuelto el mismo 9-sep-2026 sin escribir ningún módulo nuevo: `rtl/drx_ddc_quad_top.sv`
    es genérico en `N_CH` (su `generate` no distingue Rx de Tx), así que instanciarlo con `N_CH=3`
    ya es el top-level de Config A/B. Ídem `rtl/drx_range_gate_quad_top.sv`. Detalle completo, con
    las corridas reales contra xsim que lo confirman (`tb_l1_ddc_tri.sv`,
    `tb_l1_ddc_range_tri.sv`), en el cierre de [P-12](../alcance/pendientes.md#p-12), punto 1.

!!! success "16-sep-2026: degradaciones analógicas inyectadas en los vectores L1, verificadas contra xsim real"
    `tools/gen_l1_vectors.py::_cases()` suma cuatro casos a los cuatro ya existentes, cada uno con
    una sola degradación deliberada sobre un tono ya cubierto — los mismos parámetros que ya usan
    `model/tests/test_chain.py` y `model/tests/test_gating_y_vectores.py`, para que L1 caracterice
    contra la IP real justo lo que L0 ya caracteriza contra el modelo:

    - `tono_con_ruido` — AWGN a SNR = 10 dB.
    - `tono_con_offset_dc` — offset de continua a −12 dBFS sobre un tono a −6 dBFS.
    - `tono_desbalanceado` — desbalance I/Q de un frontal en cuadratura (1 dB / 3°), aplicado en
      banda base antes de subir a IF. El desplazamiento en banda base usado es 0,001 (el mismo que ya
      usa `tono_desplazado`), no el 0,01 del test de `vectors.py` — comprobado contra el modelo antes
      de fijarlo: 0,01 cae fuera de la banda de paso de esta cadena de diezmado y el DDC lo deja en
      cero, así que no serviría como caso de aceptación.
    - `tono_sobre_escala` — entrada a +6 dBFS: el ADC real satura, no envuelve.

    **Corridos los cuatro en modo fino contra xsim real** (`tcl/sim_l1.tcl`, IP de Xilinx, no el
    modelo solo):

    | Caso | Discrepancias | Lectura |
    |---|---|---|
    | `tono_con_ruido__fine` | 56/315 (18 %) | ±2-3 LSB — misma clase de residuo que [P-10](../alcance/pendientes.md#p-10) |
    | `tono_con_offset_dc__fine` | **0/315** | exacto bit a bit |
    | `tono_desbalanceado__fine` | 60/315 (19 %) | ±2-3 LSB — misma clase |
    | `tono_sobre_escala__fine` | 307/315 (97 %) | degenerado (Q≈0 en régimen permanente), igual que `tono_if__fine` sin saturar — la saturación en sí no introduce nada nuevo, el residuo es el del NCO ya conocido |

    Ninguna discrepancia es un bug nuevo: todas caen en la misma clase de residuo de cuantización del
    NCO que [P-10](../alcance/pendientes.md#p-10) ya documentó y aceptó como suelo del propio bloque,
    no en el mecanismo de la degradación inyectada.

!!! success "18-sep-2026: matriz completada — modo grueso (`__coarse`) de los cuatro casos, mismo patrón que P-12"
    Los cuatro casos ya se habían corrido en modo `__coarse` contra xsim real el propio 16-sep-2026,
    en la misma sesión que cerró el bloque anterior — quedó sin documentar. Verificado antes de
    escribir esta entrada que `rtl/`, `tcl/`, `config/`, `ip/`, `sim/`, `model/` y `tools/` no
    cambiaron una línea desde ese commit (`git diff --stat b762171 HEAD` vacío para esos directorios),
    así que los resultados siguen siendo válidos contra el árbol actual — no hubo que volver a
    correrlos. Contraste adicional: `tono_if__coarse` (3/157), `dos_tonos__coarse` (7/157) y
    `tono_desplazado__coarse` (18/157), ya documentados en [P-10](../alcance/pendientes.md#p-10) y en
    el mensaje del commit `21ba516`, coinciden cifra a cifra con los logs recuperados — confirma que
    son corridas genuinas de este mismo flujo, no artefactos de otra cosa.

    | Caso | Discrepancias | Lectura |
    |---|---|---|
    | `tono_con_ruido__coarse` | 20/157 (13 %) | ±2-5 LSB — misma clase de residuo que [P-10](../alcance/pendientes.md#p-10); proporción menor que en fino (18 %), consistente con menos muestras y distinta fase de aliasing del residuo del NCO, no con un mecanismo nuevo |
    | `tono_con_offset_dc__coarse` | **0/157** | exacto bit a bit, igual que en fino |
    | `tono_desbalanceado__coarse` | 31/157 (20 %) | ±2-5 LSB — misma clase, proporción parecida a fino (19 %) |
    | `tono_sobre_escala__coarse` | 145/157 (92 %) | degenerado (Q≈0 en régimen permanente), igual lectura que en fino (97 %) — la saturación no introduce nada nuevo |

    Mismo veredicto que en modo fino: ninguna discrepancia es un mecanismo nuevo, todas caen en el
    residuo de cuantización del NCO ya aceptado. Con esto la matriz de ocho corridas (cuatro casos ×
    dos modos) que anotaba el bloque anterior como «siguiente paso obvio» queda completa y
    documentada. **Esto no cierra ZM1**: el hito exige coincidencia bit a bit y tres de los ocho casos
    (`tono_con_ruido`, `tono_desbalanceado`, `tono_sobre_escala`, en ambos modos) siguen con residuo
    distinto de cero. Sigue pendiente, como ya dejó anotado el cierre de P-10, la decisión del equipo
    de DSP sobre si ese nivel de residuo bloquea ZM1 o amerita redefinir el criterio bit a bit.

!!! success "19-sep-2026: la decisión pendiente se toma — el hito ZM1 exige tolerancia, no bit a bit; queda un comparador por actualizar y tres huecos de Z1 sin cerrar"
    La decisión que este documento dejaba pendiente arriba se toma hoy
    ([D-12](../alcance/decisiones.md#d-12)): el residuo de cuantización del NCO (hasta ±5 LSB, 14 de
    16 combinaciones de la matriz completa de [P-11](../alcance/pendientes.md#p-11)) se acepta como
    techo normal del bloque, no como fallo. El hito ZM1 de arriba queda enmendado: para el bloque
    NCO/mezclador el criterio es «discrepancia ≤5 LSB por muestra I/Q», no bit a bit; para todo lo
    demás (framing, range gating) el bit a bit de D-05 no cambia. [P-11](../alcance/pendientes.md#p-11)
    cierra en la misma sesión, con la confirmación de dominio de que el techo de Taylor (~−88/−92
    dBc) alcanza.

    **Esto no cierra ZM1 técnicamente todavía** — es la decisión de producto, no la implementación:
    `sim/tb_sv/drx_l1_checker.sv` sigue comparando bit a bit sin tolerancia, y la matriz de 16
    combinaciones no se ha vuelto a correr contra xsim con un comparador tolerante para confirmar
    «pass» formal. Ver [D-12](../alcance/decisiones.md#d-12) para el trabajo exacto que falta.

    **Cierre, misma sesión (más tarde, 19-sep-2026):** hecho. `TOLERANCE_LSB` añadido a
    `sim/tb_sv/drx_l1_checker.sv` (0 por defecto, 5 en los testbenches de integración de la cadena
    DDC) y la matriz de 16 combinaciones corrida de nuevo contra xsim real —
    **16/16 "PASS"**. Dos de los 16 dieron falso-fallo en la primera pasada por un directorio de
    build de xsim con un kernel compilado de antes de esta tolerancia (hallazgo de infraestructura,
    no del diseño, ver [P-09](../alcance/pendientes.md#p-09)); corregido y reconfirmado limpio. Con
    esto, ZM1 bajo el criterio de D-12 queda formalmente cumplido, no solo decidido.

    **Revisión del resto de entregables de Z1 de la lista de arriba, la misma sesión:**

    - El top-level de 3 canales heterogéneos (Config A/B) **ya estaba resuelto** desde el 9-sep-2026
      (`N_CH=3` sobre `drx_ddc_quad_top.sv`/`drx_range_gate_quad_top.sv`, sin módulo nuevo) — la
      entrada del 9-sep de más arriba decía lo contrario por no haberse actualizado tras resolverlo
      el mismo día; queda corregida in situ.
    - `report_utilization` real está publicado para 4 canales homogéneos
      ([Presupuesto de recursos](../plataforma/recursos.md), 200/220 DSP48, medido) pero **no** para
      las dos configs de 3 canales que de verdad se usan en la mayoría de las pruebas: la tabla de
      150/159 DSP48 en el cierre de [P-12](../alcance/pendientes.md#p-12) es una estimación de peor
      caso ("si la cadena de Tx cuesta igual que un canal Rx completo — no confirmado"), no una
      síntesis real de un build `N_CH=3`. Sigue pendiente correr `report_utilization` sobre Config A
      y Config B de verdad.
    - **El mapa de registros AXI-Lite, listado arriba como «congelado en este punto», no existe
      todavía** — ni RTL ni documento de registros en el repo. No es una tarea menor pendiente de
      pulir: es un entregable completo de Z1 sin empezar.
    - La conmutación en caliente fino/grueso (continuidad de fase al cambiar `mode_coarse` a mitad
      de rayo) sigue explícitamente diferida — ver la cabecera de `rtl/drx_ddc_top.sv` y de
      `rtl/drx_range_gate.sv`.

!!! success "19-sep-2026: primer P&R real del datapath completo — `vector_source` escrito, `drx_top` deja de estar vacío, WNS real medido (y no cerraba a 100 MHz)"
    Al ir a diseñar el mapa de registros AXI-Lite apareció algo más grande: `rtl/drx_top.sv` seguía
    siendo el diseño vacío de Z0 (solo el latido) y `vector_source` —el primer ítem del trabajo de
    Z1 de arriba— no existía como RTL sintetizable en ningún sitio (solo `sim/tb_sv/
    drx_l1_file_source.sv`, marcado en su propia cabecera como "código de testbench, no de
    síntesis"). Consecuencia: el único WNS medido hasta hoy (5,850 ns, más arriba) era del diseño
    vacío del latido — nunca se había corrido un P&R real de la cadena DDC + range gating.

    **`vector_source` (nuevo, modo BRAM-loop únicamente):** `rtl/vector_source.sv`, `N_CH` bancos
    de BRAM independientes precargados con `$readmemh` desde un `.hex` generado por
    `tools/gen_vector_source_init.py` (reutiliza `model/drx_model/vectors.tone()`, no reinventa la
    matemática del tono). `last` pulsa cada `DEPTH` muestras como marcador artificial de "fin de
    ventana" para ejercitar el framing de `drx_range_gate` — **no** es PRF real, Z2 no existe
    todavía. `drx_top.sv` ahora instancia de verdad `vector_source` → `drx_ddc_quad_top` →
    `drx_range_gate_quad_top`, con `N_CH=3` (Config A/B de P-12, no los 4 canales Rx homogéneos).

    **Dos hallazgos de síntesis real que la simulación nunca había visto, los dos en RTL ya
    verificado por xsim (`drx_range_gate.sv`), no en código nuevo:**

    1. `mem0`/`mem1` no sintetizaban a BRAM. Primera causa: vivían en un proceso con reset
       asíncrono en su sensibilidad, aunque el reset nunca las tocara — "RAM is sensitive to
       asynchronous reset signal. this RTL style is not supported" (ninguna BRAM real de Xilinx
       tiene borrado asíncrono de contenido). Corregido separando cada banco en sus propios
       procesos de lectura y escritura, sin reset y sin ninguna sentencia compartida entre `mem0` y
       `mem1` — reestructuración puramente sintáctica (mismas condiciones, mismo flanco, mismo
       resultado), verificada de nuevo contra xsim real en fine y coarse antes de seguir: TLAST
       bit a bit, dato dentro de tolerancia D-12, igual que antes de tocar nada.
    2. Las salidas de `drx_range_gate_quad_top` no tenían adónde ir. Exponerlas una a una como
       puertos del top pedía 105 pines físicos contra los 50 disponibles en el paquete de la
       ZedBoard ("IO placement is infeasible"); `(* keep = "true" *)` sobre las señales internas,
       sin ningún puerto real aguas abajo, tampoco bastó — `opt_design` se llevó la cadena entera
       de todas formas (post-route quedó en 22 LUTs, 0 DSP, 0 BRAM: solo el latido). Se resolvió
       reduciéndolas a un único bit `debug_probe` registrado (XOR de todo el datapath), mismo
       patrón que ya usa el propio árbol para "hacer real" una señal sin consumidor
       (`unused_nco_ready` en `drx_ddc_top.sv`) — sin significado en sí mismo, solo evita que la
       síntesis real elimine lo que alimenta.

    **Primer WNS real, con los dos hallazgos ya corregidos:** `vivado -mode batch -source
    tcl/build.tcl -tclargs -platform zedboard -step impl` (sin `-step bitstream`: sin AXI-Lite ni
    DMA todavía, las salidas de range-gate no tienen destino físico, y el gate de WNS de
    `tcl/build.tcl` corre en `impl`, no en `bitstream`) — **WNS = −1,209 ns a 100 MHz. No cierra.**
    Camino crítico real: un FIFO interno del FIR Compiler (droop) de un canal hasta el puerto de
    escritura de una BRAM del range gate, 10,903 ns de dato contra 10 ns de periodo. Es exactamente
    el escenario que [Dilatación temporal](../plataforma/dilatacion-temporal.md) ya preveía como
    contingencia ("bajar a 62,5 MHz... si 100 MHz no cierra con un datapath DSP no trivial") —
    nunca antes se había medido con la cadena real para saber si hacía falta.

    **Decisión, misma sesión (vladimir):** aplicar la contingencia ya prevista — `fs_hz` de
    `zedboard` baja de 100 a 62,5 MHz en `config/params.toml`. Dilatación numérica pura (D-02):
    mismo RTL, mismo comportamiento bit a bit, más lento en tiempo real; no toca `R₁`/`R₂`/`fs` de
    la ZU9 (P-08/ADR-001 sigue sin firmar, eso es el sample rate del ADC real, un knob distinto).
    Dos tests de `model/tests/test_params.py` tenían la razón 100/250=2,5× y la PRF de pared de
    zedboard (480 Hz) grabadas a mano — actualizados a 4,0× y 300 Hz, los valores reales con el
    nuevo `fs_hz`, no un cambio de comportamiento.

    **WNS real, a 62,5 MHz:** `vivado -mode batch -source tcl/build.tcl -tclargs -platform
    zedboard -step impl` — **WNS = +2,770 ns. Cierra**, con margen. Mismo camino crítico (FIR
    Compiler droop → BRAM del range gate), ahora dentro de los 16 ns de periodo. Utilización real
    post-route: LUT 7,6 %, BRAM Tile ~21 %, DSP48 153/220 (69,6 %, coincide con la cifra ya medida
    en [P-12](../alcance/pendientes.md#p-12) fuera de contexto).

    **Con esto, ZM1 en hardware real tiene, por primera vez, un P&R completo que cierra** — antes
    de esta sesión, todo lo verificado de Z1 era simulación (xsim) o síntesis fuera de contexto. Lo
    que sigue faltando para cerrar Z1 del todo no cambia de lista, solo de orden de urgencia: el
    mapa de registros AXI-Lite (sin empezar, ahora el hueco más grande, con un top real contra el
    que diseñarlo), la conmutación en caliente fino/grueso, y `report_utilization`/timing reales
    para Config A específicamente (esta corrida fue Config B por defecto — Tx + nominal + atenuado
    genérico, el `N_CH=3` no distingue cuál de las dos).

!!! success "19-sep-2026 (más tarde): mapa de registros AXI-Lite v1, congelado — deja de ser el hueco más grande de Z1"
    `rtl/drx_axil_regs.sv` (nuevo) más `config/registers.toml`/`tools/gen_registers.py` (mismo
    patrón de fuente única + codegen que el contrato DRx↔DSP): VERSION (RO), CTRL (RW, bit 0 =
    `mode_coarse`, sustituye al `localparam` fijo que tenía `drx_top.sv`) y STATUS (write-1-to-clear,
    un bit por canal = `overrun` de `drx_range_gate_quad_top`, antes reducido a un solo bit
    `debug_probe` sin significado). Detalle completo del mapa, semántica y lo que queda fuera en
    [Mapa de registros AXI-Lite](registros.md).

    Para que write-1-to-clear funcione de verdad (que un overrun *nuevo* tras limpiar el anterior se
    vuelva a ver), `drx_range_gate.sv`/`drx_range_gate_quad_top.sv` ganan un puerto `clear` nuevo —
    antes `overrun` era sticky para siempre, sin forma de rearmarlo. Cambio de una sola línea en el
    `always_ff` de `overrun`, nada del dato I/Q ni de `mem0`/`mem1`; `sim/tb_sv/drx_l1_checker.sv` no
    compara `overrun`, así que el riesgo sobre la bit-exactitud ya verificada es bajo, pero sigue
    siendo un cambio de puertos en RTL ya verificado por xsim.

    **Decidido explícitamente fuera de v1** (con vladimir, antes de implementar): el overflow de
    saturación del DDC (`drx_saturate`, dentro de `drx_ddc_top`). Exponerlo obliga a tocar los
    puertos de `drx_ddc_top.sv`/`drx_ddc_quad_top.sv`, que sí forman parte de la matriz de 16
    corridas bit-exactas de D-12 — el costo de rehacerla no se justificaba para este primer corte.
    Sigue pendiente, explícito, no descartado.

    Verificado en este entorno con L0 real (Verilator/cocotb, `make check`, 80 tests: los 79 que ya
    había más el mapa de registros nuevo): `sim/tb/tb_drx_axil_regs.py` (VERSION/CTRL/STATUS/W1C/
    dirección reservada) y la ampliación de `sim/tb/tb_drx_range_gate.py` (el puerto `clear`: limpia,
    rearma, y el set gana sobre un clear concurrente). **Pendiente, siguiente en la cola**: rehacer
    la matriz L1 de range-gate contra xsim real (`tb_l1_ddc_range_tri.sv`, con Vivado ya en PATH en
    esta máquina) para reconfirmar TLAST/I-Q tras el puerto `clear`, y volver a cerrar P&R con el
    AXI-Lite ya integrado en `drx_top` (WNS a 62,5 MHz). No se da por cerrado hasta correr eso.

!!! success "20-sep-2026: mapa de registros v2 (OVERFLOW) y matriz L1 de 16 corridas reconfirmada contra xsim real"
    **Corrección de un supuesto de la entrada anterior:** se creía que este entorno no tenía acceso
    a Vivado. Falso — `vivado`/`xsim` 2022.2 están instalados y en PATH
    (`/home/orlando/tools/Xilinx/Vivado/2022.2`), confirmado corriendo el flujo real, no solo
    comprobando el binario. Todo lo que las entradas de más arriba dejaban como "pendiente, fuera de
    este entorno" se corrió de verdad esta misma noche.

    **Validación del toolchain, primer caso suelto:** `tcl/sim_l1.tcl -case tono_if__fine` contra el
    `drx_ddc_top` sin tocar — **PASS** (315/315 dentro de tolerancia D-12), confirmando que el flujo
    completo (IP real, `drx_l1_checker.sv` con `TOLERANCE_LSB`) sigue funcionando en esta máquina
    antes de comprometerse a la matriz completa.

    **Mapa de registros v2 — OVERFLOW:** con el toolchain confirmado, se implementó el pendiente que
    la sesión anterior dejó explícito: overflow de saturación del DDC en el mapa de registros.
    `drx_ddc_top.sv` gana un puerto `overflow` (OR de las dos ramas I/Q, combinacional, sin estado
    nuevo — el mismo criterio que `ray_flag.ddc_overflow` del contrato: por rayo, no por componente),
    propagado por `drx_ddc_quad_top.sv`. El latch sticky + write-1-to-clear vive dentro de
    `drx_axil_regs.sv` (no en `drx_ddc_top`, a propósito: `drx_saturate` es deliberadamente
    combinacional y sin estado — ver su cabecera), como registro nuevo OVERFLOW en `0x0C`.
    `config/registers.toml` sube a `schema_version = 2`. Detalle completo en
    [Mapa de registros AXI-Lite](registros.md).

    **Matriz L1 de D-12 reconfirmada tras el cambio de puertos** (`tcl/sim_l1.tcl`, los 8 casos ×
    {fine, coarse} contra `tb_l1_ddc.sv`, 2 en paralelo): **16/16 PASS**, dentro de la tolerancia de
    D-12, mismo patrón de discrepancias ya documentado (offset DC exacto bit a bit; ruido/desbalance/
    sobre-escala dentro de ±5 LSB). Confirma que exponer `overflow` no movió ni un bit del dato I/Q.
    Cada corrida real tardó entre 20 y 30 minutos contra xsim (IP de Xilinx real, no Verilator) — la
    matriz completa se corrió durante la noche, no en el hilo interactivo.

    **`tb_l1_ddc_range_tri.sv` (Config A/B, N_CH=3, con range gating) tras el puerto `clear` nuevo de
    `drx_range_gate` — también reconfirmado:** fine y coarse, `tcl/sim_l1_range_tri.tcl`, los 3
    canales de cada corrida (`tono_if`, `tono_desplazado`, `dos_tonos`) **PASS** — dentro de
    tolerancia D-12 **y TLAST bit a bit** con el modelo dorado en los 6/6 (3 canales × 2 modos).
    Confirma que el puerto `clear` nuevo no movió el dato I/Q ni el framing de rayos ya verificado.

    **Con esto, las dos reverificaciones L1 que este cambio necesitaba quedan cerradas**: matriz de
    D-12 (16/16) y range-gate tri (6/6).

!!! success "20-sep-2026 (más tarde): P&R re-cerrado con el AXI-Lite integrado — hallazgo real de integración física, no del datapath"
    `vivado -mode batch -source tcl/build.tcl -tclargs -platform zedboard -step impl`, ahora con
    `drx_axil_regs` instanciado dentro de `drx_top`.

    **Primer intento — falla en `place_design`, no por temporización:**
    `ERROR: [Place 30-58] IO placement is infeasible. Number of unplaced IO Ports (62) is greater
    than number of available sites (50)`. Causa: exponer el bus AXI-Lite completo (`wdata`/`rdata`
    de 32 bits cada uno, más el resto de señales) como puertos de `drx_top` pide del orden de 94
    pines físicos — mismo tipo de límite que ya encontraron las salidas de range-gate el 19-sep (105
    contra 50), esta vez sobre un bus de control, no sobre datos de canal. Causa raíz real: **nada
    en este repo instancia todavía un PS7 ni un interconnect AXI** que pudiera ser el maestro de
    este slave dentro del chip — sin eso, el único destino físicamente posible para esas señales son
    pines del paquete, y un bus de control de 32 bits no está pensado para salir del chip así.

    **Corrección:** los puertos AXI-Lite de `drx_axil_regs` dejan de exponerse como puertos de
    `drx_top`; se atan a valores inertes dentro del propio `drx_top` (ningún maestro emite
    transacciones nunca en esta build) — ver la cabecera de `rtl/drx_top.sv`. Esto reproduce
    exactamente la misma situación que ya tenía `mode_coarse` como `localparam` fijo antes de que
    existiera el mapa de registros: **no es una regresión frente al WNS del 19-sep, es la misma
    medición**. Deja explícito un prerrequisito nuevo y real, no diseñado aquí a propósito: el mapa
    de registros no es alcanzable desde firmware de verdad hasta que exista un puente PS7↔AXI (AXI
    GP del PS7, o un puente JTAG-a-AXI) en este repo — ver
    [Mapa de registros AXI-Lite](registros.md).

    **Resultado, segundo intento:** `place_design`/`route_design` cierran limpio —
    **WNS = 2,528 ns, WHS = 0,017 ns** ("All user specified timing constraints are met", setup y
    hold). Utilización post-route: LUT 7,61 % (4049/53200), registros 8,33 % (8865/106400), BRAM
    Tile 21,07 % (29,5/140), DSP48 **111/220 (50,45 %)**.

    **Hallazgo abierto, sin explicar, marcado como pregunta y no como hecho:** la cifra de DSP48
    (111) difiere notablemente de la medida el 19-sep (153/220, 69,6 %) para lo que debería ser
    prácticamente el mismo datapath (mismo `N_CH=3`, misma cadena DDC+range-gate; el bloque de
    registros nuevo no usa DSP48). Una inspección rápida del desglose jerárquico de post-síntesis
    (`post_synth_utilization_hier.rpt`) confirma que la rama de modo grueso (`fir_compiler_halfband`,
    `u_round_coarse_gain`) SÍ está presente en el netlist con recursos reales en los 3 canales × 2
    ramas I/Q — no parece eliminación de código muerto por `mode_coarse` atado a constante. No se
    investigó más a fondo por tiempo; queda pendiente antes de confiar en la cifra de DSP48 para
    presupuesto de recursos.

    **Aviso sobre el propio gate de `tcl/build.tcl`:** solo comprueba WNS de *setup*
    (`get_timing_paths -delay_type max`), no *hold*. En esta corrida el WHS pasó brevemente a
    negativo (−0,192 ns) en un reporte intermedio de rutado antes de resolverse a +0,017 ns en el
    resultado final — no bloqueó nada esta vez, pero el script no lo habría detectado si no se
    hubiera resuelto solo.

    **Con esto, Z1 no tiene más pendientes de verificación contra herramientas reales** por el lado
    del mapa de registros v2: L0, L1 (matriz de 16 y range-gate tri) y P&R están todos corridos y en
    verde. Lo que queda de la lista de Z1 (conmutación en caliente fino/grueso, `report_utilization`
    de Config A específica, runner de CI con Vivado, y ahora el puente PS7↔AXI para alcanzar el mapa
    de registros desde firmware de verdad) sigue exactamente donde estaba, sin resolver.

!!! success "20-sep-2026 (más tarde): discrepancia de DSP48 explicada — 111/220 es la cifra correcta"
    El hallazgo abierto de la entrada anterior quedó mal planteado: comparaba una cifra de
    **post-síntesis** (153/220, del 19-sep) contra una de **post-rutamiento** (111/220, del 20-sep)
    como si fueran la misma etapa. `post_synth_utilization_hier.rpt` — el reporte jerárquico que ya
    existía en el árbol — tiene en su propia cabecera `Design State: Synthesized`, no `Routed`: se
    generó a mano con `report_utilization -hierarchical`, fuera del flujo automatizado de
    `tcl/build.tcl` (que solo emite `post_synth_utilization.rpt`/`post_route_utilization.rpt`
    planos, nunca el jerárquico) — la propia entrada del 19-sep ya lo llamaba "fuera de contexto"
    citando [P-12](../alcance/pendientes.md#p-12). No hubo nunca una medición de post-rutamiento del
    19-sep con la que comparar.

    **Confirmado dentro de la misma corrida del 20-sep** (mismo `post_route.dcp`, sin recompilar
    nada): `post_synth_utilization.rpt` (`Design State: Synthesized`) mide **153/220**, idéntico al
    del 19-sep; `post_route_utilization.rpt` (`Design State: Routed`) mide **111/220**. La caída de
    42 DSP48 ocurre entre síntesis y rutamiento, dentro de esta misma build — no entre el 19 y el
    20-sep, y no por el mapa de registros (que no usa DSP48).

    Reabrir el checkpoint rutado y volver a correr `report_utilization -hierarchical` sobre él
    (`build/gw-logs/post_route_utilization_hier.rpt`) localiza la caída por completo: la instancia
    `fir_compiler_halfband` (7 DSP48 cada una, `KEEP_HIERARCHY = SOFT`) desaparece por completo de
    las 6 instancias (2 ramas I/Q × 3 canales) — 6 × 7 = 42, exactamente el delta. El resto del
    árbol (CIC, FIR droop, mixer, NCO, la fila propia de `drx_ddc_top` que absorbe el DSP de
    `u_round_coarse_gain`) queda bit a bit idéntico entre síntesis y rutamiento.

    **Mecanismo más probable, no verificado celda por celda (inferencia, no hecho comprobado):** el
    propio log de `opt_design` de esta corrida (`build/gw-logs/impl_zedboard_v2.log`) muestra sus
    fases de `Retarget`/`Constant propagation`/`Sweep` eliminando miles de celdas sobre el netlist ya
    con las IP reales insertadas (no sobre cajas negras). Un filtro halfband tiene, por construcción
    matemática, aproximadamente la mitad de sus coeficientes exactamente en cero — consistente con
    que `opt_design`, ya en contexto completo (no en la síntesis fuera de contexto de cada IP), haya
    eliminado los DSP48 que multiplicaban por esos coeficientes cero sin cambiar el resultado. No se
    extrajo un diff celda a celda que lo confirme de forma directa; lo que sí está confirmado es que
    la reducción es completa (0 DSP48 restantes en `u_halfband`, ninguna caída parcial ni en ningún
    otro módulo) y que no movió el WNS/WHS ya cerrados ni afecta al resultado bit-exacto de xsim (que
    verifica el RTL antes de síntesis, ajeno a esta optimización de `opt_design`).

    **Conclusión práctica:** la cifra a usar para presupuesto de recursos es **111/220 (50,45 %)**,
    la de post-rutamiento real. El 153/220 nunca fue una medición de post-rutamiento — era la cifra
    de síntesis, en las dos fechas. `CLAUDE.md` y [Mapa de registros AXI-Lite](registros.md#verificacion)
    quedan actualizados con esto; deja de figurar como pendiente en "Lo primero que hay que hacer".

!!! success "20-sep-2026 (más tarde): «`report_utilization` de Config A específicamente» — pendiente mal planteado, cerrado sin nueva síntesis"
    Este pendiente pedía correr P&R por separado para Config A (Tx+H+V) y Config B (Tx+nominal+
    atenuado), asumiendo que podían dar cifras distintas. Revisando el árbol para intentarlo:
    **no hay nada, hoy, que las distinga a nivel de RTL sintetizable.**

    - `rtl/drx_ddc_quad_top.sv` y `rtl/drx_range_gate_quad_top.sv` son el mismo `generate` genérico
      en `N_CH` para las dos — la diferencia entre A y B es qué frontend analógico alimentaría cada
      canal en la placa real, fuera de este repo, no la cadena digital (ver la cabecera de
      `drx_ddc_quad_top.sv`).
    - `rtl/vector_source.sv` toma un único `INIT_FILE` cargado con `$readmemh` **dentro** del
      `generate` por canal: los `N_CH` bancos de BRAM se precargan hoy con el mismo contenido
      replicado — no hay forma de que el bitstream sintetizado difiera entre A y B, ni siquiera por
      datos. El propio comentario del fichero ya anota como trabajo futuro (no hecho) pasar a un
      array de parámetros para contenido distinto por canal.
    - Y aunque lo hubiera: `tools/gen_vector_source_init.py` ya documenta que el contenido de la BRAM
      no afecta el cierre de temporización (STA es estructural). El único lugar donde Config A y B
      producen resultados distintos hoy es la simulación L1 funcional (`tb_l1_ddc_tri.sv`, vía
      manifiestos `stimulus_path_0/1/2` distintos en `drx_l1_file_source`) — no la síntesis ni el P&R.

    **Conclusión:** el P&R de `N_CH=3` ya corrido (19-sep y 20-sep) *es* al mismo tiempo el de
    Config A y el de Config B — son indistinguibles con el RTL actual, no dos builds pendientes de
    correr. No se ejecutó ninguna síntesis nueva porque no hay ninguna diferencia que sintetizar.
    Si algún día `vector_source` gana contenido por canal (el array de parámetros ya anotado como
    pendiente), o si la ZU9 introduce una diferencia real de ancho/generics entre configs, esta
    equivalencia hay que volver a revisarla — no es una garantía permanente, es el estado de hoy.

!!! success "20-sep-2026 (más tarde): puente PS7↔AXI real — primer PS7 de este repo, P&R cierra a WNS = 1,712 ns"
    Hallazgo del P&R anterior: `drx_axil_regs` existía y estaba verificado, pero nada en el repo
    instanciaba un PS7 ni un interconnect AXI que pudiera alcanzarlo desde firmware. `AGENTS.md`
    prohíbe diseñar por adelantado, y esto quedó deliberadamente fuera — hasta que **el usuario
    decidió explícitamente adelantarlo esta misma noche**, tras que se le mostrara el alcance real
    del cambio (no una extensión del mapa de registros: la primera vez que este repo tiene un PS de
    Zynq de verdad, con todo lo que eso implica de herramientas y de árbol de reloj).

    **Bloqueante previo, resuelto primero:** Vitis (el IDE de firmware embebido, necesario para
    generar BSP/FSBL desde un XSA) no estaba instalado — solo su instalador sin extraer
    (`Xilinx_Unified_2022.2_1014_8888`, 91 GB). Instalado a mano, recortado a Zynq-7000 + Zynq
    UltraScale+ MPSoC (las dos familias que este proyecto usa), en `/home/orlando/tools/Xilinx_Vitis/`
    — 45 minutos. El primer intento de `ConfigGen` quedó corriendo desatendido en modo interactivo
    (sin flags que evitaran el prompt) y escribió un log de **31 GiB** hasta llenar la partición raíz
    del sistema (`/`, 51 G, a 0 disponibles) — causa real de que un intento posterior de P&R muriera
    sin error de TCL. Encontrado con `lsof` (el proceso seguía vivo con el log borrado-pero-abierto),
    matado por PID, disco liberado al instante. Aparte, `/home/orlando/Documents/
    Xilinx_Unified_2022.2_1014_8888/` (el instalador ya usado) seguía ocupando 91 G sin necesidad —
    borrado.

    **Board file:** no hay ninguno de ZedBoard registrado en Vivado por defecto (es de Digilent, no
    de Xilinx). Instalado a mano desde el repo público `github.com/Digilent/vivado-boards`
    (`new/board_files/zedboard/`) a `$XILINX_VIVADO/data/boards/board_files/zedboard/` — Vivado lo
    detecta como `digilentinc.com:zedboard:part0:1.1` (no coincide con el nombre de carpeta del repo,
    `1.3`; la versión real la fija un campo interno del `board.xml`, no la carpeta — confirmado, no
    asumido).

    **Diseño, con dos hallazgos reales de esta misma sesión que cambiaron el plan original:**

    1. `create_bd_cell -type module -reference drx_top` **no admite un top SystemVerilog** en
       Vivado 2022.2 ("This type is not allowed as the top file in the reference") — el plan
       original metía `drx_top` dentro del block design como celda de módulo; no se puede. En su
       lugar, el BD (`tcl/gen_zynq_bd.tcl`) contiene solo IP (`processing_system7`,
       `axi_interconnect`, `proc_sys_reset`, `axi_protocol_converter`), y `rtl/drx_zynq_top.sv`
       (nuevo) instancia su wrapper generado junto con `drx_top` por fuera, conectados en
       SystemVerilog normal.
    2. `axi_interconnect:2.1` **no tiene ninguna propiedad de protocolo por puerto maestro**
       (confirmado listando su `CONFIG.*` completo) — su `M00_AXI` es siempre AXI4 completo
       (ID/burst/len/lock/cache/qos/region/size/last), mientras que `drx_axil_regs`/`drx_top` son
       AXI4-Lite puro. `axi_protocol_converter:2.1` traduce entre los dos (por defecto ya viene
       `SI_PROTOCOL=AXI4`/`MI_PROTOCOL=AXI4LITE`, no hizo falta configurarlo). El puerto externo del
       BD también necesitó `CONFIG.PROTOCOL AXI4LITE` puesto a mano — sin eso heredaba el AXI4
       completo del VLNV genérico aunque estuviera conectado al lado ya-Lite del conversor.

    Además, cableado a mano en vez de con automation (cuya sintaxis de `-config` no estaba verificada
    contra esta versión): `axi_interconnect` expone un `ACLK` global y uno por interfaz
    (`S00_ACLK`/`M00_ACLK`, los tres necesitan reloj); `pl_clk0` tuvo que crearse con `-type clk` (no
    genérico) para poder fijarle `CONFIG.FREQ_HZ`/`ASSOCIATED_BUSIF` — sin eso, `validate_bd_design`
    fallaba con "Bus Interface property FREQ_HZ does not match" (100 MHz por defecto contra los 62,5
    MHz reales de `FCLK_CLK0`). Todo esto se verificó corriendo Vivado de verdad en cada paso, no se
    escribió una vez y se asumió correcto.

    **`rtl/drx_top.sv` vuelve a ser un slave AXI-Lite pass-through puro** (sus puertos AXI-Lite ya no
    se atan a nada dentro del propio fichero). Para que el flujo de siempre (`-top drx_top`, sin PS7,
    el que mide solo el datapath) siguiera funcionando igual que antes de este cambio,
    `rtl/drx_top_tieoff.sv` (nuevo) hace exactamente lo que `drx_top.sv` hacía internamente antes: lo
    instancia y ata su AXI-Lite a valores inertes. `tcl/build.tcl` gana `-top {drx_top|zynq}` (por
    defecto `drx_top`, que ahora sintetiza `drx_top_tieoff` por debajo) y un paso `-step xsa`
    (`write_hw_platform -fixed -include_bit`, solo con `-top zynq`).

    **P&R real de `drx_zynq_top`:** primer intento falla en síntesis por errores de compile-order
    ("Module references are not supported in manual compile order mode" — resuelto con
    `set_property source_mgmt_mode All`, aunque el enfoque de módulo-referencia se abandonó después
    por el hallazgo 1 de arriba). Con el BD ya corregido: **síntesis limpia, 0 errores**, y
    **`-step impl` cierra: WNS = 1,712 ns, WHS = 0,033 ns** ("All user specified timing constraints
    are met"), reloj `clk_fpga_0` a 62,5 MHz derivado automáticamente del modelo de temporización del
    propio PS7 (sin `create_clock` manual, a diferencia del flujo sin PS7). Utilización post-route:
    LUT 10,83 %, registros 12,23 %, BRAM Tile 21,07 %, DSP48 159/220 (72,27 %) — aquí el DSP48 **no**
    cayó entre síntesis y rutamiento (159 en las dos etapas), a diferencia de la build sin PS7 del
    punto anterior; la eliminación de DSP48 de coeficiente cero en `fir_compiler_halfband` no fue
    determinista entre las dos builds. Dato observado, no investigado más a fondo — no bloquea nada.

    **Con esto, el mapa de registros es alcanzable desde el PS7 de verdad** (`M_AXI_GP0` → el mapa,
    dirección asignada automáticamente por Vivado dentro del espacio de GP0). Lo que sigue faltando,
    explícito y no fingido: BSP/FSBL vía Vitis desde el XSA exportado (Z4 real, `fw/Makefile` ya lo
    dice), y el puente equivalente para la ZU9 (`zynq_ultra_ps_e`, IP distinta, sin diseñar).

!!! success "21-sep-2026: «conmutación en caliente fino/grueso» — cerrado como no-requisito, no como trabajo diferido"
    Este ítem venía listado desde el 19-sep-2026 (más arriba) como el hueco más grande de Z1 tras el
    mapa de registros: continuidad de fase en `drx_ddc_top`/`drx_range_gate` al cambiar `mode_coarse`
    a mitad de rayo. Antes de diseñarlo se preguntó para qué serviría el caso de uso — ningún
    documento del repo lo explicaba, solo que estaba diferido.

    **Confirmado por vladimir:** no tiene sentido. La resolución de celda (`mode_coarse`, fino =
    125 m / grueso = 250 m) **solo se cambia entre rayos distintos**, nunca a mitad de un mismo
    rayo. No hay caso de uso — ni resolución dependiente del rango dentro de un rayo, ni
    recuperación de overrun/overflow a mitad de rayo, ni nada del encuadre por modo de barrido de
    Z4 (Split Cut / Batch Cut / Doppler Cut, que cambian de resolución entre rayos, no dentro de
    ellos) — que necesite continuidad de fase intra-rayo.

    Con esto, el mux estático que ya existe en `drx_ddc_top.sv`/`drx_range_gate.sv` (`mode_coarse`
    fijo durante una corrida, ya escribible en tiempo de ejecución desde el mapa de registros v1)
    **ya cubre el caso de uso real**: cambiar de celda entre un rayo y el siguiente no necesita
    continuidad de fase, porque cada rayo arranca de registros en cero. **No queda trabajo
    pendiente por este motivo** — no es que se difiera más, es que deja de existir como entregable
    de Z1. Cabeceras de `rtl/drx_ddc_top.sv` y `rtl/drx_range_gate.sv` y
    [Mapa de registros AXI-Lite](registros.md#deliberadamente-fuera-de-v3) actualizados.

    **Lo que queda de la lista de Z1 tras esto:** `report_utilization`/timing de Config A específica
    (ya cerrado el 20-sep, ver más arriba — no queda nada ahí), el runner de CI con Vivado
    (bloqueado por `gh auth login`), y BSP/FSBL vía Vitis (Z4 real). Z1 no tiene, hoy, ningún
    entregable de ingeniería propio sin empezar y sin bloqueante externo.

!!! success "21-sep-2026 (más tarde): runner de CI con Vivado montado — A7 cerrado; tres bugs reales de infraestructura encontrados y corregidos al correr el job `gateware` por primera vez"
    El bloqueo de `gh auth login` era de credenciales, no arquitectónico: un self-hosted runner de
    GitHub Actions puede ser esta misma máquina de desarrollo. El token de registro se generó desde
    la web de GitHub (no necesita `gh` autenticado en esta máquina) y el runner
    (`lamula-drx-dev-vivado`, label `vivado`) quedó instalado como servicio systemd, `enabled`,
    sobrevive reinicios. `HAS_VIVADO_RUNNER=true` puesto como variable de repo.

    La red de esta máquina resultó tener un Pi-hole que bloqueaba por DNS varios subdominios de
    `actions.githubusercontent.com` (`api.github.com`, `launch`, `token`, `results-receiver`, etc. —
    necesarios para que el runner registre y reciba jobs, no solo para el registro inicial).
    Blanqueados con una regla regex de whitelist; sin esto el runner nunca llega a "Listening for
    Jobs" de forma útil.

    Con el runner recibiendo jobs de verdad por primera vez, `substrato` siguió en verde pero
    `gateware` destapó tres bugs reales que ningún `make check` local había ejercitado (todos en
    código escrito pero nunca antes ejecutado de punta a punta):

    1. **"Lint de HDL" de CI desincronizado de `make lint-hdl`.** Desde que `drx_ddc_top.sv`
       instancia IP real de Xilinx, el lint necesita el blackbox de
       `sim/tb_sv/xilinx_ip_verilator_stubs.sv` (ya existía, `make lint-hdl` ya lo usaba) — pero el
       comando de `.github/workflows/ci.yml` nunca se actualizó para incluirlo, así que llevaba
       fallando en CI desde que ese stub se escribió. **No necesita Vivado**: se quedó en el job
       `substrato` (`ubuntu-latest`), solo con el argumento que faltaba.
    2. **DRC de `write_bitstream` bloqueaba el bitstream por `debug_probe`.** `-step bitstream`
       nunca se había corrido de verdad (solo `-step impl` estaba cerrado). `debug_probe` se deja
       sin restringir a propósito desde que existen `zedboard.xdc`/`zedboard_zynq.xdc` (Vivado le
       asigna un pin libre), pero el DRC de bitgen (`NSTD-1`/`UCIO-1`) trata cualquier puerto sin
       XDC como error por defecto. `tcl/build.tcl` baja esas dos reglas a `Warning` justo antes de
       `write_bitstream`, tal como el propio mensaje de Vivado lo sugiere para este caso.
       **Verificado: WNS = 2,489 ns, `drx_top_tieoff.bit`/`.bin` reales escritos.**
    3. **`tools/make_boot.sh` copiaba un `.bin` que `build.tcl` nunca produce.** El flujo por
       defecto (`-top drx_top`, sin PS7) mapea a `set top drx_top_tieoff` — el bitstream sale como
       `drx_top_tieoff.bin`, nunca `drx_top.bin`. Este script no se había corrido nunca contra un
       bitstream real antes de hoy, así que el desajuste no se había notado.

    Con los tres corregidos, el pipeline llega hasta donde puede llegar hoy: `substrato` verde,
    síntesis+bitstream de `zedboard` verde, y `BOOT.BIN reproducible` para exactamente en el límite
    ya documentado de Z4 — `exit 2`, "falta `fsbl.elf`/`drx_app.elf`" — no un error nuevo. **ZM0
    sigue sin cumplirse, pero ya no por falta de runner ni por bugs de infraestructura: solo falta
    Z4.**

    `zu9` se sacó de la matriz de CI: este Vivado 2022.2 no tiene el device pack de Zynq
    UltraScale+ instalado (`get_parts xczu9eg*` y `-filter {ARCHITECTURE == zynquplus}` devuelven
    cero). Ese leg nunca se había corrido, ni en CI ni a mano, así que tampoco es una regresión de
    hoy — es un hueco nuevo, real, que solo se hizo visible al intentar correrlo por primera vez. Ver
    [pendientes.md](../alcance/pendientes.md).

!!! success "26-sep-2026: BSP/FSBL vía Vitis — `tools/make_boot.sh` deja de fallar, `BOOT.BIN` reproducible confirmado a mano"
    El punto que `CLAUDE.md` marcaba como "lo primero que hay que hacer" para cerrar ZM0. Flujo
    completo, corrido de punta a punta en esta máquina de desarrollo:

    1. `vivado -tclargs -platform zedboard -top zynq -step xsa` — reconfirma P&R sin cambios de RTL
       desde el 25-sep (**WNS = 1,295 ns**, misma cifra) y escribe
       `build/gw/zedboard_zynq/drx_zynq_top.xsa`.
    2. `tcl/gen_bsp.tcl` (nuevo) + `tools/build_vitis.sh` (nuevo): `xsct` crea una plataforma
       standalone sobre `ps7_cortexa9_0` desde ese XSA y compila dos apps — `fsbl` (plantilla *Zynq
       FSBL* de Vitis) y `drx_app` (plantilla *Hello World* de Vitis, **placeholder deliberado, no
       el firmware real de Z4** — FreeRTOS, ensamblado de rayos y lwIP siguen sin empezar). Los
       `.elf` quedan en `build/fw/zedboard/`.
    3. `tools/make_boot.sh` ahora copia esos dos ELF desde `build/fw/$platform` antes de
       comprobar que existen (antes solo copiaba el `.bin` de `build/gw/$platform`) — deja de fallar
       con `exit 2`.

    **`BOOT.BIN` se empaquetó y se confirmó reproducible byte a byte**: mismo SHA-256 en dos
    corridas de `bootgen` seguidas.

    Dos bloqueos de sistema nuevos en esta máquina, mismo patrón que el Pi-hole del 21-sep (no
    arquitectónicos, de entorno): `xsct` necesita `Xvfb` (no estaba instalado) y, aparte,
    `libtinfo.so.5` (Ubuntu 22.04 solo trae la versión 6; el paquete `libtinfo5` vive en `universe`).
    Los dos, resueltos con `apt-get install`. Wrapper `xsct` añadido a `~/.local/bin`, mismo patrón
    que `vivado`/`bootgen`.

    **Hallazgo real de esta sesión, sin investigar todavía:** `bootgen` avisa
    `Partition fsbl.elf.0 range is overlapped with partition drx_top.bin.0 memory range` (y lo mismo
    entre `drx_top.bin` y `drx_app.elf`) — genera la imagen igual, y la reproducibilidad byte a byte
    se cumple, pero no está confirmado si es el falso positivo conocido de bootgen para particiones
    de bitstream (que no tienen una dirección de carga real, se cargan por PCAP) o un problema real
    de mapa de memoria. No bloquea el cierre de este punto; si aparece un fallo real de arranque en
    placa, empezar por aquí.

    **Primera vez que la plantilla FSBL de Vitis se generó de verdad**: el primer intento falló —
    `Zynq FSBL` no es una plantilla válida sin `xilffs` en el BSP del dominio standalone. Corregido
    con `bsp setlib -name xilffs` antes de `platform generate` en `tcl/gen_bsp.tcl`.

    **`.github/workflows/ci.yml` gana los pasos que faltaban** (export de XSA + `build_vitis.sh`,
    antes de `make_boot.sh`, mismo gate `HAS_VIVADO_RUNNER`/`matrix.platform == 'zedboard'`) — sin
    esto, `git push` seguiría fallando en CI aunque el flujo ya corra limpio a mano. **No verificado
    todavía con un `git push` real**: el runner es esta misma máquina, así que debería heredar los
    mismos wrappers de PATH que ya usa para `bootgen`, pero eso es inferencia, no una corrida de CI
    confirmada en esta sesión.

    Lo que esto NO hace, a propósito: `drx_app.elf` sigue siendo el placeholder de Vitis, no lee ni
    un registro del mapa AXI-Lite ni corre FreeRTOS — eso es el resto de Z4, sin empezar. Tampoco
    hay ningún bring-up en placa física (`BOOT.BIN` nunca se escribió en una SD ni se arrancó una
    ZedBoard real) — eso sigue fuera del alcance de este repositorio tal como está definido.

## Z2 — Motor de timing, triggers y PRF (semanas 9–13) { #z2 }

Trabajo:

- Generador de 4 triggers configurables con retardo y ancho independientes. **RTL escrito y
  verificado bit a bit contra el modelo dorado** (`rtl/drx_trigger_gen.sv` +
  `rtl/drx_trigger_one_shot.sv`, 21-sep-2026 más tarde) **e integrado en `drx_top`** vía el mapa de
  registros AXI-Lite v3 (22-sep-2026, TRIG_DELAY_0..3/TRIG_WIDTH_0..3 — ver
  [`registros.md#z2-en-v3`](registros.md#z2-en-v3)).
- **Secuenciador de 2 lotes de PRF/ancho de pulso por radial** (Batch mode de NEXRAD, D-13, cierra
  P-04): lote de PRF baja (vigilancia) + lote de PRF alta (Doppler), conteo de pulsos por lote
  configurable por registro, alternados de forma autónoma en fabric y en bucle continuo durante el
  barrido — no un único par PRF/ancho global. Valores de registro idénticos a la ZU9. **RTL escrito
  y verificado bit a bit contra el modelo dorado** (`rtl/drx_prf_batch_seq.sv`, 21-sep-2026 más
  tarde) **e integrado en `drx_top`** vía el mismo mapa v3 (TIMING_CTRL/PRF_DIV_*/PULSE_WIDTH/
  N_PULSES).
- Selección de ancho de pulso 0,8 / 1,66 / 3,3 µs (200 / 415 / 825 ciclos a 250 MHz), por lote.
- Manejo de modos de pulso y encuadre por PRI.
- **Validador de configuración PRF × rango**
  ([D-09](../alcance/decisiones.md#d-09)), aplicado **a cada uno de los 2 lotes por separado**
  (D-13: sus rangos no ambiguos son distintos por diseño), con código de error hacia el contrato.
  El modelo dorado ya lo implementa (`validate_batch`/`validate_radial`). **Mitad resuelta en RTL,
  22-sep-2026 (más tarde):** los dos checks AUTOCONTENIDOS (pulse_width en tabla + cabe en su
  propio PRI) ya se rechazan en fabric (`rtl/drx_timing_config_valid.sv`), ver la entrada de más
  abajo y [`registros.md#z2-en-v4`](registros.md#z2-en-v4). **Cerrado del todo, 22-sep-2026 (más
  tarde, tercera sesión):** PRF × rango no ambiguo, el corazón real de D-09, ya se rechaza también en
  fabric — ver la entrada correspondiente más abajo. No hizo falta ningún registro nuevo (el umbral
  resultó ser un requisito fijo de producto, no runtime); lo único que queda de este punto es el
  código de error del contrato hacia el DSP, alcance de Z4.
- Sincronización determinista entre el trigger y el inicio del gating. **Resuelto, 22-sep-2026**
  ([D-14](../alcance/decisiones.md#d-14)): `drx_range_gate` gana un puerto `ray_start`, cableado a
  `pulse_trig`, que resincroniza el corte de rayo con cada pulso de PRF (de cualquiera de los 2
  lotes) — ver la entrada de más abajo. El conteo de bins distinto por lote bajo/alto que D-13/D-14
  dejaban abierto **ya cerró** ([D-15](../alcance/decisiones.md#d-15), 25-sep-2026):
  BINS_LOW/BINS_HIGH, un registro por lote, configurable en runtime (viene de DSP/RCP según el VCP)
  — ver la entrada correspondiente más abajo. El diagnóstico de tiempo muerto descartado que D-14
  dejaba explícitamente sin BITE propio **ya cerró también, 25-sep-2026 (más tarde):**
  `ray_truncated`/GATE_TRUNCATED (mapa v6) — ver la entrada correspondiente más abajo.
- Instrumentación en fabric: contador libre en un dominio de reloj distinto, para auto-medir jitter
  y periodo. **Cerrado como no-requisito, 25-sep-2026 (no como trabajo diferido)** — ver la entrada
  correspondiente más abajo: el camino de `trig_out` + osciloscopio ya cubre lo que pide el hito
  ZM2, y un segundo dominio de reloj de verdad no mide nada que un osciloscopio externo no mida
  mejor.
- Salida de los 4 triggers a Pmod para medida con osciloscopio. **Resuelto, 25-sep-2026 (más
  tarde):** `trig_out[3:0]` ya tiene pines XDC reales (Pmod JA, `tcl/xdc/zedboard.xdc`/
  `zedboard_zynq.xdc`) — ver la entrada correspondiente más abajo.

**Hito ZM2 (fin S13):** matriz completa PRF × ancho de pulso × modo × 4 triggers en verde, en
simulación y en placa, incluida la secuencia de 2 lotes por radial de Batch mode; jitter medido y
caracterizado; combinaciones ilegales rechazadas con el código correcto.

!!! success "21-sep-2026: alcance de Z2 revisado antes de escribir código — Batch mode de NEXRAD exige 2 lotes de PRF por radial, no un único par global"
    Al arrancar Z2 se detectó que el "Trabajo" de arriba (un único par PRF/ancho de pulso global)
    no cubre el VCP objetivo: usa **Batch mode** de NEXRAD, que alterna PRF dentro del *dwell time*
    de cada radial (~10-15 ms), no por barrido completo ni por sector azimutal de varios grados como
    especulaba [P-04](../alcance/pendientes.md#p-04). Decisión de producto (vladimir, misma sesión):
    el motor de timing soporta **exactamente 2 lotes por radial** — ver
    [D-13](../alcance/decisiones.md#d-13), que cierra P-04. Consecuencia directa sobre el validador
    de [D-09](../alcance/decisiones.md#d-09): se aplica por lote, no una vez por configuración,
    porque el rango no ambiguo del lote de PRF baja y el del lote de PRF alta son distintos por
    diseño. Ningún RTL ni modelo de Z2 existía todavía en este punto, así que el cambio de alcance no
    tocó código — solo evita diseñar contra el par global equivocado.

!!! success "21-sep-2026 (más tarde): modelo dorado del motor de timing, primer código de Z2"
    `model/drx_model/timing.py`: `Batch` (valores de registro: `prf_div`, `pulse_width_cycles`,
    `n_pulses`) y `RadialBatches(low, high)` — el tipo mismo fija "2 lotes" de D-13, no una lista de
    N. Valida que el ancho de pulso quepa en su propio PRI y que sea uno de los tres de
    `config/params.toml`. `validate_batch`/`validate_radial` implementan D-09 por lote, con
    `PrfRangeIllegal`/`PulseWidthInvalid` mapeados a los códigos ya existentes en
    `contract/schema/drx_dsp_v0_1.toml` (`prf_range_illegal`, `pulse_width_invalid`).
    `trigger_times_cycles`/`radial_trigger_times_cycles`/`sweep_trigger_times_cycles` generan los
    instantes de disparo en ciclos de `fs`, con el lote alto empezando exactamente donde termina el
    bajo y sin hueco entre radiales — la base para comparar contra el RTL del generador de triggers
    cuando exista. 14 tests nuevos en `model/tests/test_timing.py`, `make check` en verde (94
    tests). Al escribirlo salió un hallazgo real, no bloqueante hoy: el mensaje `config` del
    contrato DRx↔DSP todavía tiene un solo `prf_div`/`pulse_width_idx`, no dos — ver
    [P-15](../alcance/pendientes.md#p-15).

!!! success "21-sep-2026 (más tarde): primer RTL de Z2 — `drx_prf_batch_seq`, verificado bit a bit contra el modelo dorado"
    `rtl/drx_prf_batch_seq.sv`: el secuenciador de 2 lotes de D-13 en fabric. Un contador de PRI
    (`pri_cnt`) y un índice de pulso (`pulse_idx`) por lote, con `batch_sel` conmutando en el mismo
    flanco en que `pri_cnt` vuelve a 0 — así el PRI del primer pulso del lote nuevo ya usa su propio
    divisor sin necesitar ningún hueco ni guarda de sincronización entre lotes. `pulse_trig` es
    combinacional sobre `pri_cnt` a propósito: el primer pulso tiene que caer en el ciclo 0 tras
    armar, igual que `start_cycle=0` en el modelo, sin un ciclo de latencia que el modelo no tiene.
    `tx_gate` (nivel, ancho de pulso por lote) y `radial_done` (marca el arranque de cada radial
    nuevo, nunca el primero) sí son registrados. Todavía no lo instancia `drx_top` — depende del
    mapa de registros de Z2, que no existe (P-15) — así que por ahora es una unidad suelta en
    `rtl/filelist.f`, con su propio L0.

    Verificación (`sim/tb/tb_drx_prf_batch_seq.py`, cocotb sobre Verilator): los tiempos de disparo
    y `batch_sel`, ciclo a ciclo, contra `model.drx_model.timing.sweep_trigger_times_cycles` — nada
    de aritmética de PRI reimplementada a mano en el testbench (D-03). 4/4 tests en verde en el
    primer intento tras corregir un solo detalle de anchos de bus (un cast de resize sobrante
    disparaba `WIDTH` en Verilator, ver el propio commit). `make check` en verde (95 tests). Un
    detalle de testbench que vale la pena dejar escrito: `pulse_trig` es combinacional y su primer
    valor válido existe un ciclo de reloj ENTERO antes del primer `RisingEdge` que se espera tras
    armar el secuenciador — `await ReadOnly()` antes de cada lectura (en vez de solo leer después de
    cada flanco) es lo que hace ese primer ciclo observable sin tratarlo como caso especial.

!!! success "21-sep-2026 (más tarde): generador de 4 triggers (retardo+ancho), segundo RTL de Z2"
    `rtl/drx_trigger_one_shot.sv` (un canal: `delay`+`width` de registro sobre un evento `arm`) +
    `rtl/drx_trigger_gen.sv` (`generate` de `N_TRIGGERS` instancias, mismo patrón que
    `drx_range_gate_quad_top.sv`). Los 4 comparten el mismo `arm` — en la integración real,
    `pulse_trig` de `drx_prf_batch_seq.sv`, así que cada pulso de PRF (de cualquiera de los 2
    lotes) vuelve a armar los 4 canales — y cada uno aplica su propio retardo/ancho sobre ese mismo
    instante, tal como ya modela el contrato DRx↔DSP (`trigger_delay_0..3`/`trigger_width_0..3`,
    congelado desde Z0/D-08). **Nota de interpretación, no una decisión cerrada:** que el `arm`
    sea por pulso (no una vez por radial) es la lectura más razonable dado el propósito de medida
    con osciloscopio del hito ZM2, pero ningún documento de `docs/alcance/` lo fija explícitamente
    — si resulta ser el criterio equivocado, cambia solo el cableado de `arm` en la integración,
    no este RTL.

    Añadido al modelo dorado: `model/drx_model/timing.py::one_shot_active_cycles` (D-03), con sus
    propios tests en `model/tests/test_timing.py` (16 en total ahora). Verificación RTL
    (`sim/tb/tb_drx_trigger_gen.py`, cocotb): cada uno de los 4 canales contra ese oráculo con
    retardo/ancho independientes, y que un `arm` nuevo reinicia el canal (last-arm-wins) aunque
    llegue a mitad del retardo o del pulso anterior. 3/3 tests en verde. Un detalle real de
    Verilator/cocotb que costó una vuelta: un array de salidas de 1 bit
    (`output logic trig_out[NTriggers]`) no es indexable vía VPI con `--public-flat-rw` — la
    solución fue empaquetarlo en un solo vector (`[NTriggers-1:0]`), que además es exactamente lo
    que hace falta para cablear a un Pmod. `make check` en verde (98 tests). Mismo estado que el
    secuenciador de lotes: sin integrar en `drx_top`, pendiente el mapa de registros de Z2 (P-15).

!!! success "21-sep-2026 (más tarde): drx_timing_engine — las dos piezas de Z2, cableadas juntas"
    `rtl/drx_timing_engine.sv`: instancia `drx_prf_batch_seq` + `drx_trigger_gen` en un solo
    bloque, sin lógica propia — cablea `pulse_trig` del secuenciador como `arm` del generador de
    triggers, así que los 4 triggers se rearman con cada pulso de PRF (de cualquiera de los 2
    lotes). Es el bloque que se integrará en `drx_top` el día que exista el mapa de registros de
    Z2 (P-15); hasta entonces, unidad suelta con su propio L0.

    Verificación (`sim/tb/tb_drx_timing_engine.py`): no repite la corrección interna de cada pieza
    (eso ya lo prueban sus propios L0) — solo confirma el cableado, contra
    `radial_trigger_times_cycles` + `one_shot_active_cycles` del modelo dorado aplicados en
    cadena. 1/1 test en verde. `make check` en verde (99 tests).

!!! success "22-sep-2026: mapa de registros AXI-Lite v3 — Z2 integrado en `drx_top`"
    `drx_timing_engine` deja de ser una unidad suelta: `config/registers.toml` sube a v3
    (`schema_version` 2→3, `addr_width` 6→7 — las 18 palabras de Z2 ya no cabían en 16) con
    TIMING_CTRL/TIMING_STATUS/PRF_DIV_LOW/PRF_DIV_HIGH/PULSE_WIDTH/N_PULSES/TRIG_DELAY_0..3/
    TRIG_WIDTH_0..3, `rtl/drx_axil_regs.sv` los implementa (mismo patrón sticky+W1C que OVERFLOW
    para TIMING_STATUS/`radial_done`) y `rtl/drx_top.sv` ya instancia `drx_timing_engine`
    configurado enteramente desde AXI-Lite. Detalle completo, incluidas las tres decisiones de
    diseño de esta sesión (por qué TRIG_DELAY/TRIG_WIDTH son 4 registros con nombre y no un array,
    por qué el motor sigue sin conectar a range-gate, por qué `trig_out` no tiene pines XDC
    todavía) en [`registros.md#z2-en-v3`](registros.md#z2-en-v3).

    Esto era exactamente la condición de cierre que [P-15](../alcance/pendientes.md#p-15) fijaba
    del lado del registro — mitad resuelta ahora, ver la actualización en ese mismo hallazgo. El
    lado del contrato (`contract/schema/drx_dsp_v0_1.toml`) sigue intacto a propósito: D-08 exige
    discutir cualquier cambio ahí, y ya había consenso de que es alcance de Z4, no de esta sesión.

    `sim/tb/tb_drx_axil_regs.py` gana 5 tests nuevos (TIMING_CTRL RW, TIMING_STATUS sticky/W1C/
    rearme, PRF_DIV_LOW/HIGH de 32 bits, el empaquetado low/high de PULSE_WIDTH/N_PULSES, los 4
    canales de TRIG_DELAY/TRIG_WIDTH sin pisarse) — mismo patrón que STATUS/OVERFLOW, no suman
    entradas nuevas a pytest (siguen dentro de `test_l0_axil_regs.py`). `make lint-hdl`
    (`--top-module drx_top` sobre el `filelist.f` completo) es, por ahora, la única verificación
    real de que `drx_timing_engine` está bien cableado dentro de `drx_top` — no hay L0/L1 a nivel
    de `drx_top` completo. `make check` en verde (99 tests, mismo número que antes: los tests
    nuevos son sub-tests de cocotb, no entradas nuevas de pytest).

    Lo que esto NO hace, deliberadamente: correr un P&R real con los 4 pines nuevos de `trig_out`
    (última cifra de P&R medida sigue siendo la de v2, sin este cambio) ni tocar el contrato
    DRx↔DSP. Ambos quedan como próximos pasos reales, no como trabajo diferido sin más.

!!! success "22-sep-2026 (más tarde): D-14 — `ray_start` sincroniza el corte de rayo de range-gate con cada pulso de PRF"
    Tres opciones consideradas en sesión para cerrar el hueco de sincronización que dejaba abierto
    el `drx_top.sv` de v3 (resync por hardware en cada pulso; alineación solo por configuración,
    confiando en que `PRF_DIV` sea múltiplo exacto de `bins`; o un wrapper que solo adjunta
    metadatos sin tocar `drx_range_gate`) — se eligió la primera, la única que fija sin ambigüedad
    qué significa "bin 0". Ver [D-14](../alcance/decisiones.md#d-14) para el razonamiento completo.

    `rtl/drx_range_gate.sv` gana un puerto `ray_start`: un pulso de un ciclo que fuerza el puntero
    de escritura a 0 sin marcar el banco en curso como pendiente — un recorte forzado (tiempo
    muerto entre pulsos, o un PRI mal configurado) se descarta en silencio en vez de salir como un
    rayo corto o corrupto. `rtl/drx_range_gate_quad_top.sv` lo expone como puerto único compartido
    entre los N_CH canales (mismo patrón que `mode_coarse`), y `rtl/drx_top.sv` lo cablea a
    `pulse_trig` de `drx_timing_engine` — con esto, `pulse_trig` deja de ser una señal sin
    consumidor y sale de `debug_probe_xor`.

    Es un cambio aditivo sobre RTL ya cerrado bajo [D-12](../alcance/decisiones.md#d-12): con
    `ray_start` en bajo (el estado de toda la matriz L1 ya corrida) el comportamiento es bit a bit
    idéntico al de antes del puerto, así que no hizo falta modelo dorado ni vectores nuevos.
    Verificación: 3 tests L0 nuevos en `sim/tb/tb_drx_range_gate.py` (alineación con el wrap natural
    es un no-op bit a bit; un `ray_start` a mitad de banco descarta ese banco entero sin emitirlo;
    muestras de tiempo muerto tras un rayo completo se descartan sin colarse en el siguiente) —
    8/8 tests del módulo en verde, `make check` en verde (99 tests, mismo número: son sub-tests de
    cocotb). **Reconfirmado contra xsim real** (`tb_l1_ddc_range_tri.sv`, el único testbench L1 que
    instancia `drx_range_gate`, con el puerto nuevo atado a 0): fine, 288/288 muestras en tolerancia
    D-12 y TLAST bit a bit en los 3 canales; coarse, 144/144 — ambos modos limpios, confirmando que
    el puerto añadido no cambió ni un bit del comportamiento ya cerrado.

    Lo que esto NO resuelve, a propósito: si el conteo de bins necesita diferir entre lote bajo y
    alto (ya abierto por D-13); si `pulse_trig` debe disparar también algo del lado Tx (no existe
    todavía); y no hay ningún contador ni bit de BITE que distinga un tiempo muerto normal de un
    `ray_start` que llegó tarde y truncó un rayo en curso — D-09 (PRF x rango) sigue sin aplicarse
    en RTL, aunque los otros dos checks de D-09 ya sí (ver la entrada siguiente).

    **Actualización, 25-sep-2026: el conteo de bins por lote cerró con
    [D-15](../alcance/decisiones.md#d-15) y el BITE de tiempo muerto cerró más tarde el mismo
    día — ver las entradas correspondientes más abajo.** El lado Tx sigue sin resolver.

!!! success "22-sep-2026 (más tarde): mitad de D-09 (checks autocontenidos) validada en RTL — mapa de registros v4"
    `rtl/drx_timing_config_valid.sv` (nuevo, puro combinacional, mismo patrón que `drx_saturate.sv`):
    valida que `pulse_width` esté en la tabla de `config/params.toml` y que quepa en su propio PRI
    (`pulse_width < prf_div`) -- los dos checks de D-09 que NO necesitan ningún dato externo.
    Instanciado ×2 (lote bajo/alto) dentro de `drx_timing_engine.sv`, que gatea con el resultado el
    `enable` real que llega a `drx_prf_batch_seq`: con un lote inválido, el secuenciador
    simplemente no corre, sin importar `TIMING_CTRL`. `drx_prf_batch_seq.sv` (ya cerrado y
    verificado bit a bit) no cambió -- el gateo vive un nivel arriba, en la composición.

    PRF × rango no ambiguo -- el corazón real de D-09 -- sigue sin validarse en ningún sitio de
    RTL: ese check necesita un umbral externo (`r_max_required_m`) que hoy no existe como registro
    ni como constante de `config/params.toml`. Añadirlo es alcance nuevo (subir el mapa otra vez),
    no algo que esta sesión dejó a medias por descuido -- ver
    [`registros.md#z2-en-v4`](registros.md#z2-en-v4) para el detalle completo, incluidas las
    decisiones de esta sesión (por qué "rechazar" es gatear `enable` y no un error de bus AXI, por
    qué el latch de TIMING_STATUS vive en `drx_axil_regs` y no en el validador, por qué
    `schema_version` sube a 4 aunque ningún offset se movió).

    Verificación: nuevo L0 (`sim/tb/tb_drx_timing_config_valid.py`) barre los 3 anchos de la tabla
    más uno fuera de tabla contra varios `prf_div`, bit a bit contra el oráculo
    `model/drx_model/timing.py::batch_config_valid` (D-03, nuevo). `tb_drx_timing_engine.py` gana
    un caso con un lote inválido que confirma que el motor completo se congela, no solo el
    validador; su caso de composición de triggers ya existente tuvo que pasar de anchos de pulso
    arbitrarios pequeños a uno real de la tabla (200), porque ahora el motor no corre con uno
    ilegal. `tb_drx_axil_regs.py` gana los mismos casos de sticky/W1C/set-gana-sobre-clear que ya
    cubren OVERFLOW, aplicados a TIMING_STATUS bits 1/2. `make check` en verde (104 tests).

    Lo que esto NO hace, deliberadamente: no se tocó `contract/schema/drx_dsp_v0_1.toml` (P-15
    sigue abierto del lado del contrato). P&R con el mapa v4 se confirmó por separado, ver la
    entrada siguiente.

!!! success "22-sep-2026 (más tarde): P&R re-confirmado con el mapa de registros v4 (D-09 autocontenido + `ray_start`)"
    Ninguna de las dos entradas anteriores (D-14, D-09 autocontenido) había vuelto a correr P&R —
    la última cifra medida seguía siendo la de v3 (20-sep). Corrida de confirmación, sin cambiar
    RTL: `-top drx_top -step bitstream` (flujo por defecto, sin PS7) y `-top zynq -step impl`
    (PS7 real, el camino que de verdad llega al mapa de registros). Las dos cierran:

    - `-top drx_top`: **WNS = 2,851 ns, WHS = 0,014 ns** (bitstream escrito,
      `build/gw/zedboard/drx_top_tieoff.bit`) — sube ligeramente desde los 2,770 ns del 19-sep,
      previo a todo Z2.
    - `-top zynq`: **WNS = 1,859 ns, WHS = 0,010 ns** — baja desde los 2,528 ns del 20-sep (v2). Es
      la cifra más ajustada de las cuatro medidas hasta hoy sobre este top: cada pieza nueva de Z2
      (motor de timing completo + mapa v3/v4) se apila sobre el mismo camino crítico
      PS7↔interconnect↔`drx_axil_regs`. Sigue con margen cómodo, pero es la que hay que vigilar si
      seguir sumando registros a este mapa.

    En ambos flujos, igual que el 20-sep: un reporte intermedio de `route_design` muestra WHS
    momentáneamente negativo (del orden de −0,19 ns) que se resuelve solo antes del reporte final
    — el propio gate de `tcl/build.tcl` solo mira WNS de setup, no hold, así que esto no lo
    detectaría por sí solo si no se leyera el log completo. Ningún error, ninguna advertencia
    crítica en síntesis en ninguno de los dos. No se corrió `-step bitstream -top zynq` ni `-step
    xsa` en esta pasada.

!!! success "22-sep-2026 (más tarde, tercera sesión): D-09 completo — PRF × rango no ambiguo ya se rechaza en fabric"
    El hallazgo que dejaba abierta la entrada anterior ("PRF × rango no ambiguo... necesita un
    umbral externo que hoy no existe como registro") resultó ser una sobreestimación del alcance:
    `r_max_required_m` es un requisito FIJO de producto (460 km / 115 km, no algo que el DSP negocia
    en runtime), así que no hacía falta ningún registro AXI-Lite nuevo ni subir el mapa a v5 — vive
    como invariante en `config/params.toml`, exactamente igual que `PULSE_WIDTH_CYCLES`.

    Valores investigados y fijados en sesión (vladimir, contra la literatura estándar de WSR-88D/
    NEXRAD — training.weather.gov/nwstc/NEXRAD/RADAR/Section1-2.html): **460 km** para el lote de
    vigilancia/reflectividad (PRF ≈ 326 Hz) y **115 km** para el lote Doppler (PRF ≈ 1300 Hz). El
    primero coincide, cifra a cifra, con la fila "326 Hz → 460 km" que la tabla de
    [D-09](../alcance/decisiones.md#d-09) ya traía desde antes de esta sesión — no era un ejemplo
    arbitrario, ya usaba el número real. Convertidos a `prf_div_min_low = 767198` /
    `prf_div_min_high = 191800` (ciclos de registro, invariantes entre plataformas — calculados
    contra el fs de la ZU9, 250 MHz, no el de ZedBoard, D-02, igual que `prf_div_min`/`prf_div_max`
    ya existentes).

    `rtl/drx_timing_config_valid.sv` gana un tercer check (`prf_div >= PrfDivMinRange`), como
    PARÁMETRO (no puerto): es un requisito fijo, no una entrada de runtime. Valor por defecto
    `PrfDivMinRange = 1` (sin piso, inocuo para elaboración/lint fuera de contexto).
    `rtl/drx_timing_engine.sv` gana `PrfDivMinRangeLow`/`PrfDivMinRangeHigh`, por defecto
    `PRF_DIV_MIN_LOW`/`PRF_DIV_MIN_HIGH` del paquete de parámetros, uno por instancia de
    `drx_timing_config_valid` — `enable_gated` sigue siendo la única puerta hacia
    `drx_prf_batch_seq.sv`, que no cambió. `drx_top.sv` no overridea nada: hereda los valores reales
    de producción por defecto.

    **Hallazgo real de esta sesión, no un error:** `prf_div_min_high` (191 800) queda por debajo de
    `PRF_DIV_MIN` (208 333, el techo de PRF ya congelado en 1200 Hz desde antes de Z2). Con los
    límites de PRF de hoy, ningún `prf_div` válido puede violar el piso del lote alto — ese tercer
    check no rechaza nada en la práctica todavía. Se deja implementado igual (mismo costo, y cubre
    si `PRF_DIV_MIN` cambia en el futuro), documentado como no-vinculante en vez de omitido en
    silencio.

    Verificación: `model/drx_model/timing.py::batch_config_valid` gana el tercer parámetro
    (`prf_div_min_range`, en unidades de REGISTRO — ni RTL ni el oráculo dividen en punto flotante;
    la conversión metros → `prf_div` ya se hizo una vez al generar `config/params.toml`). Tests
    nuevos en `model/tests/test_timing.py`, incluido uno contra los pisos reales de producción (caso
    1200 Hz, el mismo que D-09 ya documentaba como físicamente imposible para 460 km).
    `sim/tb/tb_drx_timing_config_valid.py` barre también alrededor de un piso de prueba pequeño
    (500, no el real) para no forzar un sweep de cientos de miles de `prf_div`.
    `sim/tb/tb_drx_timing_engine.py` gana un caso nuevo sin override (pisos reales de producción),
    solo checks combinacionales en la frontera — un dwell completo a ~767 198 ciclos/lote sería
    impracticable en L0; el caso de cableado existente pasa a overridear `PrfDivMinRangeLow/High` a 1
    explícitamente, porque sus `prf_div_low/high` pequeños ya no serían legales bajo el piso real.
    `sim/runner.py::SimJob` gana `testcases` (filtro de `cocotb.testcase`) para correr el mismo
    `test_module` bajo dos elaboraciones con parámetros incompatibles entre sí — hacía falta porque
    `build_dir` depende solo de `hdl_toplevel`, no de los parámetros. `make check` en verde
    (107 tests).

    Lo que esto NO resuelve, a propósito: el código de error del contrato hacia el DSP sigue sin
    decidirse (alcance de Z4, sin relación con que el check ya rechace en fabric). Tampoco se
    corrió P&R con este cambio — es lógica combinacional adicional dentro de un módulo ya cerrado y
    de bajo costo (una comparación de 32 bits más por instancia); la última cifra medida sigue
    siendo la de v4 (entrada anterior).

!!! success "25-sep-2026: D-15 — conteo de bins de range-gate por lote, registro configurable en runtime (mapa v5)"
    Punto abierto desde D-13/D-14: si `drx_range_gate` necesita un conteo de bins distinto por lote.
    Confirmado por vladimir en sesión: sí, es configurable, y llega a DRx a través de DSP, que a su
    vez lo recibe de RCP según el VCP en curso — la proporción entre el rango del lote de vigilancia
    y el del lote Doppler nunca es la misma. Ver [D-15](../alcance/decisiones.md#d-15) para el
    razonamiento completo.

    `mode_coarse` (CTRL bit 0) deja de llegar a `drx_range_gate` -- sigue existiendo, pero solo para
    `drx_ddc_quad_top` (decimación/tamaño de celda). `rtl/drx_range_gate.sv`/
    `rtl/drx_range_gate_quad_top.sv` ganan un puerto `bin_count` (no `bins`: SystemVerilog reserva
    esa palabra para coverpoints/randomize, Verilator la rechaza como identificador) que lo
    reemplaza por completo. `rtl/drx_prf_batch_seq.sv` gana `bins_low`/`bins_high` como entradas y
    `bin_count` como salida, con el mismo mux combinacional que ya usaba para `pulse_width`
    (seleccionado por `batch_sel`). `rtl/drx_timing_config_valid.sv` gana un cuarto check
    (`bin_count >= 1 && bin_count <= BinsMax`), mismo patrón de gateo de `enable` que los otros tres
    — `BinsMax` por defecto es `BINS_MODE_FINE` para los dos lotes (a diferencia del piso de PRF, el
    techo físico de BRAM es el mismo requisito para los dos: una sola BRAM real).

    `config/registers.toml` sube a v5: BINS_LOW (0x48) / BINS_HIGH (0x4C), RW de 32 bits completos,
    mismo patrón que PRF_DIV_LOW/HIGH. `rtl/drx_axil_regs.sv` los implementa y `rtl/drx_top.sv` deja
    de cablear `mode_coarse` hacia `drx_range_gate_quad_top` -- en su lugar cablea la salida
    `bin_count` de `drx_timing_engine`. Detalle completo, incluidas las decisiones de esta sesión,
    en [`registros.md#z2-en-v5`](registros.md#z2-en-v5).

    Verificación: `model/drx_model/timing.py::batch_config_valid` gana `bins`/`bins_max` (D-03), en
    unidades de registro (sin punto flotante). Nuevos tests en `model/tests/test_timing.py`.
    `sim/tb/tb_drx_timing_config_valid.py` añade `bin_count` al sweep existente. `sim/tb/
    tb_drx_prf_batch_seq.py` gana un caso que confirma el mux de `bin_count` contra `batch_sel`.
    `sim/tb/tb_drx_timing_engine.py` gana un caso con los pisos reales de producción
    (`BinsMaxLow/High = BINS_MODE_FINE`, sin override) que confirma que el motor completo propaga el
    techo hasta el gateo de `enable` -- solo checks combinacionales en la frontera, igual que ya hace
    el caso equivalente de D-09/PRF. `sim/tb/tb_drx_range_gate.py` reemplaza `mode_coarse` por
    `bin_count` en los 8 tests existentes -- D-14 no se re-verifica desde cero, los mismos casos de
    `ray_start` ya cubrían el framing. `sim/tb_sv/tb_l1_ddc_range_tri.sv` (xsim real, corrida
    completa contra Vivado -- no solo `--lint-only`) se reconfirmó con `bin_count` derivado
    localmente del mismo `+mode=` de siempre (este testbench no tiene motor de timing de Z2): fine,
    288/288/288 muestras en tolerancia D-12 y TLAST bit a bit en los tres canales; coarse, 144/144/144
    -- las mismas cifras que ya medía D-14, confirmando que el puerto nuevo no cambia ni un bit del
    comportamiento ya verificado. `sim/tb/tb_drx_axil_regs.py` gana el mismo RW de
    32 bits que ya cubre PRF_DIV_LOW/HIGH, aplicado a BINS_LOW/HIGH, y corrige `REGS_VERSION`/la
    dirección de "reservado" (0x48 ya no lo es) que habían quedado hardcodeadas. `sim/runner.py::
    SimJob` ya tenía `testcases` (de la entrada anterior); se reutiliza igual aquí. `make check` en
    verde (108 tests).

    Lo que esto NO resuelve, a propósito: el código de error del contrato hacia el DSP (Z4, P-15,
    sin relación con este cambio) y el diagnóstico de tiempo muerto/BITE que D-14 ya dejaba abierto.
    Tampoco se corrió P&R -- lógica combinacional adicional de bajo costo dentro de un módulo ya
    cerrado; la última cifra medida sigue siendo la de D-09/v4.

!!! success "25-sep-2026 (más tarde): BITE de tiempo muerto — `ray_truncated`, mapa de registros v6"
    Punto que D-14 dejaba explícitamente abierto: "no hay hoy ningún contador ni bit de BITE que
    distinga un tiempo muerto normal de un `ray_start` que llegó tarde y truncó un rayo en curso".
    `rtl/drx_range_gate.sv` gana un puerto de salida `ray_truncated` (sticky, por canal) y uno de
    entrada `clear_truncated` (write-1-to-clear, PROPIO -- no comparte `clear` con `overrun`, son
    dos diagnósticos distintos con registros distintos del mapa). Se dispara cuando `ray_start`
    encuentra el banco en curso con datos reales que no se completan ese mismo ciclo -- NO es
    simplemente `wr_ptr != 0` (ver la cabecera del RTL): en el ciclo exacto del wrap natural,
    `wr_ptr` sigue leyendo `last_idx`, no 0, porque la asignación a 0 del bloque de escritura
    todavía no se ha "visto" en ese mismo `always_ff`. La condición real excluye el caso en que el
    banco se completa por cuenta propia ese ciclo (`s_valid && wr_ptr == last_idx`).

    `rtl/drx_range_gate_quad_top.sv` expone los dos puertos por canal, mismo patrón array que
    `overrun`/`clear`. `config/registers.toml` sube a v6: GATE_TRUNCATED (offset 0x50, w1c, bit `c`
    por canal), registro propio y no bits nuevos de STATUS -- mismo criterio que ya separó OVERFLOW
    de STATUS en v2. `rtl/drx_axil_regs.sv`/`rtl/drx_top.sv` lo cablean con el mismo patrón de
    empaquetado/desempaquetado que ya usa `overrun`. Detalle completo, incluida la decisión de dónde
    vive el latch, en [`registros.md#z2-en-v6`](registros.md#z2-en-v6).

    Es un cambio aditivo sobre RTL ya cerrado bajo [D-12](../alcance/decisiones.md#d-12), mismo
    argumento que D-14/D-15: con `ray_start`/`clear_truncated` en bajo (el estado de toda la matriz
    L1) el comportamiento es bit a bit idéntico al de antes. Verificación: 3 tests L0 nuevos en
    `sim/tb/tb_drx_range_gate.py` (un `ray_start` alineado con el wrap natural NO dispara
    `ray_truncated` -- este caso concreto falló en el primer intento, ver el hallazgo de abajo; uno
    que descarta un banco con datos reales a medias SÍ lo dispara, sticky; `clear_truncated` lo
    limpia y permite un segundo disparo, con el mismo set-gana-sobre-clear-concurrente que ya prueba
    `overrun`) -- 11/11 tests del módulo en verde. `sim/tb/tb_drx_axil_regs.py` gana el mismo patrón
    de lectura directa + pulso de clear que ya cubre STATUS, aplicado a GATE_TRUNCATED, y corrige
    `REGS_VERSION`/la dirección de "reservado" (0x50 ya no lo es, ahora 0x54). `make check` en verde
    (108 tests, mismo número: son sub-tests de cocotb). **Reconfirmado contra xsim real**
    (`tb_l1_ddc_range_tri.sv`, con una comprobación nueva -- `$fatal` si `ray_truncated` se dispara
    alguna vez con `ray_start` atado a 0 en toda la cadena): fine, 288/288/288 muestras en tolerancia
    D-12 y TLAST bit a bit en los tres canales; coarse, 144/144/144 -- las mismas cifras que ya
    medía D-15, sin ningún `ray_truncated` espurio en ninguno de los dos modos.

    **Hallazgo real de esta sesión:** la primera versión de la condición de disparo era literalmente
    `ray_start && wr_ptr != 0`, y falló en el primer intento de L0
    (`test_ray_truncated_no_se_dispara_en_wrap_natural`, no por inspección): en el ciclo en que
    `ray_start` coincide con el wrap natural (PRI bien calibrado), `wr_ptr` en ESE ciclo sigue
    valiendo `last_idx` -- el `wr_ptr <= '0` del bloque de escritura es una asignación no bloqueante
    sobre el mismo registro que la condición lee, así que "no se ve" hasta el ciclo siguiente. La
    condición corregida excluye explícitamente el caso en que el banco se completa por cuenta propia
    ese mismo ciclo. Corregido antes de tocar xsim real, así que la reconfirmación de arriba ya
    corrió con la lógica buena.

    Lo que quedaba de la lista de Z2 tras esto -- instrumentación de jitter en fabric y pines XDC de
    `trig_out` -- se resolvió la misma sesión, más tarde: ver las dos entradas siguientes.

!!! success "25-sep-2026 (más tarde): instrumentación de jitter en fabric — cerrada como no-requisito, no como trabajo diferido"
    Este ítem venía listado desde el arranque de Z2 como bloqueado en la práctica
    (`config/params.toml` no define ningún segundo dominio de reloj). Antes de diseñarlo se preguntó
    para qué serviría un contador libre en fabric si `trig_out` (ver la entrada siguiente) ya saca
    los 4 triggers a un Pmod para medirlos con osciloscopio -- mismo criterio que ya cerró la
    conmutación en caliente fino/grueso en Z1 (`fases.md#z1`, entrada del 21-sep-2026).

    **Confirmado en sesión:** el hito ZM2 solo exige "jitter medido y caracterizado", y el camino
    del osciloscopio ya lo cubre por completo -- mide el jitter real de la señal física, en el
    dominio de tiempo que de verdad importa (el del instrumento de medida), sin depender de ningún
    supuesto sobre qué tan "independiente" es un segundo dominio de reloj derivado del mismo
    cristal de la placa. Diseñar un contador libre en un segundo dominio (p. ej. `FCLK1` del PS7)
    añadiría un CDC nuevo y recursos de fabric para auto-medir algo que, en la práctica, un
    osciloscopio externo mide mejor y sin ese riesgo de diseño. **No queda trabajo pendiente por
    este motivo** -- no es que se difiera más, es que deja de existir como entregable de Z2.

!!! success "25-sep-2026 (más tarde): `trig_out` gana pines XDC reales — Pmod JA"
    `trig_out[3:0]` era, desde el mapa de registros v3 (22-sep-2026), un puerto físico real de
    `drx_top`/`drx_top_tieoff`/`drx_zynq_top` sin ninguna restricción de pin — sintetizaba y
    lintaba limpio, pero no había forma de conectarle un osciloscopio de verdad. Lo que faltaba no
    era diseño, era una referencia de pinout físico de los Pmod de la ZedBoard en la que confiar.

    Pinout tomado del *ZedBoard (Zynq Evaluation and Development) Hardware User's Guide* oficial de
    Digilent/Avnet (Tabla 16, "Pmod Connections"): los cuatro Pmod orientados a PL (JA/JB/JC/JD)
    cuelgan del Banco 13 (3,3 V); JC1/JD1 están routeados en modo diferencial (LVDS), JA/JB son
    single-ended. Se eligió **JA** (`trig_out[0..3]` → JA1/JA2/JA3/JA4 → Y11/AA11/Y10/AA9): un
    trigger digital de un bit no necesita diferencial, y JB queda libre para otro uso futuro. El
    mapeo canal→pin es arbitrario a propósito -- ningún documento de `docs/alcance/` fija uno, lo
    único que importa para ZM2 es que cada trigger tenga un pin físico estable y documentado.
    `tcl/xdc/zedboard.xdc` (flujo `-top drx_top`) y `tcl/xdc/zedboard_zynq.xdc` (flujo `-top zynq`)
    ganan las cuatro restricciones, LVCMOS33, mismos pines en los dos.

    **P&R real re-confirmado tras el cambio** (`-step impl`, sin bitstream): esta era la primera vez
    que `place_design` corría con estos 4 pines restringidos (antes Vivado los colocaba libres,
    sin comprobar si esos sitios concretos eran alcanzables desde la lógica que los alimenta).
    `-top drx_top`: **WNS = 2,527 ns, WHS = 0,032 ns** -- cierra, prácticamente igual que los
    2,851 ns del 22-sep (la diferencia es ruido de rutamiento normal entre corridas, no una
    regresión). `-top zynq`: **WNS = 1,295 ns, WHS = 0,012 ns** -- cierra, pero baja de forma
    notable desde los 1,859 ns del 22-sep. Fijar estos 4 pines a sitios concretos (en vez de dejar
    que Vivado elija libremente) le quita margen de maniobra al rutamiento justo cerca del mismo
    camino crítico que ya se venía señalando como el más ajustado
    (PS7↔interconnect↔`drx_axil_regs`, ver la entrada del 22-sep, más tarde) -- sigue con margen
    positivo, pero es la cifra más ajustada medida hasta hoy sobre este top, y la tendencia (v3:
    2,528 ns → v4/D-14/D-09: 1,859 ns → v6+XDC: 1,295 ns) merece vigilarse antes de seguir
    sumando registros o pines a este mapa. Ningún RTL cambió -- solo restricciones físicas -- así
    que no hizo falta reconfirmar D-12 ni ninguna suite de simulación.

## Z3 — Lectores SSI + tagging az/el (semanas 14–18) { #z3 }

Estrategia de tres capas, porque una sola no da confianza:

1. **Modelo cocotb** del encoder: código Gray, longitudes de palabra de 13 y 25 bits, monoflop,
   timeout, errores de trama.
2. **Emulador SSI en fabric** en la propia ZedBoard, cableado físicamente Pmod JA → Pmod JB. Valida
   I/O real, niveles y temporización.
3. **MCU externo** como implementación independiente. Su valor no es la cobertura sino la
   **independencia**: detecta errores de interpretación compartida que un emulador escrito por la
   misma persona que el lector nunca detectaría.

Trabajo:

- Lector SSI ×2 (azimut, elevación), reloj configurable 100 kHz–2 MHz, decodificación Gray,
  detección de timeout y de trama corta o larga.
- Marcado temporal de la lectura y asociación al rayo correcto. **Esta es la parte sutil:** la
  latencia de la lectura SSI frente al instante del trigger.
- Perfiles de movimiento de antena en el MCU: rotación constante, aceleración, wrap de 360°, parada
  y glitch.
- Entrada en el registro delta por la capa física LVCMOS 3,3 V frente a RS-422
  ([P-02](../alcance/pendientes.md#p-02)).

**Hito ZM3 (fin S18):** cada rayo llega etiquetado con az/el correctos y con error temporal acotado
y medido, bajo los cinco perfiles de movimiento, contra dos emuladores independientes.

## Z4 — Camino de datos, firmware y contrato (semanas 19–24) { #z4 }

Trabajo:

- AXI DMA scatter-gather S2MM hacia buffers circulares en la DDR del PS.
- FreeRTOS sobre Cortex-A9 (ver [D4](../portabilidad/registro-delta.md)). Ensamblado de rayos: I/Q
  diezmada más metadatos — az/el, PRF, modo de pulso, ancho, contador de trigger, timestamps y
  mapeo de canales.
- Framing DRx↔DSP contra el esquema congelado en Z0.
- lwIP raw API sobre GEM0 (PHY Marvell 88E1518, RGMII).
- Plano de control y configuración completo, incluyendo aplicación de constantes de calibración.
- **Actuación AFC**: retune del NCO a partir de la estimación suministrada por el DSP, verificado
  contra el modelo NumPy.
- Encuadre por modo de barrido: Split Cut, Batch Cut y Doppler Cut.
- Status y BITE con el catálogo de fallos adaptado
  ([Plan de testing](../pruebas/plan-testing.md#inyeccion-de-fallos)).
- Captura raw ventaneada a DDR como diagnóstico.

**Hito ZM4 (fin S24):** rayos completos consumidos por un stub de DSP sobre 1GbE, con configuración
íntegra desde el par remoto y el lazo AFC cerrado. Equivalente en ZedBoard de M2 + M3.

!!! warning "El stub de DSP de este hito no es el banco de pruebas extremo a extremo"
    Cerrar ZM4 contra un stub no cierra el hueco de [P-13](../alcance/pendientes.md#p-13): la
    salida real de esta placa (`vector_source`, datos generados en el PL) seguiría sin haber
    tocado nunca el DSP ni el RCP reales.

    Desde el **28-sep-2026** ese hueco es más pequeño y más concreto: los binarios reales del DSP
    y del RCP ya hablan entre sí (fase C0 de P-13), alimentados por un emisor sintético. Lo que
    falta es exactamente sustituir ese emisor por esta placa. Dos consecuencias para el firmware
    de aquí, las dos de C0 y ninguna opinable:

    - **El DRx conecta, no escucha** (regla "el productor conecta"). El DSP escucha en
      `LAMULA_DSP_DRX_ADDR`; el cliente TCP es este proyecto, en Z4.2.
    - **El azimut tiene que avanzar dentro del radial** cuando Z3 ponga az/el reales. El consumidor
      usa el azimut del primer y del último pulso para reconstruir el sector, y un radial de ancho
      cero no es archivable como Level-II ni aceptable para ORPG.

!!! success "26-sep-2026: Z4.0 — empaquetador de rayo + AXI DMA S2MM real, P&R cierra"
    Primera pieza de Z4, planeada explícitamente antes de escribir código (fases Z4.0–Z4.6, orden
    fijado con vladimir el 26-sep-2026) para que cada paso cierre algo probable antes del siguiente.
    Las salidas de `drx_range_gate_quad_top` (N_CH canales) por fin tienen un consumidor real —
    hasta ahora `gate_ready` iba fijo a alto y el I/Q se plegaba en `debug_probe` solo para
    sobrevivir a la síntesis (ver la cabecera vieja de `drx_top.sv`).

    - **`rtl/drx_ray_packer.sv`** (nuevo): entrelaza los N_CH canales en un único AXI4-Stream de 32
      bits (`2*IQ_BITS`, un canal por palabra — no un TDATA ancho de `N_CH*32` bits, que con N_CH=3
      no es potencia de dos y el AXI DMA de Xilinx solo admite anchos que sí lo son). `TLAST` es el
      AND de los N_CH `s_last` de la muestra capturada, no de un canal cualquiera. No asume
      sincronismo perfecto entre canales: solo captura cuando los N_CH `s_valid` están altos a la
      vez, con el FWFT de cada `drx_range_gate` reteniendo su dato mientras tanto.
    - **Verificado en L0 (Verilator+cocotb)**, no en xsim — es RTL propio sin IP de Xilinx de por
      medio. Hallazgo real: la VPI que genera `--public-flat-rw` no indexa los elementos de un array
      SIN empaquetar de un puerto de TOP (`"IndexError: s_valid(GPI_REGISTER) contains no object at
      index 0"`), así que hizo falta un shim de solo-testbench
      (`sim/tb_sv/drx_ray_packer_tb_dut.sv`) que reempaqueta puerto a puerto — mismo motivo, ya
      documentado, de por qué `drx_range_gate_quad_top`/`drx_ddc_quad_top` tampoco tienen test L0
      propio. Tres casos (orden entrelazado + TLAST, TLAST exige los N_CH `s_last` a la vez,
      backpressure intermitente): 3/3 PASS.
    - **`tcl/gen_zynq_bd.tcl`**: AXI DMA (`xilinx.com:ip:axi_dma:7.1`, scatter-gather, solo canal
      S2MM — MM2S es Z4.3) + `S_AXI_HP0` del PS7 (antes deshabilitado) + interrupción de fabric
      (antes deshabilitada, `s2mm_introut` → `IRQ_F2P`) + segundo maestro de GP0 (M01, vía su propio
      `axi_protocol_converter`) para el registro de control AXI-Lite del DMA + un segundo
      `axi_interconnect` combinando `M_AXI_SG`/`M_AXI_S2MM` contra HP0 + puerto externo
      `s_axis_ray` (AXI4-Stream, hacia `drx_top.m_ray_*` vía `rtl/drx_zynq_top.sv`). Dos hallazgos
      reales corriendo esto contra Vivado de verdad: (1) en modo síncrono `axi_dma` no tiene pin de
      reloj propio para `S_AXIS_S2MM` — vive en el dominio de `m_axi_s2mm_aclk`, no
      `s_axis_s2mm_aclk` (ese pin no existe); (2) el VLNV `axis_rtl` no trae `HAS_TLAST` a verdadero
      por defecto — sin fijarlo, `axi_dma` avisaba en corrida real ("Interface connected to
      S_AXIS_S2MM does not have TLAST port"), y TLAST es justo lo que cierra cada descriptor de
      scatter-gather.
    - **`rtl/drx_top.sv`**: `drx_ray_packer` instanciado, puertos nuevos `m_ray_valid/ready/data/
      last`. `debug_probe_xor` deja de plegar `gate_valid`/`gate_i`/`gate_q`/`gate_last` (ya
      alcanzan un puerto real vía el empaquetador) y en su lugar pliega `m_ray_valid`/`m_ray_data`/
      `m_ray_last` — necesario porque `drx_top` también se sintetiza SOLO, sin PS7 y sin DMA
      (`drx_top_tieoff.sv`, para medir WNS/utilización del datapath), y ahí nadie más da un sink
      real a esas tres señales.
    - **P&R real de `-top zynq` cierra** con el DMA/HP0/interrupción ya integrados: **WNS = 1,706
      ns** (`-step impl`, sube desde los 1,295 ns de cierre de Z2 — la ruta crítica sigue siendo
      PS7↔interconnect↔`drx_axil_regs`, sin tocar por este cambio). Post-síntesis, 0 críticos / 0
      errores (el único crítico real de esta sesión, el de TLAST de arriba, se corrigió antes de
      esta cifra). `-top drx_top` (tieoff, sin PS7) también resintetiza limpio, con el datapath
      completo verificado vivo — 153 DSP48E1/31 tiles de BRAM post-síntesis, misma cifra histórica
      de siempre, confirmando que `debug_probe_xor` sigue protegiendo la cadena entera.
    - **Lo que Z4.0 NO es todavía:** no hay firmware (`drx_app.elf` sigue siendo el *Hello World* de
      Vitis), nadie programa descriptores de scatter-gather todavía (Z4.2+), y nada de esto se probó
      en una ZedBoard física — ver la advertencia de siempre sobre "validado en ZedBoard" vs.
      "validado" a secas. Siguiente paso planeado: **Z4.1**, registro `TRIG_COUNT` (mapa de
      registros v7).

!!! success "26-sep-2026 (más tarde): Z4.1 — registro TRIG_COUNT, mapa de registros v7"
    `fases.md#z4` (arriba, "Trabajo") ya listaba "contador de trigger" como uno de los metadatos que
    el firmware de ensamblado de rayos (Z4.4) tiene que adjuntar a cada rayo, junto con az/el, PRF,
    modo de pulso, ancho y timestamps. Este registro es la fuente de hardware para ese dato, antes de
    que exista el firmware que lo lea.

    - **`config/registers.toml` v7**: `TRIG_COUNT` (offset 0x54, RO, 32 bits) — contador libre que
      incrementa un pulso de `pulse_trig` de `drx_timing_engine` por ciclo. `pulse_trig` es el mismo
      pulso que D-14 ya conecta a `ray_start` de `drx_range_gate_quad_top`, así que no hace falta
      ninguna señal nueva de `drx_timing_engine` — el valor de TRIG_COUNT en el momento en que un
      rayo termina de escribirse en DDR (interrupción de fin de descriptor del AXI DMA, Z4.0) es
      directamente el índice de ese rayo.
    - **RO puro, sin sticky ni write-1-to-clear** — a propósito, distinto de STATUS/OVERFLOW/
      GATE_TRUNCATED: esos tres son diagnósticos que firmware rearma; TRIG_COUNT es un conteo
      monótono que firmware solo lee. Envuelve en 2^32 pulsos.
    - **`rtl/drx_axil_regs.sv`**: nuevo puerto `pulse_trig_in`, un sumador de 32 bits sin reset más
      que a 0. `rtl/drx_top.sv` lo alimenta con `timing_pulse_trig` (la misma señal que ya alimenta
      `ray_start` vía `u_gate`).
    - **Verificado en L0**: `sim/tb/tb_drx_axil_regs.py` gana un caso nuevo — incrementa
      exactamente un pulso por ciclo, no se mueve sin pulsos, y una escritura no tiene ningún efecto.
      `make check` en verde (109 tests, mismo número que tras Z4.0 — es un sub-test de cocotb dentro
      de una entrada de pytest ya existente, no suma una entrada nueva).
    - **Sin P&R nuevo** — mismo criterio que v5/v6: lógica de bajo costo dentro de un módulo ya
      cerrado, sin tocar ningún camino crítico.
    - Siguiente paso planeado: **Z4.2**, FreeRTOS real (reemplaza el *Hello World* de Vitis) + driver
      de registros AXI-Lite + lwIP raw sobre GEM0 — primer bring-up físico de todo el proyecto.

!!! warning "26-sep-2026 (más tarde): Z4.2 — FreeRTOS + lwIP + driver de registros, compilado y empaquetado; **el bring-up físico sigue sin hacerse**"
    `drx_app` deja de ser el *Hello World* de Vitis (`fw/src/app/`, nuevo, versionado — no dentro de
    `build/`, que sigue sin trackearse). `tcl/gen_bsp.tcl` pasa de un único dominio `standalone`
    compartido a **dos dominios** sobre la misma plataforma: `standalone_domain` para `fsbl` (el FSBL
    de Xilinx no admite FreeRTOS, la propia plantilla "Zynq FSBL" lo confirma) y un
    `freertos_domain` nuevo (`-os freertos10_xilinx`) para `drx_app`, con la librería `lwip211` y la
    plantilla de Vitis "FreeRTOS lwIP Echo Server" (Xilinx-IP-first, igual criterio que
    `AGENTS.md`: no reinventar la pila de red) como base.

    - **Hallazgo real, no cosmético:** `app create -template {...}` NO aplica los parámetros de la
      librería que trae el `.mss` de referencia de esa plantilla
      (`freertos_lwip_echo_server.mss`: `api_mode=SOCKET_API`, `lwip_dhcp=true`,
      `dhcp_does_arp_check=true`, `pbuf_pool_size=2048`) — confirmado leyendo el `.tcl` de la
      plantilla (ninguna llamada a `bsp config`) y confirmado de nuevo corriendo `bsp listparams -lib
      lwip211` después de `bsp setlib`: `api_mode` por defecto es `RAW_API` y `lwip_dhcp` por defecto
      es `false`. `echo.c` de la propia plantilla usa `lwip_socket`/`accept`/`read`/`write` — con
      `RAW_API` no habría compilado. `tcl/gen_bsp.tcl` fija los cinco parámetros a mano con `bsp
      config` explícitos, no supone que el `app create` los trae solo.
    - **`fw/include/drx_regs_hw.h` + `fw/src/app/drx_regs_hw.c` (nuevo):** primer driver real sobre
      el mapa de registros generado (`fw/include/drx_regs.h`, v7). Envuelve `Xil_In32`/`Xil_Out32`
      sobre `XPAR_M_AXI_REGS_BASEADDR` — el nombre lo fija `tcl/gen_zynq_bd.tcl` (`m_axi_regs`, el
      puerto externo del BD), determinista, no una dirección adivinada. Sin estado propio: los
      latches sticky (STATUS/OVERFLOW/GATE_TRUNCATED/TIMING_STATUS) siguen viviendo en
      `drx_axil_regs.sv` (write-1-to-clear), este driver solo los lee/limpia.
    - **`fw/include/drx_status_task.h` + `fw/src/app/drx_status_task.c` (nuevo):** tarea de FreeRTOS
      de bring-up, primer consumidor real del driver de arriba — confirma `VERSION` contra
      `DRX_REGS_VERSION` al arrancar (detecta un firmware corriendo contra un bitstream con otro mapa
      de registros) y luego sondea/limpia los diagnósticos sticky cada segundo por UART. Se arranca
      **antes** de `lwip_init()` en `main_thread()` (`fw/src/app/main.c`, adaptado de la plantilla de
      Xilinx con ese único cambio funcional) — el bring-up de registros no depende de que el enlace
      Ethernet esté arriba. No escribe ninguna configuración de timing (`TIMING_CTRL`/PRF/etc.):
      eso es ensamblado de rayos, Z4.4, no bring-up.
    - **Verificado con una recompilación real de punta a punta, no solo lectura de código:** el XSA
      existente (`build/gw/zedboard_zynq/drx_zynq_top.xsa`) era de **antes** de Z4.1 (`TRIG_COUNT`,
      mapa v7) — comparado el timestamp del XSA contra el de `rtl/drx_axil_regs.sv`/
      `config/registers.toml`, el XSA era más viejo. Se re-corrió `-top zynq -step xsa` completo
      (synth+impl+bitstream+XSA) antes de generar el BSP: **WNS = 1,711 ns** (bajando un poco de los
      1,706 ns de Z4.0/Z4.1 — mismo camino crítico PS7↔interconnect↔`drx_axil_regs`, sin cambiar).
      Con el XSA fresco, `tools/build_vitis.sh zedboard` corrió `tcl/gen_bsp.tcl` de punta a punta:
      `drx_app.elf` compila limpio (`drx_regs_hw.c`, `drx_status_task.c`, `main.c` propios + `echo.c`/
      `iic_phyreset.c` de la plantilla, únicos warnings los de `contrib/ports/xilinx/netif/xadapter.c`
      de lwIP, no de código propio) y enlaza sin símbolos sin resolver. `tools/make_boot.sh zedboard`
      empaqueta `BOOT.BIN` con el `drx_app.elf` nuevo — reproducible byte a byte en dos corridas
      (mismo SHA-256), con el mismo aviso de solapamiento de rangos de `bootgen` ya conocido desde el
      cierre de BSP/FSBL (26-sep, más arriba) — no es una regresión de esta sesión. `make check` sigue
      en 109/109: el firmware de `fw/src/app/` no lo toca (compila solo dentro del flujo de Vitis/
      xsct, `fw/Makefile` sigue siendo exclusivamente la auto-comprobación de parámetros para host).
    - **Lo que esto NO demuestra, y es la brecha real de Z4.2 tal como la define
      `z4-firmware-plan-order` (memoria del agente):** nada de esto corrió en una ZedBoard física.
      No hay UART conectado, no hay confirmación de que `DrxStatusTask_Create` de verdad imprime la
      versión del mapa contra hardware real, no hay enlace Ethernet levantado, ni ping ni conexión al
      puerto 7 del echo server. Este entorno no tiene acceso a la placa (ver la advertencia de
      siempre: "no escribas «validado» donde corresponde «validado en ZedBoard»" — aquí ni siquiera
      hay ZedBoard de por medio). **Z4.2 no cierra con esta sesión**: cierra software/toolchain
      (dominio FreeRTOS, driver, tarea, tres compilaciones reales de punta a punta) pero el "primer
      bring-up físico" que el propio nombre de la fase promete sigue pendiente de alguien con acceso
      a la placa y un cable serie/Ethernet.

!!! success "1-oct-2026: el motor de timing corriendo en silicio, y `BOOT.BIN` deja de llevar el bitstream equivocado"
    Dos cosas en la misma sesión, las dos sobre la ZedBoard física que la escalera de bring-up
    (`bringup/README.md`) dejó caracterizada. **No es Z4.3** tal como la define el orden congelado
    el 26-sep —framer del contrato, `vector_source` por DMA, MM2S, `test_stimulus_select`—; es el
    paso de bring-up que faltaba entre Z4.2 y Z4.4, y la medida «en placa» que es lo único que le
    falta al hito ZM2.

    - **`tools/make_boot.sh` empaquetaba `drx_top_tieoff.bin`**, el flujo **sin** PS7, con el
      AXI-Lite atado a valores inertes — mientras que el FSBL y `drx_app.elf` se compilan contra
      `build/gw/zedboard_zynq/drx_zynq_top.xsa`, donde `m_axi_regs` sí existe. Todo `BOOT.BIN`
      anterior al 1-oct-2026 lleva por tanto un bitstream en el que el esclavo AXI que el firmware
      direcciona no está presente. Nadie lo detectó porque **`BOOT.BIN` nunca se arrancó desde SD**:
      el bring-up físico fue por JTAG. Corregido a `build/gw/${platform}_zynq/drx_zynq_top.bin` —
      el mismo directorio del que `tools/build_vitis.sh` saca el XSA, que es lo que garantiza que
      el mapa de direcciones del firmware y el del hardware salgan de la misma corrida de Vivado.
      Con la corrección, `BOOT.BIN` sigue saliendo reproducible byte a byte.
    - **El aviso de solapamiento de `bootgen` queda cerrado como falso positivo**, con datos y no
      por analogía. `bootgen -arch zynq -read BOOT.BIN` da `load_addr` = `0x00000000` para
      `fsbl.elf` (longitud `0x18008`), `0x00000000` para el bitstream y `0x00100000` para
      `drx_app.elf` (longitud `0x30008`). El FSBL termina en `0x18008`, muy por debajo de
      `0x100000`: el único solapamiento es contra el `0x0` del bitstream, que no es una dirección
      de memoria — una partición de bitstream se carga por PCAP, no a DDR. Ya no es deuda abierta.
    - **`fw/src/app/drx_timing_cfg.c` + `fw/include/drx_timing_cfg.h` (nuevos):** el firmware por
      fin escribe la configuración del motor de timing. Hasta ahora todos los registros de timing
      valían su valor de reset, 0, que D-09 rechaza (`pulse_width` 0 no está en
      `PULSE_WIDTH_CYCLES`, `bins` 0 está por debajo del mínimo de 1) — con los dos lotes
      inválidos `drx_timing_engine` mantenía el secuenciador parado, no salía ningún `pulse_trig`
      y por tanto no había `ray_start`. Eso es exactamente lo que se vio en placa como
      `TIMING_STATUS = 0x6` con `TRIG_COUNT` clavado en 0. La secuencia que implementa
      `DrxTiming_Start()` es: parar el secuenciador (los registros solo son seguros de escribir con
      el motor parado, cabecera de `drx_prf_batch_seq.sv`) → escribir → **releer por AXI-Lite y
      comparar** → limpiar los sticky de reset → arrancar → medir. La relectura no es adorno:
      separa un camino de registros roto (los valores no vuelven) de un rechazo de D-09 (vuelven
      bien pero `TIMING_STATUS` marca el lote inválido), que son dos fallos con el mismo síntoma
      visible.
    - **Todos los valores se derivan de `fw/include/drx_params.h`**, ninguno es un número suelto
      (D-02). `prf_div` de cada lote es el máximo de **dos** pisos, no uno: el de rango no ambiguo
      del lote (D-09, que el RTL sí comprueba) y `PRF_DIV_MIN`, el techo de PRF del sistema
      (1200 Hz), que `drx_timing_config_valid.sv` **no** comprueba. Para el lote bajo manda el
      primero (767.198 > 208.333); para el alto manda el segundo, porque `PRF_DIV_MIN_HIGH` vale
      191.800 y `config/params.toml` ya avisa de que ese piso es no-vinculante hoy. Los bins por
      lote se calculan como `prf_div / R1`, acotados por `BINS_MODE_FINE` y con un bin de guarda,
      porque un rayo de N bins ocupa `N · R1` ciclos y pasarse del PRI dispara `ray_truncated`.
      Configuración resultante: lote bajo `prf_div` 767.198 (81,47 Hz) / `pulse_width` 825 /
      3687 bins / 6 pulsos; lote alto 208.333 (300,00 Hz) / 200 / 1000 bins / 41 pulsos; los 4
      canales de `drx_trigger_gen` escalonados a 0/10/20/30 µs con anchos de 1/2/4/8 µs, para que
      una sola punta de osciloscopio pueda identificar cuál es cuál en los pines de `trig_out` del
      Pmod JA.
    - **Verificado en ZedBoard**, por JTAG, con el bitstream y el XSA ya existentes (ni una línea
      de RTL cambió, así que no hizo falta P&R nuevo). Por `/dev/ttyACM0`:
      `drx_timing: en 1000 ms TRIG_COUNT avanzo 217 (esperado ~223), TIMING_STATUS = 0x1`. El
      `0x1` es `radial_done` y **solo** `radial_done`: los bits 1 y 2 (`config_invalid` de los dos
      lotes) están en 0, es decir D-09 acepta la configuración en silicio. La tarea de estado
      confirma el régimen permanente: `TRIG_COUNT` avanza ~223,7 pulsos/s medidos contra los
      223,47 que predice `(n_bajo + n_alto) / duración del radial` — 0,1 % de diferencia, que es
      la confirmación de que la PRF en placa es la pedida, no solo de que el contador se mueve.
    - **Hallazgo de método:** la primera ventana de medida eran 500 ms y dio 99 pulsos frente a
      los 111 del promedio, un 11 % de menos que no era un fallo del motor. Los pulsos no están
      repartidos de forma uniforme dentro de un radial —6 pulsos a ~81 Hz en el lote bajo, 41 a
      300 Hz en el alto—, así que una ventana corta que arranca en el borde del radial cae casi
      entera en la parte dispersa. Ventana subida a 1000 ms (casi 5 radiales) y criterio convertido
      en una banda de ±12,5 % alrededor del promedio: así deja de ser «`TRIG_COUNT` se movió» y
      pasa a ser «`TRIG_COUNT` se mueve a la PRF pedida».
    - **`STATUS (overrun) = 0x7` y `GATE_TRUNCATED = 0x7` siguen activos, y es lo esperado.**
      `rtl/drx_zynq_top.sv:175` conecta `m_ray_ready` a `s_axis_ray_tready` del AXI DMA, y **nadie
      programa descriptores todavía** — eso es Z4.4. Con `TREADY` en bajo para siempre, el
      `drx_ray_packer` no drena, `gate_ready` se queda en bajo, cada banco de `drx_range_gate`
      desborda (`overrun`) y cada `ray_start` nuevo encuentra el banco a medias
      (`ray_truncated`, D-14). Los dos diagnósticos están reportando correctamente la ausencia de
      consumidor, no un fallo del motor de timing. El bin de guarda que descuenta
      `bins_for_pri()` no se puede comprobar hasta que el DMA drene de verdad.
    - Siguiente paso: **Z4.3** de verdad, tal como lo fija el orden congelado — framer/parser del
      contrato en C, `vector_source` con modo Throttled(DDR) alimentado por DMA, AXI DMA MM2S y el
      mensaje `test_stimulus_select`.

!!! success "1-oct-2026 (más tarde): Z4.3 — contrato v0.5, framer en C, `vector_source` por DMA y el catálogo de estímulos elegible en caliente"
    Z4.3 tal como lo fija el orden congelado el 26-sep: framer/parser real del contrato en C,
    `vector_source` con modo Throttled(DDR) alimentado por DMA, AXI DMA MM2S, y el mensaje
    `test_stimulus_select`. Entregado en cinco pasos, cada uno cerrando algo probable antes del
    siguiente.

    **a — Contrato v0.5.** Mensaje nuevo `test_stimulus_select` (`down`, `type_id` 6, 8 B: `seq`,
    `vector_id`, relleno, `repeat`; 0 = bucle indefinido), enumeración `stimulus_vector` con el
    catálogo v1 —los ocho casos de `tools/gen_l1_vectors.py`, en ese orden— y dos códigos de error
    nuevos: `vector_unknown` (10) y `unimplemented` (11). El segundo no estaba previsto y hace
    falta de verdad: un receptor que CONOCE un `msg_type` pero todavía no lo aplica no puede
    contestar `unknown_message` sin mentir, porque eso le dice al otro lado que hablan versiones
    distintas. Las tres implementaciones regeneradas desde el esquema; `contract/tests/` sube a 10
    casos con dos nuevos que fijan el acoplamiento que el mensaje introduce — el catálogo del
    contrato y los casos del generador tienen que listar lo mismo **y en el mismo orden**, porque
    `vector_id` es el índice y reordenar el generador renombraría en silencio lo que ya está en el
    cable.

    **b — Framer y parser en C** (`fw/src/app/drx_contract_io.c`, `fw/include/drx_contract_io.h`).
    No existía nada: lo generado eran structs y `_Static_assert` de layout, y lo que viaja por el
    cable es una trama. El parser es incremental y con estado porque TCP parte los mensajes donde
    quiere. Dos decisiones que vale la pena no descubrir dos veces:

    - **`DrxFrameStatus` NO es `drx_dsp_error_t`.** Un `magic` que no cuadra significa que el flujo
      entero no es de este contrato y lo que procede es cerrar, no contestar; mezclarlo con los
      códigos del contrato habría obligado a inventar uno para algo que el contrato no cubre.
      `DrxFrame_ErrorCode()` traduce solo los que sí son contestables.
    - **Tras una cabecera inválida el parser se para en seco.** Saltarse la trama mala exigiría
      adivinar dónde empieza la siguiente, y un acierto por casualidad entregaría un mensaje
      inventado al plano de control.

    Y **`fw/src/app/drx_control.c`**, el plano de control: traduce mensaje a acción y produce la
    respuesta. Las acciones entran por una tabla de punteros, así que ni el framer ni el despacho
    dependen de Xilinx y los dos se compilan también para el host. Ahí los ejercita
    `fw/tests/test_contract_io.py` y `fw/tests/test_control.py` contra la implementación de Python
    generada del mismo esquema: tramas byte a byte en los dos sentidos, el parser dando lo mismo
    con empujones de 1, 7, 12 y 13 bytes (12 es exactamente la cabecera, 13 la cruza por uno), cada
    fallo de validación con su estado y su código, y el camino bytes → acción → bytes con el `seq`
    devuelto tal cual y el error de la ACCIÓN y no uno inventado por el despacho. **El fichero que
    se prueba es el mismo que Vitis compila cruzado para el Cortex-A9, no una copia.**

    **c — `vector_source` gana el modo Throttled(DDR)** y, con él, su primer L0 (no lo tenía: sus
    puertos por canal son arrays sin empaquetar y la VPI de Verilator no los indexa, así que hizo
    falta el mismo tipo de shim que ya usa `drx_ray_packer`). Stream de 16 bits, una muestra por
    beat, canales en orden ascendente; los N_CH avanzan en bloque. Mapa de registros a **v8**:
    `CTRL` bit 1 `vector_source_ddr`, un bit que v1–v7 declaraban reservado. El modo NO reemplaza a
    BRAM-loop —quitarlo habría perdido el único modo que sostiene la tasa real— y la elección pasa
    a ser de runtime, que es el punto entero del ejercicio.

    **d — AXI DMA MM2S en el block design.** Tercer maestro contra el mismo `S_AXI_HP0`, y la
    interrupción obliga por fin al `xlconcat` que la entrada de Z4.0 anticipaba (In0 = S2MM,
    In1 = MM2S, orden fijo porque el firmware lo necesita para elegir el ID). **Hallazgo real de
    Vivado:** en un puerto de interfaz externo en modo **Master** los parámetros del interfaz son
    de SOLO LECTURA —se derivan del maestro conectado— y fijarlos produce cuatro
    `CRITICAL WARNING [BD 41-737] ... It is read-only.` sin ningún efecto. Es lo contrario del
    puerto Slave `s_axis_ray`, donde fijarlos sí hace falta. Peor: la propagación de parámetros del
    BD corre dentro de `validate_bd_design`, así que leído antes el puerto todavía dice **1 byte**
    aunque el pin del DMA ya diga 2 — y `rtl/drx_zynq_top.sv` declara 16 bits, que Verilog habría
    truncado en silencio en el wrapper. El script ya no fija nada ahí y en su lugar **comprueba**
    el ancho después de validar; la comprobación saltó de verdad mientras se escribía esto, que es
    la razón por la que existe. P&R cierra: **WNS = 1,634 ns, WHS = 0,020 ns** (desde 1,711 ns —
    mismo camino crítico PS7↔interconnect↔`drx_axil_regs`).

    **e — Firmware y catálogo.** `tools/gen_stimulus_catalog.py` vuelca los MISMOS ocho casos —
    importados de `gen_l1_vectors`, no copiados; el único cambio es la longitud, que pasa a ser
    parámetro — a 62 KiB de C que viajan en la imagen. Artefacto de build, no versionado, igual que
    el `.hex` de la BRAM. `fw/src/app/drx_stimulus.c` monta el buffer entrelazado en DDR y lo
    entrega por un anillo de descriptores de `xaxidma` (el DMA es scatter-gather desde Z4.0, así
    que `XAxiDma_SimpleTransfer` no existe aquí). Por sondeo y no por interrupción a propósito: la
    tarea que rearma el DMA entre pasadas no tiene plazo que cumplir, y montar el GIC para ella
    sería código que Z4.4 va a reescribir.

    **Verificado en ZedBoard**, por JTAG:

    ```
    drx_stimulus: AXI DMA MM2S listo, 8 vectores de 4000 muestras
    drx_stimulus: vector 0 (tono_if), repeat=2
    drx_stimulus: vector tono_if -- pasadas=2 errores=0 OVERFLOW 0 -> 0
    drx_stimulus: DDR -> MM2S -> vector_source confirmado en placa
    drx_stimulus: vector 7 (tono_sobre_escala), repeat=2
    drx_stimulus: vector tono_sobre_escala -- pasadas=2 errores=0 OVERFLOW 0 -> 0
    ```

    Que una pasada se COMPLETE no es contabilidad: el stream tiene backpressure y el único que
    levanta `tready` es `vector_source` en modo Throttled(DDR) consumiendo beats. Si el modo no
    estuviera puesto, si el ancho no cuadrara o si el conjunto de N_CH no se llenara, el DMA se
    quedaría a medias. Dos pasadas completas con 0 errores es por tanto prueba de que los **bytes**
    recorrieron DDR → MM2S → PL.

    **Lo que esto NO prueba, y conviene decirlo:** que el **dato** llegue correcto hasta la salida
    del DDC. El ensayo A/B buscaba justamente eso —el último vector del catálogo es el de +6 dBFS,
    pensado para saturar— y `OVERFLOW` salió 0 con los dos, así que no discriminó. La lectura más
    probable es que no sea un fallo sino el comportamiento esperado: el vector se satura ya en el
    generador al recortarlo a 16 bits, y una senoide recortada pierde amplitud de fundamental al
    pasar por el FIR, mientras que el ajuste de ganancia de la cadena está calculado para una
    senoide limpia. Lectura alternativa, menos probable: que el dato no esté llegando y solo el
    handshake sí — pero eso exigiría que `vector_source` presentara muestras distintas de las que
    latcheó, que es lo que su L0 comprueba. **No está medido**, y el primer sitio donde se medirá
    es Z4.4, que es cuando por fin hay camino de vuelta para leer un rayo.

    Lo demás que sigue sin probarse en placa es lo mismo que antes: `STATUS (overrun) = 0x7` y
    `GATE_TRUNCATED = 0x7` siguen activos porque nadie programa descriptores S2MM todavía.

    **Deuda que deja este paso, anotada aquí para que no se pierda:** `DRX_STIMULUS_N_CH` está
    escrito a mano en `fw/include/drx_stimulus.h` y tiene que coincidir con el `parameter int
    N_CH = 3` de `rtl/drx_top.sv`. `N_CH` no vive hoy en `config/params.toml`, así que no hay nada
    que compruebe la coincidencia. Si divergen no hay error: el buffer se entrelaza con un paso
    distinto del que `vector_source` deshace y en placa se ve como un espectro raro sin ninguna
    pista del origen.

    - Siguiente paso: **Z4.4** — ensamblado de rayos sobre la interrupción de fin de descriptor
      S2MM, framing real sobre el contrato, y el manejo del `config` de 2 lotes que cierra P-15 del
      lado del contrato. Es también donde `STATUS`/`GATE_TRUNCATED` deben dejar de estar en `0x7` y
      donde se puede por fin mirar el dato.

!!! success "1-oct-2026 (noche): Z4.4 — rayos ensamblados, medidos contra el modelo, y P-15 cerrado"
    El camino de vuelta. `STATUS (overrun)` y `GATE_TRUNCATED` **caen de `0x7` a `0x0`** y llegan
    **231 rayos en 1000 ms** con `dma_errors = 0`, `bad_magic = 0`, `bad_n_ch = 0`, `short = 0`,
    `trig_gaps = 0` y `ray_gaps = 0` — uno por disparo de PRF, sin perder ninguno. Medido en
    ZedBoard por JTAG; P&R de `-top zynq` cierra en **WNS = 2,045 ns, WHS = 0,016 ns**.

    **Y por fin se midió el DATO, que es lo que Z4.3 no pudo.** Un rayo completo del lote bajo
    (`idx=279`, `bins=3689`, 11067 palabras) congelado en DDR, leído con `mrd` y contrastado contra
    `model/drx_model` alimentado con el mismo estímulo: pico en continua en los tres canales,
    **−9,02 dBFS medidos contra −9,02 dBFS del modelo**, misma potencia. La comparación es espectral
    y no muestra a muestra a propósito: el rayo empieza en un punto arbitrario del vector en bucle y
    4000 no es múltiplo de 208, así que no existe desplazamiento entero que alinee las dos series.
    Herramienta: `tools/dump_ray.py`.

    **a — Contrato v0.6, cierra [P-15](../alcance/pendientes.md#p-15).** `config` pasa a declarar los
    dos lotes (`prf_div_low/high`, `pulse_width_idx_low/high`, `n_pulses_low/high`,
    `range_bins_low/high`; de 48 a 60 B) y el enum `ray_flag` gana `batch_high`. Se rompe el mensaje
    en vez de añadir otro al lado: `config` está definido como atómico y mantener una variante de un
    solo lote modelaría un modo que D-13 descartó. `DrxTiming_Apply()` lo aplica valida-entero-antes-
    de-escribir y restaura la última configuración buena si el RTL lo rechaza.

    **b — Metadato de rayo EN BANDA.** `drx_ray_packer` antepone cuatro palabras —magic,
    `trig_count`, `ray_index`, `bin_count` más banderas de lote y celda— y TLAST sigue cayendo en el
    último beat de datos, así que un descriptor cubre cabecera y datos. Leer `TRIG_COUNT` desde el
    manejador **llega tarde**: el banco de ping-pong se completa unos cientos de ciclos antes del
    siguiente disparo y una interrupción de FreeRTOS no atiende en 5 µs; justo en el borde entre
    lotes eso atribuye el rayo al lote equivocado, que es el único caso que el metadato existe para
    distinguir. El metadato se congela al empezar a VACIAR el rayo, no en su `ray_start`: entre esos
    dos instantes pasa un rayo entero, y guardarlo exigiría una FIFO que se desincronizaría para
    siempre al primer rayo descartado. `c_sg_length_width` sube de 14 a 23 bits para que un rayo
    fino (44 284 B) quepa en un solo descriptor.

    **c — Hallazgo de placa: el PRI tiene que ser múltiplo de R₁, o `ray_truncated` miente.** Con el
    reparto anterior (PRI en el piso de D-09 y un bin de guarda) el rayo se completa unos ciclos
    antes del siguiente `ray_start`, y en ese hueco el DDC —que corre libre— escribe una o dos
    muestras decimadas en el banco siguiente. `ray_start` encuentra `wr_ptr != 0` y
    `drx_range_gate` levanta `ray_truncated` **sin haber perdido ningún rayo**: lo descartado es
    tiempo muerto. Medido: `GATE_TRUNCATED = 0x7` permanente con 231 rayos/s, `trig_gaps = 0` y
    `ray_gaps = 0` a la vez. Con el PRI redondeado arriba al múltiplo de R₁ (767 312 y 208 416, con
    3689 y 1002 bins) entran exactamente `prf_div / R₁` muestras por PRI, el banco cierra en su
    última muestra y la bandera se queda en 0. El BITE de D-14 no distingue por sí solo «llegó tarde
    y cortó un rayo» de «llegó dos muestras después del cierre natural».

    **d — `overrun` al arrancar el consumidor no es un fallo de régimen permanente.** El range-gate
    lleva llenando bancos desde que arrancó el motor de timing y nadie los vaciaba, así que los dos
    quedan marcados pendientes; el primer banco que se completa tras armar el anillo levanta
    `overrun` una vez. `DrxRay_SelfTest()` espera `DRX_RAY_SETTLE_MS` **antes** de limpiar los
    sticky por eso. Con la espera, `overrun` se queda en 0.

    **e — Framer del mensaje `ray`**, en su propio fichero y sin dependencias de Xilinx, compilado
    también para host y comparado byte a byte contra la implementación de Python generada del mismo
    esquema. El detalle que justifica el fichero y su test es el orden **I/Q**: la DDR trae
    `{I[31:16], Q[15:0]}` —en memoria `Q_lo Q_hi I_lo I_hi`— y el contrato pide el par en orden I,Q.
    Copiar la palabra tal cual produce una trama con cabecera y `payload_len` correctos y con I y Q
    cambiados en todos los bins; el parser del otro lado no puede verlo. En placa se montó la trama
    de un rayo real: **44 316 B** para 3689 bins × 3 canales, que es exactamente
    12 + 36 + 11 067 × 4.

    **f — El plano de control, ejercitado en silicio.** `drx_control_boot.c` monta un `config` de 2
    lotes con el mismo codificador que usará el cable, lo empuja por el mismo parser y comprueba que
    el `config_ack` lleva el `seq` original y que los registros cambiaron:
    `PRF_DIV_LOW 767312 -> 800000`. Lo único que no cubre es el socket. (La primera versión usaba
    `PRF_DIV_MIN_LOW`, que es justo lo que la configuración de bring-up ya deja escrito, así que la
    comprobación pasaba sin demostrar nada — se vio en la primera corrida: `767198 -> 767198`.)

    **g — Deuda de Z4.3 cerrada:** el número de canales pasa a `config/params.toml` (`n_ch_top`), de
    donde salen tanto `rtl/drx_top.sv` como `fw/include/drx_stimulus.h`, y además viaja en la
    cabecera del rayo, así que una divergencia sale en el primer rayo en vez de como un espectro raro
    sin origen.

    **Hallazgo nuevo abierto:** [P-16](../alcance/pendientes.md#p-16) — Throttled(DDR) y el motor de
    timing no pueden correr a la vez. En ese modo `s_valid` hacia el DDC está alto 1 de cada N_CH+1
    ciclos, así que un rayo necesita unas cuatro veces el PRI y `ray_start` lo trunca antes. La
    medida de rayos corre por eso en BRAM-loop, cuyo contenido es exactamente el caso `tono_if` del
    catálogo (comprobado array a array). No bloquea Z4.4.

    **Lo que NO está hecho:** no hay transporte. El framer y el plano de control están y se ejercitan,
    pero nadie abre un socket: el DSP real es **Z4.6**. `drx_ray.c` deja el sumidero como puntero de
    función precisamente para que ese paso sea un fichero nuevo y no una reescritura. Tampoco hay
    encoders SSI (P-02), así que todo rayo sale marcado `azel_invalid`, y el `timestamp_ns` se deriva
    de `trig_count` y FS_HZ: monótono y exacto en ciclos, pero no atado a ninguna hora de pared.

    **CI en rojo desde Z4.3, arreglado aquí.** El job `gateware` del runner propio no tiene entorno
    de Python: es otro job, con su propio checkout limpio, y no hereda el `.venv` que monta el job
    de substrato. Desde Z4.3 `tools/build_vitis.sh` genera el catálogo de estímulos con el modelo
    dorado, que necesita numpy, así que el paso «BSP/FSBL/app (Vitis)» moría en 0,13 s con
    `ModuleNotFoundError: No module named 'numpy'` — después de 27 minutos de síntesis. Las corridas
    de Z4.3 y de la primera de Z4.4 quedaron ambas en rojo por esto, y **no se miró hasta después de
    pushear Z4.4**: la lección operativa es que un push no está cerrado hasta que el job termina.
    `ci.yml` monta ahora el venv en ese job (con `$HOME/.local/bin` en el PATH, porque `uv` está
    instalado para el usuario y el servicio systemd del runner no lo trae), y `build_vitis.sh` deja
    de caer a un `python3` pelado: falla diciendo «correr primero `make venv`». Verificado corriendo
    los dos pasos en el propio workspace del runner antes de volver a pushear.

    - Siguiente paso: **Z4.5** — status/BITE sobre el contrato y actuación de AFC, que obliga a
      regenerar el IP del DDS Compiler con `S_AXIS_CONFIG` y a repasar la matriz 16/16 de D-12.

!!! warning "2-oct-2026: Z4.5 — actuación AFC y status/BITE; verificada en simulación, sin bring-up en placa"
    Primera vez que el NCO se puede retunear en tiempo de ejecución. Hasta hoy no era una cuestión
    de firmware: el incremento de fase vivía **congelado en la personalización de la IP**
    (`Phase_Increment {Fixed}` en `tcl/gen_ip.tcl`) y el DDS Compiler no exponía ningún puerto por el
    que cambiarlo. Z4.5 regenera esa IP, añade el registro que la escribe y el firmware que decide
    cuándo, y monta por fin el mensaje `status` del contrato, que llevaba congelado desde Z0 sin que
    nadie lo construyera.

    - **IP regenerada con `Phase_Increment {Programmable}`.** Medido sobre la IP generada de verdad,
      no supuesto: el cambio añade `s_axis_config_tvalid` + `s_axis_config_tdata[31:0]` y no mueve
      nada más — `Latency` sigue en 9, `Phase_offset` sigue `{Fixed}` con el mismo `POFF1`,
      `Noise_Shaping` sigue en Taylor. `PINC1` deja de ser *el* incremento y pasa a ser el **valor
      inicial** tras `aresetn`, que es lo que mantiene el camino sin AFC bit a bit igual que antes.
    - **Hallazgo real de infraestructura: `tcl/gen_ip.tcl` no era idempotente.** `create_ip
      -module_name X` con `ip/X/` ya presente **no reconfigura** esa IP: crea `ip/X_1/` en silencio y
      sigue, así que el `.veo` que el propio script lee después es el viejo y el XCI versionado se
      queda como estaba. No se había notado porque el script se corrió una sola vez, en Z1, y Z4.5 es
      la primera vez que hace falta **cambiar** la personalización de un core ya creado. Corregido
      con `ensure_ip`, que hace `read_ip` si el XCI existe y `create_ip` si no — sin borrar nada. El
      diff resultante del XCI es mínimo y legible (`Phase_Increment`, `C_HAS_S_CONFIG`,
      `C_S_CONFIG_TDATA_WIDTH` y los dos puertos nuevos), que es justo lo que se quiere de un
      artefacto versionado.
    - **Mapa de registros v9**: `NCO_PINC` (`0x58`, RW, 32 bits), valor de reset `NCO_PHASE_INC`,
      una sola palabra para los `N_CH` canales. Cada escritura pulsa un ciclo el canal de
      configuración del core — sin TREADY, se acepta siempre. Detalle y verificación L0 en
      [`registros.md`](registros.md#z4-en-v9).
    - **Contrato v0.7**: código de error nuevo `afc_out_of_range` (12). El campo `nco_phase_inc` del
      mensaje `afc` viaja como u64 a propósito (la ZU9 podría tener un acumulador más ancho sin
      cambiar el esquema), así que un receptor de 32 bits tiene que poder **decirlo** en vez de
      truncar: truncar convierte una corrección equivocada en una frecuencia de mezcla equivocada sin
      ningún síntoma hasta que alguien mire el espectro. `afc` no lleva `seq` y no se contesta, de
      modo que ese código viaja en `last_error` del mensaje `status` — para lo cual `drx_control.c`
      deja de tirar el resultado de `apply_afc`.
    - **Firmware, con el mismo reparto de siempre**: `drx_afc.c` (lógica pura, sin Xilinx ni
      FreeRTOS, compilada también para el host y cubierta por `fw/tests/test_afc.py`) decide
      *cuándo*; `drx_afc_app.c` escribe el registro. `apply_at_seq` se respeta de verdad: la
      corrección se aplica **entre rayos**, en el enganche que `drx_ray.c` llama al entregar cada
      uno, porque el salto de palabra de fase no conserva la fase del acumulador y aplicarlo a mitad
      de rayo lo dejaría con dos frecuencias de mezcla. La comparación con `apply_at_seq` es con
      diferencia **con signo**, no `>=`: `ray_index` envuelve en 2^32 y un `>=` plano dejaría una
      corrección colgada media eternidad cada vez que el contador diera la vuelta.
    - **Status y BITE**: `drx_status_frame.c` (otra vez sin Xilinx, contrastado byte a byte contra el
      Python generado en `fw/tests/test_status_frame.py`) monta el mensaje, y la tarea de diagnóstico
      acumula los contadores. Los registros sticky son write-1-to-clear, así que leerlos **es**
      destructivo y sólo puede hacerlo un sitio: por eso acumula la tarea y no el emisor. Tres
      banderas del catálogo se reportan a cero **y se dice por qué** en vez de rellenarlas en
      silencio: `ssi_timeout`/`ssi_frame_error` no tienen fuente hasta Z3, `mmcm_unlocked` no llega
      al mapa de registros (haría falta un bit nuevo en STATUS) y `link_down` lo sabrá lwIP en Z4.6.
    - **La matriz de 16 corridas de D-12 cerró en verde: 16/16.** Es el gate de verdad de este
      cambio y por eso se corrió entera antes de commitear nada: si el arranque del Phase Generator
      se hubiera movido al pasar a `{Programmable}`, el desfase `NCO_LUT_OFFSET_K = 655` dejaría de
      cancelar y la comparación bit a bit lo diría de inmediato. No se movió. Los ocho casos ×
      {fine, coarse} dan «dentro de tolerancia (D-12) contra el modelo dorado» —315 muestras en
      fino, 157 en grueso— sin una sola discrepancia. Coste real, por si alguien la vuelve a correr:
      ~20-25 minutos de `xsimk` por caso y `tcl/sim_l1.tcl` rehace el proyecto en cada uno, así que
      la matriz entera son ~3 h con tres casos en paralelo. Cada caso con su `-outdir` nuevo: un
      directorio de build reutilizado es exactamente lo que causó los dos falsos fallos de
      [P-09](../alcance/pendientes.md#p-09).
    - **Lo que falta para cerrar Z4.5, y no es menor:**

        1. ~~No hay P&R con la IP nueva.~~ **Resuelto el mismo día: `-top zynq -step xsa` cierra
           con la IP programable dentro — WNS = 1,626 ns, WHS = 0,015 ns, «All user specified timing
           constraints are met»**, 0 endpoints fallando ni en setup ni en hold sobre 75288. Baja
           desde los 2,045 ns de Z4.4: el canal `S_AXIS_CONFIG` añade lógica dentro del core y el
           registro `NCO_PINC` cuelga del mismo camino crítico PS7↔interconnect↔`drx_axil_regs` que
           viene estrechándose desde Z2. Sigue sobrando casi un cuarto de periodo a 62,5 MHz, pero el
           margen ya no es holgado y conviene medirlo en cada registro nuevo. Utilización post-route:
           LUT 19,62 % (10438/53200), registros 18,47 % (19653/106400), BRAM Tile 22,50 %
           (31,5/140), **DSP48 159/220 (72,27 %)** — el DSP48 no se movió, es la misma cifra desde el
           PS7 del 20-sep, así que el canal de configuración del DDS no cuesta multiplicadores.
           Aviso de lectura del log: la corrida emite un `ERROR: [Common 17-176] Overwrite of
           existing file isn't enabled ... dds_compiler_nco.dcp` y **termina igual en `rc=0`** — es
           `synth_ip` negándose a rescribir un `.dcp` que ya estaba sintetizado del XCI nuevo
           (12:24 contra las 08:39 del XCI), no un fallo de síntesis.
        2. ~~El retune no está verificado contra el modelo dorado.~~ **Resuelto el mismo día:
           `afc_retune__{fine,coarse}` PASA** — 315 muestras en fino y 157 en grueso dentro de
           tolerancia (D-12) contra el modelo dorado, con `NCO_PINC = 1073741824` escrito tras soltar
           el reset. La hipótesis `_AFC_RETUNE_AT = 0` queda **confirmada por medición**: el core
           aplica la configuración antes de su primera salida, así que no hace falta calibrar ningún
           desfase. Que NCO_PINC cambie era un registro; esto es el NCO mezclando de verdad a la
           frecuencia nueva, bit a bit contra NumPy. Queda el A/B en placa, que es otra pregunta
           (silicio, no simulación). Cómo está montado:

            - **L1, bit a bit.** El modelo dorado acepta ahora un retune
              (`NcoTaylor.retune_at`/`retune_inc`, `Ddc.nco_retune`; sin él, el oráculo de D-12 no
              se mueve — los 87 tests del modelo siguen en verde, huella SHA-256 incluida), el
              manifiesto de un caso lleva `nco_pinc`/`nco_retune_at`, `tcl/sim_l1.tcl` los convierte
              en plusarg y `tb_l1_ddc.sv` escribe el registro tras soltar el reset. El caso nuevo es
              `afc_retune__{fine,coarse}`: tono a `if_norm + 0,01` y palabra de fase la de **ese**
              tono, así que la salida vuelve a caer en continua. Queda una **hipótesis sin medir**:
              `_AFC_RETUNE_AT = 0`, es decir que la configuración está aplicada antes de la primera
              salida del NCO. Es plausible —el testbench escribe nada más soltar el reset y el core
              tarda `Latency` = 9 ciclos en dar su primera muestra— pero no está medido. Si la
              primera corrida falla, el camino es barrer `k` **contra esa misma salida del RTL**
              (una sola simulación, barrido offline), igual que se calibró `NCO_LUT_OFFSET_K`. No se
              ajusta el modelo para que pase: se mide el hardware y se escribe el número medido. **No
              hizo falta: la primera corrida pasó.**
            - **En placa, espectral.** `tools/dump_ray.py --nco-pinc <palabra>` alimenta el modelo
              con la misma palabra de fase y compara el espectro del rayo congelado, igual que la
              medida de Z4.4. Aquí **no hay ambigüedad de `k`**: el rayo que se congela es muy
              posterior al retune, así que el NCO lleva esa palabra desde mucho antes de la primera
              muestra del rayo y el transitorio del salto no cae dentro de la ventana.
        3. **No corras `tcl/sim_l1.tcl` y `tcl/build.tcl` a la vez.** Hallazgo de esta sesión, por
           haberlo hecho: los dos trabajan sobre el MISMO `ip/<core>/` —`build.tcl` deja ahí los
           productos de síntesis y `sim_l1.tcl` hace `generate_target {simulation
           instantiation_template}` sobre el mismo directorio— así que en paralelo se pisan en
           caliente. El síntoma no apunta a la causa: `synth_ip` corre bien y genera el `.dcp`, y la
           elaboración posterior falla con `ERROR: [Synth 8-439] module 'dds_compiler_nco' not
           found`, que parece un problema del RTL y no lo es. `ip/` no es directorio de build, es
           fuente versionada con productos derivados al lado, y nadie lo serializa.
        4. ~~Nada de esto corrió en una ZedBoard.~~ **Hecho el mismo día (noche), y encontró un bug
           real** — ver la entrada siguiente.

!!! success "2-oct-2026 (noche): bring-up de Z4.5 en placa — el AFC actúa, y el camino registro→DDC estaba roto"
    El bring-up hizo exactamente aquello para lo que existe: encontrar lo que la simulación no podía
    ver. **La actuación AFC funciona en silicio y el A/B espectral cierra**, pero por el camino
    apareció un desfase de un ciclo entre el strobe y el dato que dejaba al DDC mezclando con la
    palabra de la escritura **anterior**.

    **Lo que se midió bien a la primera:** `drx_status: mapa de registros v9 confirmado por
    AXI-Lite`; `drx_afc: actuacion AFC OK (NCO_PINC 1030792151 -> 1032889303 -> 1030792151)`; 231
    rayos en 1000 ms con `overrun=0x0 truncated=0x0`; y la línea de BITE viva con `BITE=0x40`
    (`CONFIG_REJECTED`) y `last_error=12` (`afc_out_of_range`) — la palabra fuera de rango que mete a
    propósito la autoprueba, recorriendo entera la cadena hasta la trama `status`. Que ese código de
    error llegue hasta ahí es justo lo que `DrxStatusTask_AttachControl` existe para conseguir, y es
    el camino que Z4.6 usará con el control del socket.

    **El bug: el NCO iba una escritura por detrás.** El lado B del A/B dio el pico en continua en vez
    de en −0,2495 de fs_dec, con `NCO_PINC` leído de vuelta por JTAG en el valor correcto. Tres
    medidas, la tercera una predicción falsable que se cumplió:

    | palabra escrita | palabra que aplicó el NCO | medido |
    |---|---|---|
    | 1025629931 | 1030792151 (la nominal anterior) | pico en +0,00000 de fs_dec |
    | 0 | 1025629931 | pico en −0,25000 de fs_dec |
    | 1030792151 | 0 | salida a cero exacto, `\|max\| = 0`, −210 dBFS |

    La tercera es la que lo cierra: si el NCO aplica el `0` anterior, deja de mezclar, el tono del
    IF se queda fuera de la banda diezmada y los filtros lo tiran. Eso es lo que pasó, al LSB.

    **Causa, en `rtl/drx_axil_regs.sv`:** `nco_pinc_we` era combinacional sobre `write_commit`, así
    que estaba en alto el mismo ciclo en que `nco_pinc_r` todavía valía lo viejo —el registro no se
    actualiza hasta el final de ese ciclo— y `drx_ddc_top` latchea el dato con el strobe. Corregido
    registrando el strobe un ciclo. **De paso mejora la temporización**: al salir un camino
    combinacional del crítico, el P&R sube de **WNS = 1,626 ns a WNS = 2,304 ns** (WHS = 0,022 ns,
    todas las restricciones cumplidas).

    **Por qué no lo vio nada de lo anterior, que es la parte que importa.** `tb_l1_ddc.sv` deja
    `nco_pinc` estable **antes** de pulsar el strobe, así que ni la matriz 16/16 de D-12 ni el caso
    `afc_retune` —los dos verdes esa misma mañana— ejercitaron nunca esta alineación: verificaban el
    DDC, no el traspaso registro→DDC. Y el L0 comprobaba el valor del registro y la duración del
    pulso por separado, que es exactamente lo que el bug respetaba. El test de ahora muestrea
    `nco_pinc` **en los ciclos en que el strobe está alto**; comprobado que falla contra el RTL
    anterior y pasa contra el corregido. La lección general: un strobe y su dato son **una sola
    cosa** a efectos de verificación, y comprobarlos por separado deja pasar justo este fallo.

    **A/B espectral, cerrado contra el modelo dorado con el bitstream corregido:**

    | lado | NCO_PINC | medido | modelo |
    |---|---|---|---|
    | A | 1030792151 (nominal) | pico en +0,00000 de fs_dec, −9,02 dBFS | +0,00000, −9,02 dBFS |
    | B | 1025629931 (retune) | pico en **−0,25000** de fs_dec, −9,01 dBFS | −0,24950, −9,02 dBFS |

    Las dos medidas salen del **mismo arranque**: `DrxAfcApp_RetuneAB` (nuevo) congela el lado A, lo
    deja 120 s para que `tools/dump_ray.py` lo lea por JTAG, descongela, escribe la palabra nueva,
    deja pasar rayos y congela el lado B. Medirlos en arranques distintos obligaría a suponer que
    nada más cambió entre los dos. La palabra se deriva de los parámetros generados
    (`DRX_NCO_PHASE_INC - (1 << 30)/DRX_R1`, un cuarto de la banda diezmada), no se clava: más
    desplazamiento se saldría de la banda y menos no se distinguiría de la resolución del espectro.

    Con esto, **Z4.5 queda cerrada**: actuación AFC verificada en silicio contra el modelo dorado, y
    no sólo «el registro cambia».

!!! info "2-oct-2026 (noche): los `overrun` que aparecen en una sesión de JTAG son del JTAG, no del camino de datos"
    Durante el bring-up, `dma_overruns` subió a 3 y `BITE` pasó a `0x42` (`CONFIG_REJECTED` +
    `DMA_OVERRUN`). Perseguido hasta la causa, porque un overrun del camino de datos sería una
    regresión seria de Z4.4 y aquí no lo es.

    **Medido, no supuesto:**

    | fase | duración | eventos `STATUS (overrun) = 0x7` |
    |---|---|---|
    | ociosa, sin tocar JTAG | 600 s | **0** |
    | 300 lecturas `mrd` de un buffer VIVO del anillo | 8 s | **2** (repetido: 2) |
    | 300 lecturas `mrd` de DDR no usada (`0x10000000`) | 8 s | **3** |

    Que una dirección de DDR **sin relación con el DMA** dé el mismo resultado descarta que sea algo
    del buffer concreto. Y el ancho de banda tampoco explica nada: 300 × 12 KB en 8 s son ~450 KB/s
    contra un S2MM de ~9,8 MB/s sobre una DDR3 de varios GB/s.

    **La causa es que `xsct` PARA el Cortex-A9 en cada `mrd`.** Medido por déficit de tick: durante
    una ráfaga, 23 s de reloj de pared contra 16 s de `uptime` de FreeRTOS — el core estuvo detenido
    ~7 s, justo lo que duró la ráfaga. Con el core parado, la interrupción de fin de descriptor del
    S2MM no recicla buffers, el anillo se seca y el range-gate desborda. Los rayos se siguen
    contando porque la ISR procesa los descriptores completados en lote al reanudar.

    **Consecuencia práctica, y es de método:** cualquier contador de BITE leído durante o después de
    una sesión de `tools/dump_ray.py` está contaminado. Las cifras limpias de Z4.4 (`dma_errors=0`,
    `overrun=0x0`) no lo están porque salen de `DrxRay_SelfTest`, que corre **antes** de la primera
    lectura por JTAG. Al interpretar un BITE en placa, mirar primero si hubo JTAG de por medio.

    Esto es un artefacto del instrumento en ZedBoard, no un riesgo de la ZU9 —allí no habrá un
    depurador leyendo DDR en producción—. Lo que sí deja como pregunta abierta, y es inferencia no
    medida: cuánto tiempo puede estar el A9 sin atender la ISR del S2MM antes de perder un rayo. En
    la ZU9, con dos FMC213 y mucho más caudal, ese margen es más estrecho. Dimensionarlo es trabajo
    de Z5, no de aquí.

!!! success "2-oct-2026 (noche): Z4.6 — hay socket, y el lazo de control cierra sobre él"
    Primera vez que el contrato DRx↔DSP viaja por un cable. Hasta hoy se ejercitaba de dos maneras,
    las dos a medias: el framer en C contra el Python generado **en el host**, y en placa con tramas
    que el propio firmware se fabricaba. Nadie había abierto un socket.

    **Forma, por [D-16](../alcance/decisiones.md#d-16):** una sola conexión TCP para los dos
    sentidos, el DRx escucha, el DSP conecta. Contrato **v0.8**: el puerto (9470) pasa a ser una
    constante del esquema, generada a C, Python y Rust. Vive ahí y no en el firmware porque es justo
    lo que las dos puntas tienen que acordar — duplicarlo a mano es la clase de desacuerdo que no da
    ningún síntoma hasta que nadie conecta.

    **Piezas:** `fw/src/app/drx_transport.c` (tarea servidora; recibe en su propia tarea y envía
    desde las de rayos y diagnóstico, con un mutex serializando los dos emisores),
    `fw/src/app/drx_ray_ctx.c` (extraído de `drx_control_boot.c`, que era el único productor de
    tramas `ray` hasta que el transporte fue el segundo), y `tools/mock_dsp.py`, que **no**
    reimplementa el contrato: todo lo que empaqueta sale de `contract/generated/drx_dsp_v0_1.py`.
    El servidor de eco de la plantilla de Vitis se va; cumplió su papel en Z4.2, que era probar que
    la pila compilaba.

    **Medido contra la ZedBoard:**

    | magnitud | medido |
    |---|---|
    | rayos | 2239 en 10 s = **223,8/s** (predicho 223,47) |
    | caudal | 36,20 MB, **28,9 Mbps** |
    | huecos de `seq` | **0** |
    | ping | 0 % de pérdida, 0,147 ms |

    **El lazo de control cierra sobre el mismo socket, sin JTAG**, que es lo que hace que esto valga
    como cierre y no como demostración. El cliente recibe el I/Q, así que el efecto de un `afc` se
    mide en los propios rayos que llegan (`--spectrum`):

    | | pico medido | modelo dorado |
    |---|---|---|
    | NCO nominal | +0,00000 de fs_dec, −9,02 dBFS | +0,00000, −9,02 dBFS |
    | tras `afc 1025629931` por la red | **−0,24950 de fs_dec, −10,45 dBFS** | −0,24950, −10,45 dBFS |

    Y el camino de error: un `afc` de 2³² vuelve como `last_error=afc_out_of_range` en el primer
    `status`, rearmado a `ok` después, con `bite=config_rejected` latcheado. Restaurar el NCO
    necesitó **una sola** escritura, que es la corrección del strobe de esta misma tarde
    sosteniéndose.

    **Dos bloqueos reales, los dos de la familia del VREF de la DDR** — un parámetro que el preset
    de Digilent deja en su valor por defecto y un síntoma que apunta a otro sitio:

    1. **`PCW_ENET0_GRP_MDIO_IO` valía `EMIO`.** El grupo MDIO estaba habilitado pero enrutado a la
       FÁBRICA, donde no hay nada; en la ZedBoard el PHY lo tiene cableado a MIO 52/53. Sin MDIO no
       se puede leer el PHY y la autonegociación nunca completa. Comprobado leyendo los MIO por
       JTAG antes de tocar nada: `MIO_PIN_52` y `MIO_PIN_53` valían `0x200` —los cuatro `L*_SEL` a
       cero, pin sin muxear— mientras `MIO_PIN_16` valía `0x2902` con `L0_SEL = 1`. Datos RGMII sí,
       gestión no. Corregido en `tcl/gen_zynq_bd.tcl`; el P&R no se mueve (**WNS = 2,304 ns**), como
       cabe esperar de un cambio de MIO del PS7.
    2. **`unable to determine type of EMAC with baseaddress 0xE000B000` es ruido, no un error.** El
       `switch` de `xemac_add` en el port de lwIP de Xilinx (`xadapter.c`) **no tiene `break` en
       ningún case**, así que toda ruta cae a `default:` y lo imprime; `default:` solo imprime y no
       toca `nif`. Aparece igual cuando el netif se añadió bien. Costó tiempo porque durante los
       primeros arranques convivía con el fallo de verdad —`Phy setup failure init_emacps`, la
       línea de ARRIBA— y parecía su consecuencia.

    Un tercero, este de cosecha propia: `DrxStatusTask_Create()` corre **antes** que el transporte
    (`main.c` lo arranca antes de `lwip_init` a propósito, para no depender del enlace), así que
    llamaba a `DrxTransport_Send` con el mutex sin crear y reventaba el `configASSERT` de FreeRTOS
    (`Assert failed in file queue.c, line 1507`). Resuelto con una guarda; la ordenación no se
    cambia, porque que el diagnóstico no dependa de la red es deliberado.

    De paso: `LWIP_DHCP` estaba a **1** en este BSP, heredado de la plantilla y nunca revisado, no
    a 0 como se venía suponiendo. El arranque esperaba un DHCP que en un enlace punto a punto no
    existe, expiraba y caía al estático (`Configuring default IP of 192.168.1.10`), retrasando otro
    tanto la escucha del puerto del contrato. **Puesto a 0 el mismo día**: la dirección no cambia y
    el arranque va directo a `Board IP` y a `drx_transport: escuchando`.

    **Soak, la misma noche: cuatro corridas, 3,2 millones de rayos, 52 GB.** La pregunta que D-16
    dejaba abierta sobre la contrapresión tiene respuesta: `sink_drops` **no** se mantiene en 0,
    pero la causa no es la red.

    | corrida | duración | rayos | caudal | huecos de `seq` |
    |---|---|---|---|---|
    | 1 | 1 h | 804 090 | 13,0 GB | 3 |
    | 2 | 1 h | 804 173 | 13,0 GB | 1 |
    | 3 | 1,5 h | 1 206 179 | 19,5 GB | 3 |

    223,4 rayos/s sostenidos a 28,9 Mbps, y **el espectro del último rayo de cada corrida sigue
    cayendo en continua a −9,02 dBFS** contra el modelo dorado: el dato no se degrada con las horas.

    Atribuir ese puñado de descartes costó tres pasadas de instrumentación, y cada una refutó la
    hipótesis anterior:

    1. **`descartados` era un solo contador** para las dos ramas del sumidero. La primera lectura
       —rayo mal formado— chocaba con `cortos=0`, y la segunda —`send` fallido— chocaba con que la
       conexión sobreviviera las tres horas, porque un `send` fallido cierra el socket. Separadas:
       **`enc_fail=3, snd_fail=0`**. Es el encoder, no la red.
    2. **`cortos=0` seguía siendo imposible**... hasta leer `drx_ray.c:202`, que solo cuenta
       `short_rays` cuando `n_words < esperadas`. Un rayo que llega **largo** no lo marcaba nadie, y
       `DrxRayFrame_Encode` lo rechaza igual porque compara con `!=`. Añadido `long_rays`.
    3. **Volcar las cifras del rayo** convirtió la deducción en medida:
       `bins=1002 n_ch=3 n_words=11067 esperadas=3006 batch=1`. Y `11067 = 3689 × 3` es exactamente
       un rayo del lote bajo: la cabecera dice lote alto y la carga útil es la del bajo.

    Eso es [P-18](../alcance/pendientes.md#p-18), hallazgo nuevo: en la frontera entre los dos lotes
    de PRF de un radial hay una ventana en la que el metadato en banda ya refleja el lote nuevo y el
    gate todavía vacía un rayo del viejo. ~1 cada 400 000 rayos, media hora. **No llega dato malo al
    DSP** —el encoder se niega a enmarcarlo, que es justo para lo que esa comprobación existe— pero
    cuesta un rayo. Y de paso explica por qué los descartes caen **siempre** junto a saltos grandes
    de `trig_count` (d = 4, 8, 14, 22) y nunca en marcha estable.

    Dos cosas más que el soak sacó, ya corregidas: `tx_bytes` era `uint32_t` y envolvía cada ~20
    minutos a este caudal (el total impreso bajaba en vez de subir), y la línea de diagnóstico no
    llevaba los contadores finos de `DrxRayStatus`, sin los cuales nada de lo de arriba se podía
    distinguir desde fuera.

    **Lo que falta para cerrar ZM4:** barrer el catálogo de estímulos contra rayos reales —
    bloqueado por [P-16](../alcance/pendientes.md#p-16), no por el transporte.

!!! success "3-oct-2026: el arreglo del transporte aguanta, y P-18 se va con los overruns"
    El soak que tenía que decidirlo estuvo a punto de perderse: la máquina de desarrollo se
    reinició a las 07:32 y `/tmp` se llevó por delante el log del cliente y la captura de UART
    enteros. **La placa no se apagó**, así que los contadores acumulados seguían en su RAM y se
    leyeron reconectando. Suerte, no diseño — ver más abajo lo que se hizo para que no vuelva a
    depender de eso.

    Con 3 h 50 min de marcha y **3 085 111 rayos**, contra el firmware de `954579c` (pool de 4
    tramas + tarea `drx_tx` dedicada):

    ```
    BITE=0x0 uptime=13804s rayos=3085111 dma_overruns=0 ddc_overflows=0 ssa_underruns=0 last_error=0
    rayo dma_err=0 resync=1 magic=0 n_ch=0 cortos=0 largos=0 trig_gaps=0(d=0) ray_gaps=0
         sink_drops=151 enc_fail=0 snd_fail=1 cola=151
    red  rayos_tx=1215129 descartados=152 status_tx=5290 tx=18759MB
    ```

    **La predicción se cumplió.** Antes del arreglo, 2 h con cliente daban ~18 overruns y 20
    ráfagas de `trig_gaps` (~212 disparos sin rayo). Ahora `dma_overruns=0` y `trig_gaps=0`. El
    sumidero llamaba a `lwip_send` dentro de la tarea de rayos: mientras el socket bloqueaba nadie
    reciclaba el anillo S2MM y el range-gate desbordaba. No era un problema de red, era bloquearse
    en ella.

    **Y [P-18](../alcance/pendientes.md#p-18) desapareció con ellos, que es el resultado que de
    verdad discrimina.** `cortos=0 largos=0 enc_fail=0`. A la tasa medida antes (4 eventos en
    1 608 220 rayos) cabía esperar ~7,7 en esta población; salieron 0, p ~ 4,5e-4 bajo Poisson. El
    conteo cubre los 3,08 M de rayos enteros y no solo los enviados, porque `short_rays`/`long_rays`
    se cuentan en `drx_ray.c` sobre cada rayo que sale del DMA, haya cliente o no. El desajuste de
    metadato en el borde de lote era un **efecto secundario de la parada**, no un fallo
    independiente. Cerrado por consecuencia, no por ILA: la ventana puede seguir en el RTL, lo que
    ya no existe es la condición que la hacía visible.

    **Lo que sí se movió es un contador nuevo, y es la contrapresión haciendo su trabajo.**
    `cola=151` (el pool sin hueco) y `snd_fail=1`, sobre 1 215 129 rayos enviados. Eso es el
    diseño funcionando, no fallando: el rayo que no cabe se pierde en el pool y se cuenta, en vez
    de parar el anillo y llevarse ~11 por ráfaga. Los 5440 s de cliente cuadran con los 5400 s del
    soak, así que el cliente corrió entero.

    **De dónde salen esos 151: la mitad de la respuesta, y la corrida de control que refuta la
    otra mitad.** La WiFi de la máquina de desarrollo entró en una tormenta de desasociaciones a
    las **05:00:13**, en mitad del soak (04:11 → 05:41) — 816 eventos
    `reason=4 locally_generated=1` con señal de −49 dBm y `rtw_8821ce: failed to send h2c command`.
    La lectura era que un host ocupado no vacía el socket, la ventana TCP se cierra y la tarea de
    TX bloquea. Puesta a prueba con 15 min de control y la WiFi sana (1 desconexión en todo el
    arranque, 0 `h2c`, carga 0,36):

    | | rayos enviados | descartes en el pool | tasa |
    |---|---|---|---|
    | soak con tormenta de WiFi | 1 215 129 | 151 | 124 ppm |
    | control con host sano | 201 082 | 5 | **25 ppm** |

    La tormenta explica el exceso, **no el suelo**. Y los 5 descartes del control dieron **un solo**
    hueco de `seq`: fueron consecutivos, ~22 ms en los que nadie vació el pool. Eso es
    [P-19](../alcance/pendientes.md#p-19), hallazgo nuevo y abierto. Lo que sí se sostiene es que
    la tubería de rayos no se detiene: `dma_overruns=0` y `trig_gaps=0` también en el control.

    **Dos cosas de infraestructura, para que esto deje de depender de la suerte:**

    1. `tools/net_drx_link.sh` — el enlace cableado al DRx no tenía configuración persistente. El
       perfil que NetworkManager crea solo para un interfaz nuevo pide DHCP, y en un enlace punto
       a punto ([D-16](../alcance/decisiones.md#d-16)) no hay servidor: bucle eterno de 45 s
       (`ip-config -> failed (reason 'ip-config-unavailable')`) que **purga la dirección en cada
       fallo**. Una `ip addr add` a mano no sobrevive ni a eso ni a un reinicio. Ahora hay un
       perfil `drx-zedboard` con 192.168.1.1/24 estática, `never-default`, sin DNS e IPv6 apagado.
    2. `tools/soak.sh` — captura UART y log del cliente en `build/soak/<fecha>/`, fuera de `/tmp`,
       con la UART abierta antes del cliente y cerrada después, para que la última línea de
       contadores quede grabada con el cliente ya desconectado. Comprueba además que nadie más
       tenga el tty abierto: dos lectores entrelazan los bytes y la captura sale ilegible, que ya
       se confundió una vez con un problema de baudios.


!!! warning "3-oct-2026 (más tarde): el motor de timing cuenta muestras — necesario para P-16, y no suficiente"
    P-16 llevaba desde el 1-oct con dos salidas escritas, las dos caras: ensanchar el stream del
    MM2S (tres cambios que tienen que aterrizar a la vez, y `N_CH × 16 = 48` bits no es potencia
    de dos, así que serían 64 con un carril muerto) o aceptar que el catálogo elegible en caliente
    solo sirve sin el motor de timing. **La tercera vía la propuso vladimir y no estaba en la
    lista: sincronizar el motor con el avance de muestras.**

    El problema no es que el DMA vaya lento. Es que las dos mitades miden el tiempo con reglas
    distintas: `drx_prf_batch_seq` cuenta ciclos de reloj (un PRI = `prf_div` ciclos de `fs`,
    D-13; `ray_start` corta ahí, D-14) y la cadena del DDC avanza solo con `valid`. Con la fuente
    a una muestra por ciclo son la misma cosa — por eso nadie lo había notado. En Throttled(DDR)
    `vector_source` junta `N_CH` beats por conjunto, el rayo tarda ~4 PRI en llenarse,
    `ray_start` lo trunca y no se completa ninguno.

    Si el motor cuenta **avances de muestra**, las dos mitades se frenan con el mismo factor y el
    rayo se llena con los mismos `prf_div / R₁` bins a cualquier tasa. En tiempo real `valid` está
    siempre alto, así que un avance es un ciclo y el motor es el de v3..v9 — no por argumento, por
    construcción: con `advance` constante a 1 la síntesis colapsa el enable.

    **Lo nuevo, con el criterio explícito de tocar lo mínimo del diseño principal:**

    | pieza | qué cambia |
    |---|---|
    | `rtl/drx_sample_pacer.sv` | **nuevo**. Define qué cuenta como un avance. Toda la lógica nueva vive aquí |
    | `rtl/drx_prf_batch_seq.sv` | un puerto `advance` |
    | `rtl/drx_trigger_one_shot.sv` | un puerto `advance` |
    | `rtl/drx_trigger_gen.sv`, `rtl/drx_timing_engine.sv` | paso a través, no tienen lógica propia |
    | mapa de registros **v10** | `TIMING_CTRL` bit 1, `timing_paced`, reset 0 |

    **La intrusión en el motor no se puede evitar, y conviene decirlo en vez de fingirlo.** La
    primera idea era no tocarlo: `drx_prf_batch_seq` YA tiene un `enable` que es un clock-enable
    de verdad (`pri_cnt`, `pulse_idx`, `batch_sel`, `radial_done` viven todos dentro de
    `else if (enable)`), así que bastaría con meter el tick ahí. No basta: `width_cnt` tiene
    `else width_cnt <= '0'`, o sea `enable` bajo lo BORRA, y gatearlo con el tick dejaría
    `tx_gate` en pulsos de un ciclo cada vez que la fuente se frena — justo el caso para el que
    existe. Hacen falta dos conceptos separados, `enable` (armado) y `advance` (paso).

    **Y un detalle que casi se escapa, que habría sido un fallo silencioso.** `pulse_trig` es
    combinacional sobre `pri_cnt == '0'`. Gateando solo los `always_ff`, `pri_cnt` se queda en 0
    durante todos los ciclos sin avance y `pulse_trig` sale **ancho** en vez de un ciclo. Lo
    consumen `ray_start` (D-14) y el contador `TRIG_COUNT`, que contarían varias veces el mismo
    pulso de PRF. El `advance` entra también en ese `assign`.

    **La verificación, que es donde está el trabajo.** `sim/tb/tb_drx_timing_paced.py` no compara
    contra el modelo dorado: compara la traza paceada —muestreada SOLO en los ciclos de avance—
    contra la del mismo motor sin pacear. Dos radiales completos, 1804 avances,
    `(pulse_trig, batch_sel, tx_gate)` muestra a muestra, con un patrón de avance irregular a
    propósito (el MM2S no entrega a cadencia regular, y un hueco periódico podría esconder un
    error que dependiera de la alineación con el PRI). El oráculo es el motor viejo porque lo que
    falta por probar no es la corrección del secuenciador —ya la cubre `tb_drx_prf_batch_seq.py`
    contra `model/drx_model/timing.py`— sino la EQUIVALENCIA de las dos bases de tiempo.

    **Los dos tests se comprobaron contra RTL mutado**, que es la única forma de saber que muerden:

    | mutante | qué pasa |
    |---|---|
    | `advance` fuera del `assign` de `pulse_trig` | «10 pulsos con el motor parado» |
    | `advance` fuera de los `always_ff` | la traza diverge en el avance 134 |

    Y uno de los dos resultados es informativo por sí solo: el test de equivalencia **no** caza el
    primer mutante, porque muestrea solo en los avances y el pulso ancho le es invisible. Por eso
    hacen falta los dos y no uno.

    **Firmware.** `DrxReg_TimingEnable()`/`Disable()` pasan a lectura-modificación-escritura: un
    `DrxReg_Write(TIMING_CTRL, 1u)` borraría el bit de pacing al arrancar el motor, y el síntoma
    sería que el barrido no produce ningún rayo sin ninguna otra pista. `DrxStimulus_Select()`
    enciende el pacing junto con el modo DDR y `DrxStimulus_Stop()` lo apaga, los dos bracketeados
    con el secuenciador parado — los bits del registro son independientes a propósito, que vayan
    juntos es una política y su sitio es el firmware.

    **Lo que NO cierra.** Throttled(DDR) sigue sin ser una fuente de tiempo real; el nombre ya lo
    decía. No valida rayos/s, caudal del transporte ni temporización del anillo del DMA — eso se
    sigue midiendo en BRAM-loop. Y el validador D-09 comprueba PRF × rango en ciclos: con el motor
    paceado el PRF real se estira, así que el check queda conservador (nunca rechaza de más) pero
    deja de hablar del PRF real. Una configuración paceada no es una configuración de tiempo real
    validada. **El conductor del barrido existe y está validado ANTES que el bitstream**, que era el punto:
    `tools/sweep_catalogo.py` no reimplementa nada —contrato y reensamblado de `mock_dsp.py`,
    medida espectral y oráculo de `dump_ray.py` con sus tolerancias— y lo propio es el bucle y el
    criterio. Se ejercitaron sus cuatro ramas contra la placa corriendo todavía el firmware sin
    P-16, de modo que el día que se corran juntos lo único sin probar sea P-16:

    | rama | cómo se provocó | resultado |
    |---|---|---|
    | coincide | BRAM-loop contra `tono_if` | −9,03 dBFS medidos y de modelo, pico en continua |
    | discrimina | el MISMO flujo contra `tono_desplazado` | DISCREPA: el modelo pone el pico en −208, se mide en 0. Exit 1 |
    | sin rayo | `test_stimulus_select` en bucle | `config_ack error=ok` y 7 s sin un solo rayo |
    | rechazo | `--id-crudo 99` | `config_ack error=vector_unknown`. Exit 1 |

    La tercera fila es un resultado por sí sola: **P-16 reproducido desde el lado del DSP por
    primera vez**. Hasta hoy solo se había visto por JTAG, en `GATE_TRUNCATED`; ahora se ve como lo
    verá quien use el receptor — se pide un vector, el DRx dice que sí, y deja de haber rayos.

    Y el ensayo sacó un bug propio, de los de divergencia silenciosa: la vuelta a BRAM-loop al
    terminar las pasadas (`DrxStimulusTask`) limpiaba el bit de DDR pero **no** el de pacing,
    porque es un camino distinto de `DrxStimulus_Stop()`. Los dos pasan ahora por `set_modo_ddr()`.

    Lo más flojo de la medida, dicho antes de que muerda: el criterio de «este rayo ya es del
    vector nuevo» es temporal (`--settle`), porque `DrxRayContext.first_after_config` existe en el
    contrato pero el firmware lo deja siempre en `false`. Si algún vector da un falso fallo
    intermitente, el primer sospechoso es ese número y no el DDC. Lo correcto es que el firmware
    ponga la bandera.

    **P&R cerrado el mismo día, y mejora:** `-top zynq -step impl` da
    **WNS = 2,394 ns, WHS = 0,013 ns** («All user specified timing constraints are met»), contra
    los 2,304 ns de Z4.5. Era lo esperable y conviene decir por qué, porque un P&R que mejora
    suele significar que algo no se sintetizó: el pacer es un AND de tres bits y los `advance`
    son clock-enables sobre registros que ya existían, no caminos combinacionales nuevos; la ruta
    crítica sigue siendo PS7↔interconnect↔`drx_axil_regs`, sin tocar.

    **Y lo que la medida en placa dijo esa misma tarde: el pacing era necesario y NO suficiente.**

    | | resultado |
    |---|---|
    | `GATE_TRUNCATED` con el motor corriendo en DDR | **`0x0`** — la firma de P-16 desaparece, los rayos salen enteros (`bins=3689`, sin `TRUNCATED`) |
    | autoprueba de arranque por DDR con el motor en marcha | `tono_if` y `tono_sobre_escala`, 2 pasadas cada uno, `errores=0` — imposible por definición antes |
    | BRAM-loop con `timing_paced = 0` | −9,03 dBFS medidos contra −9,03 del modelo: la equivalencia con v9, comprobada en silicio |
    | el DATO en DDR paceado | **−87,3 dBFS** contra −9,02 del modelo, pico en un bin arbitrario |

    La última fila es el fondo del asunto: **hay una tercera base de tiempo y el análisis no la
    miró**. `rtl/drx_ddc_mixer.sv:99` ata `nco_ready` a 1 («el DDS corre libre») y
    `tcl/gen_ip.tcl:238` tiene `CONFIG.Has_ACLKEN {false}`, así que el DDS Compiler avanza un paso
    de fase por CICLO DE RELOJ, sin `TREADY` y sin clock enable. Con la fuente a 1 de cada ~4
    ciclos, entre dos muestras la fase ha avanzado 4 pasos: el DDC mezcla a ~4× el IF, el tono cae
    fuera de la banda de paso del diezmado y la salida se va al suelo de ruido. El argumento que
    justificó el pacer —«las dos mitades se frenan con el mismo factor»— valía para el motor y el
    range-gate; el NCO es una tercera mitad. El pacer arregla la LONGITUD del rayo; el DATO
    necesita que el NCO cuente muestras también. El arreglo es simétrico —`Has_ACLKEN {true}` y
    `aclken = advance`, el parámetro ya está en el XCI— y su gate es la matriz de 16 corridas de
    D-12, 2-3 h, igual que cuando la IP se regeneró en Z4.5.

    El barrido destapó además [P-21](../alcance/pendientes.md#p-21), independiente: el MM2S se
    atasca tras unas pocas selecciones encadenadas. La mitad del fallo estaba en
    `DrxStimulus_Stop()`, que pausaba el DMA ANTES de drenar y fugaba los descriptores de la
    pasada en vuelo —el anillo aguanta cuatro y a la quinta ya no se encola nada—; corregido
    drenando primero, y no con `XAxiDma_Reset` porque MM2S y S2MM son el mismo `axi_dma` y eso se
    llevaría el anillo de rayos. La otra mitad la convirtió en medible el propio arreglo: la
    pasada **no completa en 50 ms**, y 4000 conjuntos deberían consumirse en menos de 1 ms, así
    que la cadena se para de verdad entre el MM2S y el DDC. Eso necesita un ILA.

    **Lectura de la jornada:** escribir el conductor del barrido ANTES del bitstream fue lo que
    permitió separar las tres cosas. Si hubieran llegado juntas, los −87 dBFS se habrían podido
    achacar al conductor, al pacer o al DMA sin forma de distinguirlos.


!!! success "4-oct-2026: el estímulo se carga en BRAM en tiempo de ejecución, y el MM2S sale del diseño"
    **Cambio de arquitectura, no un arreglo.** El 3-oct la medida dejó P-16 abierto por una causa
    que ninguna de las dos salidas previstas contemplaba: el DDS Compiler no tiene `aclken`
    (`rtl/drx_ddc_mixer.sv:99`, `tcl/gen_ip.tcl:238`) y avanza un paso de fase por ciclo de reloj
    mire o no `valid`. Con Throttled(DDR) entregando una muestra cada `N_CH` ciclos, el DDC
    mezclaba a ~`N_CH` veces el IF: **−87,3 dBFS contra −9,02 del modelo dorado**.

    El arreglo simétrico —regenerar la IP con `Has_ACLKEN {true}`, cablear `aclken = advance`,
    extender el diferido de `S_AXIS_CONFIG`, y la matriz de 16 corridas de D-12 como gate, 2–3 h—
    existía y no se tomó. En su lugar se eliminó la fuente con huecos: **el modo BRAM-loop, que
    siempre entregó una muestra por ciclo, pasa a ser cargable en tiempo de ejecución, y
    Throttled(DDR) sale del RTL y del block design.**

    Lo único que le faltaba a BRAM-loop era elegir el vector sin volver a sintetizar. Ahora lo
    tiene, y la ventaja frente al DMA es que sale **a tasa plena**, que es lo que hace medible el
    barrido del catálogo — lo último que le queda a ZM4.

    **Mapa de registros v11.** `CTRL` bit 2 `vector_load` (congela el lector mientras el PS
    escribe, y al soltarlo deja el puntero en la muestra 0), más `VEC_ADDR` (0x5C, puntero con
    autoincremento + banco de destino, con difusión a los `N_CH` en el banco 7), `VEC_DATA` (0x60,
    una muestra por escritura) y `VEC_LEN` (0x64, longitud del bucle, reset = `VECTOR_LOOP_LEN`).
    `CTRL` bit 1 —el `vector_source_ddr` de v8— vuelve a reservado y **no se reutiliza**: un
    firmware de v8..v10 que lo escriba no debe activar algo distinto en silencio. Detalle en
    [registros.md](registros.md#z4-en-v11).

    **Par dirección/dato y no ventana de memoria.** `addr_width = 7` son 128 B en total y una
    ventana direccionable no cabe; un `axi_bram_ctrl` habría pedido un maestro más en el
    `axi_interconnect` (los dos de `NUM_MI` están ocupados) y un segmento nuevo en el mapa de
    direcciones. A cambio, una carga de 4000 muestras son 4000 escrituras con autoincremento, del
    orden de milisegundos, una vez por selección de vector.

    **Dimensionado: 8192 muestras por canal, 12 BRAM Tile.** El xc7z020 tiene 140 tiles de 36 Kbit
    con 32768 bits de dato cada uno, o sea 2048 muestras de 16 bits por tile; 8192 × 3 canales son
    4 RAMB36 exactos por canal. Se midió antes de elegir: la ocupación de partida era 31,5/140
    (22,5 %), no el 29,5 que repetía `CLAUDE.md` desde antes de Z4.4. Se descartó ir a 32 768
    muestras/canal (48 tiles) porque no tiene cliente hoy y obligaría a sacar el catálogo de la
    imagen del firmware: 8 vectores × 3 canales × 32 Ki × 2 B no caben donde hoy caben 62 KiB.

    **Las dos longitudes, y por qué no son la misma.** `VECTOR_BRAM_DEPTH` (8192) es capacidad;
    `VECTOR_LOOP_LEN` (4000) es lo que se reproduce y el valor de reset de `VEC_LEN`. La longitud
    tiene que ser múltiplo de `IF_NORM_DEN` (25) para que el tono cierre un número entero de
    periodos, y 8192 no lo es. Las dos viven ahora en `config/params.toml` y `tools/gen_params.py`
    comprueba las dos condiciones — el gate se verificó por mutación: con `vector_loop_len = 4001`
    la generación falla en vez de dejar faldas alrededor del tono en placa. Es el mismo patrón que
    `n_ch_top`, y existe por la misma razón: `DRX_STIMULUS_N_CH` ya estuvo escrito a mano en dos
    sitios sin nada que los comparara.

    **El valor de reset de `VEC_LEN` es lo que protege la línea base.** `$readmemh` sigue
    precargando el mismo tono de 4000 muestras (ahora en un fichero de 8192 líneas, con ceros
    detrás, para no dejar ni una palabra indefinida en el array), así que **un arranque en frío
    sin ninguna escritura reproduce exactamente el bucle de v10**. Los −9,03 dBFS ya medidos
    siguen valiendo como regresión.

    **La cicatriz de v9, aplicada antes de que mordiera.** `vec_we`, `vec_addr`, `vec_bank` y
    `vec_data` se registran JUNTOS, y la dirección que ve la BRAM es la de antes del incremento
    (`vec_addr_q`). Con un strobe combinacional sobre `write_commit` —lo que tenía `nco_pinc_we`
    hasta el 2-oct— la memoria se habría llevado el dato de la escritura anterior; con
    `vec_addr_r` el vector entero habría salido desplazado una posición, que en el espectro solo
    se ve como una fase distinta. Las dos cosas tienen test, y **las dos mutaciones se
    comprobaron**: `tb_drx_axil_regs.py::test_vec_we_llega_alineado_con_direccion_y_dato` falla
    con cualquiera de ellas.

    **Un hallazgo del propio L0, que no se esperaba.** El envolvente del puntero pasó de `==` a
    `>=`. Con la igualdad estricta, acortar `vec_len` con el puntero ya más allá del nuevo final
    obliga a recorrer el banco ENTERO antes de resincronizar — y ese recorrido pasa por la parte
    no cargada de la memoria. El flujo normal nunca lo ve (`VEC_LEN` se escribe con `vec_load` en
    alto, que ya deja el puntero en 0), pero el test lo destapó y el arreglo cuesta un comparador.

    **Lo que sale del diseño.** El canal MM2S del `axi_dma` (`c_include_mm2s 0`), el tercer
    maestro del `axi_interconnect` hacia HP0 (`NUM_SI` de 3 a 2), el puerto externo `m_axis_vec`,
    el `xlconcat` de interrupciones (una sola fuente vuelve a conectarse directa a `IRQ_F2P`,
    como antes de Z4.3), la mitad DDR de `rtl/vector_source.sv`, los puertos `s_vec_*` de
    `drx_top`, y la sonda `drx_debug_probe` con su ILA — la sonda medía el camino `s_vec_*` →
    `m_ray_*`, que ya no existe. El módulo y los XCI de `ip_debug/` se quedan en el árbol sin
    instanciar; la evidencia de las tres corridas está en `evidencia/p-21/`.

    **Dos cosas que esto NO hace, y conviene no confundirlas con lo que sí hace.**

    1. **No cierra P-16.** El DDS sigue sin `aclken`. Cualquier fuente futura con huecos —un ADC
       real, el JESD204B de la ZU9 si su `valid` no es continuo— vuelve a mezclar a la frecuencia
       equivocada, con el mismo síntoma mudo, en una plataforma donde diagnosticarlo cuesta mucho
       más. P-16 se **rebaja** a «no bloquea ZedBoard», no se cierra.
    2. **No cierra P-21.** El atasco del MM2S no está arreglado ni entendido: está inalcanzable.
       Si el MM2S vuelve, vuelve con él.

    **Y una cosa que se pierde:** después de este cambio **nada en el diseño ejercita el camino
    DMA PS→PL**. `M_AXI_MM2S` contra `S_AXI_HP0` era la única cobertura de ese sentido. Decisión
    explícita del 4-oct-2026, no un descuido.

    **Firmware.** `fw/src/app/drx_stimulus.c` se reescribe entero contra la ventana de registros:
    desaparecen el buffer entrelazado de 24000 B en `.bss`, el anillo de descriptores,
    `submit_pass`/`reap_pass`, `set_modo_ddr` y la tarea de FreeRTOS que rearmaba entre pasadas —
    es decir, desaparece el mecanismo entero donde vivía P-21. `DrxStimulusTask_Create` queda como
    no-op con comentario. `repeat` distinto de 0 pasa a contestar `unimplemented` (código 11, ya
    en el contrato v0.8): la BRAM reproduce en bucle por hardware y no hay nada que cuente
    pasadas, así que aceptarlo y reproducir indefinidamente dejaría al par remoto sin enterarse.
    **El contrato no cambia de versión.**

    `DrxStimulus_Stop()` cambia de semántica y hay que decirlo: ya no devuelve la fuente al tono
    de síntesis, porque el `$readmemh` solo corre al cargar el bitstream. La BRAM se queda con el
    último vector cargado sonando; volver al nominal es cargar `tono_if`, que es el mismo tono.
    `main.c` pierde el `DrxStimulus_Stop()` previo a `DrxRay_Init` —existía porque en
    Throttled(DDR) no salía ni un rayo entero— y en su lugar recarga el vector 0, para que la
    autoprueba de rayos mida contra el mismo tono que el modelo dorado y no contra el de +6 dBFS
    que dejó el último self-test.

    `DrxStimulus_SelfTest` es ahora **más débil** que la de v8..v10, y está dicho en su cabecera:
    relee `VEC_LEN` y `CTRL` por AXI-Lite, lo que prueba que la ventana existe y que el slave
    aceptó las escrituras, pero no que el CONTENIDO de la BRAM sea el correcto — no hay camino de
    lectura desde la memoria. Antes, una pasada completa del DMA sí probaba que los bytes habían
    entrado en la PL. La prueba del dato es el espectro del rayo contra el modelo dorado.

    **Verificación.** `make check` en verde, **160 tests**. L0 de `vector_source` reescrito entero
    (9 casos) y `tb_drx_axil_regs.py` en 24. La matriz L1 de D-12 **no hace falta** y conviene
    decirlo en vez de saltársela en silencio: el DDC, el NCO, el CIC, los FIR y el range gate no
    se tocan, y `vector_source` no tiene caso L1.

    **P&R, `-top zynq -step xsa`: cierra, y la BRAM se infirió.**

    | | antes (3-oct) | ahora (4-oct) |
    |---|---|---|
    | WNS | 2,394 ns | **1,618 ns** |
    | WHS | 0,013 ns | **0,014 ns** |
    | Block RAM Tile | 31,5 / 140 (22,50 %) | **38,5 / 140 (27,50 %)** |
    | Slice LUTs | — | 9702 / 53 200 (18,24 %) |
    | Registros | 19 656 (18,47 %) | 18 604 (17,48 %) |
    | DSP48 | 159 / 220 | 159 / 220 |

    **La BRAM se infirió como BRAM**, que era el riesgo principal: +7,0 tiles contra los +6
    previstos (12 nuevos menos los ~6 del banco de 4000 que había), y las LUT no se dispararon. Si
    hubiera caído a LUTRAM —el fallo que `rtl/drx_range_gate.sv:180-186` ya documenta— el conteo
    de BRAM se habría quedado donde estaba y el de LUT habría subido en miles. Los registros bajan
    1052 al irse el camino DDR, la FSM del conjunto y la sonda de P-21.

    **El WNS baja 0,776 ns, y NO por el camino nuevo.** Era el riesgo que el plan daba por más
    probable, y la medida lo descarta: el camino crítico es

    ```
    u_drx_top/u_ddc/g_ch[1].u_ddc/g_branch[1].u_fir/.../fifo_2_reg[18]/C
      -> u_drx_top/u_regs/overflow_sticky_r_reg[1]/D
    13,940 ns, 12 niveles (CARRY4 x8, DSP48E1, LUT4 x2, LUT5), lógica 7,019 / rutado 6,921
    ```

    O sea el FIFO interno del FIR Compiler hasta el latch sticky de OVERFLOW — un camino que ya
    existía y que no toca ni `vec_we` ni los bancos. Lo que cambió es la colocación: mover 12
    tiles de BRAM y sacar el MM2S reordena el die. `drx_axil_regs` sigue siendo el sumidero del
    camino crítico, como desde Z2, pero el origen ya no es el PS7 sino el DDC. Queda margen
    (1,618 ns sobre un periodo de 16 ns) y queda la advertencia de Z2: cada pieza nueva se apila
    sobre este mismo bloque.

    **XSA, BSP y `BOOT.BIN`.** `tools/build_vitis.sh zedboard` compila y enlaza sin símbolos sin
    resolver; los únicos avisos son los tres `fall through` de `xadapter.c` del port de lwIP de
    Xilinx, ya conocidos. **El ID de interrupción del S2MM no se mueve**, que era la comprobación
    obligada tras tocar el block design: `XPAR_FABRIC_DMA_S2MM_INTROUT_INTR` sigue en **61**, que
    es el macro que usa `drx_ray.c:42`. Lo que sí cambia es un alias que nadie usa
    (`XPAR_FABRIC_AXIDMA_0_S2MM_INTROUT_VEC_ID` pasa a `XPAR_FABRIC_AXIDMA_0_VEC_ID` al quedar un
    solo canal). `tools/make_boot.sh zedboard` da `BOOT.BIN` reproducible,
    `f3923c9d…`, con los dos avisos de solapamiento de `bootgen` ya cerrados como falso positivo
    el 1-oct.

!!! success "4-oct-2026 (más tarde): medido en placa — el barrido del catálogo cierra 8/8 y con él ZM4"
    Arranque en frío tras ciclo de `SW8`, carga por JTAG con `tools/cargar.sh` (nuevo: el hermano
    de `cargar_dbg.sh` para el bitstream de producción, porque el de depuración ya no engancha
    ningún ILA).

    **El mapa y la ventana, confirmados por AXI-Lite:**

    ```
    drx_status: mapa de registros v11 confirmado por AXI-Lite
    drx_stimulus: vector 0 (tono_if), 4000 muestras en bucle
    drx_stimulus: vector tono_if -- VEC_LEN=4000 (esperado 4000) vector_load=0 OVERFLOW 0 -> 0
    ```

    **Y algo que antes era imposible por definición:** la autoprueba carga dos vectores **y** se
    capturan rayos en la misma corrida. Hasta v10, `main.c` tenía que llamar a
    `DrxStimulus_Stop()` antes de `DrxRay_Init` porque en Throttled(DDR) no salía ni un rayo
    entero. Ahora:

    ```
    drx_ray: 219 rayos en 1000 ms, overrun=0x0 truncated=0x0
    drx_ray: dma_errors=0 resync=1 bad_magic=0 bad_n_ch=0 short=0 trig_gaps=0 ray_gaps=0
    ```

    **La regresión del dato, por el cable y no por JTAG** (`tools/mock_dsp.py --spectrum`, 5 s,
    1113 rayos, **222,6 rayos/s, 0 huecos de `seq`**, BITE limpio):

    ```
    canal 0: pico en bin +0 (+0.00000 de fs_dec), -9.03 dBFS
    canal 1: pico en bin +0 (+0.00000 de fs_dec), -9.03 dBFS
    canal 2: pico en bin +0 (+0.00000 de fs_dec), -9.03 dBFS
    ```

    **−9,03 dBFS, la misma cifra de antes del cambio**, en los tres canales. Y es una prueba más
    fuerte de lo que el plan pedía: el plan quería medir el tono que `$readmemh` deja en el
    bitstream, y esto mide `tono_if` **cargado por la ventana AXI-Lite**, así que valida el camino
    de carga además del dato. Dicho lo que NO se midió: el estado de precarga pura ya no es
    observable sin recompilar, porque `main.c` carga el vector 0 al arrancar. Es el mismo tono, y
    el riesgo que esa medida cubría —que el cambio rompiera algo que funcionaba— queda cubierto
    por ésta.

    **El barrido del catálogo: `tools/sweep_catalogo.py --settle 1` → 8/8, código de salida 0.**
    Los ocho vectores coinciden con el modelo dorado en bin de pico y en nivel, en los dos
    conteos de bins que el secuenciador de lotes alterna (1002 y 3689). **Eso cierra lo último
    que le quedaba a ZM4**, y es exactamente lo que P-16 bloqueaba: el 3-oct el mismo barrido daba
    0/8 con −87,3 dBFS.

    **La primera pasada dio 7/8, y el fallo era de la herramienta.** `tono_sobre_escala` coincidía
    en espectro (−4,32 dBFS medidos contra −4,32 del modelo) pero `sweep_catalogo.py` exigía que
    levantara `ddc_overflow` por su nombre. Preguntado el modelo dorado, para los ocho vectores y
    en los dos modos: **overflow = 0 en todos**, con el pico de salida de `tono_sobre_escala` en
    21005 de 32767 — la entrada está a +6 dBFS pero el ADC la recorta antes del DDC y el ajuste de
    ganancia de Z1 deja la salida 3,9 dB por debajo del fondo. El hardware y el modelo coinciden;
    la expectativa escrita a mano era falsa, y Z4.3 ya la había marcado como no medida. Corregido
    haciendo que la bandera se compare contra lo que el modelo predice
    (`dump_ray.model_channel` devuelve ahora `overflow`) en vez de contra una lista de nombres.

    Eso deja un hueco real anotado como [P-22](../alcance/pendientes.md#p-22): con el catálogo de
    hoy **nada ejercita el camino de overflow del DDC de punta a punta en silicio** — ni
    `drx_saturate`, ni el latch sticky de `drx_axil_regs`, ni el registro OVERFLOW, ni la bandera
    de la trama `ray`. L0 lo cubre con estímulo inyectado; a la fuente real no se le ha visto
    nunca levantarlo.

!!! success "4-oct-2026 (noche): soak del catálogo — 2136 selecciones encadenadas, ningún atasco"
    La afirmación que el cambio de arquitectura deja implícita —que sin el canal MM2S no queda
    nada en el camino de estímulo que se pueda atascar— no estaba medida. Ahora sí.
    `tools/soak_catalogo.sh` (nuevo) encadena barridos del catálogo; no reusa
    `tools/conductor_p21.sh` porque la premisa de aquel se invirtió: toleraba `rc=1` porque con
    Throttled(DDR) el barrido daba 0/8 por P-16, y ahora cualquier `rc != 0` es un fallo real.

    **Primera corrida, 41 min: 201 pasadas, 1608 selecciones, cero atascos.** El criterio que
    buscaba —tres fallos seguidos— no se disparó ni una vez, y la cadena nunca se quedó parada.
    `dma_overruns = 0`, `ray_gaps = 0`, `BITE = 0x0`, **223,2 rayos/s sostenidos** (553 495 rayos
    en 2480 s) contra los 223,47 predichos.

    **Pero 27 de las 201 pasadas dieron 7/8, y eso obliga a corregir lo que se dijo por la
    tarde.** El 8/8 de la pasada suelta fue en parte suerte. Los 27 fallos son el **mismo vector y
    el mismo modo de fallo**: `dos_tonos`, con el pico en el bin espejo —`-156` donde el modelo
    pone `+156`, y una vez `-575` contra `+575` en el otro conteo de bins—.

    No es del DRx. `dos_tonos` son dos tonos colocados simétricamente alrededor del IF
    (`if_norm ∓ 0,0008`), así que en banda base el espectro es **exactamente** simétrico: el
    modelo dorado da `4657187.1` en `+156` y `4657187.1` en `-156`, bit a bit. Comparar el bin de
    `argmax` entre dos valores iguales no puede ser determinista — qué lado gana lo decide el
    ruido de cuantización, y lo decidió al revés un 13 % de las veces.

    Corregido en `tools/dump_ray.py`: `spectrum()` marca `peak_ambiguo` cuando el bin espejo está
    dentro de 0,5 dB del pico, y `sweep_catalogo.py` compara entonces `|bin|` en vez del bin con
    signo. Sale del modelo, no de una lista de nombres de vector — mismo criterio que la bandera
    de overflow, y por la misma razón. De los ocho vectores, `dos_tonos` es el único ambiguo, en
    los dos conteos de bins, así que la corrección no afloja los otros siete.

    **Segunda corrida con el criterio arreglado, 10 min: 66 pasadas, 528 selecciones, 0 fallos.**

    **Y un hallazgo nuevo que el soak hizo visible: cargar un vector cuesta un rayo.**
    `trig_gaps` sube **1,05–1,12 por selección** en las dos corridas. La causa es directa:
    `vector_load` congela el lector de `vector_source` mientras el PS escribe las 4000 muestras,
    pero el motor de timing cuenta ciclos de reloj (`timing_paced = 0`) y no se entera, así que
    `ray_start` dispara sobre una cadena sin muestras. Los 101 cortos y 96 largos acumulados son
    los rayos de esa frontera, y los 174 `enc_fail` son `DrxRayFrame_Encode` negándose a
    enmarcarlos — **no llega dato malo al DSP**. Anotado como
    [P-23](../alcance/pendientes.md#p-23), sin arreglar: cuesta un rayo cada 1600 PRIs durante un
    barrido de banco de pruebas y cero en operación normal, y arreglarlo toca el motor de timing,
    cerrado y medido desde Z2. **Cerrado como coste aceptado el 5-oct-2026**, sin tocar RTL: nadie
    necesita el barrido sin pérdida, y retener el motor con `vector_load` empalmaría un rayo en
    silencio (inferencia, no medida). Razonamiento en `pendientes.md#p-23`.

    `sink_drops`, `cola` y `snd_fail` salen altos porque el barrido conecta y desconecta 2136
    veces; son artefactos de interacción con el cliente, no criterio de salud.

!!! success "5-oct-2026: P-22 cerrado como inalcanzable por estímulo — la cota está medida"
    Se intentó diseñar el vector que levanta `ddc_overflow` y salió que no existe. La cadena del
    modelo es lineal salvo redondeos; midiendo su respuesta con un impulso de fondo de escala en
    cada posición de entrada y barriendo las 25 fases del NCO, la salida máxima posible con
    `|x| <= fs` es **0,927 fs en fino y 0,832 fs en grueso** (`tools/bound_ddc_overflow.py`, 4 min).
    Un vector con el signo de esa respuesta dio `|pico I| = 30057` de 32767 y `overflow = 0/64`.
    Subir la amplitud ya se sabía que no servía; esto cierra también «concentrar la ganancia en la
    banda de paso». Sin cambiar la ganancia de Z1 (toca D-12) no hay vector. Queda sin ver en placa
    el cableado `overflow` → sticky → trama `ray`, cubierto solo por L0; el gancho de prueba en RTL
    que lo cerraría está descrito en `pendientes.md#p-22` y no se hace sin un requisito que lo pida.

!!! success "8-oct-2026: Z4.6 cerrada — el DSP real cierra el lazo de AFC sobre la ZedBoard"
    El DSP de Rust (`lamula-dsp`) conecta al puerto 9470, configura una NEXRAD estándar (máscara
    `0x15`: RX_0 = I, RX_2 = Q, TX_BURST_0 = muestra del transmisor) y cierra el lazo de AFC contra
    la placa cargada por JTAG, con la ZedBoard dilatada ×4 respecto de la ZU9 (`fs_dec` medida
    ≈ 150,5 kHz).

    **Medido.** Estimador del burst contra el pico de la FFT del canal 2, con el NCO barrido de
    −40 kHz a +40 kHz y N = 4, 8 y 16: coinciden, sin sesgo. Lazo cerrado, 90 s: pico del canal 2
    de **−0,416 a 0,000 de `fs_dec`** (−17,48 a **−9,03 dBFS**, el mismo −9,03 que el modelo
    dorado), 1168 rayos sin huecos de `seq`, `afc_bite = 0`, `afc_freq_meas_hz = −62 501 Hz` y
    `afc_control_freq_hz = −62 499 Hz` (a 30 s la diferencia era 1,1 kHz; el resto era el primer
    orden con tau = 2 s).

    **Causa de la convergencia a medias.** El burst se mide DESPUÉS del DDC ya retunado, o sea que
    lo medido es el residuo `d − x`. El DSP lo filtraba como absoluto: punto fijo `x = d/2`
    (−31,2 kHz medido). Arreglo en el DSP (`AfcLoop::update_residual`), no en el firmware. Del lado
    del DRx: el sello del rayo lleva la configuración realmente aplicada (`drx_timing_cfg.c`,
    `drx_ray_ctx.c`).

    **Sin verificar.** El signo (mezclador conjugado, `NCO = rx_if − freq`) se validó solo en la
    ZedBoard; falta confirmarlo en la ZU9 ([P-24](../alcance/pendientes.md#p-24)).

## Z5 — Endurecimiento y dossier de portabilidad (semanas 25–28) { #z5 }

Trabajo:

- Campañas de inyección de fallos ([catálogo](../pruebas/plan-testing.md#inyeccion-de-fallos)) y
  soak de 72 h.
- [Campaña de throughput sintético](#throughput).
- Cierre del [registro delta de portabilidad](../portabilidad/registro-delta.md) con evidencia por
  entrada.
- **Dossier de migración**: qué cambia exactamente al pasar a ZU9, fichero por fichero, con la lista
  de regeneraciones de IP.
- `BOOT.BIN` y procedimiento de provisionado de placa limpia, probado desde cero.
- Documentación.

**Hito ZM5 (fin S28):** todo lo construible sin JESD está construido, validado y documentado, y
existe un plan de migración ejecutable.

!!! warning "11-oct-2026: soak de 72 h — integridad demostrada, pero sobre una configuración que nadie eligió"
    Corrió del 8-oct 19:36 al 11-oct 19:36 EDT (`tools/soak.sh 259200`, evidencia en
    `build/soak/20261008-193558/`), contra la ZedBoard sin reiniciar desde el 8-oct 12:09.

    **Qué quedó demostrado.** 20 864 353 rayos recibidos, 461 696 MB, `BITE=0x0` todo el tiempo,
    `dma_overruns=0`, `ddc_overflows=0`, `ray_gaps=0`, `enc_fail=0`, `cortos=0`, `largos=0`,
    `magic=0`, `dma_err=0`, `snd_fail` sin cambios durante la corrida. Cuadre cliente contra placa:
    `rayos_tx` pasó de 45 313 a 20 909 652 (20 864 339 enviados) y el cliente recibió 20 864 353;
    la diferencia de 14 cabe en las ventanas de muestreo. Lo que la placa envió, llegó.

    **Descartes.** `sink_drops` subió 1019 (≈49 ppm, uno cada ~3,6 min, ritmo estable de principio a
    fin) y el cliente contó 145 huecos de `seq`, unos 7 rayos por hueco de media (cociente, no
    medido hueco a hueco). No hay causa atribuida: la UART solo lleva `uptime`, no hora de pared, y
    la línea `rayo ...` solo se imprime cuando cambia el contador, con intervalos crecientes. Los
    avisos del host (`rtw_8821ce`, NetworkManager) son del WiFi, no del enlace `enp1s0`, y no hay
    evidencia de que sean la causa. El trabajo de ADR-001 corrió en la misma máquina con
    `nice -n 19 taskset -c 3`; la tasa de descartes fue similar durante y después (≈0,004/s contra
    ≈0,005/s), lo que va contra una causa de carga del host, aunque la comparación es gruesa.

    **Qué NO es este soak.** Corrió con la configuración que dejó en la placa la sesión del DSP real
    del 8-oct, no con la de bring-up, y `soak.sh` no la fijó ni la registró. Leída de 966 rayos vivos
    el 11-oct:

    | Campo | Medido | Bring-up |
    |---|---|---|
    | `prf_div` | 776 398 en ambos lotes (80,50 Hz a 62,5 MHz) | 767 312 / 208 416 |
    | `bins` | 1840 en ambos lotes | 3689 / 1002 |
    | lotes | 6 + 6 rayos, alternando | 6 + 41 pulsos |
    | `pulse_width_idx` / `pulse_mode` / `cell_mode` | 1 / 0 / 1 | — |
    | caudal | 14,2 Mbps, 80,5 rayos/s | 28,9 Mbps, 223 rayos/s |

    Por tanto las cifras de arriba valen para esa configuración y esa carga, y **no son comparables
    con el soak del 3-oct** (3,08 M rayos, `huecos de seq` 0, 223 rayos/s). Ambos lotes comparten
    PRF y ancho de pulso, así que tampoco es una configuración Batch real de NEXRAD. El mensaje
    `config` exacto que mandó el DSP no está registrado en ningún sitio: la sesión del 8-oct no
    dejó transcripción y el log de UART empieza después del arranque.

    **Hallazgo nuevo: los 966 rayos leídos llevan la bandera `TRUNCATED`** (`ray_flags` `0x5`/`0x25`).
    `drx_ray_ctx.c` la pone cuando `GATE_TRUNCATED` es distinto de 0 en el momento del rayo.
    Hipótesis inicial: `776398 mod 208 = 142`, o sea PRI no múltiplo de R₁ como en Z4.4. **Corrección
    del 12-oct (ver «Causa de `TRUNCATED`» más abajo):** la regla de Z4.4 era incompleta, y la
    «config de bring-up» de 300 000/800 000 que se citó aquí no es la que corre el hardware. Lo que sí
    quedó demostrado es que no era un bit sticky de firmware: con placa reiniciada y otra config
    desaparece. Los ~20,8 M de rayos del soak de 72 h iban, con alta probabilidad, marcados, y
    `resumen.txt` no tenía contador de truncados.

    **Firmware.** El `drx_app.elf` cargado es del 8-oct 12:07, anterior al commit `6a70f45` (19:08),
    que cambió `drx_timing_cfg.c` y `drx_ray_ctx.c`. No consta de qué árbol salió, así que el soak no
    se puede atar a un commit.

    **Para que el próximo soak sirva como evidencia de Z5:**

    1. Reiniciar la placa y mandar explícitamente la configuración deseada, o capturar un rayo y la
       configuración aplicada al inicio y al final (`prf_div`, `bins`, `ray_flags`).
    2. Estampar hora de pared en las líneas de UART.
    3. Que `mock_dsp.py` cuente rayos perdidos por hueco, no solo eventos, y registre la hora de
       cada hueco.
    4. Registrar el commit y el SHA del ELF cargado en `resumen.txt`, y un contador de rayos
       `TRUNCATED`.

    El requisito «soak de 72 h» de Z5 **sigue sin cumplirse** con evidencia fiable de configuración.

!!! success "12-oct-2026: soak de 8 h con la config de bring-up — limpio, 0 descartes"
    Corrió del 12-oct 06:25 al 14:25 EDT (`tools/soak.sh 28800`, evidencia en
    `build/soak/20261012-062512/`), tras reiniciar la placa, recompilar el ELF
    (`0f4de029e6e28109`, 11-oct 21:20, árbol en `daac970`; solo `tools/` sucio) y cargarlo con
    `tools/cargar.sh`. Antes, 15 min de prueba (`build/soak/20261011-212134/`, 201 061 rayos): idéntico
    resultado. Sin JTAG ni DSP real conectados durante la corrida.

    **Medido.** 6 433 922 rayos recibidos (`seq` 7 294 291 a 13 728 212, 6 433 922 consecutivos), 104 155
    MB, 223,4 rayos/s, 28,9 Mbps. **0 huecos de `seq`, 0 rayos `TRUNCATED`**, `BITE=0x0`,
    `dma_overruns=0`, `ddc_overflows=0`, `trig_gaps=0`, `ray_gaps=0`, `sink_drops=0`, `enc_fail=0`,
    `cortos=0`, `largos=0`, `cola=0`, `rayo sin enmarcar` 0. `snd_fail=1`, `resync=1` y
    `descartados=1` fijos desde el arranque (no crecieron). Config **que declaran las cabeceras** de los
    rayos: lote alto `prf_div=300000`, `bins=1002` (5 612 570 rayos) y lote bajo `prf_div=800000`,
    `bins=3689` (821 352), `pulse_width_idx` 0 y 2, `cell_mode=0`. **Esos `prf_div` no son los que
    corría el hardware**, ver «Causa de `TRUNCATED`» abajo. Cuadre contra la placa: `rayos_tx` +6 428 106 desde
    la primera lectura, 5 816 menos que el cliente, que cabe en los ~26 s entre que el cliente
    conectó y esa lectura.

    **Contra el soak de 72 h.** Allí hubo 1019 descartes (≈49 ppm); a esa tasa aquí habría salido
    del orden de 300 y salieron 0. Cambiaron a la vez la config (80,5 contra 223 rayos/s), el ELF y el
    reinicio de la placa, así que **no se puede atribuir** a una sola de las tres. Queda sin
    explicar la causa de los descartes de aquel soak.

    **Causa de `TRUNCATED`, 12-oct-2026 (análisis de RTL y firmware, no medido en placa).**

    - **La cabecera miente sobre `prf_div`.** `DrxControlBoot_SelfTest` manda un `config` sintético
      (`prf_div` 800 000 / 300 000, `fw/src/app/drx_control_boot.c:67`) que `DrxTiming_Apply` guarda en
      `g_applied`; al terminar, el propio self-test reescribe los **registros** con
      `DrxTiming_DefaultConfig` (767 312/3689 y 208 416/1002, alineados a R₁), pero no toca `g_applied`.
      `DrxTiming_GetRayMeta` lee `g_applied`, así que los rayos declaran 800 000/300 000 mientras el
      motor corre 767 312/208 416. Inferencia, no lectura de registros: encaja con 0 `TRUNCATED` y con la
      Z4.4. Los `prf_div` de la cabecera son, mientras no llegue un `config` real, los del self-test. Es un
      bug de firmware, **corregido y medido en placa el 12-oct-2026** (`27a5d51`,
      `DrxTiming_RestoreDefault`): tras recargar, `tools/mock_dsp.py` vio en 2240 rayos cabeceras con
      `prf_div` 208 416 (1958 rayos, lote alto) y 767 312 (282 rayos, lote bajo), 0 huecos, 0 `TRUNCATED`.
      Con el fix la inferencia de arriba queda confirmada para la cabecera; el soak de 72 h del 8-oct
      sigue sin config registrada.
    - **Regla real.** `drx_range_gate` corre libre: un `valid` cada `dec` ciclos (R₁ = 208 en fino, R₂ =
      416 en grueso) y un `ray_start` cada `prf_div`. `ray_start` levanta `ray_truncated` si `wr_ptr ≠ 0`.
      Con `n = prf_div / dec` muestras por PRI, no hay `TRUNCATED` solo si `n` es múltiplo entero de
      `bins`; sin truncar y con **un** rayo por PRI, solo si `prf_div = bins × dec`. Modelo por eventos
      (`rtl/drx_range_gate.sv:236-275`, script en el scratchpad de la sesión):

        | prf_div / bins / dec | muestras/PRI | rayos/PRI | truncados/PRI |
        |---|---|---|---|
        | 767 312 / 3689 / 208 (alineado) | 3689,00 | 1 | 0 |
        | 208 416 / 1002 / 208 (alineado) | 1002,00 | 1 | 0 |
        | 767 198 / 3688 / 208 (Z4.4, con guarda) | 3688,45 | 1 | 0,45 |
        | 300 000 / 1002 / 208 (cabecera) | 1442,31 | 1 | 1 |
        | 800 000 / 3689 / 208 (cabecera) | 3846,15 | 1 | 1 |
        | 776 398 / 1840 / 416 (DSP, `cell_mode=1`) | 1866,34 | 1 | 1 |

      Cuadra con las tres observaciones: Z4.4 (0,45 de media con guarda, 0 alineado), el soak de 72 h
      (966/966) y el de 8 h (0). **La explicación de Z4.4 era incompleta:** el PRI tiene que ser múltiplo
      de `dec` **y además** igual a `bins × dec`; con `dec` = 416 (grueso) el múltiplo es de R₂.
    - **El DSP de 72 h no tenía factor 2 sin explicar:** `cell_mode=1` usa R₂ = 416 y `1840 × 416 =
      765 440 < 776 398`; sobran 26 muestras por PRI, que `ray_start` descarta cada vez.
    - **`DrxTiming_Apply` acepta esa config.** `batch_ok` solo exige `bins × dec < prf_div`
      (`drx_timing_cfg.c:378`), así que un DSP que mande `bins` por debajo de `prf_div / dec` recibe
      `config_ack` OK y rayos `TRUNCATED` en todos. Es el BITE funcionando, pero el DSP no se entera salvo
      por la bandera.

    **Límites.** Son 8 h, no 72 h: el requisito de Z5 sigue sin cumplirse con esta prueba. Un solo
    cliente Python que solo lee, sin lazo de AFC del DSP real. La mezcla de lotes (87 % / 13 %) es la
    de la config de bring-up, no una Batch real de NEXRAD (pendiente decidir cuál pide Z5).

## Campaña de throughput: es un ensayo aparte { #throughput }

Consecuencia incómoda de la dilatación: a 100 MHz la salida es
`100e6/208 × 4 B × 4 ch = 7,69 MB/s = 61,5 Mbps`, muy por debajo de los 154 Mbps reales. **Los
ensayos de throughput sobre el camino de fabric no son representativos.**

La solución es desacoplarlos, en dos ensayos independientes:

1. **Rayos sintéticos desde el PS.** El PS genera rayos a la tasa real de 19,23 MB/s — y a 1,5× y 2×
   como margen — y los transmite por GEM/lwIP con el framing real. Valida lo que hay que validar
   (pila de red, framing, gestión de buffers, latencia) sin depender del fabric dilatado.
2. **DMA S2MM con generador de patrones en fabric** a la tasa real, para caracterizar el camino
   AXI-HP → DDR independientemente del DDC.

## Corrección al orden de prioridades original

El orden propuesto inicialmente era: DDC+gating → timing → SSI → camino de datos → CI. Los cuatro
primeros se aceptan tal cual. Dos cosas cambian:

- **CI y flujo Tcl no van los últimos: son precondición.** Van en [Z0](#z0), por el argumento del
  recuadro de esa sección.
- **El congelado del esquema DRx↔DSP tampoco va cuarto.** Se separa *definir el esquema* (Z0, coste
  bajo, dependencia externa alta) de *implementar el transporte* (Z4, coste medio, dependencia
  nula). Ver [D-08](../alcance/decisiones.md#d-08).

El resto del orden queda intacto.

## Definición de terminado (semana 28)

El firmware LAMULA DRx, sobre una ZedBoard provisionada desde cero por un `BOOT.BIN` construido por
CI de forma reproducible, reproduce vectores de IF conocidos a través de la capa de abstracción de
fuente de muestras, los baja a banda base y los diezma en la PL a I/Q compleja enrejada en rango
para ambos tamaños de celda con concordancia bit a bit contra el modelo dorado, genera los cuatro
triggers a la PRF y anchos de pulso configurados con jitter caracterizado, rechaza las combinaciones
ilegales de PRF y rango, lee dos encoders SSI contra dos emuladores independientes y etiqueta cada
rayo con azimut y elevación con error temporal acotado, ensambla los rayos bajo FreeRTOS y los
transmite a un consumidor de DSP sobre GEM 1GbE conforme al esquema DRx↔DSP congelado, aplica la
corrección AFC suministrada, encuadra los tres modos de barrido, reporta status y BITE bajo todas
las inyecciones de fallo del catálogo, sostiene la tasa real de 19,23 MB/s en la campaña sintética
de throughput, y sobrevive 72 horas de soak.

Y, explícitamente, **no** valida: el enlace JESD204B, el árbol de clocking y SYSREF, la
sincronización multi-dispositivo, la tasa de 250 MSPS, el frontal analógico real, la interfaz del
DAC AD9129 ni la capa física RS-422. Esos siete elementos siguen abiertos y son el contenido del
trabajo sobre la ZU9.
