# Mapa de registros AXI-Lite — v2 (Z1)

Hasta el 19-sep-2026 este entregable de Z1 no existía en absoluto — ni RTL ni documento. Esta
página describe el mapa **v2**, congelado por partes en dos sesiones seguidas del mismo día
(19/20-sep-2026): lo que expone hoy `drx_top` por AXI-Lite, y lo que deliberadamente queda fuera
todavía.

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
- **P&R** — pendiente de volver a cerrar (`-step impl`, WNS a 62,5 MHz) con el AXI-Lite ya
  integrado en `drx_top` y los puertos `overflow`/`clear` nuevos. El P&R del 19-sep fue sobre el
  `drx_top` de antes de este mapa de registros.
