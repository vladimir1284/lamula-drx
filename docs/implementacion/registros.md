# Mapa de registros AXI-Lite — v2 (Z1)

Hasta el 19-sep-2026 este entregable de Z1 no existía en absoluto — ni RTL ni documento. Esta
página describe el mapa **v2**, congelado por partes en dos sesiones seguidas del mismo día
(19/20-sep-2026): lo que `drx_top` controla y observa hoy vía `drx_axil_regs`, y lo que
deliberadamente queda fuera todavía. La sección de más abajo explica por qué "vía AXI-Lite" no
significa todavía "alcanzable desde firmware real".

Fuente única de verdad: `config/registers.toml`. `tools/gen_registers.py` genera
`rtl/generated/drx_regs_pkg.sv` (RTL) y `fw/include/drx_regs.h` (firmware) desde ese fichero —
ninguno de los dos se edita a mano, igual que el resto de paquetes generados del proyecto
(`make gen`, `make check` valida que coinciden).

## Por qué existe ahora y no antes

`rtl/drx_top.sv` era el diseño vacío de Z0 hasta el 19-sep-2026: no tenía datapath real contra el
que diseñar un mapa de registros. Con `vector_source` → `drx_ddc_quad_top` →
`drx_range_gate_quad_top` ya integrados (ver [`fases.md#z1`](fases.md#z1)), había por primera vez
algo real que controlar (`mode_coarse`, fijo hasta entonces por `localparam`) y algo real que
observar (`overrun` por canal, reducido hasta entonces a un único bit `debug_probe` sin significado,
solo para que la síntesis no eliminara la cadena que lo alimentaba).

**v1** (19-sep) congeló VERSION/CTRL/STATUS sin overflow, a propósito: exponerlo exigía tocar los
puertos de `drx_ddc_top.sv`/`drx_ddc_quad_top.sv`, ya verificados bit-exacto contra el modelo
dorado (matriz L1 de 16 corridas, D-12), y el costo de rehacer esa matriz no se justificaba para un
primer corte. **v2** (20-sep, misma noche) añade OVERFLOW ya con esos puertos añadidos y la matriz
reconfirmada — ver [Verificación](#verificacion) más abajo.

## Cómo se llega a este mapa desde firmware — o cómo no, todavía

**Hallazgo del 20-sep-2026, al cerrar P&R con este mapa integrado por primera vez:** los puertos
AXI-Lite de `drx_axil_regs` NO llegan a puertos de `drx_top`. Exponerlos tal cual (un bus de 32 bits
de datos, más el resto de señales) pide del orden de 94 pines físicos — muy por encima de los 50
sitios del paquete de la ZedBoard, el mismo tipo de límite que ya encontraron las salidas de
range-gate el 19-sep (`ERROR: [Place 30-58] IO placement is infeasible`). La causa raíz no es un
detalle de XDC: **nada en este repo instancia todavía un PS7 ni un interconnect AXI** que pudiera
ser el maestro de este slave dentro del chip. Sin eso, el único destino físicamente posible para
esas señales son pines del paquete, y un bus de control de 32 bits no está pensado para salir del
chip así — en un diseño Zynq real, el maestro vive dentro del PS (AXI GP) y la conexión es interna
al SoC, no pines de usuario.

Para el build actual de ZedBoard, los puertos de `drx_axil_regs` se atan a valores inertes dentro
de `drx_top` (ningún maestro emite transacciones nunca) — ver la cabecera de `rtl/drx_top.sv`. Esto
deja el mapa de registros completo y verificado a nivel de RTL (L0 y L1, ver
[Verificación](#verificacion)), pero **no alcanzable desde firmware de verdad todavía**: hace falta
un puente PS7↔AXI (PS7 vía AXI GP, o un puente JTAG-a-AXI para depuración) que no existe en este
repo y no se diseña aquí a propósito (AGENTS.md: no se diseña por adelantado). Es un prerrequisito
nuevo y real para Z4 (o antes, si hace falta acceso de depuración más pronto).

## El mapa

AXI4-Lite, 32 bits de datos, direcciones alineadas a palabra de 4 bytes, `ADDR_WIDTH=6` (16
palabras — deja hueco explícito para Z2 sin diseñarlo ahora). Implementado en `rtl/drx_axil_regs.sv`,
instanciado dentro de `rtl/drx_top.sv`.

| Offset | Nombre   | Acceso            | Bits usados   | Significado |
|--------|----------|-------------------|---------------|-------------|
| `0x00` | VERSION  | RO                | `[31:0]`      | Versión de este mapa de registros (`schema_version` de `config/registers.toml`, hoy 2). Permite a firmware confirmar que habla con el mapa que espera antes de tocar el resto. |
| `0x04` | CTRL     | RW                | `[0]`         | `mode_coarse`: 0 = fino (valor de reset, el mismo comportamiento que el `localparam` fijo anterior), 1 = grueso. Compartido por los `N_CH` canales de `drx_top` — no hay control por canal, igual que antes. Bits `[31:1]` reservados: leen 0, una escritura ahí no tiene efecto. |
| `0x08` | STATUS   | RO + write-1-to-clear | `[N_CH-1:0]` | Bit `c` = `overrun` sticky del canal `c` de range-gate (`drx_range_gate_quad_top.overrun[c]`). El latch sticky vive en `drx_range_gate` (puerto `clear` nuevo — ver más abajo); este bloque solo lo lee y pulsa la limpieza en origen. Si hay un overrun genuino el mismo ciclo que la limpieza, gana el set. |
| `0x0C` | OVERFLOW | RO + write-1-to-clear | `[N_CH-1:0]` | Bit `c` = overflow de saturación del DDC del canal `c` (`drx_ddc_quad_top.overflow[c]`, combinación de las ramas I/Q de `drx_ddc_top`). A diferencia de STATUS, el latch sticky vive **dentro de `drx_axil_regs`**, no en la fuente: `drx_saturate` es deliberadamente combinacional y sin estado (ver su cabecera), así que añadir un latch ahí habría tocado más de lo necesario en un núcleo ya verificado bit a bit. Misma prioridad set-sobre-clear que STATUS. |
| `0x10`… | — | — | — | Reservado, sin implementar. Lee 0, escribir no tiene efecto. Para Z2 (triggers, PRF); no se diseña por adelantado. |

`N_CH` es el mismo generic que ya usa `drx_top` (3 hoy, Config A/B de
[P-12](../alcance/pendientes.md#p-12); sería `N_RX_CH` en la ZU9). El ancho de STATUS/OVERFLOW se
ajusta solo cuando `N_CH` cambie, sin re-congelar el mapa.

### Semántica del slave

`drx_axil_regs.sv` es un slave AXI4-Lite mínimo a propósito: sin bursts (AXI-Lite no los tiene),
una transacción en vuelo a la vez por canal (no se acepta un nuevo AW/W hasta que B se aceptó; ídem
AR/R), responde siempre OKAY. `WSTRB` se ignora: todos los registros de este mapa se escriben
completos de 32 bits.

### Dos sticky latches, dos sitios distintos — y por qué

STATUS y OVERFLOW parecen el mismo patrón (sticky + write-1-to-clear) pero el latch vive en dos
sitios distintos:

- **STATUS**: el latch ya existía en `drx_range_gate` (para el antiguo `debug_probe`), así que se
  reutiliza — solo se le añadió un puerto `clear` para poder rearmarlo. El registro de este bloque
  es una ventana directa sobre ese estado.
- **OVERFLOW**: `drx_saturate` nunca tuvo estado propio, a propósito (es una función combinacional
  pura, más fácil de verificar bit a bit). En vez de añadirle uno, el latch se creó aquí, en
  `drx_axil_regs`, que es puro RTL de glue sin ninguna verificación bit-exacta previa que proteger.

## Deliberadamente fuera de v2

- **Cualquier registro de Z2** (triggers, PRF programable). El hueco de direcciones (`0x10` en
  adelante) queda reservado sin diseñarlo por adelantado.
- **Conmutación en caliente fino/grueso**: `mode_coarse` sigue siendo estático durante una corrida
  a nivel de RTL (`drx_ddc_top`/`drx_range_gate`), aunque ahora se pueda escribir en tiempo de
  ejecución — cambiarlo a mitad de rayo no tiene continuidad de fase garantizada. Ese trabajo sigue
  diferido, ver la cabecera de esos dos ficheros.

## Verificación

- **L0 (Verilator/cocotb, corre en cualquier entorno con Verilator)**: `sim/tb/tb_drx_axil_regs.py`
  cubre VERSION de solo lectura, CTRL read/write y su efecto en `mode_coarse`, STATUS y OVERFLOW
  (lectura, pulso de write-1-to-clear, y para OVERFLOW específicamente: que el sticky sobrevive
  aunque la fuente vuelva a 0, que rearma tras un clear, y que un set concurrente con un clear
  gana), y que las direcciones reservadas lean 0 sin efecto de escritura. `sim/tb/tb_drx_range_gate.py`
  añade la prueba directa del nuevo puerto `clear` de `drx_range_gate` al nivel del propio módulo.
  `make sim` / `make check` los corren — 80 tests de pytest en verde (cada uno arranca su propia
  regresión de cocotb; los sub-tests nuevos de OVERFLOW/`clear` viven dentro de los dos ya
  existentes de `test_l0_axil_regs.py`/`test_l0_range_gate.py`, no suman entradas nuevas a pytest).
- **L1 (xsim real, con IP de Xilinx) — reconfirmado, 20-sep-2026:**
  - Matriz completa de D-12 contra `sim/tb_sv/tb_l1_ddc.sv` (8 casos × {fine, coarse} = 16
    combinaciones, `tcl/sim_l1.tcl`), tras añadir el puerto `overflow` a `drx_ddc_top.sv`/
    `drx_ddc_quad_top.sv`: **16/16 PASS**, dentro de la tolerancia de D-12. Confirma que exponer el
    overflow no movió ni un bit del dato I/Q ya verificado.
  - `sim/tb_sv/tb_l1_ddc_range_tri.sv` (`tcl/sim_l1_range_tri.tcl`, Config A/B N_CH=3 con range
    gating), tras añadir el puerto `clear` a `drx_range_gate.sv`/`drx_range_gate_quad_top.sv`: fine
    y coarse, 3 canales cada uno — **6/6 PASS**, dentro de tolerancia D-12 **y TLAST bit a bit** con
    el modelo dorado. Confirma que `clear` no movió ni el dato ni el framing ya verificados.
- **P&R — re-cerrado, 20-sep-2026** (`-step impl`, con `drx_axil_regs` integrado y sus puertos
  atados a valores inertes — ver la sección de arriba): **WNS = 2,528 ns, WHS = 0,017 ns** ("All
  user specified timing constraints are met", setup y hold). Utilización post-route: LUT 7,61 %,
  registros 8,33 %, BRAM Tile 21,07 %, DSP48 111/220 (50,45 %) — esta última cifra no cuadra con la
  medida el 19-sep (153/220) para prácticamente el mismo datapath y queda como pregunta abierta sin
  explicar, ver [`fases.md#z1`](fases.md#z1), entrada del 20-sep. El primer intento de este P&R
  falló en `place_design` por el problema de pines descrito arriba, antes de la corrección.
