# Bring-up físico de la ZedBoard

Proyecto desechable, ajeno al DRx. Su único objetivo es que, cuando se cargue el
diseño real, un fallo se pueda atribuir al diseño y no al cable, al driver, al
jumper o al terminal serie.

Cada escalón añade **una sola** capa nueva y tiene un criterio de paso. No se
avanza sin él: esa es toda la gracia.

| Escalón | Capa nueva | Si falla, el fallo está en |
|---|---|---|
| 0 | permisos y drivers del host | udev, grupos, ModemManager |
| 1 | cable y placa | alimentación, jumpers, JTAG |
| 2 | bitstream y pines de la PL | Vivado, XDC, reloj Y9 |
| 3 | PS, DDR, UART, descarga de ELF | `ps7_init`, BSP, `stdout` |
| 4 | AXI-Lite PS→PL (escritura) | interconnect, direcciones, reset |
| 4b | AXI-Lite PL→PS (lectura) | lo mismo, en la otra dirección |
| 5 | el diseño real del DRx | y solo entonces, el DRx |

## Por qué vive en `bringup/` y no en `rtl/`

`tools/check_hardcoded_clock.py` falla el CI ante cualquier literal decimal ≥ 1e6
en `rtl/`, `fw/`, `sim/`, `model/`, `tcl/` y `contract/`. Un divisor de reloj
necesita por definición una constante de reloj. `bringup/` queda fuera de ese
barrido. Nada de este directorio toca el DRx: `make check` tiene que seguir
pasando sin cambios.

## Los dos puertos serie, que no son lo que parecen

Verificado con `udevadm` en esta máquina:

- **`/dev/ttyACM0`** — `Cypress-USB2UART-0123456`. Es el USB-UART de la ZedBoard,
  cableado a **UART1 del PS** (MIO48/49). Esta es la consola.
- **`/dev/ttyUSB0`** — `Digilent USB Device`, serie `210248452965`, FTDI FT232H
  `0403:6014`. **No es un puerto serie del PL**: es el programador JTAG. Que
  aparezca como `ttyUSB` solo significa que `ftdi_sio` se enganchó al enumerarse.
  `hw_server` lo desengancha él mismo por libusb la primera vez que reclama el
  cable, y a partir de ahí el nodo `ttyUSB` desaparece. No lo abras nunca con un
  terminal serie.

La ZedBoard no tiene un segundo USB-UART. Una consola del lado PL exigiría un
AXI UARTLite más un dongle USB-TTL **de 3,3 V** en un Pmod. Fuera del alcance de
este proyecto.

---

## Escalón 0 — entorno del host

Requiere `sudo`. En este orden:

```sh
# 1. Drivers de cable JTAG (reglas udev: permisos sobre el nodo USB del cable).
#    OJO al `cd`: el script llama a sus ayudantes por ruta relativa.
cd "$XILINX_VIVADO/data/xicom/cable_drivers/lin64/install_script/install_drivers"
sudo ./install_drivers
cd -

# 2. Acceso al puerto serie
sudo usermod -aG dialout "$USER"

# 3. Terminal serie
sudo apt-get install -y picocom

# 4. Que ModemManager deje en paz el UART de la ZedBoard
sudo cp bringup/udev/99-zedboard-uart.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
```

El punto 1 **tiene que correrse desde su propio directorio**: `install_drivers`
invoca `./install_digilent.sh`, `./setup_xilinx_ftdi` y `./setup_pcusb` por ruta
relativa, y desde cualquier otro sitio falla con `not found` y `Return code = 1`.

La regla del punto 4 va como fichero versionado
(`bringup/udev/99-zedboard-uart.rules`) y no como un `printf | sudo tee` a
propósito: es una línea larga, y cualquier terminal que la parta deja a udev
descartando la primera mitad (`The line takes no effect, ignoring`) y aplicando
la segunda a **todos** los dispositivos del sistema, porque queda como una
asignación sin ninguna condición. Si alguna vez la escribes a mano, compruébala
con `cat -A`: un único `$`, al final.

Después: **desenchufa y vuelve a enchufar los dos cables USB de la placa**
(`J17` JTAG y `J14` UART). Tiene que ser un desenchufe físico, no
`udevadm trigger`: las reglas de Xilinx exigen `ACTION=="add"` y `trigger` emite
eventos `change`. Y **abre una sesión nueva** (o `newgrp dialout`) para que el
cambio de grupo tenga efecto.

