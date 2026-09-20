# CLAUDE.md — LAMULA DRx

Punto de entrada para un agente o una persona que se incorpora en frío. Esta página dice **dónde
está el proyecto ahora**; las reglas de ingeniería están en `AGENTS.md` y no se repiten aquí.

## Qué es

Receptor digital FPGA del sistema LAMULA. Digitaliza el IF del radar, hace conversión a banda base y
diezmado en la lógica programable, ensambla los rayos con sus metadatos bajo FreeRTOS y los entrega
al LAMULA DSP por 1GbE contra el contrato DRx↔DSP. Su única interfaz externa es DRx↔DSP: no habla
con el RCP ni con ORPG.

- **Plataforma objetivo:** Zynq UltraScale+ ZU9 + 2× VadaTech FMC213 (ADC: 2× TI ADS42JB69, dual
  16 bits, 250 MSPS, JESD204B). **Aún no comprada.**
- **Plataforma de desarrollo actual:** Digilent ZedBoard, XC7Z020-CLG484-1.

## Estado, a 20 de septiembre de 2026

**Z0 — substrato: cerrada.** `make check` sigue en verde (79 tests hoy, Verilator + gcc + NumPy +
lint). Detalle en el tutorial de `docs/tutorial/` e inventario en `docs/implementacion/substrato.md`.
El runner de CI con Vivado (`[self-hosted, vivado]`, `HAS_VIVADO_RUNNER`) sigue sin montarse — ZM0
tal como lo define `docs/implementacion/fases.md` («`git push` produce un `BOOT.BIN` byte a byte sin
intervención humana») sigue sin cumplirse en CI, solo demostrado a mano (5-sep-2026). Ver A7/A8 en
`docs/alcance/pendientes.md`.

**Z1 — DDC + range gating: en curso, avanzada, no cerrada.** `rtl/drx_ddc_top.sv` existe, corre
contra IP real de Xilinx (DDS Compiler, CIC Compiler, FIR Compiler ×2) y está verificado con la
matriz completa de L1 (8 casos × {fine, coarse} = 16 corridas contra xsim real, con tolerancia
D-12). **`rtl/drx_top.sv` dejó de ser el diseño vacío de Z0**: instancia de verdad `vector_source`
(nuevo) → `drx_ddc_quad_top` → `drx_range_gate_quad_top`, `N_CH=3`, y tiene un P&R real (no solo
simulación) que cierra temporización. Estado de cada entregable de Z1, `docs/implementacion/
fases.md#z1` es la fuente viva:

