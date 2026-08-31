# Substrato Z0: qué existe y cómo se corre

Esta página describe lo que hay **construido y verde** en el repositorio, y cómo ejecutarlo. La
planificación está en [Fases Z0–Z5](fases.md) y la disposición de directorios en
[Estructura del repositorio](estructura-repo.md); aquí solo va el estado ejecutable.

## Arranque

```sh
make venv     # crea .venv e instala requirements-dev.txt (pinado)
make check    # todos los gates que corre el CI en el job de substrato
```

`make check` necesita `verilator` y `gcc` en el PATH. Verilator viene de los repositorios de la
distribución (`apt install verilator`); no hace falta Vivado para nada de lo anterior.

## La fuente única de verdad

`config/params.toml` es el paquete de parámetros de [D-02](../alcance/decisiones.md#d-02). De él
salen, por generación, las vistas de los cuatro consumidores:

| Consumidor | Cómo lo lee |
|---|---|
| `rtl/` | `rtl/generated/drx_params_pkg.sv`, generado |
| `fw/` | `fw/include/drx_params.h`, generado |
| `tcl/` | `tcl/generated/drx_params.tcl`, generado |
| `model/`, `sim/` | `drx_model.params`, que lee el TOML directamente |

```sh
python3 tools/gen_params.py            # regenera
python3 tools/gen_params.py --check    # gate de CI: falla si hay desfase
```

Cambiar `fs`, `R₁` o `R₂` —que es lo que va a pasar cuando se cierren
[P-01](../alcance/pendientes.md#p-01) y [P-08](../alcance/pendientes.md#p-08)— es editar dos líneas
del TOML y regenerar. Ese es el motivo entero de que este fichero exista antes que el RTL.

!!! warning "El gate de la constante hardcodeada es real, no decorativo"
    `tools/check_hardcoded_clock.py` falla la build si aparece un literal decimal ≥ 10⁶ en `rtl/`,
    `fw/`, `sim/`, `model/`, `tcl/` o `contract/`. Ignora comentarios y ficheros generados, y admite
    el marcador `clock-const-ok: <razón>` para las excepciones legítimas —que hoy son dos: la
    velocidad de la luz y una conversión de unidades—. Cada excepción lleva su razón escrita.

## Modelo dorado

`model/drx_model/` es el oráculo de [D-03](../alcance/decisiones.md#d-03): NCO con truncamiento de
fase, mezclador complejo, CIC de Hogenauer con desbordamiento intencionado, FIR de coeficientes
cuantizados, enrejado en rango y generador de vectores con degradaciones inyectables. Todo en
aritmética entera; la coma flotante solo aparece antes de cuantizar y en el análisis.

Los coeficientes del FIR están **congelados** en `config/coeffs/` y son los que se cargarán en el
FIR Compiler. No se rediseñan en cada ejecución: si lo hicieran, una actualización de scipy movería
el oráculo por debajo.

```sh
python3 tools/gen_coeffs.py --check
```

La suite del modelo incluye una **huella del oráculo**: un vector conocido produce una salida cuyo
SHA-256 está fijado en el test. Cualquier cambio de comportamiento del modelo la mueve, y eso
obliga a justificarlo en el commit en lugar de que pase inadvertido.

!!! danger "Lo que el modelo todavía no puede prometer"
    La cadena está modelada contra la configuración *pretendida* de la IP de Xilinx, no contra la IP
    real: en Z0 no hay Vivado ni IP generada. La correspondencia bit a bit modelo↔IP se establece en
    Z1 y es ahí donde pueden aparecer ajustes de redondeo. Hoy el modelo es autoconsistente,
    determinista y reproducible, que es lo que Z0 promete — no más.

## Simulación

Runner único de doble backend en `sim/runner.py`, tal como pide
[D-05](../alcance/decisiones.md#d-05).

- **L0 — Verilator:** funciona. `make sim`.
- **L1 — xsim:** **no funciona, y no por falta de trabajo:** cocotb no tiene backend para xsim. Ver
  [P-09](../alcance/pendientes.md#p-09). El backend está declarado y falla con un mensaje explícito
  que nombra el hallazgo, en vez de estar ausente en silencio; hay un test que comprueba justamente
  eso.

## Contrato DRx↔DSP v0.1

Congelado unilateralmente según [D-08](../alcance/decisiones.md#d-08). Fuente única en
`contract/schema/drx_dsp_v0_1.toml`; de ahí salen las tres implementaciones: C (lado DRx), Rust
(lado DSP, que es un servicio Rust) y Python (referencia de los tests).

El test de contrato compila un programa en C con la cabecera generada, vuelca los bytes de cada
mensaje y los compara con los que produce la implementación de Python. Si los layouts divergen, el
test falla. **La implementación de Rust no se compila aquí** —no hay toolchain de Rust en este
repositorio— y de ella solo se comprueba que las constantes de tamaño coinciden; el test de layout
del lado Rust le toca al proyecto DSP.

Formato: little-endian, empaquetado, sin relleno implícito, **solo enteros en el cable**. Los
ángulos viajan como cuenta cruda del encoder y la corrección AFC como palabra de fase absoluta del
NCO: en Hz haría falta que el DSP conociera el `FS_HZ` del DRx, y eso rompería D-02.

## Gateware: escrito, no ejecutado

`tcl/build.tcl` implementa el flujo no-project de [D-07](../alcance/decisiones.md#d-07) —síntesis,
implementación con el WNS como gate duro, informes y bitstream con `-bin_file`—, `tcl/ip.tcl`
regenera la IP desde los XCI versionados y `tools/make_boot.sh` empaqueta el `BOOT.BIN` y comprueba
la reproducibilidad empaquetando dos veces y comparando.

**Nada de esto se ha ejecutado nunca:** no hay Vivado en el entorno de desarrollo ni runner de CI
con licencia. El job `gateware` del CI existe y está condicionado a que aparezca un runner
etiquetado. Hasta que corra, **el hito ZM0 no está cerrado**: CI verde sobre el substrato no es lo
mismo que un `BOOT.BIN` reproducible byte a byte.

## Estado de los puntos de Z0

| Punto de Z0 | Estado |
|---|---|
| Estructura de repositorio | Hecho |
| Paquete único de parámetros con `FS_HZ` | Hecho, con gate de regeneración y de constante hardcodeada |
| Flujo Vivado no-project en Tcl | Escrito, **no ejecutado** (falta Vivado) |
| Runner cocotb de doble backend | L0 hecho; L1 bloqueado por [P-09](../alcance/pendientes.md#p-09) |
| Modelo dorado NumPy + generador de vectores | Hecho |
| Congelado del esquema DRx↔DSP v0.1 | Hecho, con codegen para C, Rust y Python |
| Gates de CI | Hechos salvo los que necesitan Vivado |
| `BOOT.BIN` reproducible byte a byte | **Pendiente**: depende de Vivado |