Criterio de paso:

- `id` lista `dialout`.
- El nodo USB del JTAG está en modo `666`:
  `ls -l /dev/bus/usb/001/$(printf %03d $(cat /sys/bus/usb/devices/1-2/devnum))`
- `picocom -b 115200 /dev/ttyACM0` abre sin `Permission denied`.
- `udevadm control --log-priority=debug` no hace falta; si algo no casa,
  `udevadm test /sys/bus/usb/devices/1-2` enseña qué regla gana.

**`/dev/ttyUSB0` no lo quita ninguna regla udev.** Lo único que instala Xilinx
para este cable es

```
ACTION=="add", ATTR{idVendor}=="0403", ATTR{manufacturer}=="Digilent", MODE:="666"
```

es decir, permisos sobre el nodo USB, nada más: no hay `unbind` ni lista negra de
`ftdi_sio` en ningún sitio. Quien desengancha el driver del kernel es
`hw_server`, por libusb, la primera vez que abre el cable — y a partir de ese
momento `/dev/ttyUSB0` desaparece.

**Consecuencia práctica, y es la trampa de este escalón:** la *primera* corrida
de `xsct` después de un arranque en frío puede devolver `targets` y
`jtag targets` **vacíos**, porque `ftdi_sio` todavía tenía el cable. Repítela.
La segunda ya lista la cadena. Un primer intento vacío no es un fallo de
alimentación ni de jumpers; si el segundo también sale vacío, entonces sí.

Alternativa al punto 4 si no usas ningún módem:
`sudo systemctl mask --now ModemManager`.

### Supuestos físicos, a comprobar en la placa

1. Alimentada y encendida (`SW8`), con el USB de JTAG (`J17`) y el USB-UART
   (`J14`) conectados.
2. Jumpers de modo de arranque en **JTAG**: `MIO[6:2] = 00000`, que en la
   ZedBoard son `JP7`–`JP11`, todos al lado de GND. Contrástalo con el *ZedBoard
   Hardware User's Guide*; no está afirmado de memoria aquí.
3. `JP6` colocado si tu revisión lo requiere para alimentar el VCCO de los
   bancos de la PL.

---

## Escalón 1 — ver la placa, sin construir nada

```sh
xsct
  connect
  targets
```

**Criterio de paso:** la lista incluye un `xc7z020` y los dos
`ARM Cortex-A9 MPCore`.

**Repite el comando si la primera vez sale vacío** — ver la trampa de
`ftdi_sio` en el escalón 0. Si la segunda también sale vacía, vuelve a los
supuestos físicos y comprueba que el nodo USB del cable está en modo `666`.

---

## Escalón 2 — blinker de PL puro

Sin PS, sin DDR, sin UART, sin una línea de C.

```sh
vivado -mode batch -source bringup/tcl/build_blink.tcl
vivado -mode batch -source bringup/tcl/program.tcl -tclargs build/bringup/blink.bit
```

**Criterio de paso:** los ocho LEDs cuentan en binario, visiblemente. LD0 cambia
varias veces por segundo.

Prueba a la vez: drivers de cable, carga de bitstream, que el oscilador de `Y9`
vive, y que los LOC de los LEDs son correctos.

---

## Escalón 3 — «Hello World» del PS por el UART

Reutiliza el XSA que el repositorio ya produce, sin regenerarlo y sin tocar
`tcl/gen_bsp.tcl`.

El cuarto argumento `ocm` enlaza la aplicación a OCM (`ps7_ram_0`, 192 KiB) en
vez de a DDR. Fue obligatorio mientras la DDR no funcionaba; desde que el XSA
lleva `PCW_UIPARAM_DDR_USE_INTERNAL_VREF` (ver la sección de la DDR, más abajo)
ya no hace falta. Se conserva porque sigue siendo útil para aislar la DDR de
cualquier otro problema en una corrida de diagnóstico.

```sh
xsct bringup/tcl/gen_bringup_bsp.tcl \
  build/gw/zedboard_zynq/drx_zynq_top.xsa \
  bringup/src/hello.c hello ocm

# en otra terminal
picocom -b 115200 /dev/ttyACM0        # salir: Ctrl-A Ctrl-X

xsct bringup/tcl/run_jtag.tcl \
  build/gw/zedboard_zynq/drx_zynq_top.bit \
  build/bringup/hello.elf \
  build/gw/zedboard_zynq/drx_zynq_top.xsa
```

