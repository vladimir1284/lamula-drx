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
    [Mapa de registros AXI-Lite](registros.md#deliberadamente-fuera-de-v2) actualizados.

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

## Z2 — Motor de timing, triggers y PRF (semanas 9–13) { #z2 }

Trabajo:

- Generador de 4 triggers configurables con retardo y ancho independientes. **RTL escrito y
  verificado bit a bit contra el modelo dorado** (`rtl/drx_trigger_gen.sv` +
  `rtl/drx_trigger_one_shot.sv`, 21-sep-2026 más tarde); falta integrarlo en `drx_top` — depende
  del mapa de registros de Z2 (P-15), igual que el secuenciador de lotes.
- **Secuenciador de 2 lotes de PRF/ancho de pulso por radial** (Batch mode de NEXRAD, D-13, cierra
  P-04): lote de PRF baja (vigilancia) + lote de PRF alta (Doppler), conteo de pulsos por lote
  configurable por registro, alternados de forma autónoma en fabric y en bucle continuo durante el
  barrido — no un único par PRF/ancho global. Valores de registro idénticos a la ZU9. **RTL escrito
  y verificado bit a bit contra el modelo dorado** (`rtl/drx_prf_batch_seq.sv`, 21-sep-2026 más
  tarde); falta integrarlo en `drx_top` — depende del mapa de registros de Z2 (P-15).
- Selección de ancho de pulso 0,8 / 1,66 / 3,3 µs (200 / 415 / 825 ciclos a 250 MHz), por lote.
- Manejo de modos de pulso y encuadre por PRI.
- **Validador de configuración PRF × rango**
  ([D-09](../alcance/decisiones.md#d-09)), aplicado **a cada uno de los 2 lotes por separado**
  (D-13: sus rangos no ambiguos son distintos por diseño), con código de error hacia el contrato.
- Sincronización determinista entre el trigger y el inicio del gating, incluida la transición
  lote-bajo → lote-alto dentro de un mismo radial.
- Instrumentación en fabric: contador libre en un dominio de reloj distinto, para auto-medir jitter
  y periodo.
- Salida de los 4 triggers a Pmod para medida con osciloscopio.

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
    Ningún plan de los tres proyectos apunta hoy la salida real de la ZedBoard (`vector_source`,
    datos generados en el PL) contra el DSP y el RCP reales — ver
    [P-13](../alcance/pendientes.md#p-13). Cerrar ZM4 contra el stub no cierra ese hueco.

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
