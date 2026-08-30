# CLAUDE.md — LAMULA DRx

Punto de entrada para un agente o una persona que se incorpora en frío. Esta página dice **dónde
está el proyecto ahora**; las reglas de ingeniería están en `AGENTS.md` y no se repiten aquí.

## Qué es

Receptor digital FPGA del sistema LAMULA. Digitaliza el IF del radar, hace conversión a banda base y
diezmado en la lógica programable, ensambla los rayos con sus metadatos bajo FreeRTOS y los entrega
al LAMULA DSP por 1GbE contra el contrato DRx↔DSP. Su única interfaz externa es DRx↔DSP: no habla
con el RCP ni con ORPG.

- **Plataforma objetivo:** Zynq UltraScale+ ZU9 + 2× VadaTech FMC213. **Aún no comprada.**
- **Plataforma de desarrollo actual:** Digilent ZedBoard, XC7Z020-CLG484-1.

## Estado, a 30 de agosto de 2026

**Fase Z0 — substrato. No empezada.** El repositorio contiene documentación y nada más: no hay RTL,
ni firmware, ni flujo Tcl, ni testbenches, ni modelo dorado. El primer trabajo de código es
literalmente el primer punto de `docs/implementacion/fases.md`.

Lo que sí está hecho y verificado:

- El sitio de documentación se construye y se despliega solo a
  <https://lamula-drx-docs.pages.dev> en cada push a `main` que toque `docs/`. Detalles,
  credenciales y deuda conocida del CI en `docs/implementacion/infraestructura.md`.
- El plan de 28 semanas (Z0–Z5), las diez decisiones congeladas, el plan de verificación y el
  registro delta de portabilidad están escritos y publicados.
- Existe un brief de investigación ejecutable para el hallazgo P-01 en
  `research/p-01-orpg-gate-spacing.md`.

## Orden de lectura

1. `docs/alcance/contexto.md` — qué es y qué no es, y la relación con los proyectos DSP y RCP.
2. `docs/alcance/decisiones.md` — las diez decisiones congeladas (D-01…D-10). Ninguna se revierte
   sin discutirlo.
3. `docs/alcance/pendientes.md` — hallazgos abiertos (P-01…P-06), supuestos de entorno a verificar y
   riesgos de la estrategia ZedBoard.
4. `docs/implementacion/fases.md` — el plan de trabajo.
5. `AGENTS.md` — las reglas que no se negocian, antes de escribir la primera línea de código.

`docs/referencia/` conserva íntegros los dos documentos de los que deriva todo lo anterior: el plan
de ZedBoard y el project plan original de 34 semanas para la ZU9.

## Lo primero que hay que hacer

**Fase Z0**, en este orden: estructura de repositorio, flujo Vivado no-project en Tcl, paquete único
de parámetros con `FS_HZ`, runner cocotb de doble backend, modelo dorado en NumPy, y el congelado del
esquema DRx↔DSP v0.1. Nada de funcionalidad. El hito es CI verde sobre un diseño vacío que produce un
`BOOT.BIN` reproducible byte a byte.

**No empieces por el DDC.** El substrato primero no es burocracia: sin flujo guionizado y sin
regresión el modelo de entrega acelerado por agentes no funciona, y reconstruirlo al final cuesta un
mes.

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
```

Todavía no hay comandos de build de gateware ni de firmware: los crea Z0.

## Advertencia que hay que repetir

Esta plataforma **no valida** JESD204B, el árbol de clocking y SYSREF, la sincronización
multi-dispositivo, los 250 MSPS, el frontal analógico real, la interfaz del DAC AD9129 ni la capa
física RS-422. El riesgo número uno del proyecto es hardware-bound y no se reduce con trabajo de
software. **No escribas «validado» donde corresponde «validado en ZedBoard».**
