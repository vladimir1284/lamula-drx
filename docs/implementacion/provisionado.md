# Provisionado de una placa limpia

**Arranque desde SD probado el 16-oct-2026** (borrador del 8-oct, actualizado con la evidencia). La
definición de terminado de [Z5](fases.md#z5) pide «una ZedBoard provisionada desde cero por un
`BOOT.BIN` construido por CI de forma reproducible». El primer intento destapó un bug de empaquetado:
`boot.bif` listaba el bitstream como `.bin` y bootgen lo guardaba como dato de PS, así que la PL
nunca se configuraba. Corregido en `639d709`; con el `.bit` la placa arranca sola y cumple el
criterio de aceptación de abajo. «Reproducible» sigue medido solo para dos empaquetados del mismo
`.bit`, no entre corridas de Vivado.

## Lo que sí está medido

| Paso | Estado | Evidencia |
|---|---|---|
| Construir el gateware (`-top zynq -step xsa`) | Hecho, en CI | job `ci`, runner `[self-hosted, vivado]` |
| Generar BSP/FSBL/`drx_app` | Hecho | `tools/build_vitis.sh` |
| Empaquetar `BOOT.BIN` reproducible | Hecho | `tools/make_boot.sh` (dos `bootgen` → mismo hash) |
| Cargar bitstream + firmware por JTAG | Hecho, repetidamente | `tools/cargar.sh`, `bringup/README.md` |
| Arrancar desde SD | Hecho, 16-oct-2026 | `BOOT.BIN` sha256 `de21ef14…`; `build/soak/20261016-230257/` |

## Procedimiento (ejecutado el 16-oct-2026)

1. **Artefactos.** Bajar el artefacto `gateware-zedboard` del job `ci`, o construir en local:
   `vivado -mode batch -source tcl/build.tcl -tclargs -platform zedboard -top zynq -step xsa`,
   luego `tools/build_vitis.sh` y `tools/make_boot.sh zedboard`. Comprobar `BOOT.BIN.sha256`.
2. **Tarjeta SD.** Una partición FAT con `BOOT.BIN` en la raíz. Una partición FAT (`vfat`) con `BOOT.BIN`
   en la raíz funcionó en esta placa.
3. **Jumpers de modo de arranque.** Poner la ZedBoard en modo SD. *Las posiciones no están en el
   repositorio: salen del manual de la ZedBoard rev. D.* Con `BOOT_MODE` (0xF800025C) = 5 el modo es SD.
4. **Consola.** `/dev/ttyACM0` a 115200 8N1 (**solo un lector**; ver `tools/soak.sh`). Es el
   USB-UART del PS, no el `ttyUSB0`, que es el JTAG.
5. **Enlace.** `tools/net_drx_link.sh` deja `enp1s0` en 192.168.1.1/24. El firmware fija
   192.168.1.10 (`fw/src/app/main.c:162`).
6. **Encender y comprobar**, por la UART y sin JTAG: línea `mapa de registros v11 confirmado por
   AXI-Lite`, `drx_status: red conectada`, y `ping 192.168.1.10`.
7. **Cliente.** `tools/mock_dsp.py --seconds 10`: rayos a ~223/s y 0 huecos de `seq`.

## Riesgos conocidos al arrancar desde SD

- **Todo artefacto de `build/` anterior al 1-oct-2026 es defectuoso** (VREF de DDR; bitstream
  equivocado en `make_boot.sh`). **Todo `BOOT.BIN` anterior al 16-oct-2026 también** (bitstream
  empaquetado como `.bin`, PL sin configurar). Reconstruir desde un árbol posterior.
- **Diagnóstico si el LED DONE no enciende:** `bootgen -arch zynq -read BOOT.BIN`. El bitstream debe
  salir con `attributes 0x20`; con `0x10` es el bug del `.bin`.
- **`ps7_init` por JTAG no es lo mismo que el FSBL.** Cargando por JTAG, `ps7_init` lo corre `xsct`;
  desde SD lo hace el FSBL. El 16-oct-2026 no apareció ningún ajuste que viviera solo en el flujo
  JTAG: DDR, MDIO/red y reloj de PL funcionaron desde el FSBL.
- **Reprogramar la PL con tráfico vivo cuelga HP0** y solo se sale con ciclo de alimentación. Si el
  arranque desde SD falla y se «recarga por JTAG» encima, aplica la misma regla de
  `tools/cargar.sh`: un solo intento.
- **Reloj de PL:** hoy 62,5 MHz. Si se firma ADR-001 cambia `fs` y todo `BOOT.BIN` se reconstruye.

## Criterio de aceptación

Placa sin ningún ELF cargado por JTAG, encendida con la SD, llega por sí sola a los pasos 6 y 7 y
sostiene al menos 10 minutos sin `dma_overruns`.

**Cumplido el 16-oct-2026:** pasos 6 y 7 sin JTAG, y `tools/soak.sh 660` con 147 442 rayos,
0 huecos de `seq` y `dma_overruns=0` (`build/soak/20261016-230257/`). Aviso de la cabecera de
`tools/make_boot.sh` retirado.