**Criterio de paso:** aparecen la cabecera y los `tick N` en `/dev/ttyACM0`. Los
`tick` importan: distinguen «arrancó y se colgó» de «arrancó y sigue vivo».

Prueba a la vez: el PS arranca, `ps7_init` deja los relojes y el MIO usables, el
`stdout` del BSP sale por UART1, y la descarga de ELF por JTAG funciona. **No**
prueba la DDR: el ELF se enlaza a OCM precisamente para sacar esa capa de aquí.

### Si no hace falta `picocom`

`sg dialout -c '...'` da acceso al puerto serie sin abrir una sesión nueva,
cuando el proceso que lanza los comandos arrancó antes del `usermod -aG
dialout`. Captura la consola a un fichero mientras corre `xsct`:

```sh
sg dialout -c 'stty -F /dev/ttyACM0 115200 raw -echo; timeout 45 cat /dev/ttyACM0 > build/bringup/uart.log' &
xsct bringup/tcl/run_jtag.tcl ...
wait; cat build/bringup/uart.log
```

### Dos trampas de `xsct` que costaron varias corridas

**`loadhw` no define `ps7_init`** en xsct 2022.2: falla con `invalid command
name "ps7_init"`. El procedimiento vive en `ps7_init.tcl`, dentro del propio XSA
(que es un zip). `bringup/tcl/run_jtag.tcl` lo extrae y lo carga solo.

**`rst -system` deja el DAP inalcanzable** hasta un apagado físico. En modo de
arranque JTAG resetea el SLCR y corta los relojes de depuración; sin imagen de
arranque válida la BootROM nunca los restaura. Síntoma:

```
DAP (APB AP transaction error, DAP status 0x30000021)
```

y `targets` deja de listar el APU y los dos A9. `rst -por` no existe para el
target `xc7z020`, y matar `hw_server` no arregla nada. Solo lo recupera `SW8`.
`run_jtag.tcl` usa `rst -cores`, que resetea los dos A9 sin tocar el SLCR.

---

## Escalones 4 y 4b — el contador en software que mueve los LEDs

Primer cruce PS → PL de este repositorio.

```sh
vivado -mode batch -source bringup/tcl/build_gpio.tcl

xsct bringup/tcl/gen_bringup_bsp.tcl \
  build/bringup/bringup_bd_wrapper.xsa \
  bringup/src/counter_leds.c counter_leds ocm

# en otra terminal
picocom -b 115200 /dev/ttyACM0

xsct bringup/tcl/run_jtag.tcl \
  build/bringup/bringup_bd_wrapper.bit \
  build/bringup/counter_leds.elf \
  build/bringup/bringup_bd_wrapper.xsa
```

**Criterio de paso del escalón 4, los dos a la vez:**

- Los LEDs cuentan en binario.
- El terminal imprime el mismo valor en la columna `led=`.

**Criterio de paso del escalón 4b:** mueve los switches y la columna `sw=` los
sigue. Esto valida el camino de **lectura**, del que depende
`DrxReg_SelfTest()` (`fw/src/app/drx_regs_hw.c:72-82`). Es una puerta aparte a
propósito: si la escritura va y la lectura no, el síntoma en el DRx sería
«VERSION devuelve basura», y no quieres diagnosticar eso por primera vez con el
diseño completo cargado.

Si `XGpio_Initialize` falla, comprueba el nombre del símbolo en el
`xparameters.h` que generó el BSP:

```sh
grep -n 'GPIO' build/bringup/vitis_ws/bringup_plat/*/*/bsp/*/include/xparameters.h
```

---

## Escalón 5 — primer bring-up real del DRx, todavía por JTAG

Ya no es demo. Usa lo que el repositorio ya produce, sin reconstruir nada.

```sh
# en otra terminal
picocom -b 115200 /dev/ttyACM0

xsct bringup/tcl/run_jtag.tcl \
  build/gw/zedboard_zynq/drx_zynq_top.bit \
  build/fw/zedboard/drx_app.elf \
  build/gw/zedboard_zynq/drx_zynq_top.xsa
```

