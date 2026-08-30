# ZedBoard: frontera dura y cobertura alcanzable

**Plataforma:** Digilent ZedBoard (Xilinx XC7Z020-CLG484-1)
**Rol:** plataforma de desarrollo primaria mientras no exista hardware ZU9 + FMC213

## Lo que esta placa no puede cubrir

El XC7Z020 en empaquetado CLG484 **no expone transceptores gigabit**. Sin MGTs no hay JESD204B en
ninguna forma: ni PHY, ni establecimiento de link, ni alineación de lanes, ni SYSREF, ni latencia
determinista, ni sincronización multi-dispositivo. Adicionalmente el conector FMC de la ZedBoard es
**LPC**, y la VadaTech FMC213 requiere HPC con lanes de transceptor, de modo que la mezzanine
tampoco es acoplable físicamente.

!!! danger "El riesgo número uno recibe cero mitigación"
    El bring-up de JESD204B y del clocking es el riesgo principal del proyecto y es
    **hardware-bound**: no se reduce con trabajo de software, y seguirá sin retirarse todo el tiempo
    que la ZU9 no exista. Todo lo demás de este sitio es real y valioso, pero no compra ni un punto
    porcentual de ese riesgo concreto. La única vía es una plataforma con MGTs — ver
    [P-03](../alcance/pendientes.md#p-03).

Tampoco quedan cubiertos: la tasa de 250 MSPS, el IF analógico real de 60 MHz, el DAC AD9129, el
loopback DAC→ADC como oráculo de a bordo, y la capa física RS-422 de los encoders.

## Cobertura por componente

De los 13 componentes del receptor, la ZedBoard permite construir y validar **10 completos y 2
parciales**. Estimación: **~70 % de las líneas del WBS**, con la salvedad de que el 30 % excluido
contiene el elemento de mayor riesgo.

| Componente | Cobertura | Sustituto en ZedBoard |
|---|---|---|
| Clocking & SYSREF | **Ninguna** | — |
| JESD204B RX | **Ninguna** | Reproductor de vectores desde DDR/BRAM |
| Cadena DDC | Completa | Idéntica; solo cambia el reloj |
| Range Gating | Completa | Idéntica, tiempo dilatado |
| Motor de timing/trigger | Completa | Idéntica, tiempo dilatado |
| Lectores SSI | Alta (lógica sí, PHY no) | Emulador en fabric + MCU vía Pmod LVCMOS |
| Camino AXI DMA | Completa | Mismo IP, mismo flujo |
| Ray Assembler (PS) | Alta | FreeRTOS sobre A9 en lugar de R5 |
| Transporte DRx↔DSP | Completa | GEM0 + lwIP, 1GbE real |
| Control/Config Handler | Completa | Portable línea por línea |
| Camino DAC / Tx-reference | Parcial | Síntesis NCO sí; interfaz AD9129 no |
| Status & BITE | Completa | Con catálogo de fallos adaptado |
| Diagnósticos (captura raw) | Completa | Idéntica |

## Sustitución de oráculos

El plan original apoyaba la corrección en el loopback DAC→ADC del FMC213, que aquí no existe. Los
sustitutos son mejores en precisión y peores en realismo, y conviene tener claro exactamente qué se
pierde en cada caso:

| Oráculo del plan original | Sustituto en ZedBoard | Qué se pierde |
|---|---|---|
| Loopback DAC→ADC | Modelo NumPy + inyección de vectores | Realismo analógico, ruido, no linealidades |
| IF real de 60 MHz | Vectores sintéticos con ruido, offset DC, clipping y desbalance I/Q inyectados a propósito | Comportamiento del frontal real |
| Encoders reales | Emulador SSI en fabric + MCU independiente | Capa física RS-422, dinámica de antena |
| DSP como par de red | Stub consumidor + simulador de señal del DSP | Semántica real de consumo |

Lo perdido no desaparece: cada fila de esta tabla tiene una entrada correspondiente en el [registro
delta](../portabilidad/registro-delta.md), y las degradaciones analógicas se inyectan
sintéticamente en los vectores desde Z1 para no descubrirlas en la ZU9.

## Frontera de las tres condiciones de contorno

Tres cosas hacen que el trabajo en esta placa sea transferible en lugar de desechable, y las tres
son decisiones de arquitectura que hay que tomar **antes de escribir RTL**:

1. **[Capa de abstracción de fuente de muestras](fuente-de-muestras.md)** — para que nada aguas
   abajo dependa de si las muestras vienen de JESD o de un reproductor.
2. **[Dilatación temporal uniforme por `FS_HZ`](dilatacion-temporal.md)** — para que los vectores y
   los valores esperados sean bit a bit los mismos en ambas plataformas.
3. **[Modelo dorado como oráculo](../pruebas/modelo-dorado.md)** — para que el oráculo sea exacto y
   no estadístico.
