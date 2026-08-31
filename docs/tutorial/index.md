# Tutorial: entender el substrato del DRx

Estas páginas no son una referencia: son un **camino de aprendizaje**. Van en orden, cada una
explica por qué existe lo que explica antes de decir cómo funciona, y todas terminan con resultados
reales — números y salidas de consola que produce el repositorio hoy, no ejemplos inventados.

Si solo quieres el inventario de lo que hay construido y su estado, ve a
[Substrato Z0](../implementacion/substrato.md). Si quieres **entenderlo**, sigue aquí.

## El orden

| | Página | Qué aprendes |
|---|---|---|
| 1 | [El paquete de parámetros](01-parametros.md) | Por qué una sola constante gobierna el proyecto entero, y cómo se impide que aparezca una segunda |
| 2 | [Aritmética de punto fijo](02-punto-fijo.md) | Complemento a dos, redondeo, saturación, y por qué un LSB importa |
| 3 | [La cadena DDC](03-ddc.md) | NCO, mezclador, CIC, FIR y enrejado en rango, con las gráficas que salen del modelo |
| 4 | [Simulación](04-simulacion.md) | Qué son Verilator, cocotb y pytest, cómo encajan y dónde se rompió el plan |
| 5 | [El contrato DRx↔DSP](05-contrato.md) | Un esquema, tres lenguajes, y cómo se comprueba que no divergen |
| 6 | [Gateware](06-gateware.md) | El flujo Vivado sin GUI y qué hace falta para un `BOOT.BIN` reproducible |
| 7 | [Resultados](07-resultados.md) | Todo lo que está verde hoy, con su salida real |

## Antes de empezar: monta el entorno

```sh
make venv     # crea .venv e instala requirements-dev.txt, con versiones pinadas
make check    # corre todos los gates que no necesitan Vivado
```

Hacen falta `verilator`, `gcc` y `make` en el PATH. En Debian y Ubuntu:

```sh
sudo apt-get install -y verilator gcc make
```

## Las herramientas externas, y por qué cada una

Este proyecto usa piezas de terceros. Cada enlace va a la documentación oficial; si algo de las
páginas siguientes te suena a magia, empieza por aquí.

### Simulación y verificación