**Criterio de paso:** `drx_status_task` imprime, y `DrxReg_SelfTest()` **no**
reporta mapa desincronizado — es decir, el `VERSION` leído del silicio coincide
con `DRX_REGS_VERSION`.

Dos cosas que esperar y no confundir con un fallo:

- `fw/src/app/main.c:241` llama a `DrxStatusTask_Create()` **antes** de
  `lwip_init()` (`:244`), así que la salida de estado aparece aunque no haya
  cable Ethernet.
- Sin Ethernet, el DHCP agota el tiempo y cae a `192.168.1.10/24`
  (`main.c:266-272`). Es el comportamiento diseñado.

Esto cierra el «bring-up físico pendiente» que Z4.2 dejó abierto, y evita por
completo el camino de `BOOT.BIN` (ver más abajo).

---

## La DDR de esta ZedBoard: un parámetro del preset, no un fallo de hardware

Encontrado y cerrado el 1 de octubre de 2026. La DDR3 de esta placa está sana.
Lo que estaba mal era un parámetro del PS7 que el board file de Digilent no fija.

**Causa raíz:** `apply_board_preset` contra `zedboard/1.3` **no** fija
`PCW_UIPARAM_DDR_USE_INTERNAL_VREF`. Ni `board.xml` ni `preset.xml` mencionan
VREF, así que el parámetro cae al default del IP `processing_system7_v5.5`, que
es 0 — VREF externo. En esta placa el VREF externo no llega al PHY, de modo que
el controlador completa su inicialización contra una referencia inexistente.

El preset propio de Xilinx para esta misma placa sí lo pone:
`processing_system7_v5_5/preset/ZedBoard.tcl:218`,
`CONFIG.PCW_UIPARAM_DDR_USE_INTERNAL_VREF {1}`.

**El arreglo**, una línea después de `apply_board_preset`:

```tcl
set_property -dict [list \
  CONFIG.PCW_UIPARAM_DDR_USE_INTERNAL_VREF {1} \
] [get_bd_cells $ps7]
```

Ya aplicado en `bringup/tcl/gen_bringup_bd.tcl`. **`tcl/gen_zynq_bd.tcl`
necesita el mismo cambio** — ver «Hallazgo abierto», más abajo.

### El síntoma, para reconocerlo otra vez

El controlador se declara inicializado y los datos no vuelven:

```
DDRC CTRL   0xF8006000 = 0x00000081     (arrancado)
DDRC STATUS 0xF8006054 = 0x00000121     (bits [2:0] = 1, modo normal)
DDRIOB DCI  0xF8000B74 = 0x0000291F     (DCI terminado)
  0x00100000  escrito=0x3C2C0000  leido=0x00000000  FALLA
  0x08000000  escrito=0x343C0000  leido=0xFFEDFFFF  FALLA
```

Las lecturas devuelven ruido flotante o ceros, y cambian entre corridas. El
acceso a `0x1F000000` llega a colgar el interconnect del PS; de ahí solo se sale
con `SW8`. Con el VREF interno activado, `DDRC STATUS` pasa a `0x00000001` — los
bits 5 y 8 de más son la pista barata.

### Cómo se aisló

La referencia independiente es el **ZedBoard OOB Design de Avnet (sep-2012)**,
`ZedBoard_OOB_Design.zip`. `digilent.com` devuelve 403 a `curl`; se recuperó del
Wayback Machine. Trae `sw/hw_platform/ps7_init.tcl` (el `ps7_init` original, de
origen distinto al nuestro), `boot_image/zynq_fsbl.elf` y `sd_image/` con el
`BOOT.BIN` y el Linux de fábrica. Trae además `sw/hw_platform/ps7_init.html`,
que documenta cada escritura campo a campo — es lo que permitió decodificar el
registro sin recurrir al UG585.

Secuencia de corridas, cada una desde un POR físico:

| Init aplicado | Resultado |
|---|---|
| `ps7_init` de Avnet (2012) | 6/6 OK, mapa completo hasta `0x1FFFFFF0`, ráfaga de 64 palabras sin fallos |
| El nuestro, sin bitstream cargado | 6/6 FALLA |
| El nuestro + los 16 registros de retardo de Avnet | Cuelga el bus en el primer acceso |
| El nuestro + los 22 de `ddr_init` + los 3 de `DDRIOB` | 6/6 OK |
| El nuestro + solo los 3 de `DDRIOB` | 6/6 OK |
| El nuestro + solo `0xF8000B6C` | **6/6 OK** |

