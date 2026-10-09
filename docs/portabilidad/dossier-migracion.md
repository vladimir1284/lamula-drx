# Dossier de migración ZedBoard → ZU9

**Borrador del 8-oct-2026, para completar en [Z5](../implementacion/fases.md#z5).** Lista qué cambia
al pasar a la ZU9, fichero por fichero, y qué IP hay que regenerar. Complementa al [registro
delta](registro-delta.md): el registro dice *qué se comporta distinto*; este documento dice *dónde
hay que tocar*.

**Cómo se construyó, y su límite.** El mapa de ficheros sale de una búsqueda por `grep` sobre el
repositorio, no de una migración real. Se comprobaron a mano tres afirmaciones (guarda de
`tcl/build.tcl:69`, `bootgen -arch zynq` en `tools/make_boot.sh:67,71`, `ps7_cortexa9_0` en
`tcl/gen_bsp.tcl:55,58`); el resto son citas de la búsqueda y las líneas pueden haberse movido. Las
columnas «Cambio en ZU9» que dependen de cómo se comporta Vivado o Vitis con `zynq_ultra_ps_e` son
**inferencias, no medidas**: este Vivado 2022.2 no tiene instalado el device pack de UltraScale+
(A11 en [pendientes](../alcance/pendientes.md)), así que nada de esto se ha podido sintetizar.

## Requisito previo: decidir `fs`

Casi todo lo de abajo se mueve de golpe si [ADR-001](../alcance/adr-001-fs-r1-r2.md) se firma
(`fs` = 143,9 MHz en la ZU9). Migrar a ZU9 con el `fs` de D-04 (250 MHz) es posible, pero repite
la migración después. Léase la sección «Revisión del 8-oct-2026» del ADR antes de planificar.

## Qué no cambia

El camino de parámetros ya está preparado para las dos plataformas. `config/params.toml` tiene
`[platform.zu9]` con `fs_hz` y `part`; `tools/gen_params.py` emite los bloques `ifdef
DRX_PLATFORM_ZU9` (`rtl/generated/drx_params_pkg.sv`, `fw/include/drx_params.h`,
`tcl/generated/drx_params.tcl`); `fw/Makefile` ya acepta `PLATFORM=zu9`; `tcl/build.tcl` ya pasa
`-verilog_define DRX_PLATFORM_ZU9`; `gen_stimulus_catalog.py` ya conoce `zu9`. El RTL del datapath
(DDC, range-gate, motor de timing, packer) no nombra ninguna primitiva de 7-series: no hay ningún
`DSP48E1` escrito a mano en `rtl/`. Lo que cambia ahí es el presupuesto, no el código.

## Qué cambia, por directorio

### Bloque de PS y arranque (trabajo nuevo, el grueso)

| Fichero | Hoy | En ZU9 |
|---|---|---|
| `tcl/gen_zynq_bd.tcl` | `processing_system7:5.5`, claves `PCW_*` (VREF interno de DDR, MDIO en MIO 52–53, `S_AXI_HP0`, ancho 32) | `zynq_ultra_ps_e`, claves `PSU__*` distintas; nombres y anchos de puertos HP/HPC distintos. **Reescritura, no renombrado.** Los dos bugs de placa de la ZedBoard (VREF de DDR, MDIO del PHY) son específicos del preset de Digilent y **no se transfieren**; el equivalente en la ZU9 depende de la portadora, que no existe |
| `rtl/drx_zynq_top.sv` | envoltorio del BD con PS7 | envoltorio nuevo para el PS de UltraScale+ |
| `tcl/build.tcl:69-73` | `error` si `-top zynq` y plataforma ≠ zedboard | quitar la guarda, añadir el envoltorio de ZU9 |
| `tcl/gen_bsp.tcl:55,58` | dominios sobre `ps7_cortexa9_0` | `psu_cortexa53_0` (o R5, **decisión abierta**; D4 del registro delta) y revisar el dominio FreeRTOS |
| `tools/make_boot.sh:67,71` | `bootgen -arch zynq`, FSBL de Zynq-7000 | `-arch zynqmp`, BIF y FSBL/PMUFW distintos (inferencia) |
| `tools/build_vitis.sh:13-14` | `platform=zedboard` por defecto, XSA `*_zynq` | pasar `zu9` y el XSA nuevo |
| `fw/src/app/drx_ray.c:42-43` | `XPAR_FABRIC_DMA_S2MM_INTROUT_INTR` (61 en ZedBoard) | el ID de interrupción cambia; sale del BSP regenerado |
| `fw/src/app/drx_dma.c`, `drx_regs_hw.c` | `XPAR_*` del BSP | regenerar BSP; no se edita a mano |
| `fw/src/app/main.c:183,189` | EMAC de Zynq-7000 | GEM de la ZU9 (inferencia) |
| `fw/include/drx_ray.h`, `drx_ray.c` | comentario sobre `Xil_DCacheInvalidateRange`; no hay llamada viva en `fw/` | **verificar coherencia de caché en A53**: el A9 no tiene CCI y el A53 sí (D5). No se verificó que la ruta DMA→DDR→CPU siga siendo coherente sin invalidar |
| `rtl/drx_ray_packer.sv:12-13` | restricción del ancho de TDATA del AXI DMA S2MM | revisar contra el ancho de HP de la ZU9 (128 bits, D5) |

### Restricciones y pines

| Fichero | Hoy | En ZU9 |
|---|---|---|
| `tcl/xdc/zedboard.xdc`, `zedboard_zynq.xdc` | `PACKAGE_PIN` de reloj (Y9), reset (P16), LED (T22) y `trig_out` sobre Pmod JA (Y11/AA11/Y10/AA9) | XDC nuevo: pines salen de la portadora y del FMC213, que **no están elegidos** (P-02, P-03) |
| `rtl/drx_top.sv:61` | comentario: sin Pmod mapeado | mapa de pines de la ZU9; el SSI pasa de LVCMOS 3,3 V a RS-422 (D6) |

### Regeneración de IP

Las cuatro IP versionadas como XCI se regeneran contra `xczu9eg-ffvb1156-2-e` con `tcl/gen_ip.tcl
-platform zu9`. **Antes** hay que instalar el device pack de UltraScale+; sin él la regeneración
falla.

| IP | Versión | Notas para la regeneración |
|---|---|---|
| `ip/cic_compiler_ddc` | cic_compiler 4.0 | si ADR-001 se firma, `cic_rate` 52 → 30 |
| `ip/dds_compiler_nco` | dds_compiler 6.0 | `Phase_Increment` programable (Z4.5). Reverificar `NCO_LUT_OFFSET_K` = 655 (`tcl/gen_ip.tcl:180`) con la matriz de D-12 |
| `ip/fir_compiler_droop` | fir_compiler 7.2 | coeficientes dependen de `cic_rate`; salen de `make gen` |
| `ip/fir_compiler_halfband` | fir_compiler 7.2 | 6 instancias. El recuento de DSP48 de la ZedBoard (111/220) **no** predice el de la ZU9 (DSP48E2) |
| `ip_debug/drx_debug_ila` | ila 6.2 | `tcl/gen_ip_debug.tcl`, regenerar o retirar |

Los bloques del BD (`axi_dma:7.1`, `axi_interconnect:2.1`, `proc_sys_reset:5.0`,
`axi_protocol_converter:2.1`) son los mismos IP, pero hay que releer sus parámetros: anchos de HP y
`c_include_sg` se fijaron contra el PS7.

### CI

`.github/workflows/ci.yml:85-88` tiene `platform: [zedboard]`; `zu9` se sacó de la matriz por falta
del device pack. Volver a añadirla es lo último, tras instalarlo. Las etapas XSA/BSP/`BOOT.BIN`
(`ci.yml:116-130`) están condicionadas a `zedboard` y necesitan su variante.

### Throwaway: `bringup/`

La escalera de bring-up está atada a la ZedBoard de arriba abajo (`xc7z020`, `ps7_init`,
`ps7_cortexa9_0`, pines Y9/T22, consola `/dev/ttyACM0`). **No se porta; se reescribe** cuando llegue
la portadora, y las lecciones de [xsct/JTAG](../implementacion/fases.md#z4) no se transfieren sin
reverificar (`psu_init` en vez de `ps7_init`).

## Lo que ninguna migración de ficheros cubre

D1 (JESD204B, MGT, SYSREF), D8 (DAC AD9129) y D6 (SSI diferencial) son trabajo nuevo sin
equivalente en la ZedBoard; ver el [registro delta](registro-delta.md). Este dossier no los
estima: no hay fichero que cambiar porque todavía no existe el fichero.

## Lo que falta para cerrar este dossier en Z5

1. Instalar el device pack de UltraScale+ y comprobar que `gen_ip.tcl -platform zu9` regenera las
   cuatro IP. Hoy es una suposición.
2. Decidir A53 o R5 para el firmware (D4) antes de reescribir `gen_bsp.tcl`.
3. Anotar evidencia por entrada del registro delta (D1–D12), como pide ese documento.
4. Repetir la búsqueda de ficheros específicos de plataforma tras ADR-001, que añade las
   constantes de PRF y ancho de pulso a la lista.
