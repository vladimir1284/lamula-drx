# Capa de abstracción de fuente de muestras (SSA)

Sin esta capa, el trabajo en ZedBoard es desechable. Con ella, es transferible.

## El interfaz

Se define un único interfaz AXI4-Stream de muestras con backpressure:

```
sample_stream: TDATA[N*16-1:0] (N canales entrelazados o N streams paralelos)
               TVALID / TREADY
               TUSER = {channel_id, sample_valid_mask, source_tag}
               TLAST = fin de ventana de captura
```

## Las dos implementaciones

- **`jesd204b_source`** — solo en ZU9. IP de Xilinx sobre transceptores GTH.
- **`vector_source`** — reproductor de vectores. Es la implementación que existe hoy y la que
  **sobrevive en la placa real** como inyector de vectores digitales.

Todo lo que está aguas abajo — DDC, gating, DMA, PS — se desarrolla y se valida contra la SSA,
nunca contra la fuente concreta. Eso convierte la inyección de vectores digitales en ciudadano de
primera clase en lugar de un hack de bring-up, lo cual también es lo correcto para la placa final:
el plan original ya contaba con inyección digital al nivel del ADC/JESD como método de prueba
determinista.

## Reproductor de vectores: tres modos

El ancho de banda de DDR3 de la ZedBoard (32 bits a 533 MT/s, unos 2133 MB/s de pico; *estimación*
de ~1400 MB/s sostenidos) limita lo que se puede reproducir en tiempo real dilatado. De ahí tres
modos con compromisos distintos:

| Modo | Fuente | Canales | Tasa | Uso |
|---|---|---|---|---|
| **RT** | DDR vía MM2S DMA | 1–2 | 100 MSPS (≈200–400 MB/s) | Fidelidad temporal, señales largas |
| **BRAM-loop** | BRAM, forma de onda repetitiva | 4 | 100 MSPS | Ensayos de tasa sostenida y de timing |
| **Throttled** | DDR con backpressure AXIS | 4 | < tiempo real | Corrección funcional, bit-exacta |

BRAM disponible en el 7Z020: 4,9 Mb ≈ 613 KB. A 16 bits × 4 canales son unas **76 k
muestras/canal**, es decir 766 µs de señal a 100 MSPS — suficiente para varias PRIs a PRF alta.

!!! success "1-oct-2026: *Throttled* implementado y verificado en ZedBoard (Z4.3)"
    `rtl/vector_source.sv` tiene desde hoy los dos modos: BRAM-loop, que es el que tenía, y
    **Throttled(DDR)**, con las muestras llegando por AXI4-Stream desde el canal MM2S de un AXI DMA
    alimentado por la DDR del PS. Se elige en tiempo de ejecución con `CTRL` bit 1 (mapa de
    registros v8) y el vector concreto con el mensaje `test_stimulus_select` del contrato (v0.5).
    **RT sigue sin implementar.**

    Formato del stream: 16 bits, UNA muestra por beat, canales en orden ascendente y repitiendo.
    Los N_CH canales avanzan en bloque —se juntan N_CH beats en un conjunto y los N_CH salidas se
    presentan a la vez, y el conjunto no se retira hasta que todos los consumidores lo han tomado—,
    que es más estricto de lo que exige AXI4-Stream y es justo el punto de este modo: dejar que un
    canal se adelantara convertiría un desfase de muestra en un resultado distinto sin ningún error
    visible.

    Verificado en placa por JTAG: el DMA completa pasadas enteras con 0 errores, y eso **es** la
    prueba de que los bytes entraron en la PL, porque el stream tiene backpressure y el único que
    levanta `tready` es `vector_source` en este modo. Lo que ese ensayo **no** prueba es que el
    dato llegue correcto hasta la salida del DDC: no hay camino de vuelta para leerlo hasta que
    Z4.4 ensamble rayos. Ver `fases.md#z4`, entrada del 1-oct.

**El modo *Throttled* produce salida bit a bit idéntica al modo RT; solo tarda más.** Es el modo de
referencia para corrección, y por eso la limitación de ancho de banda de DDR no compromete la
validación funcional: solo la fidelidad temporal, que se cubre con BRAM-loop.

## Consecuencia para la portabilidad

Cuando llegue la ZU9, la migración de la fuente de muestras es sustituir un módulo que cumple un
interfaz por otro que cumple el mismo interfaz. Nada aguas abajo cambia, y el `vector_source` se
queda para inyectar vectores conocidos en la placa real — que sigue siendo la única forma de tener
un oráculo exacto e independiente del frontal analógico.