Un registro: `DDRIOB_DDR_CTRL @ 0xF8000B6C`.

| campo | bits | Avnet `0xE09` | nuestro `0x260` |
|---|---|---|---|
| `VREF_INT_EN` | 0 | 1 | 0 |
| `VREF_SEL` | 4:1 | 4 | 0 |
| `VREF_EXT_EN` | 6:5 | 0 | 3 |
| `REFIO_EN` | 9 | 1 | 1 |
| `REFIO_TEST` | 11:10 | 3 | 0 |

### Hipótesis descartadas por el camino

Se dejan anotadas porque cada una costó una corrida, y porque la lista explica
por qué el diagnóstico tardó: todas las capas intermedias daban limpio.

| Hipótesis | Evidencia que la descarta |
|---|---|
| Camino JTAG → DDR roto, DDR sana | La sonda la ejecuta la CPU desde OCM, con `Xil_DCacheFlushRange`/`InvalidateRange` alrededor. Falla igual. |
| `ps7_init` aplica datos de silicio equivocados | `ps_version` devuelve `0x0` (silicio 1.0). Confirmado por dos vías: el IDCODE JTAG es `03727093` (revisión 0) y `hw_server` bloquea `0xF8006078`, registro que solo existe en silicio 3.0. |
| Configuración del PS7 del DRx en concreto | El XSA de bring-up usa `apply_board_preset` a secas y falla idéntico. El fallo está en el preset, no en el DRx. |
| SLCR bloqueado al escribir la DDR | `ps7_init.tcl` hace `mwr -force 0XF8000008 0x0000DF0D` al principio de cada sección. `LOCKSTA = 0x1` al final es normal. |
| Los retardos del `ps7_init` de Tcl (`mask_delay` a velocidad de JTAG) | El FSBL hace el mismo init compilado en C. Cambia el síntoma, no lo arregla. |
| MMU o cache del Cortex-A9 | El acceso por el AHB-AP del DAP (target `APU`) falla igual. |
| Alimentación de 12 V ausente | Confirmado puesto en J20. |
| Bypass de PLL por jumper | `0xF800010C = 0x3F`, los tres PLL enganchados; y la UART sale exacta a 115200 con `BAUD=0x7C`, `BDIV=6`. |
| Jumper mal puesto, en general | La DDR3 es del lado PS y está cableada fija: ningún jumper selecciona su tensión, su terminación ni su reloj. |
| Regulador de VTT / VCCO_DDR muerto | Era la hipótesis número 1 antes de la prueba A/B. La DDR pasa 6/6 con el mismo hardware y otra configuración, así que la alimentación está bien. |
| Integridad de señal en una placa de 2012 | Lo mismo: 0 fallos en 512 MiB. |
| Los 16 registros de retardo de DQS/DQ | Difieren de los de Avnet, pero sustituirlos solos no arregla nada. Son calibración de placa recalculada entre 2012 y el board file actual, no la causa. |

Los cuatro registros `DDRIOB_DATA0/1` y `DDRIOB_DIFF0/1` (`0xF8000B48`–`0x54`)
que releían con los bits 7 y 8 de más quedan explicados: son la zona de
`DCI_TYPE` y modo de buffer de entrada, y con el VREF mal configurado la
calibración de DCI converge a otro sitio. Era síntoma, no causa.

---

## Hallazgos abiertos, fuera del alcance de este directorio

### 1. `tcl/gen_zynq_bd.tcl` genera un PS7 con la DDR inservible

Mismo defecto que se arregló en `bringup/tcl/gen_bringup_bd.tcl`: el PS7 del DRx
se configura con `apply_board_preset` y nada más, así que
`PCW_UIPARAM_DDR_USE_INTERNAL_VREF` se queda en 0 y la DDR3 no retiene datos.
Verificado en placa el 1-oct-2026; detalle completo en la sección de la DDR, más
arriba.

Consecuencia directa: **todo lo que el repositorio ha producido hasta hoy para
ZedBoard —XSA, BSP, FSBL, `drx_app.elf`, `BOOT.BIN`— arranca sobre una DDR que
no funciona.** Nunca se detectó porque nada de eso se había ejecutado en silicio.

