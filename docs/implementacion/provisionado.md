# Provisionado de una placa limpia

**Borrador del 8-oct-2026. El arranque desde SD nunca se ha probado en ninguna ZedBoard.** La
definición de terminado de [Z5](fases.md#z5) pide «una ZedBoard provisionada desde cero por un
`BOOT.BIN` construido por CI de forma reproducible». Lo que existe hoy es la mitad: `BOOT.BIN` sale
reproducible byte a byte, y el firmware real se ha cargado **por JTAG** con `tools/cargar.sh`. El
paso intermedio, que la placa arranque sola desde una tarjeta SD, **no se ha ejecutado**
(`tools/make_boot.sh` lo dice en su cabecera).

## Lo que sí está medido

| Paso | Estado | Evidencia |
|---|---|---|
| Construir el gateware (`-top zynq -step xsa`) | Hecho, en CI | job `ci`, runner `[self-hosted, vivado]` |
| Generar BSP/FSBL/`drx_app` | Hecho | `tools/build_vitis.sh` |
| Empaquetar `BOOT.BIN` reproducible | Hecho | `tools/make_boot.sh` (dos `bootgen` → mismo hash) |
| Cargar bitstream + firmware por JTAG | Hecho, repetidamente | `tools/cargar.sh`, `bringup/README.md` |
| Arrancar desde SD | **No hecho** | — |

## Procedimiento propuesto (sin probar)

1. **Artefactos.** Bajar el artefacto `gateware-zedboard` del job `ci`, o construir en local:
   `vivado -mode batch -source tcl/build.tcl -tclargs -platform zedboard -top zynq -step xsa`,
   luego `tools/build_vitis.sh` y `tools/make_boot.sh zedboard`. Comprobar `BOOT.BIN.sha256`.
2. **Tarjeta SD.** Una partición FAT con `BOOT.BIN` en la raíz. *El formato exacto y el nombre del
   fichero son el estándar de Xilinx para Zynq-7000; no lo he verificado contra esta placa.*
3. **Jumpers de modo de arranque.** Poner la ZedBoard en modo SD. *No escribo las posiciones aquí:
   hay que sacarlas del manual de la ZedBoard rev. D, y el repositorio no las recoge.*
4. **Consola.** `/dev/ttyACM0` a 115200 8N1 (**solo un lector**; ver `tools/soak.sh`). Es el
   USB-UART del PS, no el `ttyUSB0`, que es el JTAG.
5. **Enlace.** `tools/net_drx_link.sh` deja `enp1s0` en 192.168.1.1/24. El firmware fija
   192.168.1.10 (`fw/src/app/main.c:162`).
6. **Encender y comprobar**, por la UART y sin JTAG: línea `mapa de registros v11 confirmado por
   AXI-Lite`, `drx_status: red conectada`, y `ping 192.168.1.10`.
7. **Cliente.** `tools/mock_dsp.py --seconds 10`: rayos a ~223/s y 0 huecos de `seq`.

## Riesgos conocidos al arrancar desde SD

- **Todo artefacto de `build/` anterior al 1-oct-2026 es defectuoso** (VREF de DDR; bitstream
  equivocado en `make_boot.sh`). Reconstruir desde un árbol posterior.
- **`ps7_init` por JTAG no es lo mismo que el FSBL.** Cargando por JTAG, `ps7_init` lo corre `xsct`;
  desde SD lo hace el FSBL. Si algún ajuste vivía solo en el flujo JTAG, aparecerá aquí. *No sé si
  hay alguno; es justo lo que este procedimiento comprobaría.*
- **Reprogramar la PL con tráfico vivo cuelga HP0** y solo se sale con ciclo de alimentación. Si el
  arranque desde SD falla y se «recarga por JTAG» encima, aplica la misma regla de
  `tools/cargar.sh`: un solo intento.
- **Reloj de PL:** hoy 62,5 MHz. Si se firma ADR-001 cambia `fs` y todo `BOOT.BIN` se reconstruye.

## Criterio de aceptación

Placa sin ningún ELF cargado por JTAG, encendida con la SD, llega por sí sola a los pasos 6 y 7 y
sostiene al menos 10 minutos sin `dma_overruns`. Si se cumple, se anota la fecha aquí y se retira el
aviso de la cabecera de `tools/make_boot.sh`.
