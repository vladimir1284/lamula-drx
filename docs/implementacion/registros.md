# Mapa de registros AXI-Lite — v7 (Z1 + Z2 + Z4.1)

Hasta el 19-sep-2026 este entregable de Z1 no existía en absoluto — ni RTL ni documento. Esta
página describe el mapa **v7** (26-sep-2026): lo que `drx_top` controla y observa hoy vía
`drx_axil_regs`, y lo que deliberadamente queda fuera todavía. La sección de más abajo explica por
qué "vía AXI-Lite" no significa todavía "alcanzable desde firmware real".

**v3** añade el bloque de Z2 (`drx_timing_engine`, [D-13](../alcance/decisiones.md#d-13)) — ver
[El mapa](#el-mapa) y [Z2 en v3](#z2-en-v3) más abajo. **v4** usa 2 de los bits que v3 dejaba
reservados de TIMING_STATUS para los checks autocontenidos de D-09 — ver [Z2 en v4](#z2-en-v4).
**v5** añade BINS_LOW/BINS_HIGH (conteo de bins de range-gate por lote, [D-15](../alcance/decisiones.md#d-15))
y con eso cierra D-09 del todo — ver [Z2 en v5](#z2-en-v5). **v6** añade GATE_TRUNCATED, el BITE de
tiempo muerto que D-14 dejaba explícitamente abierto — ver [Z2 en v6](#z2-en-v6). **v7** añade
TRIG_COUNT, el contador de trigger que el firmware de ensamblado de rayos (Z4.4) necesitará como
metadato — ver [Z4 en v7](#z4-en-v7). v1/v2 (Z1, 19/20-sep-2026) siguen descritas tal cual en la
sección [Historial](#historial-v1v2).

Fuente única de verdad: `config/registers.toml`. `tools/gen_registers.py` genera
`rtl/generated/drx_regs_pkg.sv` (RTL) y `fw/include/drx_regs.h` (firmware) desde ese fichero —
ninguno de los dos se edita a mano, igual que el resto de paquetes generados del proyecto
(`make gen`, `make check` valida que coinciden).

## Historial (v1/v2) { #historial-v1v2 }

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

## Cómo se llega a este mapa desde firmware

**Hallazgo del 20-sep-2026, al cerrar P&R con este mapa integrado por primera vez:** los puertos
AXI-Lite de `drx_axil_regs` no llegaban a puertos de `drx_top`. Exponerlos tal cual (un bus de 32
bits de datos, más el resto de señales) pedía del orden de 94 pines físicos — muy por encima de los
50 sitios del paquete de la ZedBoard, el mismo tipo de límite que ya encontraron las salidas de
range-gate el 19-sep (`ERROR: [Place 30-58] IO placement is infeasible`). La causa raíz no era un
detalle de XDC: nada en el repo instanciaba todavía un PS7 ni un interconnect AXI que pudiera ser el
maestro de este slave dentro del chip.

**Resuelto la misma noche (20-sep-2026, más tarde): puente PS7↔AXI real, override explícito de
"no se diseña por adelantado" decidido por el usuario tras ver el alcance completo del cambio.**
`tcl/gen_zynq_bd.tcl` construye un block design con `processing_system7` (preset de MIO/DDR del
board file oficial de Digilent — `github.com/Digilent/vivado-boards`, instalado a mano en esta
máquina, no viene con Vivado — `digilentinc.com:zedboard:part0:1.1` según lo detecta esta
instalación), `FCLK_CLK0` a la misma frecuencia de fabric del proyecto (62,5 MHz, D-02 — no un
reloj nuevo), `M_AXI_GP0` habilitado, y un `axi_interconnect` + `axi_protocol_converter` (AXI4 →
AXI4-Lite; `axi_interconnect:2.1` no tiene downgrade de protocolo por puerto, confirmado) hacia el
mapa de registros. `rtl/drx_top.sv` volvió a ser un slave AXI-Lite pass-through puro (sus puertos ya
no se atan a nada dentro del propio fichero); `rtl/drx_zynq_top.sv` (nuevo) instancia el wrapper de
ese BD junto con `drx_top` y los conecta — `drx_top` no puede vivir *dentro* del BD como referencia
de módulo (`create_bd_cell -type module -reference` no admite un top SystemVerilog en Vivado 2022.2,
confirmado corriendo esto).

`tcl/build.tcl -top zynq` (en vez del `-top drx_top` de siempre, que sigue existiendo sin cambios
para medir solo el datapath — `rtl/drx_top_tieoff.sv`, nuevo, es su wrapper de valores inertes)
cierra P&R real: **WNS = 1,712 ns, WHS = 0,033 ns**, reloj de 62,5 MHz derivado automáticamente del
propio modelo de temporización del PS7 con el preset aplicado — sin `create_clock` manual, a
diferencia del flujo sin PS7. `-step xsa` exporta la plataforma de hardware
(`write_hw_platform -fixed -include_bit`) para que Vitis (instalado en esta máquina el 20-sep-2026,
`/home/orlando/tools/Xilinx_Vitis/`, específicamente para esto) genere BSP/FSBL — **eso sigue siendo
Z4 real**, `fw/Makefile` ya lo dice explícitamente y `tools/make_boot.sh` sigue fallando igual que
hoy hasta que exista `fsbl.elf`. El puente deja de ser el hueco; el firmware de verdad no.

## El mapa

AXI4-Lite, 32 bits de datos, direcciones alineadas a palabra de 4 bytes, `ADDR_WIDTH=7` (32
palabras — subió de 6/16 en v3 porque el bloque de Z2 no cabía). Implementado en
`rtl/drx_axil_regs.sv`, instanciado dentro de `rtl/drx_top.sv`.

| Offset | Nombre   | Acceso            | Bits usados   | Significado |
|--------|----------|-------------------|---------------|-------------|
| `0x00` | VERSION  | RO                | `[31:0]`      | Versión de este mapa de registros (`schema_version` de `config/registers.toml`, hoy 5). Permite a firmware confirmar que habla con el mapa que espera antes de tocar el resto. |
| `0x04` | CTRL     | RW                | `[0]`         | `mode_coarse`: 0 = fino (valor de reset), 1 = grueso. Compartido por los `N_CH` canales de `drx_ddc_quad_top` (decimación/tamaño de celda). Desde v5 (D-15) ya NO llega a `drx_range_gate` — el conteo de bins de range-gate es BINS_LOW/BINS_HIGH, no una elección fino/grueso fija. Bits `[31:1]` reservados: leen 0, una escritura ahí no tiene efecto. |
| `0x08` | STATUS   | RO + write-1-to-clear | `[N_CH-1:0]` | Bit `c` = `overrun` sticky del canal `c` de range-gate (`drx_range_gate_quad_top.overrun[c]`). El latch sticky vive en `drx_range_gate` (puerto `clear` nuevo — ver más abajo); este bloque solo lo lee y pulsa la limpieza en origen. Si hay un overrun genuino el mismo ciclo que la limpieza, gana el set. |
| `0x0C` | OVERFLOW | RO + write-1-to-clear | `[N_CH-1:0]` | Bit `c` = overflow de saturación del DDC del canal `c` (`drx_ddc_quad_top.overflow[c]`, combinación de las ramas I/Q de `drx_ddc_top`). A diferencia de STATUS, el latch sticky vive **dentro de `drx_axil_regs`**, no en la fuente: `drx_saturate` es deliberadamente combinacional y sin estado (ver su cabecera), así que añadir un latch ahí habría tocado más de lo necesario en un núcleo ya verificado bit a bit. Misma prioridad set-sobre-clear que STATUS. |
| `0x10` | TIMING_CTRL | RW | `[0]` | `enable` de `drx_prf_batch_seq` (arranca/detiene el secuenciador de 2 lotes, D-13). Reset: 0 (detenido). |
| `0x14` | TIMING_STATUS | RO + write-1-to-clear | `[2:0]` | Bit 0 = `radial_done` sticky de `drx_prf_batch_seq` (radial completo: lote bajo + lote alto). Bits 1/2 (v4, D-09; ampliado en v5/D-15) = `config_invalid` del lote bajo/alto — cubre pulse_width fuera de tabla, no cabe en su PRI, prf_div bajo el piso de rango, o bins sobre el techo de BRAM; mientras cualquiera esté en 1, `drx_timing_engine` mantiene el secuenciador sin correr, sin importar TIMING_CTRL. Los tres bits comparten el mismo patrón set-sobre-clear que OVERFLOW. Bits `[31:3]` reservados: leen 0. |
| `0x18` | PRF_DIV_LOW | RW | `[31:0]` | `prf_div` del lote bajo (vigilancia/PRF baja), ciclos de `FS_HZ` por PRI. Validado en RTL desde v5 (D-09 completo): junto con "cabe en su propio PRI" (desde v4, ver PULSE_WIDTH), un `prf_div` que dé un rango no ambiguo por debajo de 460 km (piso fijo) también deja el lote inválido — ver [Z2 en v5](#z2-en-v5). |
| `0x1C` | PRF_DIV_HIGH | RW | `[31:0]` | `prf_div` del lote alto (Doppler/PRF alta). Mismas condiciones que PRF_DIV_LOW. |
| `0x20` | PULSE_WIDTH | RW | `[15:0]`/`[31:16]` | Bits 15:0 = ancho de pulso (ciclos) del lote bajo; bits 31:16 = del lote alto. Empaquetados: cada uno cabe en 16 bits (`PulseWidthBits` de `drx_prf_batch_seq.sv`). Validado en RTL desde v4 (D-09, checks autocontenidos): tiene que estar en la tabla de `config/params.toml` **y** caber en el `prf_div` de su propio lote, o el lote queda inválido — ver TIMING_STATUS y [Z2 en v4](#z2-en-v4). |
| `0x24` | N_PULSES | RW | `[15:0]`/`[31:16]` | Bits 15:0 = pulsos del lote bajo antes de pasar al alto; bits 31:16 = pulsos del lote alto antes de `radial_done`. Mismo empaquetado que PULSE_WIDTH. |
| `0x28`–`0x34` | TRIG_DELAY_0..3 | RW | `[31:0]` | Retardo (ciclos desde `pulse_trig`) de cada uno de los `N_TRIGGERS=4` canales de `drx_trigger_gen`. Un registro por canal, no un array — ver [Z2 en v3](#z2-en-v3). |
| `0x38`–`0x44` | TRIG_WIDTH_0..3 | RW | `[31:0]` | Ancho del pulso de cada canal. Tiene que ser ≥ 1 (sin validar en RTL, ver la cabecera de `drx_trigger_one_shot.sv`). |
| `0x48` | BINS_LOW | RW | `[31:0]` | Conteo de bins de range-gate del lote bajo (D-15, v5): cuántas muestras decimadas entran en un rayo de este lote. Configurable en runtime — viene de DSP, que a su vez lo recibe de RCP según el VCP. Validado en RTL: tiene que ser ≥ 1 y no superar `BINS_MODE_FINE` (3689, la profundidad física real de la BRAM de `drx_range_gate`), o el lote queda inválido — ver TIMING_STATUS y [Z2 en v5](#z2-en-v5). |
| `0x4C` | BINS_HIGH | RW | `[31:0]` | Conteo de bins de range-gate del lote alto (Doppler). Mismas condiciones que BINS_LOW. |
| `0x50` | GATE_TRUNCATED | RO + write-1-to-clear | `[N_CH-1:0]` | Bit `c` = `ray_truncated` sticky del canal `c` de range-gate (BITE de D-14, v6) — ver [Z2 en v6](#z2-en-v6). |
| `0x54` | TRIG_COUNT | RO | `[31:0]` | Contador libre de 32 bits: incrementa un pulso de `pulse_trig` de `drx_timing_engine` (el mismo que ya dispara `ray_start`, D-14) por ciclo. Sin write-1-to-clear — es un conteo monótono, no un diagnóstico sticky; envuelve en 2^32 pulsos. Ver [Z4 en v7](#z4-en-v7). |
| `0x58` | NCO_PINC | RW | `[31:0]` | Palabra de incremento de fase del NCO (v9, Z4.5), compartida por los `N_CH` canales: todos ven el mismo IF. Valor de reset = `NCO_PHASE_INC`, el mismo PINC1 que la IP del DDS Compiler lleva como valor inicial, así que no escribir aquí deja la cadena bit a bit como antes de v9. **Cada** escritura pulsa el canal `S_AXIS_CONFIG` del core, incluso si el valor no cambia. Ver [Z4 en v9](#z4-en-v9). |
| `0x5C`… | — | — | — | Reservado, sin implementar. Lee 0, escribir no tiene efecto. |

`N_CH` es el mismo generic que ya usa `drx_top` (3 hoy, Config A/B de
[P-12](../alcance/pendientes.md#p-12); sería `N_RX_CH` en la ZU9). El ancho de STATUS/OVERFLOW se
ajusta solo cuando `N_CH` cambie, sin re-congelar el mapa. `N_TRIGGERS` (4, `drx_params_pkg`) es
fijo — los 4 registros TRIG_DELAY_*/TRIG_WIDTH_* no escalan con ningún generic.

### Z2 en v3 { #z2-en-v3 }

`drx_timing_engine` (D-13: 2 lotes de PRF/ancho de pulso por radial + `N_TRIGGERS` de retardo/ancho
independientes, ver [`fases.md#z2`](fases.md#z2)) ya se instancia dentro de `rtl/drx_top.sv`,
configurado enteramente desde este mapa. Tres decisiones de esta sesión, documentadas aquí porque
ningún otro sitio las fija:

- **TRIG_DELAY/TRIG_WIDTH son 4 registros con nombre, no un registro con un array.**
  `rtl/drx_trigger_gen.sv` ya había encontrado (sesión anterior, ver su cabecera) que un array sin
  empaquetar de **puertos de salida** de 1 bit no es indexable de forma fiable vía VPI en
  Verilator/cocotb (`trig_out` tuvo que pasar de array a vector empaquetado por esto).
  `drx_axil_regs` expone TRIG_DELAY/TRIG_WIDTH como salidas de 32 bits — no se repitió el
  experimento para confirmar si un array ancho también falla, se aplicó la misma precaución
  directamente: 8 puertos escalares (`trig_delay_0`..`3`, `trig_width_0`..`3`). `drx_top.sv` es
  quien los empaqueta hacia el array sin empaquetar que sí acepta `drx_timing_engine` como
  **entrada** (eso sí funciona, confirmado con `trig_delay`/`trig_width` de `drx_trigger_gen.sv`).
- **`drx_timing_engine` NO está conectado a `drx_range_gate`/`vector_source` todavía.** Sigue
  siendo, en la práctica, una isla dentro de `drx_top`: sus salidas de reloj de radar
  (`pulse_trig`/`batch_sel`/`pulse_width`/`tx_gate`) solo llegan a `debug_probe_xor` (para que la
  síntesis no elimine la cadena, mismo patrón que ya usa este fichero), no a ningún consumidor real.
  Ninguna decisión documentada dice cómo debe sincronizarse el trigger con el inicio del gating —
  uno de los puntos abiertos de [`fases.md#z2`](fases.md#z2) — y resolverlo tocaría
  `drx_range_gate.sv`, ya cerrado y verificado bit a bit bajo D-12 en Z1.

  **Actualización, 22-sep-2026 (más tarde, mismo día): resuelto por D-14.** `ray_start` conecta
  `pulse_trig` con `drx_range_gate_quad_top` — ver [D-14](../alcance/decisiones.md#d-14). El lado
  de `vector_source`/Tx sigue sin conectar (D-14 lo deja explícitamente abierto). El conteo de bins
  por lote que este mismo párrafo no mencionaba se resolvió después, en v5 —
  ver [Z2 en v5](#z2-en-v5).
- **`trig_out` es un puerto físico real de `drx_top` (y de `drx_top_tieoff`/`drx_zynq_top`, que lo
  pasan a través) pero sin pines XDC.** `tcl/xdc/zedboard.xdc` no tiene mapeado ningún Pmod de la
  ZedBoard y no hay en este repo una referencia de pinout físico verificada para inventar una
  asignación — el propósito de este puerto (osciloscopio, hito ZM2) necesita esa asignación para
  ser útil de verdad. Lint limpio (`make lint-hdl`, con `--top-module drx_top` sobre el `filelist.f`
  completo) y `make check` en verde (99 tests), pero **el P&R real no se ha vuelto a correr en esta
  sesión** con estos 4 pines nuevos — la última cifra de P&R medida (WNS/WHS/utilización, ver
  [Verificación](#verificacion)) sigue siendo la de v2, antes de este cambio.

Lo que v3 explícitamente **no** hace, aunque su condición de cierre lo mencione: tocar
`contract/schema/drx_dsp_v0_1.toml`. [P-15](../alcance/pendientes.md#p-15) fijaba "cuando se diseñe
el mapa de registros de Z2" como su condición de cierre, y ese mapa ya existe — pero P-15 seguía
**abierto** del lado del contrato: D-08 dice que cambiarlo exige subir `version_minor` y actualizar
tests, y eso mismo documento lo marca como alcance de Z4, no de esta sesión. Tocar el contrato
congelado sin discutirlo antes rompería esa regla aunque el registro que lo motiva ya exista.
(P-15 cerró el 1-oct-2026 con el contrato v0.6, en Z4.4 — ver `fases.md#z4`.)

### Z2 en v4 { #z2-en-v4 }

**22-sep-2026 (más tarde).** D-09 fija que "el manejador de configuración debe validar y rechazar
las combinaciones ilegales" — hasta v3 nada en RTL lo hacía, ver la entrada de arriba en
[Deliberadamente fuera de v3](#deliberadamente-fuera-de-v3). v4 cierra la mitad AUTOCONTENIDA de
ese check (la que no necesita ningún dato externo): `rtl/drx_timing_config_valid.sv`, instanciado
×2 (lote bajo/alto) dentro de `drx_timing_engine.sv`, verifica que `pulse_width` esté en la tabla
de `config/params.toml` y que quepa en su propio PRI (`pulse_width < prf_div`).

Decisiones de esta sesión:

- **"Rechazar" en fabric no puede ser un error de bus.** El slave de `drx_axil_regs` responde
  siempre OKAY (ver [Semántica del slave](#semantica-del-slave)) y eso no cambia. El rechazo real es
  que `drx_timing_engine` gatea su `enable` interno hacia `drx_prf_batch_seq` con
  `config_valid_low && config_valid_high`: con un lote inválido, el secuenciador de lotes
  simplemente no corre (mismo efecto que `TIMING_CTRL.enable=0`), sin importar lo que diga ese
  registro. `drx_prf_batch_seq.sv` (ya cerrado y verificado bit a bit) no cambió — el gateo vive un
  nivel arriba, en la composición.
- **El latch vive en `drx_axil_regs`, no en el validador.** Mismo argumento que ya fija OVERFLOW en
  su cabecera: `drx_timing_config_valid.sv` es deliberadamente combinacional y sin estado, así que
  el sticky + write-1-to-clear de TIMING_STATUS bits 1/2 se añadió en `drx_axil_regs`, no en el
  validador ni en `drx_timing_engine`.
- **PRF × rango no ambiguo sigue sin validarse en ningún sitio de RTL.** Ese check necesita un
  umbral externo (`r_max_required_m`) que hoy no existe como registro ni como constante de
  `config/params.toml` — añadirlo es subir el mapa otra vez (registro nuevo + decidir de dónde sale
  el valor), no un descuido de esta sesión. Sigue listado en
  [Deliberadamente fuera de v3](#deliberadamente-fuera-de-v3), sin cerrar.

  **Actualización 22-sep-2026 (más tarde, tercera sesión): cerrado, y SIN registro nuevo.** La
  premisa de arriba ("hace falta un registro nuevo") resultó sobreestimada: `r_max_required_m` es un
  requisito FIJO de producto (460 km / 115 km, valores estándar WSR-88D/NEXRAD), no un parámetro que
  el DSP configura en runtime — vive como invariante en `config/params.toml`
  (`prf_div_min_low`/`prf_div_min_high`), igual que `PULSE_WIDTH_CYCLES`, y como PARÁMETRO (no
  puerto) en `drx_timing_config_valid.sv`/`drx_timing_engine.sv`. El mapa de registros no cambia; no
  hay v5. Detalle completo, incluida la aritmética y el hallazgo de que el piso del lote alto es
  no-vinculante hoy, en `fases.md#z2`, entrada del 22-sep (más tarde, tercera sesión).
- **`schema_version` sube a 4** aunque ningún offset se movió: v3 documentaba los bits 1/2 de
  TIMING_STATUS como "reservados, leen 0" — redefinirlos es un cambio de semántica del mapa que un
  firmware futuro necesita poder detectar, mismo criterio que ya se aplicó en v1→v2/v2→v3.

Verificación: nuevo L0 (`sim/tb/tb_drx_timing_config_valid.py`) barre los 3 anchos de la tabla más
uno fuera de tabla contra varios `prf_div`, bit a bit contra el oráculo
`model/drx_model/timing.py::batch_config_valid` (D-03). `tb_drx_timing_engine.py` gana un caso con
un lote inválido que confirma que el motor completo (no solo el validador) se queda congelado; su
caso ya existente de composición de triggers tuvo que pasar a usar un `pulse_width` de la tabla real
(200) en vez de un valor arbitrario pequeño, porque ahora el motor no corre con uno ilegal.
`tb_drx_axil_regs.py` gana los mismos casos de sticky/W1C/set-gana-sobre-clear que ya cubren
STATUS/OVERFLOW, aplicados a los bits 1/2 de TIMING_STATUS. `make check` en verde (104 tests).

Lo que esto NO hace, deliberadamente: no vuelve a correr el P&R (la última cifra medida sigue siendo
la de v3, sin este cambio — la lógica añadida es pequeña y puramente combinacional/de registro, pero
no se ha medido) y no toca `contract/schema/drx_dsp_v0_1.toml` (P-15 sigue abierto del lado del
contrato, sin relación con este cambio).

### Z2 en v5 { #z2-en-v5 }

**25-sep-2026.** Cierra D-09 del todo: PRF × rango no ambiguo (ver la actualización dentro de
[Z2 en v4](#z2-en-v4)) y ahora también el conteo de bins de range-gate por lote
([D-15](../alcance/decisiones.md#d-15)). Hasta esta sesión, `BINS_MODE_FINE`/`BINS_MODE_COARSE`
(3689/1844, `config/params.toml`) eran los únicos conteos de bins posibles, elegidos por
`mode_coarse` — una elección fino/grueso, no un registro por lote. Batch mode (D-13) pide algo
distinto: el lote de vigilancia necesita ver más lejos que el de Doppler, y esa proporción la fija
el VCP, vía RCP → DSP → DRx — no es un valor fijo de `config/params.toml`.

Decisiones de esta sesión:

- **`mode_coarse` deja de llegar a `drx_range_gate`.** Sigue existiendo (CTRL bit 0), pero solo para
  `drx_ddc_quad_top` (decimación/tamaño de celda) — un eje distinto e independiente del conteo de
  bins. `drx_range_gate`/`drx_range_gate_quad_top` ganan un puerto `bin_count` (no `bins`:
  SystemVerilog reserva esa palabra para coverpoints/randomize) que reemplaza `mode_coarse` por
  completo en ese módulo.
- **El conteo activo lo compone `drx_timing_engine`, no `drx_axil_regs`.** `drx_prf_batch_seq` gana
  `bins_low`/`bins_high` como entradas y `bin_count` como salida, con el mismo mux combinacional que
  ya usaba para `pulse_width` (seleccionado por `batch_sel`) — ningún registro nuevo de "cuál está
  activo", el mux ya existía para otra señal.
- **El techo (D-09) es un PARÁMETRO, no un registro, igual que el piso de PRF de v4.**
  `drx_timing_config_valid.sv` gana un cuarto check (`bin_count >= 1 && bin_count <= BinsMax`);
  `BinsMax` por defecto es `BINS_MODE_FINE` para los dos lotes — a diferencia del piso de PRF (que sí
  difiere por lote), el techo es el mismo requisito físico (una sola BRAM real) para los dos.
- **`schema_version` sube a 5** por el mismo criterio que v1→v2/v2→v3/v3→v4: dos registros nuevos
  (BINS_LOW/BINS_HIGH) y un cambio de semántica de CTRL bit 0 (ya no llega a range-gate) que
  firmware necesita poder detectar.

Verificación: `model/drx_model/timing.py::batch_config_valid` gana `bins`/`bins_max` (D-03).
`sim/tb/tb_drx_timing_config_valid.py` añade `bin_count` al sweep. `sim/tb/tb_drx_prf_batch_seq.py`
gana un caso que confirma el mux de `bin_count`. `sim/tb/tb_drx_timing_engine.py` gana un caso con
los pisos reales de producción (BinsMaxLow/High = BINS_MODE_FINE sin override) que confirma que el
motor completo propaga el techo hasta el gateo de `enable`. `sim/tb/tb_drx_range_gate.py` reemplaza
`mode_coarse` por `bin_count` en los 8 tests existentes (D-14 no se re-verifica desde cero: los
mismos casos de `ray_start` ya cubrían el framing, solo cambió cómo se fija la profundidad del rayo).
`sim/tb_sv/tb_l1_ddc_range_tri.sv` (xsim real, corrida completa contra Vivado) se reconfirmó con
`bin_count` derivado del mismo `+mode=` de siempre — fine: 288/288/288 muestras en tolerancia D-12 y
TLAST bit a bit en los tres canales; coarse: 144/144/144 — las mismas cifras que ya medía D-14,
confirmando que el puerto nuevo no cambia ni un bit del comportamiento ya verificado bajo D-12.
`sim/tb/tb_drx_axil_regs.py` gana el mismo RW de 32 bits
completos que ya cubre PRF_DIV_LOW/HIGH, aplicado a BINS_LOW/HIGH, y su test de "dirección reservada"
se corrigió a `0x50` (0x48 ya no es reservado). `make check` en verde (108 tests).

Lo que esto NO hace, deliberadamente: no se corrió P&R con este cambio (lógica combinacional
adicional dentro de un módulo ya cerrado, de bajo costo — una comparación de 32 bits más por
instancia — la última cifra medida sigue siendo la de v4/D-09) y no toca el código de error del
contrato hacia el DSP (sigue siendo alcance de Z4, P-15).

### Z2 en v6 { #z2-en-v6 }

**25-sep-2026 (más tarde).** Cierra el BITE de tiempo muerto que [D-14](../alcance/decisiones.md#d-14)
dejaba explícitamente abierto: hasta esta sesión, un `ray_start` que descartaba un banco de
`drx_range_gate` a medias (tiempo muerto acumulado, o un PRI configurado más corto que `bin_count`)
lo hacía en completo silencio — nada en el mapa de registros distinguía eso de la operación normal
(el wrap natural del propio conteo de bins).

Decisiones de esta sesión:

- **El latch vive en `drx_range_gate`, no en `drx_axil_regs` — mismo criterio que STATUS/overrun,
  no que OVERFLOW/TIMING_STATUS.** `drx_range_gate` ya conoce `wr_ptr` ciclo a ciclo; recalcular la
  misma condición un nivel arriba, a partir de señales derivadas, sería duplicar lógica sin
  necesidad. Puerto nuevo por canal: `ray_truncated` (salida, sticky) y `clear_truncated` (entrada,
  write-1-to-clear).
- **`clear_truncated` es un puerto PROPIO, no reutiliza `clear` (el de `overrun`).** Son dos
  diagnósticos distintos con registros distintos del mapa (STATUS vs. GATE_TRUNCATED); si
  compartieran el mismo `clear`, limpiar uno limpiaría el otro sin que firmware lo pidiera.
- **GATE_TRUNCATED es un registro propio (offset nuevo, 0x50), no bits nuevos de STATUS.** Mismo
  argumento que ya separó OVERFLOW de STATUS en v2: son fuentes y semánticas distintas, aunque el
  patrón sticky+W1C sea idéntico.
- **La condición de disparo NO es simplemente `wr_ptr != 0`.** Un `ray_start` que coincide con el
  ciclo exacto en que el banco se completa por cuenta propia (`s_valid && wr_ptr == last_idx`) deja
  `wr_ptr` en `last_idx` (no en 0) hasta que esa misma asignación no bloqueante "se ve" — leerlo tal
  cual habría marcado como truncamiento un wrap perfectamente normal. La condición real es "`wr_ptr`
  != 0 Y el banco no se completa por cuenta propia este mismo ciclo" — ver la cabecera de
  `rtl/drx_range_gate.sv` para el razonamiento completo. Se encontró exactamente este falso positivo
  al correr L0 la primera vez (`test_ray_truncated_no_se_dispara_en_wrap_natural`), no por
  inspección.
- **`schema_version` sube a 6** por el mismo criterio que las subidas anteriores: un registro nuevo
  que firmware necesita poder detectar (offsets 0x54 en adelante siguen reservados).

Verificación: es una característica de interlock de hardware, no un bloque numérico con oráculo de
valores — mismo argumento que ya justificaba no tener modelo dorado para `ray_start`/D-14. Tres
tests L0 nuevos en `sim/tb/tb_drx_range_gate.py` (un `ray_start` alineado con el wrap natural NO
dispara `ray_truncated`; uno que descarta un banco con datos reales a medias SÍ lo dispara y es
sticky; `clear_truncated` lo limpia y permite un segundo disparo, con el mismo set-gana-sobre-clear-
concurrente que ya prueba `overrun`) — 11/11 tests del módulo en verde. `sim/tb/tb_drx_axil_regs.py`
gana el mismo patrón de lectura directa + pulso de clear que ya cubre STATUS, aplicado a
GATE_TRUNCATED, y su test de "dirección reservada" se corrigió a 0x54 (0x50 ya no lo es).
`sim/tb_sv/tb_l1_ddc_range_tri.sv` gana una comprobación nueva (`$fatal` si `ray_truncated` se
dispara alguna vez con `ray_start` atado a 0 en toda la cadena) y se reconfirmó completa contra xsim
real (`clear_truncated` atado a 0): fine, 288/288/288 muestras en tolerancia D-12 y TLAST bit a bit
en los tres canales; coarse, 144/144/144 -- las mismas cifras que ya medía D-15, sin ningún
`ray_truncated` espurio en ninguno de los dos modos. `make check` en verde (108 tests, mismo
número: son sub-tests de cocotb).

Lo que esto NO hace, deliberadamente: no se corrió P&R con este cambio (mismo argumento que v5 —
lógica de bajo costo dentro de un módulo ya cerrado) y no toca el código de error del contrato hacia
el DSP (Z4, P-15). La instrumentación de jitter en fabric y los pines XDC de `trig_out` se
resolvieron aparte, la misma sesión, más tarde — ver [Deliberadamente fuera de v3](#deliberadamente-fuera-de-v3)
y `fases.md#z2`.

### Z4 en v7 { #z4-en-v7 }

**26-sep-2026, Z4.1.** Primera pieza de firmware/datapath planeada después de Z4.0 (empaquetador de
rayo + AXI DMA S2MM, ver `fases.md#z4`). `fases.md#z4` ya listaba "contador de trigger" como uno de
los metadatos que el firmware de ensamblado de rayos (Z4.4) tiene que adjuntar a cada rayo junto con
az/el, PRF, modo de pulso, ancho y timestamps — este registro es la fuente de hardware para ese dato,
antes de que exista el firmware que lo lea.

- **RO puro, sin sticky ni write-1-to-clear — a propósito, distinto de STATUS/OVERFLOW/
  GATE_TRUNCATED.** Los otros tres son diagnósticos (algo salió mal, y firmware necesita poder
  rearmarlos para ver el próximo evento). TRIG_COUNT no es un diagnóstico: es un contador monótono
  que firmware lee, no un latch que firmware limpia. Envuelve en 2^32 pulsos en vez de saturar.
- **Cuenta `pulse_trig`, no un pulso nuevo.** `drx_timing_engine.pulse_trig` ya es la señal que
  D-14 conecta a `ray_start` de `drx_range_gate_quad_top` — el mismo evento que arranca un rayo
  nuevo es el que este registro cuenta, así que el valor de TRIG_COUNT en el momento en que un rayo
  termina de escribirse en DDR (interrupción de fin de descriptor del AXI DMA, Z4.0) es directamente
  el índice de ese rayo. No hace falta ninguna señal nueva de `drx_timing_engine`.
- **`schema_version` sube a 7** por el mismo criterio que las subidas anteriores.

Verificación: `sim/tb/tb_drx_axil_regs.py` gana `test_trig_count_incrementa_por_pulso_y_es_solo_
lectura` — incrementa exactamente un pulso de `pulse_trig_in` por ciclo, no se mueve solo sin
pulsos, y una escritura no cambia nada (a diferencia de los registros W1C, ninguna dirección de
escritura tiene efecto sobre él). `make check` en verde. No se corrió P&R con este cambio — mismo
argumento que v5/v6: lógica de bajo costo (un sumador de 32 bits) dentro de un módulo ya cerrado, sin
tocar ningún camino crítico.

### Z4 en v8 { #z4-en-v8 }

**1-oct-2026, Z4.3.** `CTRL` bit 1 pasa a ser `vector_source_ddr`, el selector entre los dos modos de
fuente de muestras de [la tabla de `fuente-de-muestras.md`](../plataforma/fuente-de-muestras.md):
BRAM-loop (0, valor de reset) y Throttled(DDR) (1).

- **Un bit que v1–v7 declaraban "reservado, lee 0".** Por eso sube la versión: redefinir un bit que
  el mapa prometía siempre a cero es un cambio de semántica visible desde firmware, no solo de RTL
  interno. Mismo criterio exacto que v4, que hizo lo propio con dos bits de TIMING_STATUS.
- **Sin registro nuevo.** Es un único bit de modo, del mismo tipo que `mode_coarse` y con la misma
  regla de uso: solo es seguro cambiarlo con la cadena parada, porque `vector_source` no vacía el
  conjunto de N_CH muestras a medio llenar al conmutar.
- **Qué desbloquea.** Hasta v8 el vector que reproducía la PL quedaba fijado en tiempo de SÍNTESIS
  (`$readmemh` sobre la BRAM, `tools/gen_vector_source_init.py`), así que barrer el catálogo de ocho
  casos de `tools/gen_l1_vectors.py` costaba ocho corridas de Vivado. Con este bit más el canal MM2S
  del AXI DMA, el vector se elige en tiempo de ejecución con el mensaje `test_stimulus_select` del
  contrato (v0.5) y cuesta un DMA.

Verificación: `sim/tb/tb_drx_axil_regs.py` gana `test_ctrl_vector_source_ddr_rw`, que comprueba
explícitamente que los bits 0 y 1 son **independientes** — los dos salen de la misma escritura a
CTRL, así que un desplazamiento de un bit en el RTL dejaría a `mode_coarse` siguiendo al selector de
fuente, y en placa eso se vería como "la decimación cambia sola al activar el modo DDR", un síntoma
que no apunta a este registro. De paso, `REGS_VERSION` en ese testbench pasa a leerse de
`config/registers.toml` en vez de estar clavado: los OFFSETS siguen siendo literales (si alguien
mueve un registro, el test tiene que decirlo), pero la VERSIÓN es un contador cuyo valor fijo solo
hacía que cada bump rompiera el test sin informar de nada. P&R re-corrido con el cambio completo de
Z4.3 (DMA MM2S incluido): **WNS = 1,634 ns**, bajando desde 1,711 ns.

### Z4 en v9 { #z4-en-v9 }

**2-oct-2026, Z4.5.** `NCO_PINC` (`0x58`, RW, 32 bits): la palabra de incremento de fase del NCO,
escribible en tiempo de ejecución. Es la actuación AFC, y hasta v8 era **imposible** — no por falta
de firmware, sino porque el incremento vivía congelado en la personalización de la IP
(`Phase_Increment {Fixed}` en `tcl/gen_ip.tcl`) y el core no exponía **ningún** puerto por el que
cambiarlo.

- **La IP se regeneró con `Phase_Increment {Programmable}`.** Medido sobre la IP generada de verdad,
  no supuesto: el cambio añade `s_axis_config_tvalid` + `s_axis_config_tdata[31:0]` y no mueve nada
  más — `Latency` sigue en 9, `Phase_offset` sigue `{Fixed}` con el mismo `POFF1`, `Noise_Shaping`
  sigue en Taylor. Por eso `NCO_LUT_OFFSET_K` (el desfase de arranque de 655 posiciones de LUT que
  documenta `tcl/gen_ip.tcl`) **no** se recalibra a ciegas: la matriz de 16 corridas de D-12 es la
  que tiene la última palabra y se vuelve a correr entera tras el cambio.
- **PINC1 deja de ser "el" incremento y pasa a ser el VALOR INICIAL tras `aresetn`.** Eso es lo que
  mantiene válido el camino sin AFC: `drx_ddc_top` no escribe ninguna configuración al arrancar,
  sólo cuando este registro se lo pide, así que un sistema que nunca escriba aquí se comporta
  exactamente como v8.
- **El canal de configuración no tiene TREADY** (`Has_TREADY {false}` vale para todas las interfaces
  del core), así que un pulso de un ciclo basta y no hay handshake que esperar. Lo único que
  `drx_ddc_top` tiene que respetar es su propio estirador de reset de 512 ciclos: una escritura que
  llegue con el core todavía en reset queda **pendiente** y se emite en cuanto `ip_rst_n` sube, en
  vez de perderse en silencio.
- **Una sola palabra para los `N_CH` canales.** Un retune que moviera sólo uno los dejaría
  desalineados en frecuencia, y no hay ningún caso de uso que lo pida.
- **Sin continuidad de fase en el salto.** El acumulador sigue desde donde estaba con el incremento
  nuevo. Es el mismo criterio que `mode_coarse` y por el mismo motivo: la corrección se aplica
  **entre rayos** (`apply_at_seq` del mensaje `afc`), nunca dentro de uno, así que la discontinuidad
  cae en una frontera donde a nadie le importa.

- **El strobe va REGISTRADO, y eso no es un detalle de estilo.** Los `*_clear` de este mismo módulo
  son combinacionales desde `write_commit` y están bien así, porque leen `wdata_r` directamente: el
  dato que acompaña al pulso ya es el bueno. `nco_pinc_we` no puede serlo. Su consumidor
  (`drx_ddc_top`) latchea `nco_pinc` con el flanco en que ve el pulso, y `nco_pinc_r` no vale lo
  nuevo hasta el final de ese ciclo. Con el strobe combinacional, **el DDC se llevaba la palabra de
  la escritura anterior**. Un ciclo de retardo alinea el pulso con el dato. Medido en placa, no
  deducido — ver el hallazgo del 2-oct-2026 en [fases.md](fases.md#z4).

Verificación en L0: `sim/tb/tb_drx_axil_regs.py` gana
`test_nco_pinc_arranca_en_nco_phase_inc_y_pulsa_al_escribir`, que separa las cuatro cosas que
importan —valor de reset, lectura/escritura, strobe y **alineación del strobe con el dato**— porque
fallan por motivos distintos. El strobe tiene que durar **uno** y pulsar en **cada** escritura,
incluso si el valor no cambia: un pulso largo le metería la misma configuración varias veces al
core, que no tiene TREADY con el que rechazarlas.

La cuarta comprobación se añadió **después** de que el bug saliera en placa, y es la lección del
episodio: contar pulsos no bastaba. El strobe duraba un ciclo y el registro acababa en el valor
correcto —las dos cosas que el test comprobaba— y aun así el consumidor se llevaba la palabra
equivocada. El test de ahora muestrea `nco_pinc` **en los ciclos en que `nco_pinc_we` está alto** y
exige que ya valga lo nuevo; comprobado que falla contra el RTL anterior y pasa contra el corregido.

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

## Deliberadamente fuera de v3

- **Validación de D-09/D-13 al nivel del registro — completa desde el 25-sep-2026 (D-15), sin subir
  el mapa por el check de PRF, pero SÍ por el techo de bins.** Ver [Z2 en v4](#z2-en-v4)/
  [Z2 en v5](#z2-en-v5). `PULSE_WIDTH` fuera de tabla, que no quepa en su PRI, un `PRF_DIV_LOW`/
  `PRF_DIV_HIGH` que dé un rango no ambiguo ilegal, y un `BINS_LOW`/`BINS_HIGH` que supere la
  profundidad física de BRAM — los cuatro se rechazan en RTL (`drx_timing_engine` no corre el
  secuenciador de lotes mientras cualquiera sea cierto, y lo reporta en TIMING_STATUS bits 1/2). El
  piso de rango sigue siendo un PARÁMETRO (no registro) de `drx_timing_config_valid.sv` (460 km /
  115 km, invariante de `config/params.toml`) — por eso ESE check no subió el mapa. El conteo de
  bins en sí SÍ es un registro nuevo (BINS_LOW/HIGH, v5): a diferencia del piso de PRF, es un valor
  configurable en runtime (viene de DSP/RCP según el VCP), no un requisito fijo. Lo único que sigue
  sin decidirse: qué código de error del contrato reportar hacia el DSP — eso sigue siendo alcance
  de Z4 (firmware, ver P-15).
- **Pines XDC / P&R real para `trig_out`.** Ver [Z2 en v3](#z2-en-v3). **Resuelto, 25-sep-2026 (más
  tarde):** Pmod JA (`Y11`/`AA11`/`Y10`/`AA9`), P&R reconfirmado en `tcl/xdc/zedboard.xdc`/
  `zedboard_zynq.xdc` — ver `fases.md#z2`, entrada correspondiente.
- **El lado del contrato de [P-15](../alcance/pendientes.md#p-15).** `contract/schema/
  drx_dsp_v0_1.toml` sigue con un solo `prf_div`/`pulse_width_idx`, sin campos para 2 lotes.
- **Conmutación en caliente fino/grueso** — cerrado como no-requisito, 21-sep-2026, no diferido:
  `mode_coarse` sigue siendo estático durante una corrida a nivel de RTL (`drx_ddc_top`, único
  consumidor desde v5/D-15 — ya no llega a `drx_range_gate`), aunque se pueda escribir en tiempo de
  ejecución. Confirmado por vladimir que esto no hace falta — la resolución de celda solo cambia
  entre rayos distintos, nunca a mitad de uno, así que el mux estático que ya existe cubre el caso
  de uso real sin necesitar continuidad de fase. Detalle en `fases.md#z1`, entrada del 21-sep.

## Verificación

- **L0 (Verilator/cocotb, corre en cualquier entorno con Verilator)**: `sim/tb/tb_drx_axil_regs.py`
  cubre VERSION de solo lectura, CTRL read/write y su efecto en `mode_coarse`, STATUS y OVERFLOW
  (lectura, pulso de write-1-to-clear, y para OVERFLOW específicamente: que el sticky sobrevive
  aunque la fuente vuelva a 0, que rearma tras un clear, y que un set concurrente con un clear
  gana), que las direcciones reservadas lean 0 sin efecto de escritura, y — añadido en v3 —
  TIMING_CTRL read/write, TIMING_STATUS (mismo sticky/W1C/set-gana que OVERFLOW pero sobre
  `radial_done_in`), PRF_DIV_LOW/HIGH de 32 bits completos, el empaquetado low/high de
  PULSE_WIDTH/N_PULSES, y los 4 canales de TRIG_DELAY/TRIG_WIDTH sin pisarse entre sí.
  `sim/tb/tb_drx_range_gate.py` añade la prueba directa del nuevo puerto `clear` de
  `drx_range_gate` al nivel del propio módulo. — Añadido en v4 (D-09): nuevo
  `sim/tb/tb_drx_timing_config_valid.py`, barrido bit a bit contra el oráculo
  `batch_config_valid` del modelo dorado; `tb_drx_timing_engine.py` gana el caso de un lote
  inválido congelando el motor completo; `tb_drx_axil_regs.py` gana el mismo sticky/W1C/set-gana
  de OVERFLOW aplicado a TIMING_STATUS bits 1/2. `make sim` / `make check` los corren — 104 tests
  de pytest en verde (`test_l0_timing_config_valid.py` es entrada nueva; los demás sub-tests de
  v4 viven dentro de `test_l0_timing_engine.py`/`test_l0_axil_regs.py` ya existentes, no suman
  entradas). `make lint-hdl` (Verilator, `--top-module drx_top` sobre el `filelist.f` completo)
  también cubre v4: es lo único que ejercita hoy la instanciación real de `drx_timing_engine`
  dentro de `drx_top.sv`.
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
  registros 8,33 %, BRAM Tile 21,07 %, **DSP48 111/220 (50,45 %) — esta es la cifra correcta para
  presupuesto de recursos.** La comparación inicial contra el 153/220 del 19-sep resultó ser entre
  dos etapas distintas (síntesis contra rutamiento), no entre dos builds distintas — dentro de esta
  misma corrida, post-síntesis también mide 153/220 y cae a 111/220 recién en el rutamiento, toda la
  caída dentro de las seis instancias de `fir_compiler_halfband`. Detalle completo en
  [`fases.md#z1`](fases.md#z1), entrada del 20-sep (más tarde). El primer intento de este P&R falló
  en `place_design` por el problema de pines descrito arriba, antes de la corrección.
- **P&R del puente PS7↔AXI, 20-sep-2026 (más tarde)** (`-top zynq`, `drx_zynq_top` con PS7 real):
  **WNS = 1,712 ns, WHS = 0,033 ns** ("All user specified timing constraints are met"), reloj
  `clk_fpga_0` a 62,5 MHz derivado del propio PS7, sin `create_clock` manual. Utilización post-route:
  LUT 10,83 %, registros 12,23 %, BRAM Tile 21,07 %, DSP48 159/220 (72,27 %) — a diferencia de la
  build sin PS7, aquí el DSP48 **no cayó** entre síntesis y rutamiento (159 en las dos etapas); la
  optimización de `opt_design` que eliminó los DSP48 de coeficiente cero de `fir_compiler_halfband`
  en la otra build no se repitió aquí de forma determinista — dato observado, sin explicar más a
  fondo (no bloquea nada, ver [`fases.md#z1`](fases.md#z1)).
- **P&R re-confirmado tras los pines XDC de `trig_out`, 25-sep-2026 (más tarde, v6)** — primera vez
  que `place_design` corre con esos 4 pines restringidos a sitios concretos (Pmod JA) en vez de
  dejar que Vivado los coloque libremente: `-top drx_top`, **WNS = 2,527 ns, WHS = 0,032 ns**
  (cierra, prácticamente igual que la última cifra medida sobre este top); `-top zynq`,
  **WNS = 1,295 ns, WHS = 0,012 ns** (cierra, pero es la cifra más ajustada medida hasta hoy sobre
  este top — ver [`fases.md#z2`](fases.md#z2), entrada correspondiente, para la tendencia completa
  y por qué merece vigilarse).
