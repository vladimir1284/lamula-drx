# ADR-001 · `fs`, R₁ y R₂ — propuesta para sustituir a D-04

**Estado: PROPUESTA. No aplicada.** Nada de `config/params.toml` se ha tocado. Sustituir
[D-04](decisiones.md#d-04) exige firma de dirección técnica y de compra, que son los dueños de
[P-08](pendientes.md#p-08); esta página es el documento sobre el que firmar o rechazar, no el
registro de una decisión ya tomada.

**Fecha de redacción:** 30 de agosto de 2026 · **Sustituiría a:** D-04 · **Cierra:**
[P-01](pendientes.md#p-01) y [P-08](pendientes.md#p-08) · **Toca también:**
[D-02](decisiones.md#d-02), por el reloj de la plataforma de desarrollo.

## Contexto

D-04 fijó R₁ = 208 y R₂ = 416 con `fs` = 250 MHz, que es el rate máximo de los convertidores del
FMC213. De ahí sale una celda de 249,427 m en el modo grueso. Dos hallazgos posteriores dicen que
esa combinación no sirve:

- **P-01.** ORPG no tolera un espaciado aproximado: lo valida contra una **lista blanca**. La
  recombinación azimutal de super-res admite `{250, 1000}` en reflectividad y solo 250 en Doppler, y
  la validación de moments dual-pol exige 250 exacto. Una celda de 249,427 m se declara como 249 y
  el radial **se descarta**, no se degrada.
- **P-08.** `fs` es un grado de libertad. Los convertidores son *de hasta* 250 MSPS; nada obliga a
  operarlos ahí. Si `fs` se elige bien, la celda cae donde se quiere sin necesidad de remuestreo
  fraccionario.

El dato que faltaba para decidir ya está: el ADC del FMC213 son dos **TI ADS42JB69**, cuya tabla de
condiciones recomendadas especifica **60–250 MSPS en modo 10x** y **40–156,25 MSPS en modo 20x**.
143,9 MHz está dentro de los dos.

## Decisión propuesta

**`fs` = 143,9 MHz, R₁ = 120, R₂ = 240**, con el IF de 60 MHz muestreado directo en la primera zona
de Nyquist.

| | R | celda | error acumulado a 460 km | bins a 460 km |
|---|---|---|---|---|
| Modo fino | 120 | 125,000330 m | 1,21 m sobre 3679 bins | 3680 |
| Modo grueso | 240 | 250,000660 m | 1,21 m sobre 1839 bins | 1840 |

Contra los 1054 m de D-04 tal como está hoy. El valor que se declara a ORPG es **250 exacto**, que
es lo que exige la lista blanca de P-01, y 1840 bins son justo el tope duro de reflectividad del
ORPG (1840 × 250 m = 460 km), no uno por encima.

Por qué esta y no otra de la tabla de alternativas de P-08:

- **Reloj en rejilla de 100 kHz.** 143,9 MHz sale por integer-N desde la referencia de 10 MHz de la
  casa. Sin PLL fraccional-N y por tanto sin espurios fraccionales, que era la única objeción seria
  a la variante de `fs` exacta (249,427325 MHz).
- **Factores de diezmado limpios.** 240 = 2⁴·3·5 y 120 = 2³·3·5, frente al 13 de 208 = 2⁴·13, que es
  un factor incómodo para una cadena CIC.
- **R₂ = 2·R₁ intacto**, así que se conserva la cadena única con etapa ÷2 y no hacen falta dos
  cadenas, que es lo que obligaría la opción B de P-01 (R₂ = 417).
- **Cuatro transceptores en vez de ocho.** A 250 MHz el modo 20x del ADS42JB69 queda fuera de rango
  y hay que usar 10x, o sea cuatro lanes por ADC. A 143,9 MHz el 20x sirve (2,878 Gbps, bajo el
  máximo de 3,125), y los cuatro canales de la tarjeta caben en cuatro MGTs. Entra en la selección
  de portadora de [P-03](pendientes.md#p-03).

## Lo que esto obliga a cambiar y no estaba en P-08

**El `fs` de la ZedBoard también se mueve.** El paquete de parámetros exige que el IF caiga en un
número entero de hercios en **las dos** plataformas — lo comprueba `drx_params_selftest.c` con
`IF_HZ · IF_NORM_DEN == FS_HZ · IF_NORM_NUM`, y `Params.if_hz` levanta excepción si no. Con
`fs` = 143,9 MHz el IF normalizado pasa a ser 60/143,9 = **600/1439**, y 1439 es primo, así que
cualquier `fs` de plataforma tiene que ser múltiplo de 1439 Hz. **100 MHz no lo es.**

| `fs` de ZedBoard | IF | dilatación | nota |
|---|---|---|---|
| **99,998988 MHz** | 41,6952 MHz | **1,439015** | **Recomendada.** 1439 × 69 492 |
| 100,000427 MHz | 41,6958 MHz | 1,438994 | Lo más cerca de 100 MHz por arriba |
| 100,73 MHz | 42 MHz | 1,428571 | Múltiplo redondo de 1439 |
| 71,95 MHz | 30 MHz | exactamente 2 | Dilatación legible, pero reloj irreal |
| ~~100 MHz~~ | — | — | **Ilegal**: el IF no cae en hercios enteros |

Se propone **99,998988 MHz**, y se elige por **realismo del reloj, no por legibilidad**. Es el
múltiplo de 1439 más cercano a los 100 MHz de hoy: se queda **10,1 ppm por debajo**, así que el
reloj de fabric de la ZedBoard no se mueve en la práctica y la plataforma de desarrollo sigue
corriendo a la velocidad a la que va a doler el timing.

La alternativa de 71,95 MHz es más bonita sobre el papel —dilatación exactamente 2, IF de 30 MHz
redondos— y se descarta a propósito: bajar el reloj de fabric a menos de la mitad del de destino
cierra timing con holgura, pero por eso mismo **esconde** la presión de recursos y de rutado que sí
va a aparecer en la ZU9. Una plataforma de desarrollo que no reproduce el problema no lo detecta. El
precio de 99,998988 MHz es un número feo en el XDC y una dilatación que no se razona de cabeza; a
cambio, el riesgo ya registrado de que *«el 7Z020-1 no cierre a 100 MHz con 4 canales»* se sigue
midiendo en vez de esquivarse.

**`FS_HZ` es el número del que se derivan los parámetros, no una promesa sobre el oscilador.** Un
Zynq-7000 no sintetiza 99,998988 MHz exactos —los relojes de PL salen de divisores enteros del PLL
del PS— y no hace falta que lo haga: la comparación bit a bit contra el modelo dorado vive en el
dominio de la muestra, no en el del tiempo de pared, y nada en la ZedBoard se contrasta contra un
reloj externo. Lo que cambia con este valor es el paquete de parámetros; el cristal de la placa se
queda donde está. Los 10 ppm de diferencia se ven en los valores de pared derivados —el pulso de
200 ciclos pasa de 2,000000 µs a 2,000020 µs— y son irrelevantes en la plataforma de desarrollo.

La afirmación de P-08 de que la dilatación bajaría de 2,5 a 1,439 se sostiene con este `fs`, con la
corrección de que el valor exacto es 1,439015 y no 1,439.

Esto obliga a enmendar la frase de [D-02](decisiones.md#d-02) que dice que el reloj de fabric
objetivo en ZedBoard es 100 MHz, y a anotar la entrada correspondiente en el [registro
delta](../portabilidad/registro-delta.md).

## El diff, si se aprueba

En `config/params.toml`:

```toml
[invariant]
if_norm_num = 600      # era 6
if_norm_den = 1439     # era 25
r1 = 120               # era 208
r2 = 240               # era 416
bins_mode_fine = 3680  # era 3689
bins_mode_coarse = 1840  # era 1844

[chain]
cic_rate = 30          # era 52; 30 × 4 = 120

[platform.zu9]
fs_hz = 143_900_000    # era 250_000_000

[platform.zedboard]
fs_hz = 99_998_988     # era 100_000_000; = 1439 × 69 492
```

`fir_decim` se queda en 4, así que los bordes de banda del FIR —normalizados a la frecuencia de
entrada del filtro— no se mueven. Después, `make gen`.

**El SHA-256 del oráculo se va a mover, y es correcto que se mueva.** Los coeficientes del
compensador de droop se diseñan contra la respuesta del CIC, y esa respuesta depende de `cic_rate`:
al pasar de R = 52 a R = 30 el droop es menor y el compensador sale distinto. `make gen` regenera
`config/coeffs/`, la huella de `model/tests/test_chain.py` cambia y hay que decir en el commit que
cambió por esto. Después, `make figures`, porque las gráficas del tutorial las dibuja el modelo.

## Consecuencias

- **Z1 puede empezar.** La arquitectura de la cadena de diezmado deja de estar bloqueada, que es lo
  que P-01 y P-08 estaban reteniendo.
- **Menos presión de recursos** que con R = 208: los factores se descomponen en etapas más cómodas
  para una cadena CIC. En la **ZU9** el reloj además baja de 250 a 143,9 MHz, que es holgura de
  timing real; en la **ZedBoard no baja** —99,998988 MHz son los 100 MHz de hoy menos 10 ppm— y eso
  es deliberado, por lo dicho arriba sobre el realismo del reloj.
- **La tasa de línea JESD204B baja** con `fs`, lo que va a favor del margen; queda por confirmar que
  el modo elegido del convertidor admite ese rate y que SYSREF sigue siendo submúltiplo entero del
  LMFC. A 143,9 MHz en modo 20x con K = 32 y F = 2, SYSREF sale a 2,2484 MHz por división entera del
  reloj de dispositivo.
- **Nada del RTL cambia de estructura**, si se cumple D-02: todo se deriva de `FS_HZ`. Cambian
  parámetros, no arquitectura.

## Riesgo que queda abierto, y no bloquea firmar

**El PLL del FMC213 no está identificado.** VadaTech describe un «wide-band PLL» con referencia por
panel frontal, portadora o referencia de a bordo, pero no publica la pieza; su hoja de datos devuelve
HTTP 403. **Dato nuevo, 7-sep-2026:** el sistema completo usa una referencia externa disciplinada por
GPS (confirmado en sesión, ver [P-03](pendientes.md#p-03) y [A9](pendientes.md#supuestos-de-entorno-a-verificar)),
casi con certeza la "referencia de 10 MHz de la casa" de este párrafo — pero sigue sin ficha técnica,
así que el PFD de 100 kHz de abajo es todavía la mejor suposición, no un dato confirmado. Si es el LMK04828 del ejemplo de aplicación de TI, 143,9 MHz sale con el VCO a 2446,3 MHz
(143,9 × 17, dentro del rango de VCO0) y N entero desde 10 MHz, pero con un PFD de 100 kHz, que sube
el ruido en banda del lazo — y el presupuesto de jitter de apertura es de ~100 fs rms. **Hay que
pedir a VadaTech la pieza del PLL y su configuración.**

Si resultara que la tarjeta no puede sintetizar 143,9 MHz, el plan B documentado en P-08 sigue en
pie: 247 MHz con R₁ = 206 / R₂ = 412, que da 54 m de error acumulado, reloj en rejilla de 1 MHz y
cadena única. Y en último caso la opción B de P-01, R₂ = 417 con cadena propia.

## Revisión del 8-oct-2026: lo que el diff de arriba no contempla

El ADR se redactó el 30-ago-2026, antes de Z1–Z4. Desde entonces el repositorio ha cambiado en
cuatro puntos que el diff de arriba, aplicado tal cual, rompería o dejaría incoherentes. **La
decisión de fondo (143,9 MHz, 120/240) no cambia**; cambia lo que cuesta aplicarla y lo que hay que
incluir en el diff. Nada de `config/params.toml` se ha tocado con esta revisión.

### 1. El `fs` de la ZedBoard ya no es 100 MHz, y 99,998988 MHz ya no tiene sentido

El argumento de «realismo del reloj» sostenía que la ZedBoard debía quedarse cerca de 100 MHz para
seguir midiendo la presión de timing. Esa medida ya se hizo: el 19-sep-2026 el datapath completo
**no cerró a 100 MHz** (WNS = −1,209 ns) y `fs_hz` de zedboard bajó a **62,5 MHz**
(`config/params.toml`). El valor vigente hoy es 62 500 000.

62,5 MHz **no es múltiplo de 1439**, así que con `if_norm` = 600/1439 es ilegal igual que lo era
100 MHz. El múltiplo de 1439 más cercano es **62 500 087 Hz** (1439 × 43 433, +1,39 ppm). La
dilatación pasa de 4,0 hoy (250 / 62,5) a 143,9 / 62,500087 = **2,3024** contra el nuevo `fs` de
la ZU9. Ese número sustituye a la «dilatación 1,439» del cuerpo del ADR, que ya no es alcanzable
en esta placa: la propia razón de bajar `fs` de la ZedBoard fue que 100 MHz no cierra. La fila de 99,998988
MHz de la tabla de `fs` de ZedBoard queda sin efecto.

### 2. Las constantes de PRF y ancho de pulso dependen de `fs` y el diff no las toca

El diff solo cambia `if_norm`, `r1`, `r2`, `bins_*`, `cic_rate` y los dos `fs_hz`. Pero
`config/params.toml` calcula otras constantes **contra el `fs` de la ZU9 de 250 MHz** y las trata
como invariantes de registro. Con `fs` = 143,9 MHz siguen siendo números de registro, pero ya no
significan lo mismo:

| Constante | Hoy (250 MHz) | Con 143,9 MHz | Efecto si no se cambia |
|---|---|---|---|
| `prf_div_min` | 208 333 (1200 Hz) | 119 917 | el techo de PRF baja de 1200 Hz a 690,7 Hz y el lote Doppler (~1300 Hz) deja de ser configurable |
| `prf_div_max` | 1 250 000 (200 Hz) | 719 500 | el suelo de PRF sube de 200 Hz a 115 Hz |
| `prf_div_min_low` (460 km) | 767 198 | 441 599 | D-09 exigiría 799 km de rango no ambiguo (PRF ≤ 187,6 Hz) y **rechazaría el lote de vigilancia estándar de ~326 Hz** |
| `prf_div_min_high` (115 km) | 191 800 | 110 400 | exigiría PRF ≤ 750 Hz; hoy no vincula porque `prf_div_min` lo tapa, pero deja de ser coherente |
| `pulse_width_cycles` | 200 / 415 / 825 | 115 / 239 / 475 | los pulsos durarían 1,39 / 2,89 / 5,73 µs en vez de 0,8 / 1,66 / 3,3 µs |

Estas cinco aparecen además **escritas a mano fuera de `params.toml`** en
`rtl/drx_ray_packer.sv`, `fw/src/app/drx_timing_cfg.c`, `fw/src/app/drx_control_boot.c`,
`fw/src/drx_ray_frame_selftest.c`, `fw/tests/test_contract_io.py`, `test_ray_frame.py`,
`test_control.py`, `sim/tb/tb_drx_timing_engine.py` y `sim/tests/test_l0_timing_engine.py`. Eso es
lo que el gate `tools/check_hardcoded_clock.py` no ve, porque son conteos de ciclos y no relojes.
Hay que auditarlas una a una; es el coste real de aplicar el ADR y no estaba estimado. Los valores de
la columna «Con 143,9 MHz» son aritmética mía sobre las fórmulas del propio `params.toml`
(`ceil(r·2·fs/c)`); **verificar con `gen_params.py` antes de firmar**, no son resultado de una
corrida.

### 3. `vector_loop_len` tiene que cambiar

`VECTOR_LOOP_LEN` (hoy 4000) debe ser múltiplo de `IF_NORM_DEN`, y `gen_params.py` lo comprueba. Hoy
`IF_NORM_DEN` = 25 y 4000 = 160 × 25. Con 1439 el valor legal más cercano dentro de
`vector_bram_depth` (8192) es **4317** (3 × 1439); las alternativas son 1439, 2878, 5756 y 7195. Esto
cambia lo que suena en bucle y, con ello, el catálogo de ocho vectores de estímulo y las
referencias de espectro que ya están medidas en placa (−9,02/−9,03 dBFS): hay que remedir.

### 4. Qué verificación hay que repetir, y cuánto cuesta

Cambiar `cic_rate` de 52 a 30 regenera el CIC Compiler y los coeficientes del compensador FIR. Las
dos cosas invalidan evidencia ya cerrada:

- **La matriz de 16 corridas de D-12 contra xsim real** (8 casos × {fino, grueso}). Cada corrida son
  ~20–25 min y no hay caché; con tres en paralelo, 2–3 h.
- **`NCO_LUT_OFFSET_K` = 655** (`tcl/gen_ip.tcl:180`) se calibró contra el arranque del Phase
  Generator. El comentario del fichero dice que no se recalibra al cambiar la IP, pero eso se
  verificó con la matriz de D-12 para **la frecuencia de IF de entonces**; con `if_norm` = 600/1439
  la palabra de fase es otra. *Inferencia, no medida:* lo esperable es que siga cancelando, pero solo
  la matriz lo dice.
- **P&R de `-top zynq`**, que hoy cierra con WNS ≈ 1,6 ns a 62,5 MHz. El cambio de `cic_rate` mueve
  el camino crítico (FIFO del FIR Compiler → `overflow_sticky_r`).
- **Bring-up en placa:** las cifras de Z4.4–Z4.6 (rayos/s, −9,03 dBFS, AFC cerrado con el DSP real)
  se vuelven a medir con el nuevo `fs`. El caudal en pared también cambia: la PRF de pared de la
  ZedBoard es `fs / prf_div`.

**Estimación de esfuerzo si se aprueba: 1–2 días de trabajo con hardware, no «dos líneas y
`make gen`».** La frase de `substrato.md` y de `CLAUDE.md` que dice que aplicarlo es «el diff más
`gen_params.py`» describe el cambio en `params.toml`, no el cierre de verificación, y está
desactualizada por Z1–Z4.

## Firma

| Rol | Quién | Decisión | Fecha |
|---|---|---|---|
| Dirección técnica | | | |
| Compra de hardware | | | |
| Especialistas de dominio (P-01) | | | |

Hasta que esta tabla esté rellena, `config/params.toml` no se toca y D-04 sigue vigente
provisionalmente.
