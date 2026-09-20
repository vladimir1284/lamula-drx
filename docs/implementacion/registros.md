# Mapa de registros AXI-Lite — v1 (Z1)

Hasta el 19-sep-2026 este entregable de Z1 no existía en absoluto — ni RTL ni documento. Esta
página describe el mapa **v1, congelado para Z1**: lo que expone hoy `drx_top` por AXI-Lite, y lo
que deliberadamente queda fuera todavía.

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

## El mapa

AXI4-Lite, 32 bits de datos, direcciones alineadas a palabra de 4 bytes, `ADDR_WIDTH=6` (16
palabras — deja hueco explícito para Z2 sin diseñarlo ahora). Implementado en `rtl/drx_axil_regs.sv`,
instanciado dentro de `rtl/drx_top.sv`.

| Offset | Nombre   | Acceso            | Bits usados   | Significado |
|--------|----------|-------------------|---------------|-------------|
| `0x00` | VERSION  | RO                | `[31:0]`      | Versión de este mapa de registros (`schema_version` de `config/registers.toml`, arranca en 1). Permite a firmware confirmar que habla con el mapa que espera antes de tocar CTRL/STATUS. |
| `0x04` | CTRL     | RW                | `[0]`         | `mode_coarse`: 0 = fino (valor de reset, el mismo comportamiento que el `localparam` fijo anterior), 1 = grueso. Compartido por los `N_CH` canales de `drx_top` — no hay control por canal, igual que antes. Bits `[31:1]` reservados: leen 0, una escritura ahí no tiene efecto. |
| `0x08` | STATUS   | RO + write-1-to-clear | `[N_CH-1:0]` | Bit `c` = `overrun` sticky del canal `c` de range-gate (`drx_range_gate_quad_top.overrun[c]`). Escribir un 1 en el bit `c` lo limpia; si hay un overrun genuino el mismo ciclo que la limpieza, gana el set — un fallo real nunca se pierde por una carrera con firmware. |
| `0x0C`… | — | — | — | Reservado, sin implementar. Lee 0, escribir no tiene efecto. Para Z2 (triggers, PRF); no se diseña por adelantado. |

`N_CH` es el mismo generic que ya usa `drx_top` (3 hoy, Config A/B de
[P-12](../alcance/pendientes.md#p-12); sería `N_RX_CH` en la ZU9). El ancho de STATUS se ajusta
solo cuando `N_CH` cambie, sin re-congelar el mapa.

### Semántica del slave

`drx_axil_regs.sv` es un slave AXI4-Lite mínimo a propósito: sin bursts (AXI-Lite no los tiene),
una transacción en vuelo a la vez por canal (no se acepta un nuevo AW/W hasta que B se aceptó; ídem
AR/R), responde siempre OKAY. `WSTRB` se ignora: todos los registros de este mapa se escriben
completos de 32 bits.

## Deliberadamente fuera de v1

- **Overflow de saturación del DDC** (`drx_saturate`, dentro de `drx_ddc_top`). Sigue con
  `overflow` sin exponer más allá del propio módulo (ver la cabecera de `rtl/drx_saturate.sv`).
  Exponerlo obliga a añadir puertos a `drx_ddc_top.sv` y `drx_ddc_quad_top.sv` — módulos ya
  verificados bit-exacto contra el modelo dorado (matriz L1 de 16 corridas, D-12) — lo que exige
  volver a correr esa matriz completa contra xsim real para reconfirmar que el cambio de puertos no
  movió nada. Pendiente explícito de una iteración siguiente de Z1, no descartado.
- **Cualquier registro de Z2** (triggers, PRF programable). El hueco de direcciones (`0x0C` en
  adelante) queda reservado sin diseñarlo por adelantado.

## Verificación

- **L0 (Verilator/cocotb, corre en cualquier entorno con Verilator)**: `sim/tb/tb_drx_axil_regs.py`
  cubre VERSION de solo lectura, CTRL read/write y su efecto en `mode_coarse`, lectura de STATUS,
  el pulso de write-1-to-clear, y que las direcciones reservadas lean 0 sin efecto de escritura.
  `sim/tb/tb_drx_range_gate.py` añade la prueba directa del nuevo puerto `clear` de
  `drx_range_gate`: que limpia `overrun`, que un overrun genuino posterior se vuelve a ver (rearme),
  y que un set concurrente con un clear gana. `make sim` / `make check` los corren.
- **L1 (xsim real, con IP de Xilinx) y P&R** — pendiente de correr tras este cambio: el puerto
  `clear` nuevo en `drx_range_gate.sv`/`drx_range_gate_quad_top.sv` solo toca el `always_ff` de
  `overrun` (nada del dato I/Q ni de `mem0`/`mem1`), y `sim/tb_sv/drx_l1_checker.sv` no compara
  `overrun` en absoluto (solo `i_data`/`q_data`) — bajo riesgo, pero sigue siendo un cambio de
  puertos en RTL ya verificado por xsim, así que corresponde reconfirmar la matriz de
  `tb_l1_ddc_range_tri.sv` contra xsim real, y volver a cerrar P&R (`-step impl`, WNS a 62,5 MHz)
  con el AXI-Lite ya integrado en `drx_top`, antes de dar esto por cerrado del todo.
