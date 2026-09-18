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

## Estado, a 5 de septiembre de 2026

**Fase Z0 — substrato. Casi cerrada.** Ya hay código, y corre: `make check` deja 69 tests en verde
sobre Verilator, gcc y NumPy. Lo construido está explicado en el tutorial de `docs/tutorial/` e
inventariado en `docs/implementacion/substrato.md`; el resumen es:

- Paquete único de parámetros en `config/params.toml`, con generación a SystemVerilog, C y Tcl, gate
  de regeneración y gate de constante de reloj hardcodeada — los dos fallan la build.
- Modelo dorado en NumPy: NCO, mezclador, CIC de Hogenauer, FIR de coeficientes congelados, enrejado
  en rango y generador de vectores con degradaciones. Con huella SHA-256 del oráculo en los tests.
- Runner cocotb con L0 sobre Verilator en verde. **L1 no pasa por cocotb** —no tiene backend para
  xsim, hallazgo P-09, ya decidido—: es SystemVerilog nativo con el oráculo cruzando por fichero.
  El arnés (lector de vectores y comparador bit a bit) está verificado sobre Verilator 5.006 y sobre
  xsim; `tcl/sim_l1.tcl` ya corrió de punta a punta el 5-sep-2026 (ver más abajo).
- Contrato DRx↔DSP v0.1 congelado, con codegen para C, Rust y Python y test de contrato que compara
  bytes entre C y Python.
- RTL: diseño vacío a propósito (latido derivado de `FS_HZ`) más el paquete del interfaz SSA.
- Firmware: auto-comprobación de parámetros que compila para las dos plataformas.

**El 5 de septiembre de 2026, primera máquina con Vivado (desarrollo, no CI):** se instaló Vivado ML
Standard 2022.2 (WebPACK) y se ejecutó, por primera vez, todo el flujo que hasta entonces estaba
«escrito y revisado pero nunca ejecutado»:

- `tcl/build.tcl -platform zedboard -step bitstream`: síntesis + place & route + bitstream,
  **WNS = 5,850 ns** (timing cerrado, con margen).
