# Glosario de Firmware y RTOS

Este glosario define los términos técnicos, acrónimos y conceptos de sistemas embebidos, RTOS y lógica reconfigurable utilizados en la documentación del firmware de LAMULA DRx.

---

### A
- **AXI (Advanced eXtensible Interface):** Estándar de bus de comunicación de alto rendimiento desarrollado por ARM, utilizado para la interconexión de bloques IP dentro del SoC Zynq-7000.
- **AXI-Lite:** Variante simplificada del protocolo AXI4 diseñada para transferencias de control punto a punto de 32 bits, sin soporte para ráfagas (*bursts*).
- **AXI HP (High Performance):** Puerto AXI esclavo de alto ancho de banda en el PS7 que otorga a las IP de la PL acceso directo con baja latencia al controlador de memoria RAM DDR3.

### B
- **BITE (Built-In Test Equipment):** Conjunto de mecanismos de autodiagnóstico integrados en hardware y software para detectar, registrar y reportar fallos operativos (como desbordamientos o truncamiento de datos).
- **BSP (Board Support Package):** Capa de abstracción de software provista por Xilinx que contiene los *drivers* de dispositivo de bajo nivel y el código de inicialización para la plataforma hardware específica.

### D
- **DDC (Digital Down Converter):** Conversor digital descendente. Módulo de procesamiento digital de señales que traslada la señal de frecuencia intermedia (IF) a banda base compleja ($I/Q$) y reduce la tasa de muestreo mediante filtrado y decimación.

### F
- **FSBL (First Stage Boot Loader):** Primer programa ejecutado por la CPU tras la BootROM. Inicializa los relojes del PS, el controlador de memoria DDR3 y carga el *bitstream* de la FPGA antes de transferir el control a la aplicación principal.
- **FS_HZ:** Frecuencia de muestreo base del sistema radar (62.5 MHz en la implementación sobre ZedBoard).

### G
- **GIC (Generic Interrupt Controller):** Controlador genérico de interrupciones de arquitectura ARM (modelo pl390 en el Zynq-7000). Administra las fuentes de interrupción del PS y las líneas provenientes de la PL (`IRQ_F2P`).

### I
- **ISR (Interrupt Service Routine):** Rutina de servicio de interrupción. Función en C ejecutada en contexto de interrupción de hardware en respuesta a un evento del GIC.

### N
- **NCO (Numerically Controlled Oscillator):** Oscilador numéricamente controlado. Generador de señal senoidal y cosenoidal digital utilizado en el mezclador del DDC para sintonizar la frecuencia intermedia.

### P
- **PL (Programmable Logic):** Lógica Programable. Matriz de FPGA reconfigurable del SoC Zynq donde se implementan las IP de procesamiento DSP del radar.
- **Preempción:** Capacidad del kernel de FreeRTOS para suspender inmediatamente la ejecución de una tarea en curso al activarse otra tarea de mayor prioridad.
- **PRF (Pulse Repetition Frequency):** Frecuencia de repetición de impulsos del radar ($1/\text{PRI}$).
- **PRI (Pulse Repetition Interval):** Intervalo de repetición de impulso. Tiempo transcurrido entre dos disparos consecutivos del transmisor.
- **PS (Processing System):** Subsistema de procesamiento de silicio fijo del SoC Zynq, compuesto por los núcleos ARM Cortex-A9, controladores de memoria y periféricos MIO.

### S
- **S2MM (Stream-to-Memory-Mapped):** Modo de operación del AXI DMA que transfiere datos desde un flujo continuo AXI4-Stream en la PL hacia un espacio de memoria mapeado en la RAM DDR3 del PS.

### T
- **Tick:** Interrupción periódica generada por un temporizador de hardware que utiliza el kernel de FreeRTOS para medir el tiempo, gestionar retardos y realizar cambios de contexto. En este proyecto se configura a 1000 Hz (1 ms).

### W
- **W1C (Write-1-to-Clear):** Semántica de registros de estado en hardware donde la escritura de un bit en `1` limpia dicha bandera de error, mientras que escribir `0` no produce ningún efecto.

### Z
- **ZedBoard:** Placa de desarrollo basada en el SoC Xilinx Zynq-7000 (XC7Z020-CLG484-1), utilizada como plataforma de desarrollo y prototipado del receptor LAMULA DRx.
