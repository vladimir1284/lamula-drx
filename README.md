# LAMULA DRx

Receptor digital FPGA del sistema LAMULA. Digitaliza el IF del radar, hace conversión a banda base y
diezmado en la lógica programable, ensambla los rayos con sus metadatos bajo FreeRTOS y los entrega
al LAMULA DSP por 1GbE contra el contrato DRx↔DSP.

- **Plataforma objetivo:** Zynq UltraScale+ ZU9 + 2× VadaTech FMC213 (aún no comprada).
- **Plataforma de desarrollo actual:** Digilent ZedBoard, XC7Z020-CLG484-1.

## Documentación

El plan de trabajo, las decisiones congeladas, el plan de verificación y el registro de deuda de
portabilidad viven en `docs/` y se publican en <https://lamula-drx-docs.pages.dev>.

Si te incorporas en frío, empieza por `CLAUDE.md`: dice dónde está el proyecto, en qué orden leer y
qué está bloqueado. Si vas a escribir código, lee `AGENTS.md` primero. El estado de la
infraestructura (repo, Pages, secrets, CI) está en `docs/implementacion/infraestructura.md`.

Para construir el sitio localmente:

```sh
uvx --with mkdocs-material==9.* mkdocs serve
```

## Estado

Fase Z0 — substrato, **en curso**. Existen el paquete único de parámetros, el modelo dorado en
NumPy, el runner de simulación L0 sobre Verilator, el contrato DRx↔DSP v0.1 con codegen para C, Rust
y Python, el diseño vacío de RTL y los gates de CI que no necesitan Vivado. El flujo Tcl está escrito
pero **nunca se ha ejecutado**, y el `BOOT.BIN` reproducible —que es el hito ZM0— sigue pendiente por
la misma razón.

Qué hay exactamente y cómo se corre: `docs/implementacion/substrato.md`.

```sh
make venv     # entorno de Python
make check    # todos los gates del CI que corren sin Vivado
```