- `tcl/sim_l1.tcl`: encontró y corrigió tres bugs propios de la infraestructura de simulación (no
  del diseño) — dos en el propio `tcl/sim_l1.tcl`, uno de compatibilidad de xsim con
  `$value$plusargs`. Detalle completo en [P-09](docs/alcance/pendientes.md#p-09). Con los tres
  fixes, llega exactamente al abort **diseñado** para esta fase: falta `drx_ddc_top` (Z1).
- `tools/make_boot.sh zedboard`: se comporta como está documentado, falla limpio por los
  entregables de Z4 que aún no existen (`fsbl.elf`, `drx_app.elf`).

**Lo que sigue sin estar hecho:** todo lo anterior fue manual, en una máquina de desarrollo — **no
hay todavía un runner de CI con Vivado**, así que el hito ZM0 tal como lo define
`docs/implementacion/fases.md` (`git push` produce un `BOOT.BIN` reproducible byte a byte, sin
intervención humana) sigue sin cumplirse. El job `gateware` de `.github/workflows/ci.yml` ya existe
y está listo, condicionado a `vars.HAS_VIVADO_RUNNER` y a un runner `[self-hosted, vivado]` que
todavía no se ha montado. Ver los supuestos A7 y A8 en `docs/alcance/pendientes.md`.

Lo que sí está hecho y verificado:

- El sitio de documentación se construye y se despliega solo a
  <https://lamula-drx-docs.pages.dev> en cada push a `main` que toque `docs/`. Detalles,
  credenciales y deuda conocida del CI en `docs/implementacion/infraestructura.md`.
- El plan de 28 semanas (Z0–Z5), las once decisiones congeladas, el plan de verificación y el
  registro delta de portabilidad están escritos y publicados.
- Existe un brief de investigación ejecutable para el hallazgo P-01 en
  `research/p-01-orpg-gate-spacing.md`.

## Orden de lectura

1. `docs/alcance/contexto.md` — qué es y qué no es, y la relación con los proyectos DSP y RCP.
2. `docs/alcance/decisiones.md` — las once decisiones congeladas (D-01…D-11). Ninguna se revierte
   sin discutirlo.
3. `docs/alcance/pendientes.md` — hallazgos abiertos (P-01…P-06), supuestos de entorno a verificar y
   riesgos de la estrategia ZedBoard.
4. `docs/implementacion/fases.md` — el plan de trabajo.
5. `AGENTS.md` — las reglas que no se negocian, antes de escribir la primera línea de código.

`docs/referencia/` conserva íntegros los dos documentos de los que deriva todo lo anterior: el plan
de ZedBoard y el project plan original de 34 semanas para la ZU9.

## Lo primero que hay que hacer

El flujo ya se demostró a mano (ver arriba). Lo que falta para cerrar Z0 del todo:

1. **Montar el runner de CI `[self-hosted, vivado]`** y poner `HAS_VIVADO_RUNNER=true` — el job
   `gateware` ya está escrito en `.github/workflows/ci.yml`, solo falta la máquina. Sin esto, ZM0
   sigue siendo «se demostró en una máquina, no lo garantiza el CI», que no es lo mismo.
2. Con eso resuelto, **Z1 (`drx_ddc_top`) queda desbloqueado**: el substrato (flujo guionizado +
   regresión de L0 y L1) ya existe y ya corrió de verdad, así que empezar por el DDC ahora ya no es
   saltarse el orden — antes de la sesión del 5-sep-2026 sí lo era, por eso la regla existía.

El argumento de fondo sigue siendo el mismo: sin flujo guionizado y sin regresión el modelo de
entrega acelerado por agentes no funciona, y reconstruirlo al final cuesta un mes. Ya no falta
construirlo — falta automatizarlo en CI.

Y no toques `R₁`/`R₂` ni `fs` en `config/params.toml` hasta que haya ADR: P-01 y P-08 siguen
abiertos. Cuando lo haya, el cambio es de dos líneas más `python3 tools/gen_params.py`.

P-08 ya no espera ningún dato externo: el rate mínimo del ADS42JB69 es de 60 MSPS en modo 10x, así
que los 143,9 MHz propuestos están en spec. Lo que falta es escribir el ADR que sustituya a D-04.

## Lo que está bloqueado, y por quién

| Bloqueante | Bloquea | Dueño |
|---|---|---|
| [P-01](docs/alcance/pendientes.md) — ¿tolera ORPG el error de celda del 0,24 %? | La arquitectura de la cadena CIC/FIR de Z1. Si la respuesta es «exactitud requerida», D-04 se cae y cambia el presupuesto de DSP48 | Especialistas de dominio |
| P-05 — `RDA_Backend_Py` sin localizar | La parte empírica de P-01. Es la única fuente que demuestra qué acepta un ORPG real | vladimir |
| P-02 — capa física de los encoders SSI | La especificación de la portadora ZU9. Si es RS-422 y la portadora no lleva transceptores, falta hardware | Compra + especialistas |
| P-03 — plataforma de spike para JESD204B | El riesgo número uno del proyecto, que la ZedBoard no mitiga en absoluto | Dirección técnica |

P-01 y P-05 son el par urgente: Z1 va a escribir la cadena de diezmado y necesita saber si R₁ = 208 /
R₂ = 416 sobrevive. El brief de `research/` está listo para lanzarse en cuanto aparezca
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

# gateware: ejecutado a mano el 5-sep-2026 en una máquina de desarrollo con Vivado
# 2022.2; el runner de CI con Vivado todavía no existe (A7)
vivado -mode batch -source tcl/build.tcl -tclargs -platform zedboard -step bitstream
vivado -mode batch -source tcl/sim_l1.tcl -tclargs -platform zedboard -case tono_if__fine
tools/make_boot.sh zedboard
```

## Advertencia que hay que repetir

Esta plataforma **no valida** JESD204B, el árbol de clocking y SYSREF, la sincronización
multi-dispositivo, los 250 MSPS, el frontal analógico real, la interfaz del DAC AD9129 ni la capa
física RS-422. El riesgo número uno del proyecto es hardware-bound y no se reduce con trabajo de
software. **No escribas «validado» donde corresponde «validado en ZedBoard».**
