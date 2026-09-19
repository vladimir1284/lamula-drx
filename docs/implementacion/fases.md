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

## Z2 — Motor de timing, triggers y PRF (semanas 9–13) { #z2 }

Trabajo:

- Generador de 4 triggers configurables con retardo y ancho independientes.
- PRF programable en todo el rango, con valores de registro idénticos a la ZU9.
- Selección de ancho de pulso 0,8 / 1,66 / 3,3 µs (200 / 415 / 825 ciclos a 250 MHz).
- Manejo de modos de pulso y encuadre por PRI.
- **Validador de configuración PRF × rango**
  ([D-09](../alcance/decisiones.md#d-09)) con
  código de error hacia el contrato.
- Sincronización determinista entre el trigger y el inicio del gating.
- Instrumentación en fabric: contador libre en un dominio de reloj distinto, para auto-medir jitter
  y periodo.
- Salida de los 4 triggers a Pmod para medida con osciloscopio.

**Hito ZM2 (fin S13):** matriz completa PRF × ancho de pulso × modo × 4 triggers en verde, en
simulación y en placa; jitter medido y caracterizado; combinaciones ilegales rechazadas con el
código correcto.

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