- **Bit-exactitud del NCO:** resuelta y CUMPLIDA. [D-12](docs/alcance/decisiones.md#d-12) acepta el
  residuo medido (≤5 LSB) como techo del bloque; `sim/tb_sv/drx_l1_checker.sv` ya tiene
  `TOLERANCE_LSB` y la matriz completa de 16 combinaciones corrió contra xsim real bajo ese
  comparador — **16/16 "PASS", confirmado con reverificación limpia** (2 de las 16 dieron
  falso-fallo en la primera pasada por un directorio de build de xsim reutilizado de antes de D-12
  — kernel con `TOLERANCE_LSB=0` por defecto, detectado por timestamp; corregido borrando el build
  y regenerando vectores, ver `pendientes.md`#p-09). [P-11](docs/alcance/pendientes.md#p-11)
  cerrado, confirmado que el techo de Taylor (~−88/−92 dBc) alcanza.
- **Top-level de 3 canales heterogéneos (Config A Tx+H+V / Config B Tx+nominal+atenuado):**
  resuelto — `rtl/drx_ddc_quad_top.sv` y `rtl/drx_range_gate_quad_top.sv` son genéricos en `N_CH`,
  `N_CH=3` ya es ese top-level, verificado contra xsim real (`tb_l1_ddc_tri.sv`,
  `tb_l1_ddc_range_tri.sv`). Ver [P-12](docs/alcance/pendientes.md#p-12).
- **`vector_source` (BRAM-loop):** escrito (`rtl/vector_source.sv`), el primer ítem de Z1 que no
  existía como RTL sintetizable hasta el 19-sep-2026. Solo modo BRAM-loop; RT y Throttled (DDR)
  siguen sin implementar.
- **P&R real del datapath completo, 19-sep-2026:** primera vez que se mide temporización de la
  cadena real (antes, el único WNS medido era del diseño vacío del latido). A 100 MHz **no
  cerraba** (WNS = −1,209 ns, camino crítico FIR Compiler droop → BRAM de range-gate) — la
  contingencia que ya preveía `docs/plataforma/dilatacion-temporal.md` resultó necesaria de
  verdad. **`fs_hz` de zedboard bajó de 100 a 62,5 MHz** (`config/params.toml`, dilatación
  numérica pura, D-02 — no toca `R₁`/`R₂`/`fs` de la ZU9). A 62,5 MHz: **WNS = +2,770 ns, cierra**.
  Dos hallazgos de síntesis real en `drx_range_gate.sv` (RTL ya verificado por xsim, no código
  nuevo) tuvieron que corregirse en el camino — ver `fases.md#z1`, entrada del 19-sep — sin cambiar
  su comportamiento (reverificado bit a bit / D-12 contra xsim tras cada uno).
- **Mapa de registros AXI-Lite:** v2, `rtl/drx_axil_regs.sv` + `config/registers.toml`
  (fuente única, codegen con `tools/gen_registers.py`, mismo patrón que el contrato DRx↔DSP).
  VERSION (RO), CTRL (RW, `mode_coarse`, sustituye el `localparam` fijo que tenía `drx_top`),
  STATUS (write-1-to-clear, `overrun` por canal de range-gate) y OVERFLOW (write-1-to-clear,
  overflow de saturación del DDC por canal, añadido 20-sep-2026). Detalle en
  `docs/implementacion/registros.md`. Verificado con L0 real (80/80 en `make check`) **y con xsim
  real**: la matriz completa de D-12 (16 combinaciones, `tb_l1_ddc.sv`) se reconfirmó tras añadir
  el puerto `overflow` — **16/16 PASS** — y `tb_l1_ddc_range_tri.sv` (fine/coarse, 3 canales cada
  uno) tras el puerto `clear` de `drx_range_gate` — **6/6 PASS**, TLAST bit a bit incluido (ver
  `docs/implementacion/fases.md#z1`, entrada del 20-sep). **P&R ya re-cerrado también** (ver el
  punto siguiente) — sus puertos AXI-Lite NO llegan a pines físicos de `drx_top` (94 pines contra
  50 sitios, el mismo límite del hallazgo de range-gate del 19-sep): se atan a valores inertes, y
  **falta un puente PS7↔AXI real, no diseñado todavía, para que firmware pueda alcanzar el mapa
  desde hardware de verdad** — ver la cabecera de `rtl/drx_top.sv`.
- **P&R re-cerrado con el AXI-Lite integrado, 20-sep-2026:** `-step impl` — **WNS = 2,528 ns,
  WHS = 0,017 ns** ("All user specified timing constraints are met"). Post-route: LUT 7,61 %
  (4049/53200), registros 8,33 % (8865/106400), BRAM Tile 21,07 % (29,5/140), **DSP48 111/220
  (50,45 %)** — cifra que **no cuadra** con la medida el 19-sep (153/220, 69,6 %) para
  prácticamente el mismo datapath; una inspección rápida no encontró eliminación de código muerto
  de la rama gruesa, pero la discrepancia sigue sin explicar — ver `fases.md#z1`, entrada del
  20-sep más tarde. El propio gate de `tcl/build.tcl` solo comprueba WNS de setup, no de hold (el
  hold pasó brevemente a negativo en un reporte intermedio antes de resolverse solo).
- **Conmutación en caliente fino/grueso:** diferida explícitamente, sin empezar (`rtl/drx_ddc_top.sv`,
  `rtl/drx_range_gate.sv`).
- Nuevo hallazgo abierto, no bloqueante: [P-14](docs/alcance/pendientes.md#p-14) — falta evaluar la
  varianza de los estimadores de momento bajo el residuo aceptado por D-12, contra Doviak & Zrnic
  cap. 6. Deuda de validación sobre una decisión ya tomada, no una condición de cierre de Z1.

Lo que sí está hecho y verificado, además de lo de arriba:

- El sitio de documentación se construye y se despliega solo a
  <https://lamula-drx-docs.pages.dev> en cada push a `main` que toque `docs/`. Detalles,
  credenciales y deuda conocida del CI en `docs/implementacion/infraestructura.md`.
- El plan de 28 semanas (Z0–Z5), doce decisiones congeladas, el plan de verificación y el registro
  delta de portabilidad están escritos y publicados.
- P-01 (tolerancia de celda) cerró el 7-sep-2026: exactitud requerida, confirmado también en modo
  fino. P-05 (`RDA_Backend_Py`) sigue abierto, sin localizar.

## Orden de lectura

1. `docs/alcance/contexto.md` — qué es y qué no es, y la relación con los proyectos DSP y RCP.
2. `docs/alcance/decisiones.md` — las doce decisiones congeladas (D-01…D-12). Ninguna se revierte
   sin discutirlo.
3. `docs/alcance/pendientes.md` — hallazgos abiertos (P-01…P-14), supuestos de entorno a verificar y
   riesgos de la estrategia ZedBoard.
4. `docs/implementacion/fases.md` — el plan de trabajo.
5. `AGENTS.md` — las reglas que no se negocian, antes de escribir la primera línea de código.

`docs/referencia/` conserva íntegros los dos documentos de los que deriva todo lo anterior: el plan
de ZedBoard y el project plan original de 34 semanas para la ZU9.

## Lo primero que hay que hacer

Para cerrar Z1 de verdad, en orden:

1. **Puente PS7↔AXI para el mapa de registros** — hallazgo del 20-sep-2026: los puertos AXI-Lite de
   `drx_axil_regs` están atados a valores inertes dentro de `drx_top` (no llegan a pines físicos,
   ver más abajo), así que el mapa de registros existe y está verificado pero **no es alcanzable
   desde firmware de verdad todavía**. Hace falta un PS7 (o un puente JTAG-a-AXI) instanciado en
   este repo — no existe ni se ha diseñado. Nuevo, no estaba en esta lista antes del P&R del 20-sep.
2. **Explicar la discrepancia de DSP48** entre el P&R del 19-sep (153/220) y el del 20-sep con el
   AXI-Lite integrado (111/220) para prácticamente el mismo datapath — ver `fases.md#z1`, entrada
   del 20-sep. No se investigó a fondo; no confiar en ninguna de las dos cifras para presupuesto de
   recursos hasta resolverlo.
3. **Conmutación en caliente fino/grueso** (continuidad de fase en `drx_ddc_top`/`drx_range_gate`) —
   diferida desde el diseño original, sin empezar.
4. Medir `report_utilization`/timing real de Config A específicamente (Tx+H+V) — las corridas hasta
   ahora midieron Config B genérica (`N_CH=3` no distingue cuál).
5. Montar el runner de CI `[self-hosted, vivado]` y poner `HAS_VIVADO_RUNNER=true` — sigue
   pendiente desde Z0, el job `gateware` de `.github/workflows/ci.yml` ya está escrito. Vivado/xsim
   están en PATH en esta máquina (`/home/orlando/tools/Xilinx/Vivado/2022.2`), confirmado corriendo
   el flujo real (síntesis + P&R + xsim), no solo el binario.

`sim/tb_sv/drx_l1_checker.sv` ya tiene tolerancia (`TOLERANCE_LSB`, D-12) y la matriz de 16 corrió
16/16 «PASS» contra xsim real, confirmado — ese punto ya está cerrado, no solo decidido. La misma
matriz se volvió a correr completa el 20-sep-2026 tras añadir el puerto `overflow` a
`drx_ddc_top.sv`/`drx_ddc_quad_top.sv` (mapa de registros v2): **16/16 PASS** de nuevo.
`tb_l1_ddc_range_tri.sv` (fine/coarse, 3 canales cada uno) también se reconfirmó el mismo día tras
el puerto `clear` de `drx_range_gate`: **6/6 PASS**, TLAST bit a bit incluido.

Y no toques `R₁`/`R₂` ni `fs` en `config/params.toml` hasta que haya ADR: P-08 sigue abierto (P-01
ya cerró — exactitud requerida). Cuando lo haya, el cambio es de dos líneas más
`python3 tools/gen_params.py`.

P-08 ya no espera ningún dato externo: el rate mínimo del ADS42JB69 es de 60 MSPS en modo 10x, así
que los 143,9 MHz propuestos están en spec. Lo que falta es escribir el ADR que sustituya a D-04.

## Lo que está bloqueado, y por quién

| Bloqueante | Bloquea | Dueño |
|---|---|---|
| P-14 — varianza de los estimadores de momento (Doviak & Zrnic cap. 6) bajo el residuo aceptado por D-12 | No bloquea Z1 hoy, pero sí la confianza en D-12 a largo plazo | Especialistas de dominio |
| P-05 — `RDA_Backend_Py` sin localizar | Cerrar del todo P-01 con evidencia empírica de ORPG real (P-01 ya cerró por decisión, esto es la verificación que faltó) | vladimir |
| P-02 — capa física de los encoders SSI | La especificación de la portadora ZU9. Si es RS-422 y la portadora no lleva transceptores, falta hardware | Compra + especialistas |
| P-03 — plataforma de spike para JESD204B | El riesgo número uno del proyecto, que la ZedBoard no mitiga en absoluto | Dirección técnica |

El brief de `research/` para P-01/P-05 sigue listo para lanzarse en cuanto aparezca
`RDA_Backend_Py`; sin esa fuente el agente solo puede leer especificación, y ya hay precedente
documentado en `lamula-rcp/spike-fase0/RESULTADO-rda-orpg.md` de que eso no basta.

## Comandos

```sh
# sitio de documentación
uvx --with 'mkdocs-material==9.*' mkdocs serve
uvx --with 'mkdocs-material==9.*' mkdocs build --strict   # tiene que pasar limpio antes de commitear

# substrato
make venv          # crea .venv con requirements-dev.txt (pinado)
make check         # todos los gates del CI que corren sin Vivado
make gen           # regenera parámetros, coeficientes y contrato
make sim           # solo la suite L0 sobre Verilator

# gateware: ejecutado a mano, máquina de desarrollo con Vivado 2022.2; el
# runner de CI con Vivado todavía no existe (A7). `-step impl` (P&R real, sin
# bitstream: sin AXI-Lite/DMA las salidas de range-gate no tienen destino
# físico) cierra a 62,5 MHz desde el 19-sep-2026 (WNS = +2,770 ns)
python3 tools/gen_vector_source_init.py   # antes de sintetizar: $readmemh de vector_source lo necesita
vivado -mode batch -source tcl/build.tcl -tclargs -platform zedboard -step impl
vivado -mode batch -source tcl/build.tcl -tclargs -platform zedboard -step bitstream
vivado -mode batch -source tcl/sim_l1.tcl -tclargs -platform zedboard -case tono_if__fine
tools/make_boot.sh zedboard
```

## Advertencia que hay que repetir

Esta plataforma **no valida** JESD204B, el árbol de clocking y SYSREF, la sincronización
multi-dispositivo, los 250 MSPS, el frontal analógico real, la interfaz del DAC AD9129 ni la capa
física RS-422. El riesgo número uno del proyecto es hardware-bound y no se reduce con trabajo de
software. **No escribas «validado» donde corresponde «validado en ZedBoard».**
