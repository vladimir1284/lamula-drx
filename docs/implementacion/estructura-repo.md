# Estructura del repositorio

Se establece en [Z0](fases.md#z0) y no se improvisa después. El principio es que **el CI pueda
construir todo sin abrir la GUI de Vivado**, y que un agente pueda razonar sobre el árbol sin
conocimiento tácito.

```
rtl/         RTL custom en SystemVerilog: motor de timing, lectores SSI, gating,
             framing, vector_source, wrappers de la SSA
ip/          Ficheros .xci versionados de la IP de Xilinx (DDS/CIC/FIR Compiler,
             AXI DMA); la regeneración está guionizada, no manual
tcl/         Flujo Vivado no-project: síntesis, implementación, bitstream,
             report_utilization y report_timing
fw/          Firmware del PS: FreeRTOS, ensamblado de rayos, transporte DRx↔DSP,
             plano de control, status/BITE
sim/         Testbenches cocotb y el runner de doble backend (Verilator + xsim)
model/       Modelo dorado en NumPy y el generador de vectores
contract/    Esquema DRx↔DSP versionado y su codegen para C y para el lenguaje del DSP
docs/        Este sitio
```

## Reglas de la estructura

- **`ip/` guarda XCI, no salidas generadas.** Los productos de `generate_target` son artefactos de
  build y no se versionan. La regeneración vive en `tcl/`.
- **`model/` es la fuente de verdad numérica.** Si el RTL y el modelo discrepan, hay un bug en uno de
  los dos y hay que encontrarlo; no se ajusta el modelo para que pase el test.
- **`contract/` genera código para los dos lados.** El esquema es una sola fuente de verdad, y las
  dos implementaciones se derivan de ella — no se escriben a mano en paralelo.
- **El paquete de parámetros con `FS_HZ` es único** y lo consumen `rtl/`, `fw/`, `sim/` y `model/`.
  Ninguno de los cuatro define su propia copia.

## Gates de CI

Todos corren en cada push. Ninguno es opcional.

| Gate | Qué comprueba |
|---|---|
| Lint HDL | Estilo y errores estáticos en `rtl/` |
| Constante de reloj hardcodeada | **Falla la build** si aparece una frecuencia literal fuera del paquete de parámetros |
| Regresión de simulación | Suites L0 (Verilator) y L1 (xsim) — ver [Plan de testing](../pruebas/plan-testing.md) |
| Build de firmware | `fw/` compila contra el BSP |
| Tests de contrato | El codegen de `contract/` es consistente en ambos lados |
| Ensamblado de `BOOT.BIN` | Reproducible byte a byte |
| Reportes de temporización | Se ejecutan también con el `FS_HZ` real de la ZU9, aunque no haya placa ([D2](../portabilidad/registro-delta.md)) |

El último merece énfasis: correr el cierre de temporización contra `FS_HZ` = 250 MHz desde el
principio es la única forma de que la deuda de la entrada D2 del registro delta no se descubra el
día que llegue el hardware.
