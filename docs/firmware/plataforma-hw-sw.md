# Plataforma Hardware/Software (ZedBoard, Zynq-7000, PS/PL)

El sistema LAMULA DRx se implementa actualmente sobre la placa de desarrollo **Digilent ZedBoard**, equipada con un SoC **Xilinx Zynq-7000 (XC7Z020-CLG484-1)**. El Zynq-7000 integra en un solo chip un sistema de procesamiento basado en ARM dual-core (PS) y una matriz de lógica programable FPGA Artix-7 (PL).

## Arquitectura del Zynq-7000 en LAMULA DRx

El SoC Zynq-7000 se divide claramente entre el subsistema de procesamiento por software y la lógica de hardware configurable:

```
+----------------------------------------------------------------------------------+
|                                  ZYNQ-7000 SoC                                   |
|                                                                                  |
|  +-------------------------------------+    +---------------------------------+  |
|  |     Processing System (PS7)         |    |     Programmable Logic (PL)     |  |
|  |                                     |    |                                 |  |
|  |  +-------------------------------+  |    |  +---------------------------+  |  |
|  |  | Cortex-A9 Core 0 (FreeRTOS)   |  |    |  | drx_top (62.5 MHz)       |  |  |
|  |  +-------------------------------+  |    |  |                           |  |  |
|  |  | GIC pl390 Interrupt Control   |  |    |  | - vector_source (BRAM)    |  |  |
|  |  | DDR3 Controller (512 MB)      |  |    |  | - drx_ddc_quad_top        |  |  |
|  |  | Gigabit Ethernet (GEM0)       |  |    |  | - drx_range_gate_quad_top |  |  |
|  |  | UART1 Console (115200)        |  |    |  | - drx_timing_engine       |  |  |
|  |  +-------------------------------+  |    |  | - drx_ray_packer          |  |  |
|  |                                     |    |  | - drx_axil_regs v11       |  |  |
|  |  +-------------------------------+  |    |  +---------------------------+  |  |
|  |  | AXI GP0 Master (Control)      |==|====|=>| AXI-Lite Regs (0x43C00000)  |  |  |
|  |  | AXI GP0 Master (DMA Control)  |==|====|=>| AXI DMA Regs  (0x40400000)  |  |  |
|  |  | AXI HP0 Slave  (Data Import)  |<=|====|==| AXI DMA S2MM Data (DDR3)    |  |  |
|  |  | IRQ_F2P[0] Line (IRQ ID 61)   |<=|====|==| s2mm_introut Interrupt      |  |  |
|  |  +-------------------------------+  |    |  +---------------------------+  |  |
|  +-------------------------------------+    +---------------------------------+  |
+----------------------------------------------------------------------------------+
```

### 1. Processing System (PS)
- **CPU:** Dual ARM Cortex-A9 MPCore hasta 666 MHz (FreeRTOS se ejecuta en el Núcleo 0).
- **Memoria RAM:** 512 MB DDR3 (bus de 32 bits a 533 MHz) mapeados desde `0x00000000` hasta `0x1FFFFFFF`.
- **Memoria On-Chip (OCM):** 256 KB de SRAM de alta velocidad (`0xFFFC0000`), donde el FSBL arranca antes de inicializar la DDR.
- **Controlador de Interrupciones (GIC):** ARM Generic Interrupt Controller (pl390) que administra las interrupciones del PS y las líneas `IRQ_F2P` provenientes de la PL.
- **Periféricos MIO Usados:**
  - **Ethernet (GEM0):** Conectado al PHY Marvell 88E1518 de la ZedBoard mediante interfaz RGMII (pines MIO 16..27) y línea de administración MDIO (MIO 52..53).
  - **UART1:** Conectado a la interfaz USB-UART de la ZedBoard (MIO 48..49) configurado a 115200 baudios (8N1) para consola de log.

