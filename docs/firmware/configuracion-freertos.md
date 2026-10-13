# Configuración de FreeRTOS y BSP

El entorno de ejecución del firmware de LAMULA DRx se genera automáticamente mediante scripts TCL a través del producto **Xilinx Software Development Tool (XSCT)**. Esta página describe la configuración del kernel de **FreeRTOS v10.4** y de la biblioteca de red **lwIP v2.1.1** definidas en el Board Support Package (BSP).

## Configuración del BSP (`tcl/gen_bsp.tcl`)

El script `tcl/gen_bsp.tcl` construye el espacio de trabajo de Vitis y genera dos dominios de software sobre el mapa de hardware exportado en el archivo `.xsa`:

1. **`standalone_domain`:** Sistema *bare-metal* para compilar el First Stage Boot Loader (`fsbl.elf`).
2. **`freertos_domain`:** Entorno FreeRTOS 10 con la biblioteca `lwip211` para la aplicación principal (`drx_app.elf`).

```tcl
# Extracto de tcl/gen_bsp.tcl
domain create -name freertos_domain -os freertos10_xilinx -proc ps7_cortexa9_0
domain active freertos_domain
bsp setlib -name lwip211

# Parámetros del Kernel y lwIP
bsp config tick_rate 1000
bsp config api_mode SOCKET_API
bsp config lwip_dhcp false
bsp config dhcp_does_arp_check false
bsp config ipv6_enable false
bsp config pbuf_pool_size 2048
```

---

## Parámetros Clave del Kernel FreeRTOS

| Parámetro / Macro | Valor | Justificación TÉcnica |
|---|---|---|
| **`configTICK_RATE_HZ`** | `1000` (1 kHz) | Aumentado desde los 100 Hz por defecto. Permite una resolución temporal de 1 ms (`pdMS_TO_TICKS(1) = 1`). Esto es necesario para realizar sondeos de alta frecuencia en la PL sin degradar el rendimiento con retardos de 10 ms. |
| **`configUSE_PREEMPTION`** | `1` | Preempción activada. Garantiza que cuando la ISR del DMA despierte a la tarea `drx_ray` (prioridad 2), esta desalojo inmediatamente a cualquier tarea de menor prioridad. |
| **`configMAX_PRIORITIES`** | `8` | Opciones de prioridad de `0` (Idle) a `7`. La aplicación utiliza prioridades 1 y 2. |
| **`configTOTAL_HEAP_SIZE`**| `65536` B (64 KB) | Tamaño del mapa de memoria dinámica gestionado por `heap_4.c`. |
| **`configCHECK_FOR_STACK_OVERFLOW`** | `2` | Verificación activa de desbordamiento de pila en cambios de contexto. |

---

## Configuración de la Pila de Red lwIP (v2.1.1)

lwIP opera en modo **Sockets API** (`SOCKET_API`), habilitando un entorno de sockets multithread estándar (`lwip_socket`, `lwip_bind`, `lwip_listen`, `lwip_accept`, `lwip_recv`, `lwip_send`).

### Parámetros de Red
- **Modo de Asignación IP:** IP Estática (`lwip_dhcp = false`).
- **Dirección IP de la Placa:** `192.168.1.10` / Máscara: `255.255.255.0` / Gateway: `192.168.1.1`.
- **Puerto de Escucha del Contrato:** `5000` (`DRX_DSP_TCP_PORT`).
- **Pool de Pbufs (`pbuf_pool_size`):** Configurado en `2048` buffers para absorber ráfagas de datos en la interfaz Gigabit Ethernet sin perder tramas.

---

## Hooks de Diagnóstico en FreeRTOS

El firmware implementa funciones *hook* para atrapar fallos catastróficos durante el desarrollo:

1. **`vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName)`:**
   Se dispara si una tarea supera su tamaño de pila asignado. Imprime por UART el nombre de la tarea responsable y congela el sistema para evitar la corrupción de memoria en DDR3.
2. **`vApplicationMallocFailedHook(void)`:**
   Se dispara si `pvPortMalloc()` no puede asignar la memoria solicitada en el heap de FreeRTOS.
