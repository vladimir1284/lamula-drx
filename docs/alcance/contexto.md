# Contexto: qué es y qué no es este proyecto

## El sistema

El frontal analógico del radar existe y se conoce bien: cadena de IF a 60 MHz, transmisor,
antena/servo y sensores. LAMULA DRx reemplaza el hardware y el software de adquisición heredados
(Vesta DRX) por un receptor propio sobre Zynq que entrega al DSP I/Q compleja calibrada y enrejada
en rango.

El reparto de responsabilidades es deliberado:

- **La lógica programable (PL) tiene el tiempo real duro.** Interfaz JESD204B del ADC, cadena DDC,
  motor de timing/trigger y lectores de encoder SSI viven en fabric.
- **El procesador (PS) es delgado y nunca está en el camino del trigger.** Ensambla rayos desde
  buffers de DMA, los etiqueta con metadatos y los transmite por GEM 1GbE bajo FreeRTOS.
- **El producto en el cable es la I/Q diezmada.** El flujo real de 250 MSPS no sale del chip. Un
  solo canal crudo a 250 MSPS son unos 2 Gbps, por encima de 1GbE; la captura cruda existe solo
  como diagnóstico ventaneado a DDR.

## Objetivos, en orden de prioridad

1. Levantar el enlace JESD204B del ADC y el clocking sobre ZU9 + FMC213 con captura determinista y
   alineada entre canales.
2. Implementar el DDC (NCO + diezmado) en la PL, produciendo I/Q compleja en banda base a la tasa
   de celda de rango para celdas de 125 m y 250 m.
3. Generar la temporización del radar en la PL: cuatro triggers configurables, PRF 200–1200 Hz,
   anchos de pulso 0,8 / 1,66 / 3,3 µs.
4. Leer los dos encoders de posición SSI y etiquetar cada rayo con azimut y elevación.
5. Ensamblar los rayos en el PS bajo FreeRTOS y transmitirlos al DSP por el contrato DRx↔DSP sobre
   GEM 1GbE.
6. Sintetizar la referencia de Tx por DAC y aplicar la corrección AFC (ajuste del NCO) estimada por
   el DSP.
7. Ser configurado y controlado enteramente a través del DSP, sin interfaz local, reportando status
   y BITE.

## Fuera de alcance

- **Frontal analógico, cadena de IF, transmisor y servo de antena** — hardware existente. Nos
  interfazamos al IF y a los encoders SSI.
- **Procesamiento de señal (I/Q → momentos)** — es el proyecto DSP. Nosotros entregamos rayos de
  I/Q diezmada.
- **RCP y ORPG** — proyectos separados; el DRx nunca les habla directamente.
- **Streaming continuo de ADC crudo** — limitado por el enlace. Solo captura ventaneada a DDR como
  diagnóstico.
- **Estimación de AFC** — la hace el DSP; el DRx solo actúa la corrección.
- **Conexión al IF y a la antena reales, y puesta en servicio sobre el radar** — posterior al
  mes 8.

Diferido y documentado, no construido ahora: opción PetaLinux/AMP en el PS, escalado a una segunda
portadora o más módulos, captura de larga duración a SSD a bordo, autocalibración avanzada,
migración a JESD204C, portadoras alternativas o digitalizadores distintos del FMC213, y
adquisición redundante en caliente.

## Por qué el desarrollo empieza en una ZedBoard

La ZU9 + FMC213 no está comprada. Esperar a que llegue es tiempo perdido en todo lo que no depende
de ella, y resulta que eso es la mayoría del trabajo: la cadena DDC, el gating de rango, el motor
de timing, los lectores SSI, el camino AXI DMA, el firmware del PS, el transporte DRx↔DSP, el plano
de control y el status/BITE se pueden construir y validar completos sobre un XC7Z020.

Lo que no se puede es exactamente lo que más importa. Ver [Frontera y
cobertura](../plataforma/zedboard.md).

## Relación con los proyectos hermanos

El **DSP** es el único par de red del DRx y copropietario del contrato DRx↔DSP. El **RCP** origina
la configuración, que llega al DRx relevada por el DSP. Los tres proyectos comparten equipo y
cronograma, y el contrato DRx↔DSP es el punto de sincronización entre el DRx y el resto.

## Equipo y modelo de entrega

Tres personas: un desarrollador principal (HDL + firmware embebido) y dos especialistas que actúan
como QA y dominio. El desarrollador principal carga la construcción; los especialistas son dueños
de la corrección, la validación en banco y la integración con el DSP.

El modelo de entrega es **spec-and-test-first acelerado por agentes**, y eso tiene una consecuencia
estructural que no es negociable: el diseño no puede vivir en un proyecto GUI de Vivado. Los
agentes no pueden operar sobre él, las builds no son reproducibles y la regresión no existe. El
flujo Tcl no-project y el CI son **precondición**, no trabajo de cierre. Ver
[Fases, Z0](../implementacion/fases.md#z0).
