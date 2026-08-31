# 4 · Simulación

## Las tres piezas

Simular RTL necesita tres cosas distintas, y conviene no confundirlas:

| Pieza | Qué hace | En este repo |
|---|---|---|
| **Simulador** | Elabora el HDL y avanza el tiempo | [Verilator](https://verilator.org/guide/latest/) |
| **Framework de testbench** | Escribe el estímulo y comprueba la respuesta | [cocotb](https://docs.cocotb.org/en/stable/) |
| **Runner** | Construye, lanza y recoge resultados | [pytest](https://docs.pytest.org/en/stable/) sobre `sim/runner.py` |

### Verilator

No es un simulador de eventos clásico: **traduce SystemVerilog a C++**, lo compila y ejecuta el
binario resultante. Por eso es rápido y por eso es gratis. Su límite es que solo entiende
Verilog/SystemVerilog sintetizable, no VHDL ni IP cifrada.

Ese límite es exactamente la razón de que el plan tenga dos niveles: L0 para el RTL custom, L1 para la
IP de Xilinx. Ver [D-05](../alcance/decisiones.md#d-05).

### cocotb

Escribe los bancos **en Python**, no en SystemVerilog. Se engancha al simulador por VPI y las
corrutinas de Python dirigen el reloj y las señales:

```python title="sim/tb/tb_drx_heartbeat.py"
@cocotb.test()
async def test_periodo_del_latido(dut):
    """`level` conmuta exactamente cada DIV ciclos."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)
    ...
```

La ventaja concreta para este proyecto: el modelo dorado **también** es Python, así que el testbench
puede importarlo directamente y comparar bit a bit sin ficheros intermedios ni conversiones. Ese es el
argumento entero a favor de cocotb frente a escribir los bancos en SystemVerilog.

## El detalle que hace que la disciplina se sostenga

Mira de dónde sale el periodo de reloj del testbench:

```python title="sim/tb/tb_drx_heartbeat.py"
PARAMS = load("zedboard")
#: Periodo de reloj en picosegundos, derivado de FS_HZ. Nada de literales (D-02).
CLK_PERIOD_PS = round(1e12 / PARAMS.fs_hz)  # clock-const-ok: conversión de unidades s->ps
```

No hay un `10` escrito en ninguna parte. Si mañana `fs` pasa a 143,9 MHz por
[P-08](../alcance/pendientes.md#p-08), el banco se mueve solo. Un `Clock(dut.clk, 10, units="ns")`
habría sido más corto de escribir y habría sido, precisamente, la deuda que
[D-02](../alcance/decisiones.md#d-02) existe para impedir.

## Una sola lista de fuentes

Verilator y Vivado tienen que compilar exactamente lo mismo. Si cada uno lleva su lista, un día
divergen y un backend compila algo que el otro no ve:

```
# rtl/filelist.f
rtl/generated/drx_params_pkg.sv
rtl/ssa/drx_ssa_pkg.sv
rtl/drx_heartbeat.sv
rtl/drx_top.sv
```

`sim/runner.py` la lee con Python; `tcl/build.tcl` la lee con un `proc` de Tcl. Una lista, dos
consumidores.

## Los waivers de lint llevan razón escrita

El lint corre con `-Wall`, y `-Wall` en Verilator es estricto de verdad: avisa de parámetros sin usar,
de señales sin leer, de anchos que no cuadran. Dos avisos son legítimos aquí y se silencian **con su
razón**:

```systemverilog title="sim/verilator_waivers.vlt"
`verilator_config

// drx_ssa_pkg define el formato del interfaz SSA (D-01). En Z0 no hay todavía
// ninguna implementación que lo consuma, así que sus anchos aparecen sin usar.
// El waiver desaparece solo en Z1, cuando `vector_source` los use.
lint_off -rule UNUSEDPARAM -file "*/drx_ssa_pkg.sv"

// drx_params_pkg es el paquete de parámetros: por definición contiene valores
// que un top concreto no usa (el latido no usa los factores del DDC). Exigir que
// todo top use todos los parámetros obligaría a trocear el paquete, que es
// justamente lo que D-02 prohíbe.
lint_off -rule UNUSEDPARAM -file "*/drx_params_pkg.sv"
```

Un waiver sin razón es deuda; con razón es una decisión. El segundo, además, es interesante: un
paquete de parámetros **siempre** tendrá valores que un top concreto no usa. La alternativa —trocear
el paquete para que cada top use el suyo— es exactamente lo que D-02 prohíbe.

El catálogo completo de avisos está en la
[documentación de Verilator](https://verilator.org/guide/latest/warnings.html); es lo que hay que
leer cuando el lint falla.

## El runner

```python title="sim/runner.py"
@dataclass
class SimJob:
    """Una elaboración más una ejecución, independiente del backend."""

    hdl_toplevel: str
    test_module: str
    parameters: dict[str, object] = field(default_factory=dict)
    backend: str = L0
    waves: bool = False
```

Un detalle no obvio y que costó encontrar: **cocotb pasa al simulador el `sys.path` del proceso
padre**, no las variables de entorno que le des. Si `sim/tb` no está en el path del pytest que lanza,
el simulador arranca y no encuentra el módulo del testbench. De ahí:

```toml title="pyproject.toml"
# `sim/tb` va en el path porque cocotb pasa el sys.path del proceso padre
# al simulador: es así como el backend encuentra los testbenches.
pythonpath = ["model", "sim", "sim/tb"]
```

Los parámetros del RTL se sobreescriben desde el runner, que es como el banco simula un divisor de 5
ciclos en vez de los 50 000 000 reales:

```python title="sim/tests/test_l0_heartbeat.py"
SimJob(
    hdl_toplevel="drx_heartbeat",
    test_module="tb_drx_heartbeat",
    parameters={"DIV": 5},
    backend=L0,
).run()
```

## Una ejecución real

```
INFO: Running command perl /usr/bin/verilator -cc --exe -Mdir build/sim/verilator/drx_heartbeat
  -DCOCOTB_SIM=1 --top-module drx_heartbeat --vpi --public-flat-rw --prefix Vtop --timing -Wall
  sim/verilator_waivers.vlt -GDIV=5
  rtl/generated/drx_params_pkg.sv rtl/ssa/drx_ssa_pkg.sv rtl/drx_heartbeat.sv rtl/drx_top.sv

     0.00ns INFO     cocotb    Running on Verilator version 5.006 2023-01-22
     0.00ns INFO     cocotb    Running tests with cocotb v1.9.2
     0.00ns INFO     cocotb.regression  Found test tb_drx_heartbeat.test_periodo_del_latido
     0.00ns INFO     cocotb.regression  Found test tb_drx_heartbeat.test_reset_asincrono
     0.00ns INFO     cocotb.regression  running test_periodo_del_latido (1/2)
   350.00ns INFO     cocotb.regression  test_periodo_del_latido passed
   350.00ns INFO     cocotb.regression  running test_reset_asincrono (2/2)
   460.00ns INFO     cocotb.regression  test_reset_asincrono passed
   460.00ns INFO     cocotb.regression
  ** tb_drx_heartbeat.test_periodo_del_latido   PASS         350.00           0.00      81042.87  **
  ** tb_drx_heartbeat.test_reset_asincrono      PASS         110.00           0.00      81732.09  **
```

Fíjate en el `-GDIV=5` de la línea de Verilator: es el parámetro sobreescrito. Y en los 350 ns de
tiempo simulado, que a 100 MHz son 35 ciclos — suficiente para siete conmutaciones del latido con
DIV=5.

Desde limpio, con la compilación de C++ incluida, tarda unos 17 segundos; en ejecuciones sucesivas es
casi instantáneo porque el `make` de Verilator es incremental.

## Qué prueba el banco de Z0

El diseño de Z0 es **vacío a propósito**: un divisor que hace parpadear un LED. Lo que el banco
demuestra no es funcionalidad de receptor, es que el substrato está cerrado de punta a punta:

1. El paquete de parámetros llega al RTL y el RTL elabora.
2. El divisor se deriva de `FS_HZ` y se puede sobreescribir por parámetro.
3. El reset asíncrono funciona.
4. El testbench en Python puede importar el modelo y leer los parámetros.

```python title="sim/tb/tb_drx_heartbeat.py"
@cocotb.test()
async def test_reset_asincrono(dut):
    """El reset asíncrono pone `level` a cero sin esperar al reloj."""
    ...
    assert int(dut.level.value) == 1, "el latido no llegó a conmutar antes del reset"
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    assert int(dut.level.value) == 0, "el reset no forzó `level` a cero"
```

## Lo que se rompió: L1 y xsim

[D-05](../alcance/decisiones.md#d-05) dice, literalmente, que un único runner de cocotb cubre los dos
backends: Verilator para L0 y **xsim** —el simulador de Vivado— para L1, porque los cores del DDC son
cajas negras que Verilator no puede elaborar.

Verilator sí. **xsim no.** Los runners que trae cocotb 1.9.2 son:

```sh
$ .venv/bin/python -c "
import inspect, cocotb.runner as r
print(sorted(n for n, o in vars(r).items()
             if inspect.isclass(o) and issubclass(o, r.Simulator) and o is not r.Simulator))
"
['Ghdl', 'Icarus', 'Nvc', 'Questa', 'Riviera', 'Verilator', 'Xcelium']
```

No hay xsim, y no es una omisión de la versión pinada: cocotb nunca ha soportado el simulador de
Vivado.

Esto importa porque L1 es justo el nivel que valida lo que Verilator no puede: sin L1 no hay
comparación bit a bit contra el DDS/CIC/FIR Compiler reales, y eso es el hito ZM1 entero.

La decisión de ingeniería tomada aquí fue **no esconderlo**. El backend está declarado y falla con un
mensaje que nombra el hallazgo:

```python title="sim/runner.py"
if self.backend == L1:
    raise BackendNotAvailable(
        "El backend xsim no está soportado por cocotb 1.9.2 (runners: "
        "icarus, questa, ghdl, nvc, riviera, verilator, xcelium). "
        "Ver P-09 en docs/alcance/pendientes.md. L1 no puede correr hasta "
        "que P-09 se resuelva."
    )
```

Y hay un test que comprueba que sigue fallando así:

```python title="sim/tests/test_l0_heartbeat.py"
def test_l1_declara_su_bloqueo():
    """L1 no está mudo: falla con la razón y con el hallazgo que lo bloquea.

    Si algún día este test empieza a fallar es porque P-09 se resolvió, y
    entonces hay que borrarlo y escribir la suite L1 de verdad.
    """
    job = SimJob(hdl_toplevel="drx_top", test_module="tb_drx_heartbeat", backend=L1)
    with pytest.raises(BackendNotAvailable, match="P-09"):
        job.run()
```

Las opciones y su coste están en [P-09](../alcance/pendientes.md#p-09). La recomendada es escribir los
bancos de L1 en SystemVerilog nativo para xsim, con el modelo dorado escribiendo vectores de entrada y
de salida esperada a fichero: se pierde el «un solo runner» de D-05 y se gana no depender de ninguna
licencia nueva.

!!! question "Una pregunta abierta que conviene hacerse"
    Si el equipo acaba eligiendo comprar licencia de Questa o Riviera, el argumento de coste de D-05
    —«simulación gratis, sin licencia en el runner de CI»— se cae entero, y con él parte de la
    justificación de SystemVerilog frente a VHDL. Puede que lo que haga falta no sea una enmienda a
    D-05 sino revisarla completa.

---

**Anterior:** [3 · La cadena DDC](03-ddc.md) ·
**Siguiente:** [5 · El contrato DRx↔DSP](05-contrato.md)
