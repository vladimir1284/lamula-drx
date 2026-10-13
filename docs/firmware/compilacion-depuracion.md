# Cómo Compilar, Cargar y Depurar

Esta página proporciona las instrucciones necesarias para compilar el firmware desde los scripts del repositorio, generar la imagen de arranque `BOOT.BIN`, programar la placa ZedBoard y ejecutar herramientas de depuración mediante consola UART y JTAG.

## Flujo de Compilación Automática

El proceso de generación de binarios no requiere interactuar con la interfaz gráfica de Vivado ni Vitis; todo se ejecuta por línea de comandos mediante scripts TCL y Bash (disciplina D-07: "cero clics").

```
  +-----------------------+
  | tcl/gen_zynq_bd.tcl   |
  | rtl/drx_zynq_top.sv   |
  +-----------------------+
              |
              v (tcl/build.tcl -top zynq -step xsa)
  +-----------------------+
  | build/zynq.xsa        |
  | build/system.bit      |
  +-----------------------+
              |
              +-------------------------------------+
              |                                     |
              v (gen_stimulus_catalog.py)           v (xsct tcl/gen_bsp.tcl)
  +-----------------------+               +-----------------------+
  | drx_stimulus_catalog  |               | fsbl.elf              |
  | (.c / .h)             |               | drx_app.elf           |
  +-----------------------+               +-----------------------+
              |                                     |
              +------------------+------------------+
                                 |
                                 v (tools/make_boot.sh + boot.bif)
                      +---------------------+
                      | BOOT.BIN            |
                      +---------------------+
```

### Comandos de Compilación

1. **Generación de Paquetes y Catálogos:**
   ```bash
   make gen
   python3 tools/gen_stimulus_catalog.py --platform zedboard
   ```

2. **Síntesis e Implementación del Bitstream + Exportación XSA:**
   ```bash
   tclsh tcl/build.tcl -top zynq -step impl
   tclsh tcl/build.tcl -top zynq -step xsa
   ```

3. **Compilación del BSP, FSBL y Firmware con Vitis (XSCT):**
   ```bash
   ./tools/build_vitis.sh
   ```

4. **Embalaje de Imagen de Arranque BOOT.BIN:**
   ```bash
   ./tools/make_boot.sh
   ```
   El script utiliza la especificación BIF `tcl/boot/boot.bif` para empaquetar `fsbl.elf`, `system.bit` y `drx_app.elf` en el binario final `build/fw/zedboard/BOOT.BIN`.

---

## Carga y Ejecución en la ZedBoard

### Opción A: Arranque desde Tarjeta SD (Producción)
1. Formatea una tarjeta SD en FAT32.
2. Copia el archivo `build/fw/zedboard/BOOT.BIN` a la raíz de la tarjeta SD.
3. Configura los puentes de selección de arranque de la ZedBoard (`JP7`–`JP11`) en modo SD: `MIO[5:2] = 0110` (`JP7` a GND, `JP8` a GND, `JP9` a 3V3, `JP10` a 3V3, `JP11` a GND).
4. Inserta la tarjeta SD y enciende la placa con el interruptor `SW8`.

### Opción B: Carga Directa por JTAG (Desarrollo Rápido)
Puedes cargar la memoria y la PL directamente mediante el cliente de línea de comandos de Xilinx (XSCT):

```bash
xsct
# Dentro de la consola XSCT:
connect
targets -set -filter {name =~ "ARM*#0"}
rst -system
pb_init
fpga build/fw/zedboard/system.bit
dow build/fw/zedboard/drx_app.elf
con
```

---

## Métodos de Depuración

### 1. Consola UART de Log
Conecta un cable micro-USB al puerto `UART` de la ZedBoard. Abre una terminal serie configurada a **115200 baudios, 8 bits de datos, sin paridad, 1 bit de parada (8N1)**:

```bash
picocom -b 115200 /dev/ttyACM0
```

Un arranque exitoso mostrará la siguiente secuencia en consola:
```text
drx_timing: motor de timing iniciado correctamente
drx_stimulus: ventana v11 detectada
drx_ray: S2MM listo, 16 buffers de 44300 B
drx_ray: 231 rayos en 1000 ms, overrun=0x0 truncated=0x0
-----lwIP Socket Mode Echo server Demo Application ------
Board IP: 192.168.1.10
Netmask : 255.255.255.0
Gateway : 192.168.1.1
Server Port 5000 Connect With..
```

### 2. Congelamiento de Rayos e Inspección con Python (`dump_ray.py`)
Para verificar la exactitud bit a bit del datapath de la PL respecto al modelo dorado sin necesidad de recibir paquetes Ethernet:

1. El firmware congela un rayo en DDR3 invocando `DrxRay_Freeze()`.
2. Desde la máquina host, ejecuta el script de volcado por JTAG/UART:
   ```bash
   python3 tools/dump_ray.py --port /dev/ttyACM0
   ```
3. El script lee la dirección de memoria emitida por `DrxRay_DumpLast()`, descarga las muestras I/Q directamente desde la RAM y las compara contra el modelo matemático en `model/drx_model/`.
