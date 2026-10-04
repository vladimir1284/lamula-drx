# Presupuesto de recursos

!!! danger "Medido contra Vivado real, 9-sep-2026 — el DSP48 NO cabe con holgura"
    La tabla de abajo (estimación ±40 %) asumía FIR **time-shared entre 8 streams** (10 DSP48 en
    vez de uno por stream). Esa no es la arquitectura que Z1 implementó:
    `rtl/drx_ddc_quad_top.sv` es explícito en su cabecera — **sin resource-sharing entre canales**,
    cada canal instancia su propio juego completo de IP. Sintetizado de verdad (`synth_design
    -mode out_of_context`, XC7Z020-1, sobre `drx_ddc_top`/`drx_ddc_quad_top` tal como están hoy en
    el árbol, más una variante de sondeo con el NCO en `Noise_Shaping {Taylor_Series_Corrected}`
    — ver [P-11](../alcance/pendientes.md#p-11) y [P-12](../alcance/pendientes.md#p-12)):

    | Bloque | DSP48 medido |
    |---|---|
    | Un canal DDC completo (NCO + mixer + CIC + FIR-droop + FIR-semibanda + escalado de ganancia, dos ramas I/Q), `Noise_Shaping {None}` | **50** |
    | El mismo canal, NCO en `Noise_Shaping {Taylor_Series_Corrected}` (config actual desde [D-11](../alcance/decisiones.md#d-11), 18-sep-2026) | **53** (NCO: 0 → 3 DSP48; a cambio libera 7 RAMB36) |
    | **4 canales Rx** (`drx_ddc_quad_top`, `None` — medido, no extrapolado) | **200 / 220 (91 %)** |
    | 4 canales Rx + Taylor en los 4 NCO (extrapolado desde el delta medido de 1 canal) | 212 / 220 (96 %) |
    | 5 canales (si el conversor de muestra de Tx también necesita cadena DDC completa — **no decidido**, ver A10) | **250 / 220 — no cabe**, sin tocar Taylor |
    | 5 canales + Taylor | **265 / 220 — no cabe**, 45 DSP48 por encima |

    Con la arquitectura de hoy (sin compartir recursos), **el receptor de 4 canales por sí solo ya
    deja el 91 % del DSP48 de la XC7Z020-1 ocupado**, antes de tocar el motor de timing (Z2), los
    lectores SSI (Z3), el DMA o cualquier instrumentación en fabric. La tabla de abajo, con su
    veredicto de "cabe con holgura, margen para 8 canales", **queda invalidada** por este dato —
    se conserva tachada más abajo por trazabilidad, no como referencia vigente.

Para 4 canales de DDC + gating + timing + SSI + DMA sobre XC7Z020 — ~~estimación ±40 %, superada por
la medición de arriba~~:

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
| **Total estimado (SUPERADO, ver arriba)** | ~~**~34**~~ | **~16 000** | **~22** |
| **Disponible en 7Z020** | 220 | 53 200 | 140 |
| **Ocupación (SUPERADA, ver arriba)** | ~~15 %~~ **91 % medido, solo DDC** | 30 % | 16 % |

## Veredicto

~~Cabe con holgura. Queda margen para 8 canales o para instrumentación en fabric~~ — **falso**,
contradicho por la medición de arriba. El veredicto real: el DSP48 es ahora el recurso crítico, no
un recurso sobrante. Con 4 canales sin compartir recursos no queda margen creíble para nada más
(20 DSP48 libres, 9 %), 5 canales no cabe en absoluto si el conversor de Tx necesita su propia
cadena, y activar `Taylor_Series_Corrected` en los 4 NCO existentes (la vía que evalúa
[P-11](../alcance/pendientes.md#p-11) para el presupuesto de rango dinámico) deja solo 8 DSP48
libres (3,6 %) — sin margen de verdad para cerrar rutado/temporización, no solo sin margen
aritmético.

**Lo que esto obliga a reabrir**, antes de seguir invirtiendo en Z1/Z2 sobre esta arquitectura:

1. **Resource-sharing entre canales**, la vía que `drx_ddc_quad_top.sv` documenta como descartada
   para ZM1 ("optimización para más adelante, no un requisito"). Con este dato, deja de ser
   opcional si se quiere dejar margen para Z2-Z4 o para Taylor — es la única palanca que no cambia
   el algoritmo ni el criterio de verificación bit a bit.
2. **Confirmar si el conversor de Tx necesita cadena DDC completa** (A10, sin decidir) antes de
   asumir que "4 canales" es el número de diseño — si la respuesta es sí, la arquitectura actual no
   cabe en la ZedBoard en ningún caso, con o sin Taylor.
3. Esta tabla ya no es una estimación a corregir "en la primera build de Z1" — la build ya
   corrió. Cualquier cambio de ancho, de técnica de NCO, o de conteo de canales necesita repetir
   `synth_design -mode out_of_context` sobre el bloque tocado antes de comprometerse a un número,
   no volver a estimar a mano.

**El cuello de botella no será el área** — dicho en la versión anterior de esta página, ahora
retirado. Sí lo es, y de los tres riesgos originales sigue habiendo dos más, sin resolver:

1. **Cierre de temporización a 100 MHz en grado -1.** Con el DSP48 ya al 91-96 %, esto se agrava:
   la congestión de rutado alrededor de bloques DSP densos es exactamente el patrón que dificulta
   cerrar timing, no un problema independiente del área.
2. **Ancho de banda de DDR** para la reproducción de vectores de 4 canales en tiempo real. Dejó
   de ser un riesgo del reproductor el 4-oct-2026: Throttled(DDR) salió del diseño y el estímulo
   se carga en BRAM, que entrega una muestra por ciclo sin tocar la DDR. El coste es de
   capacidad, no de ancho de banda — 8192 muestras por canal × `N_CH` = 3 son **12 BRAM Tile** de
   los 140 — y a cambio el bucle no puede representar un perfil que dependa del rango: un rayo
   completo en modo fino son 208 416 muestras por canal, 102 tiles. Ver [Fuente de
   muestras](fuente-de-muestras.md#reproductor-de-vectores-los-modos-previstos-y-el-que-quedo).