!!! warning "Hallazgo de Bring-up: VREF Interno y MUX de MDIO"
    Durante el bring-up de la plataforma (`tcl/gen_zynq_bd.tcl`), se descubrieron dos inconsistencias críticas en el *board file* estándar de Digilent:
    1. **VREF DDR3:** El archivo de preset de Digilent dejaba `PCW_UIPARAM_DDR_USE_INTERNAL_VREF = 0`, dejando la memoria DDR3 inestable. Se forzó en 1 en la generación del Block Design.
    2. **MIO MDIO Ethernet:** `PCW_ENET0_GRP_MDIO_IO` venía mapeado por defecto a EMIO (fábrica), aislando el PHY. Se re-enrutó explícitamente a `MIO 52 .. 53` para permitir que lwIP auto-negocie el enlace 1GbE.

### 2. Lógica Programable (PL)
- **FPGA:** Xilinx Zynq-7000 XC7Z020-CLG484-1.
- **Dominio de Reloj:** Un reloj único derivado del PS7 (`FCLK0`) opera a **62.5 MHz** (FS_HZ), alimentando tanto la interconexión AXI como toda la cadena de procesamiento de señales en `drx_top`.
- **Recursos Disponibles:** 53,200 LUTs, 106,400 Flip-Flops, 140 bloques BRAM de 36 Kb, y 220 slices DSP48E1.

---

## Interfaces Frontera PS/PL

La comunicación entre el código C en FreeRTOS y los módulos SystemVerilog en la PL se realiza a través de tres fronteras estándar AXI:

| Interfaz | Tipo AXI | Dirección Base / ID | Uso en LAMULA DRx |
|---|---|---|---|
| **AXI GP0 M00** | AXI4-Lite Master | `0x43C00000` | Acceso de lectura/escritura a los registros de control y estado de `drx_top` (`drx_axil_regs` v11). |
| **AXI GP0 M01** | AXI4-Lite Master | `0x40400000` | Control del motor Scatter-Gather del AXI DMA (`S_AXI_LITE`). |
| **AXI HP0** | AXI4 Slave 32-bit | `0x00000000` (DDR) | Transferencia DMA S2MM de alta velocidad desde `drx_ray_packer` a los buffers circulares en DDR3. |
| **IRQ_F2P[0]** | Interrupción Fabric | IRQ ID 61 (SPI) | Señal de fin de transferencia de rayo (`s2mm_introut`) proveniente del AXI DMA hacia el GIC. |

---

## Mapa de Memoria del Sistema (PS Space)

El espacio de direcciones visto por el procesador Cortex-A9 es el siguiente:

```
+------------------------+ 0x00000000
|                        |
|  Memoria RAM DDR3      | (512 MB - Programa C, Heap FreeRTOS y Buffers DMA)
|                        |
+------------------------+ 0x1FFFFFFF
|  Reservado / Perif PS  |
+------------------------+ 0x40400000
|  AXI DMA Control Regs  | (32 KB - S_AXI_LITE del AXI DMA)
+------------------------+ 0x43C00000
|  drx_top Registros AXI | (4 KB - Mapa v11 drx_axil_regs)
+------------------------+ 0xE0000000
|  Periféricos PS7       | (UART, GEM0, SDIO, GPIO PS)
+------------------------+ 0xF8000000
|  Registros SLCR PS7     | (Control de Relojes y Resets)
+------------------------+ 0xFFFC0000
|  On-Chip Memory (OCM)  | (256 KB - Usado por FSBL en el arranque)
+------------------------+ 0xFFFFFFFF
```

---

## Consideraciones para la Migración a Zynq UltraScale+ (ZU9)

Aunque el desarrollo actual corre sobre ZedBoard, la arquitectura del firmware respeta las siguientes abstracciones para la portabilidad a Zynq UltraScale+ ZU9:
- **`xparameters.h`:** Todas las direcciones base y números de interrupción se obtienen dinámicamente mediante las macros de Xilinx (`XPAR_M_AXI_REGS_BASEADDR`, `XPAR_AXIDMA_0_DEVICE_ID`).
- **Ancho de Bus AXI:** El canal DMA actual utiliza 32 bits de datos. En la ZU9 escalará a 64 o 128 bits sin modificar el código de la tarea `drx_ray`.
