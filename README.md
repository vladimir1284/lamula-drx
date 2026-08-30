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

Fase Z0 — substrato, **no empezada**. El repositorio contiene documentación y nada más: no hay RTL,
firmware, flujo Tcl, testbenches ni modelo dorado. Ver `docs/implementacion/fases.md`.
