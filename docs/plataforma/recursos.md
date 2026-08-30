# Presupuesto de recursos

!!! note "Estimación, ±40 %"
    Estas cifras son inferencias a partir de las hojas de datos y de la experiencia con IP
    equivalente. **Hay que verificarlas con `report_utilization` real** antes de comprometerse a
    ellas. La primera build de Z1 debe publicar los números medidos y sustituir esta tabla.

Para 4 canales de DDC + gating + timing + SSI + DMA sobre XC7Z020:

| Bloque | DSP48 | LUT | BRAM36 |
|---|---|---|---|
| DDS ×4 (NCO 16 bit) | 8 | 1 200 | 4 |
| Mixer complejo ×4 | 16 | 800 | 0 |
| CIC ×8 (N=5, R=52) | 0 | 4 000 | 0 |
| FIR compensador + final (time-shared, 8 streams) | 10 | 2 500 | 4 |
| Range gating + framing | 0 | 2 000 | 4 |
| Reproductor de vectores + infra AXIS | 0 | 1 500 | 6 |
| AXI DMA SG + interconnect | 0 | 2 500 | 4 |
| Motor de timing | 0 | 800 | 0 |
| SSI ×2 + emulador | 0 | 600 | 0 |
| **Total estimado** | **~34** | **~16 000** | **~22** |
| **Disponible en 7Z020** | 220 | 53 200 | 140 |
| **Ocupación** | 15 % | 30 % | 16 % |

## Veredicto

Cabe con holgura. Queda margen para 8 canales o para instrumentación en fabric — que es
precisamente lo que hace viable el contador libre en dominio de reloj distinto que auto-mide jitter
de trigger en Z2.

**El cuello de botella no será el área.** Serán dos cosas:

1. **Cierre de temporización a 100 MHz en grado -1.** Es el motivo de que el objetivo no sea
   250 MHz y de que exista el plan de contingencia a 62,5 MHz.
2. **Ancho de banda de DDR** para la reproducción de vectores de 4 canales en tiempo real, mitigado
   por los modos BRAM-loop y Throttled — ver [Fuente de
   muestras](fuente-de-muestras.md#reproductor-de-vectores-tres-modos).