| Herramienta | Qué es | Por qué la usamos |
|---|---|---|
| [Verilator](https://verilator.org/guide/latest/) | Compilador de Verilog/SystemVerilog a C++ que produce un simulador nativo | Rápido y libre, sin licencia en el runner de CI. Es el nivel L0 de [D-05](../alcance/decisiones.md#d-05) |
| [cocotb](https://docs.cocotb.org/en/stable/) | Framework para escribir testbenches de HDL **en Python** en vez de en SystemVerilog | Los bancos comparten lenguaje con el modelo dorado, así que el oráculo se importa directamente en el testbench |
| [pytest](https://docs.pytest.org/en/stable/) | Runner de tests de Python | Un único comando corre el modelo, la simulación, el contrato y el firmware |
| [Verilator: catálogo de avisos](https://verilator.org/guide/latest/warnings.html) | La lista de qué significa cada `UNUSEDSIGNAL`, `WIDTH`… | Es lo que hay que leer cuando el lint falla en CI |

### Numérico

| Herramienta | Qué es | Por qué |
|---|---|---|
| [NumPy](https://numpy.org/doc/stable/) | Álgebra y arrays en Python | El modelo dorado trabaja sobre arrays de enteros de 64 bits |
| [SciPy · señal](https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.firwin2.html) | Diseño de filtros, entre otras cosas | `firwin2` diseña el FIR compensador por muestreo en frecuencia |

### Formatos y configuración

| Herramienta | Qué es | Por qué |
|---|---|---|
| [TOML](https://toml.io/en/) | Formato de configuración legible y sin ambigüedades | `config/params.toml` es la fuente única de verdad |
| [`tomllib`](https://docs.python.org/3/library/tomllib.html) | Lector de TOML en la biblioteca estándar de Python desde 3.11 | Leer los parámetros no añade ninguna dependencia |
| [Ruff](https://docs.astral.sh/ruff/) | Linter y formateador de Python | Gate de estilo en CI |
| [uv](https://docs.astral.sh/uv/) | Gestor de entornos y paquetes de Python | Instala el entorno pinado en segundos, igual en local que en CI |

### FPGA y hardware

| Documento | Qué es | Dónde aparece |
|---|---|---|
| [ZedBoard](https://digilent.com/reference/programmable-logic/zedboard/start) | La placa de desarrollo: Zynq-7000 XC7Z020 | Plataforma actual; ver [Frontera y cobertura](../plataforma/zedboard.md) |
| [UG585 · Zynq-7000 TRM](https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM) | Manual de referencia del SoC | El PS que ejecutará el firmware |
| [UG892 · Flujos de diseño de Vivado](https://docs.amd.com/r/en-US/ug892-vivado-design-flows-overview) | Modo proyecto frente a modo no-proyecto | El flujo de `tcl/` es no-proyecto, por [D-07](../alcance/decisiones.md#d-07) |
| [UG835 · Comandos Tcl de Vivado](https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands) | Referencia de `synth_design`, `route_design`… | Cada comando de `tcl/build.tcl` |
| [UG1283 · Bootgen](https://docs.amd.com/r/en-US/ug1283-bootgen-user-guide) | Empaquetado del `BOOT.BIN` | `tcl/boot/boot.bif` y `tools/make_boot.sh` |
| [PG079 · CIC Compiler](https://docs.amd.com/r/en-US/pg079-cic-compiler) | La IP de filtro CIC | Lo que el modelo dorado tiene que reproducir bit a bit |
| [PG149 · FIR Compiler](https://docs.amd.com/r/en-US/pg149-fir-compiler) | La IP de filtro FIR | Carga los coeficientes de `config/coeffs/` |
| [PG141 · DDS Compiler](https://docs.amd.com/r/en-US/pg141-dds-compiler) | El NCO | Modo de truncamiento de fase |
| [PG021 · AXI DMA](https://docs.amd.com/r/en-US/pg021-axi-dma) | Transferencia a la DDR del PS | Z4 |
| [AMBA AXI4-Stream](https://developer.arm.com/documentation/ihi0051/latest) | El protocolo de streaming | La [SSA](../plataforma/fuente-de-muestras.md) es AXI4-Stream |
| [IEEE 1800 · SystemVerilog](https://standards.ieee.org/ieee/1800/7743/) | El estándar del lenguaje | El RTL custom, por [D-05](../alcance/decisiones.md#d-05) |

### Teoría

| Referencia | Para qué |
|---|---|
| [Filtro CIC (resumen)](https://en.wikipedia.org/wiki/Cascaded_integrator%E2%80%93comb_filter) | Entender integradores y peines antes de leer el modelo |
| Hogenauer, *An economical class of digital filters for decimation and interpolation*, IEEE TASSP, 1981 · [DOI](https://doi.org/10.1109/TASSP.1981.1163535) | El artículo original: de aquí sale la fórmula del ancho de registro |
| [Oscilador controlado numéricamente](https://en.wikipedia.org/wiki/Numerically-controlled_oscillator) | Qué es una palabra de fase y por qué truncarla produce espurios |
| [Complemento a dos](https://en.wikipedia.org/wiki/Two%27s_complement) | La representación de todos los enteros con signo del proyecto |

### Infraestructura

| Herramienta | Dónde |
|---|---|
| [GitHub Actions](https://docs.github.com/en/actions) | `.github/workflows/ci.yml` y `docs.yml` |
| [MkDocs Material](https://squidfunk.github.io/mkdocs-material/) | Este sitio |
| [Cloudflare Pages](https://developers.cloudflare.com/pages/) | Donde se publica |
| [Rust](https://www.rust-lang.org/) | El lado DSP del contrato; ver [contrato](05-contrato.md) |

!!! note "Cómo se mantiene esto honesto"
    Todas las gráficas de este tutorial salen de `tools/gen_docs_figures.py`, que las dibuja
    ejecutando el propio modelo dorado. Todos los números y las salidas de consola están copiados de
    ejecuciones reales. Si el modelo cambia y alguien no regenera, la documentación y el código
    discrepan de forma visible en vez de en silencio.
