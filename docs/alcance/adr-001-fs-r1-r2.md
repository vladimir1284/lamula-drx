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
| **71,95 MHz** | 30 MHz | **exactamente 2** | Recomendada |
| 99,998988 MHz | 41,6952 MHz | 1,439015 | Lo más cerca de 100 MHz por debajo |
| 100,000427 MHz | 41,6958 MHz | 1,438994 | Lo más cerca por arriba |
| 100,73 MHz | 42 MHz | 1,428571 | Múltiplo redondo de 1439 |
| ~~100 MHz~~ | — | — | **Ilegal**: el IF no cae en hercios enteros |

Se propone **71,95 MHz**, por dos razones. La dilatación queda en exactamente 2, que es un factor
que se razona de cabeza al leer una forma de onda, y baja el reloj de fabric, lo que ataca de frente
un riesgo ya registrado: *«el 7Z020-1 no cierra a 100 MHz con 4 canales»*. El precio es que la
plataforma de desarrollo se aleja algo más de la de destino en velocidad; a cambio, la afirmación de
P-08 de que la dilatación bajaría a 1,439 **es incorrecta** salvo que se acepte un `fs` de
99,998988 MHz, y ese número no lo quiere nadie escrito en un XDC.

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
fs_hz = 71_950_000     # era 100_000_000
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
- **Menos presión de recursos y de timing** que con R = 208: los factores se descomponen en etapas
  más cómodas y el reloj es más bajo en las dos plataformas.
- **La tasa de línea JESD204B baja** con `fs`, lo que va a favor del margen; queda por confirmar que
  el modo elegido del convertidor admite ese rate y que SYSREF sigue siendo submúltiplo entero del
  LMFC. A 143,9 MHz en modo 20x con K = 32 y F = 2, SYSREF sale a 2,2484 MHz por división entera del
  reloj de dispositivo.
- **Nada del RTL cambia de estructura**, si se cumple D-02: todo se deriva de `FS_HZ`. Cambian
  parámetros, no arquitectura.

## Riesgo que queda abierto, y no bloquea firmar

**El PLL del FMC213 no está identificado.** VadaTech describe un «wide-band PLL» con referencia por
panel frontal, portadora o referencia de a bordo, pero no publica la pieza; su hoja de datos devuelve
HTTP 403. Si es el LMK04828 del ejemplo de aplicación de TI, 143,9 MHz sale con el VCO a 2446,3 MHz
(143,9 × 17, dentro del rango de VCO0) y N entero desde 10 MHz, pero con un PFD de 100 kHz, que sube
el ruido en banda del lazo — y el presupuesto de jitter de apertura es de ~100 fs rms. **Hay que
pedir a VadaTech la pieza del PLL y su configuración.**

Si resultara que la tarjeta no puede sintetizar 143,9 MHz, el plan B documentado en P-08 sigue en
pie: 247 MHz con R₁ = 206 / R₂ = 412, que da 54 m de error acumulado, reloj en rejilla de 1 MHz y
cadena única. Y en último caso la opción B de P-01, R₂ = 417 con cadena propia.

## Firma

| Rol | Quién | Decisión | Fecha |
|---|---|---|---|
| Dirección técnica | | | |
| Compra de hardware | | | |
| Especialistas de dominio (P-01) | | | |

Hasta que esta tabla esté rellena, `config/params.toml` no se toca y D-04 sigue vigente
provisionalmente.