El arreglo es una línea en `tcl/gen_zynq_bd.tcl`, después de
`apply_bd_automation`:

```tcl
CONFIG.PCW_UIPARAM_DDR_USE_INTERNAL_VREF {1} \
```

Después hay que regenerar el XSA (`-top zynq -step xsa`) y, con él, BSP y
firmware. Queda fuera de este directorio por el alcance acordado; merece su
propio commit.

### 2. `tools/make_boot.sh` empaqueta el bitstream equivocado

`tools/make_boot.sh:22,31` empaqueta el bitstream equivocado:

```sh
gwdir="$repo_root/build/gw/$platform"
cp "$gwdir/drx_top_tieoff.bin" "$outdir/drx_top.bin"
```

`drx_top_tieoff` es el flujo **sin PS7**, con el AXI-Lite atado a valores
inertes. Pero el FSBL y `drx_app.elf` se compilan contra
`build/gw/zedboard_zynq/drx_zynq_top.xsa`, donde `m_axi_regs` sí existe. El
`BOOT.BIN` que produce el CI hoy lleva por tanto un bitstream en el que el
esclavo AXI que el firmware direcciona no está presente.

Lectura más probable: en placa, `DrxReg_SelfTest()` leería basura o colgaría el
bus. Lectura alternativa, menos probable: que el aviso de solapamiento de rangos
que `bootgen` ya emite esté relacionado — sin verificar.

Es un arreglo de una línea. Nadie lo ha detectado porque `BOOT.BIN` nunca se
arrancó. No bloquea nada de aquí porque el escalón 5 va por JTAG.

---

## Bitácora

Rellénala según pasen los escalones. Lo que no se escribió aquí no pasó.

| Escalón | Fecha | Resultado | Notas |
|---|---|---|---|
| 0 — entorno del host | 2026-10-01 | PASA | `install_drivers` hay que correrlo desde su directorio. La regla de ModemManager se partió en dos líneas al pegarla; de ahí que ahora viva en `bringup/udev/`. `MODE:="666"` se aplicó con `udevadm trigger --action=add --subsystem-match=usb`, sin desenchufar. |
| 1 — placa visible por JTAG | 2026-10-01 | PASA | `Digilent Zed 210248452965`, `arm_dap` idcode `4ba00477`, `xc7z020` idcode `03727093`, APU + 2× Cortex-A9 (Running). La primera corrida salió vacía: `ftdi_sio` tenía el cable. |
| 2 — blinker de PL | 2026-10-01 | PASA | `blink.bit` cargado, `End of startup status: HIGH`, `DONE = 1`, WNS = 7,235 ns. Confirmado a ojo: los ocho LEDs cuentan en binario. Primer bitstream de este repositorio que corre sobre silicio. |
| 3 — Hello World del PS | 2026-10-01 | PASA | Cabecera y `tick N` por `/dev/ttyACM0`, con el ELF **enlazado a DDR** y la sonda de DDR 5/5 OK ejecutada por la CPU, `0x1F000000` incluido. UART1 confirmada aparte escribiendo bytes a pelo en `0xE0001030`: llegó `JTAG\r\n` a 115200. Dos trampas de `xsct` resueltas (`loadhw` no define `ps7_init`; `rst -system` tumba el DAP). La primera corrida fue con el ELF en OCM porque la DDR parecía muerta; resultó ser `PCW_UIPARAM_DDR_USE_INTERNAL_VREF` sin fijar — sección propia más arriba. |
| 4 — contador → LEDs | | | |
| 4b — switches → terminal | | | |
| 5 — `drx_app` real | | | Desbloqueado el 1-oct-2026 al arreglar la DDR. Requisito previo: `tcl/gen_zynq_bd.tcl` necesita `PCW_UIPARAM_DDR_USE_INTERNAL_VREF {1}` y un XSA nuevo, o `drx_app` no tendrá memoria donde correr. |

## Alcance

Nada de esto valida JESD204B, el árbol de clocking, SYSREF, los 250 MSPS, el
frontal analógico, el DAC AD9129 ni la capa física RS-422. Lo que se gana es que
el camino de carga y depuración deja de ser una incógnita. En esta bitácora
corresponde escribir «verificado en ZedBoard», nunca «validado».
