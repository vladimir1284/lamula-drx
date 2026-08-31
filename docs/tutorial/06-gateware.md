# 6 · Gateware

!!! danger "Esta página describe código que nunca se ha ejecutado"
    No hay Vivado en el entorno de desarrollo ni runner de CI con licencia. El flujo de `tcl/` está
    **escrito y revisado, no probado**. Todo lo que sigue explica el diseño y por qué es así; la
    primera ejecución real es lo que cierra el hito ZM0, y hasta entonces no hay bitstream ni
    `BOOT.BIN`. Ver los supuestos A7 y A8 en [pendientes](../alcance/pendientes.md).

## Modo proyecto y modo no-proyecto

Vivado se puede usar de dos maneras, y
[UG892](https://docs.amd.com/r/en-US/ug892-vivado-design-flows-overview) las describe:

- **Modo proyecto.** Hay un `.xpr` que guarda las fuentes, la configuración de la IP, las
  restricciones y el estado de las ejecuciones. Es lo que sale al abrir la GUI.
- **Modo no-proyecto.** No hay `.xpr`. Un script Tcl lee las fuentes, sintetiza, implementa y escribe
  el bitstream. Todo el estado está en el script y en las fuentes versionadas.

[D-07](../alcance/decisiones.md#d-07) elige el segundo, y el argumento no es estético:

> El modelo de entrega acelerado por agentes es el argumento central de viabilidad para un equipo de
> tres personas, y ese modelo no funciona si el diseño vive en un proyecto GUI de Vivado: los agentes
> no pueden operar sobre él, las builds no son reproducibles y la regresión no existe.

Un `.xpr` es un fichero XML con rutas absolutas, orden de compilación y estado de ejecuciones. Dos
personas que abren la GUI y hacen «lo mismo» producen dos `.xpr` distintos. Un script Tcl no.

Cuesta unas dos semanas hacerlo bien al principio y un mes de reconstrucción hacerlo al final.

## El flujo

```sh
vivado -mode batch -source tcl/build.tcl -tclargs \
       -platform zedboard -step bitstream -outdir build/gw/zedboard
```

Pasos: `synth`, `impl`, `bitstream`. Cada uno incluye los anteriores. La referencia de cada comando
está en [UG835](https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands).

### De dónde salen la pieza y el periodo

```tcl title="tcl/build.tcl"
source [file join $repo_root tcl generated drx_params.tcl]
...
set part      [::drx::get PART            $opt(platform)]
set period_ns [::drx::get CLK_PERIOD_NS   $opt(platform)]
```

Ni la pieza ni el periodo están escritos en el script: salen del paquete de parámetros. Y el
`create_clock` se **genera**, no se escribe en el XDC:

```tcl title="tcl/build.tcl"
# El periodo NO se escribe en el XDC: sale del paquete de parámetros.
set clk_xdc [file join $opt(outdir) clock_generated.xdc]
set handle [open $clk_xdc w]
puts $handle "create_clock -period $period_ns -name clk \[get_ports clk\]"
close $handle
read_xdc $clk_xdc
```

El XDC versionado solo lleva restricciones **físicas**, que sí son de la placa y no del reloj:

```tcl title="tcl/xdc/zedboard.xdc"
# Aquí NO hay periodo de reloj: el `create_clock` lo emite el flujo a partir de
# `tcl/generated/drx_params.tcl`, que deriva de config/params.toml (D-02). Un
# periodo literal en este fichero falla el gate de CI.

set_property -dict {PACKAGE_PIN Y9  IOSTANDARD LVCMOS33} [get_ports clk]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS25} [get_ports rst_n]
set_property -dict {PACKAGE_PIN T22 IOSTANDARD LVCMOS33} [get_ports led_heartbeat]
```

Y no es una convención de buena voluntad: `tools/check_hardcoded_clock.py` escanea también los `.xdc`,
así que un `create_clock -period 10.000` escrito a mano ahí **falla la build**.

### La IP va como XCI, y la regeneración está guionizada

```tcl title="tcl/build.tcl"
# IP versionada como XCI. En Z0 no hay ninguna; el bucle queda listo para Z1.
set xci_files [glob -nocomplain [file join $repo_root ip *.xci]]
if {[llength $xci_files]} {
  read_ip $xci_files
  generate_target all [get_ips]
  synth_ip [get_ips]
}
```

`ip/` guarda **XCI y nada más**. Los productos de `generate_target` son artefactos de build y no se
versionan: son grandes, dependen de la versión de Vivado y se regeneran. Una IP regenerada a mano en
una máquina distinta es la forma más barata de perder la reproducibilidad del bitstream.

En Z0 no hay IP. `tcl/ip.tcl` existe ya porque Z1 va a crear el
[DDS](https://docs.amd.com/r/en-US/pg141-dds-compiler),
[CIC](https://docs.amd.com/r/en-US/pg079-cic-compiler) y
[FIR Compiler](https://docs.amd.com/r/en-US/pg149-fir-compiler), y el sitio donde se crean tiene que
estar decidido **antes**, no después.

### El cierre de temporización es un gate, no un informe

```tcl title="tcl/build.tcl"
# El cierre de temporización tiene que ser un gate, no un informe que nadie lee.
set wns [get_property SLACK [get_timing_paths -delay_type max]]
puts "WNS = $wns ns"
if {$wns < 0} {
  error "temporización no cerrada en $opt(platform): WNS = $wns ns"
}
```

*WNS* es el *worst negative slack*: el margen del camino más apretado. Negativo significa que el
diseño no cumple el periodo pedido. Dejarlo como informe garantiza que alguien lo mire la primera
semana y nunca más.

### Las dos plataformas se construyen siempre

El CI corre la matriz completa:

```yaml title=".github/workflows/ci.yml"
strategy:
  matrix:
    platform: [zedboard, zu9]
```

Y esto es lo que dice la [estructura del repositorio](../implementacion/estructura-repo.md) sobre por
qué:

> Correr el cierre de temporización contra `FS_HZ` = 250 MHz desde el principio es la única forma de
> que la deuda de la entrada D2 del registro delta no se descubra el día que llegue el hardware.

No hay placa ZU9, pero sí hay pieza ZU9 en las bibliotecas de Vivado. Sintetizar contra ella cuesta
minutos de CI y avisa meses antes de que un camino no vaya a cerrar a 250 MHz.

La selección de plataforma llega al RTL por macro de preprocesador:

```tcl
if {$opt(platform) eq "zu9"} {
  lappend synth_args -verilog_define DRX_PLATFORM_ZU9
}
```

que es lo que activa la rama correspondiente del paquete generado.

## El `BOOT.BIN`, y por qué «reproducible byte a byte» es difícil

El hito ZM0 es *un `git push` produce un `BOOT.BIN` reproducible byte a byte*. En una Zynq, el
`BOOT.BIN` lo arma [bootgen](https://docs.amd.com/r/en-US/ug1283-bootgen-user-guide) a partir de un
descriptor `.bif`:

```text title="tcl/boot/boot.bif"
the_ROM_image:
{
  [bootloader] fsbl.elf
  drx_top.bin
  drx_app.elf
}
```

El orden importa: FSBL primero, luego el bitstream, luego la aplicación.

La reproducibilidad depende de tres cosas, y ninguna sale gratis:

```sh title="tools/make_boot.sh"
#   1. Versión de Vivado/Vitis PINADA. Dos versiones distintas dan bitstreams
#      distintos aunque el RTL sea idéntico.
#   2. Usar el `.bin` crudo y no el `.bit`: la cabecera del .bit lleva marca de
#      tiempo y por sí sola rompe la reproducibilidad.
#   3. Semilla de implementación fija (`-seed`) y sin pasos dependientes del
#      número de hilos.
```

El punto 2 es el que sorprende: la cabecera del `.bit` incluye la fecha y la hora de generación, así
que dos builds idénticas dan ficheros distintos. Por eso el flujo pide el `.bin` crudo:

```tcl
# `-bin_file` produce además el .bin crudo, sin la cabecera del .bit que lleva
# marca de tiempo: es el que se usa para el BOOT.BIN reproducible byte a byte.
write_bitstream -force -bin_file [file join $opt(outdir) drx_top.bit]
```

Y el script no se fía: empaqueta dos veces y compara.

```sh title="tools/make_boot.sh"
bootgen -image boot.bif -arch zynq -o BOOT.BIN -w on
sha256sum BOOT.BIN > BOOT.BIN.sha256

# Segunda pasada: el mismo comando tiene que dar el mismo hash.
bootgen -image boot.bif -arch zynq -o BOOT.repeat.bin -w on
if ! cmp -s BOOT.BIN BOOT.repeat.bin; then
  echo "BOOT.BIN NO es reproducible: dos empaquetados dieron ficheros distintos" >&2
  exit 3
fi
```

También falla con un mensaje claro por lo que hoy falta de verdad:

```sh
$ tools/make_boot.sh zedboard
falta fsbl.elf: lo produce Z4, no Z0
falta drx_app.elf: lo produce Z4, no Z0
```

El FSBL y la aplicación son firmware, y el firmware real es Z4. Z0 puede tener el bitstream y el
procedimiento; el `BOOT.BIN` completo, no.

## El diseño que se sintetiza en Z0

Vacío a propósito. Un divisor que hace parpadear un LED:

```systemverilog title="rtl/drx_heartbeat.sv"
module drx_heartbeat #(
    // Ciclos por medio periodo del latido. Por defecto medio segundo derivado de
    // FS_HZ; los testbenches lo bajan para no simular 10^8 ciclos.
    parameter int DIV = int'(drx_params_pkg::FS_HZ / 2)
) (
    input  logic clk,
    input  logic rst_n,
    output logic level  // conmuta cada DIV ciclos: apto para un LED
);
```

No es un ejercicio: es el cierre del lazo completo —parámetros → RTL → síntesis → placa— con la
mínima funcionalidad posible. Si el LED parpadea a 1 Hz en la ZedBoard, entonces el paquete de
parámetros llegó al bitstream, el reloj es el que se pidió y el flujo funciona. Y si mañana se
construye para la ZU9, el mismo RTL da 1 Hz a 250 MHz sin tocar una línea.

## El interfaz SSA, definido pero sin implementar

Z0 define el formato de la [capa de abstracción de fuente de muestras](../plataforma/fuente-de-muestras.md)
—[D-01](../alcance/decisiones.md#d-01)— sin implementarlo:

```systemverilog title="rtl/ssa/drx_ssa_pkg.sv"
// Identidad de la implementación que produce el stream. Viaja en TUSER para
// que el status/BITE pueda reportar de dónde salieron las muestras sin que
// ninguna etapa de proceso tenga que saberlo.
typedef enum logic [SSA_SOURCE_TAG_BITS-1:0] {
  SSA_SRC_JESD204B         = 2'd0,  // solo ZU9
  SSA_SRC_VECTOR_RT        = 2'd1,  // DDR vía MM2S DMA
  SSA_SRC_VECTOR_BRAM      = 2'd2,  // bucle en BRAM
  SSA_SRC_VECTOR_THROTTLED = 2'd3   // DDR con backpressure; bit-exacto con RT
} ssa_source_tag_e;
```

El interfaz es [AXI4-Stream](https://developer.arm.com/documentation/ihi0051/latest) con
backpressure. Lo importante de D-01 es que **nada aguas abajo distingue qué implementación está
activa**: cuando llegue la ZU9, migrar la fuente de muestras es sustituir un módulo que cumple el
interfaz por otro que cumple el mismo interfaz, y `vector_source` se queda en la placa final como
inyector de vectores conocidos.

Definir el formato en Z0 y no en Z1 cuesta media hora y evita que el primer módulo que se escriba en
Z1 imponga su propio formato de facto.

## Qué hace falta para cerrar esto

1. Una máquina o un runner con Vivado y licencia. El job del CI ya existe, condicionado a la variable
   `HAS_VIVADO_RUNNER`.
2. Fijar la versión de Vivado y anotarla.
3. Ejecutar `tcl/build.tcl` para las dos plataformas y arreglar lo que salga — es la primera
   ejecución, y sería raro que saliera a la primera.
4. Empaquetar y comprobar la reproducibilidad cuando Z4 produzca los ELF.

Hasta entonces, «CI verde» significa **verde en el substrato**, no ZM0 cerrado. Conviene no confundir
las dos cosas al informar de progreso.

---

**Anterior:** [5 · El contrato DRx↔DSP](05-contrato.md) ·
**Siguiente:** [7 · Resultados](07-resultados.md)
