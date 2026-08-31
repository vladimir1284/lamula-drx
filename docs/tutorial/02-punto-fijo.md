# 2 · Aritmética de punto fijo

## Por qué esto es el corazón del proyecto

El plan original apoyaba la corrección del receptor en el **loopback DAC→ADC** del FMC213: se
sintetiza un IF conocido en el DAC, se captura en el ADC y se comprueba la I/Q diezmada. Es un
oráculo excelente y la ZedBoard no lo tiene.

El sustituto, [D-03](../alcance/decisiones.md#d-03), es un **modelo de referencia en NumPy**
bit-exacto. El intercambio es explícito: se pierde realismo —no dice nada del frontal analógico— y se
gana exactitud. Y la exactitud es lo que atrapa los bugs de punto fijo, que son los que se esconden.

De ahí la regla dura: **ninguna prueba pasa por «se ve razonable»**. La salida del DDC se compara
bit a bit. Si el RTL y el modelo discrepan en un LSB, hay un bug en uno de los dos y hay que
encontrarlo — no se ajusta el modelo para que el test pase.

Eso solo funciona si el modelo redondea **exactamente** igual que el hardware. Esta página es sobre
eso.

## El convenio

Todo entero con signo del proyecto es
[complemento a dos](https://en.wikipedia.org/wiki/Two%27s_complement), y en el modelo `bits` es
siempre el **ancho total con signo**, igual que se declara en el RTL:

```systemverilog
logic signed [15:0] muestra;   // bits = 16
```

```python title="model/drx_model/fixed.py"
def limits(bits: int) -> tuple[int, int]:
    """Rango representable con signo en complemento a dos."""
    return -(1 << (bits - 1)), (1 << (bits - 1)) - 1
```

Con 16 bits: −32 768 a +32 767. Asimétrico, y esa asimetría importa: el fondo de escala positivo es
32 767, no 32 768.

## Las cuatro operaciones, y cuándo cada una

### `wrap` — desbordar a propósito

```python
>>> fixed.wrap(np.array([32767, 32768, -32769, 65536]), 16)
array([ 32767, -32768,  32767,      0])
```

Es lo que hace un registro cuando se pasa. Suena a bug, y en casi todo el datapath lo sería — pero
en los **integradores del CIC es correcto y obligatorio**. Hogenauer demostró que el desbordamiento
intermedio de los integradores se cancela en los peines siempre que el ancho de registro sea el
adecuado. Un modelo con precisión infinita daría otro resultado en los transitorios y la comparación
bit a bit contra la IP fallaría. Esto se explica entero en [la página del DDC](03-ddc.md).

### `saturate` — desbordar es un fallo, y hay que reportarlo

```python
>>> valores, overflow = fixed.saturate(np.array([0, 40000, -40000]), 16)
>>> valores
array([     0,  32767, -32768])
>>> overflow
array([False,  True,  True])
```

Devuelve la bandera **por muestra**, no un booleano global. El DDC tiene que reportar saturación por
status/BITE, no esconderla: la suite de aceptación tiene un caso explícito de entrada sobre-escala.

Envolver donde había que saturar convierte un pico de señal en una raya espectral falsa — un pico
positivo se convierte en un valor muy negativo, y eso es un escalón enorme que el filtro reparte por
toda la banda. Hay un test que lo fija:

```python title="model/tests/test_gating_y_vectores.py"
def test_la_entrada_sobre_escala_satura_en_vez_de_envolver():
    """Envolver en vez de saturar convierte un pico en una raya espectral falsa."""
    x = vectors.tone(PARAMS, 4096, dbfs=+6.0)
    low, high = fixed.limits(PARAMS.sample_bits)
    assert x.max() == high
    assert x.min() == low
```

### `shift_round` — redondeo al más cercano, empate hacia arriba

```python
>>> fixed.shift_round(np.array([3, 4, 5, 6, -3, -4, -5]), 1)
array([ 2,  2,  3,  3, -1, -2, -2])
```

Es el modo **«Round half up»** de la IP de Xilinx: se suma medio LSB y se desplaza.

### `shift_truncate` — truncamiento hacia −infinito

```python
>>> fixed.shift_truncate(np.array([3, 4, 5, -1, -3]), 1)
array([ 1,  2,  2, -1, -2])
```

Es lo que hace un `>>>` en SystemVerilog y el modo **«Truncation»** de la IP.

### Por qué las dos existen por separado

Mira la diferencia en −1:

| Entrada | `shift_round(x, 1)` | `shift_truncate(x, 1)` |
|---|---|---|
| −1 | **0** | **−1** |
| −3 | −1 | −2 |
| 5 | 3 | 2 |

Un LSB. Parece nada, hasta que te das cuenta de que el truncamiento no es un error simétrico: **sesga
siempre hacia abajo**, así que introduce un offset de continua. Medido sobre un tono real de −20 dBFS
con 200 000 muestras:

```sh
$ PYTHONPATH=model .venv/bin/python -c "
from drx_model import fixed, vectors
from drx_model.params import load
p = load('zedboard')
x = vectors.tone(p, 200000, dbfs=-20.0)
for shift in (4, 8):
    t = fixed.shift_truncate(x, shift); r = fixed.shift_round(x, shift)
    print(f'shift={shift}: media truncando={t.mean():+.4f} LSB, media redondeando={r.mean():+.4f} LSB')
"
shift=4: media truncando=-0.5600 LSB, media redondeando=-0.0400 LSB
shift=8: media truncando=-0.5600 LSB, media redondeando=+0.0400 LSB
```

Medio LSB de continua constante, independiente del desplazamiento. En un receptor de radar esa
continua aparece como una señal falsa en velocidad cero — exactamente donde está el clutter que se
quiere filtrar. Elegir mal el modo de redondeo en una etapa es el tipo de bug que no se ve en una
gráfica y sí se ve en una comparación bit a bit.

Por eso el modelo tiene las dos funciones con nombres distintos y tests separados, en vez de una sola
que «desplaza».

## Cuantizar la entrada

El ADC no produce números reales: produce enteros saturados.

```python title="model/drx_model/fixed.py"
def quantize(values, bits: int, full_scale: float = 1.0):
    """Cuantiza una señal real de coma flotante a un entero con signo de `bits`.

    Lo que se salga satura, igual que satura un ADC real.
    """
```

```python
>>> fixed.quantize(np.array([0.0, 1.0, 2.0, -2.0]), 16)
array([     0,  32767,  32767, -32768])
```

Esta es la **única** frontera donde la coma flotante toca el camino de datos. A partir de aquí todo
es entero: NCO, mezclador, CIC, FIR, gating. La coma flotante vuelve a aparecer solo en el análisis
—espectros, gráficas— y nunca alimenta a un resultado que se compare bit a bit.

## Crecimiento de bits

Cuando multiplicas dos enteros con signo de 16 bits, el resultado necesita 32. Cuando sumas 208 de
ellos, necesitas 8 más. Llevar la cuenta de eso es la mitad del diseño de un datapath de punto fijo, y
el modelo la expone en vez de esconderla:

```python title="model/drx_model/fixed.py"
def growth_bits(gain: float) -> int:
    """Bits de crecimiento necesarios para una ganancia lineal dada."""
    return int(np.ceil(np.log2(gain)))
```

```python
>>> fixed.growth_bits(1.0), fixed.growth_bits(2.0), fixed.growth_bits(3.0)
(0, 1, 2)
```

El caso serio es el CIC: ganancia 52⁵ = 380 204 032, es decir 29 bits de crecimiento sobre los 16 de
entrada, o sea registros de 45 bits. Cabe en `int64`, y el modelo se niega a construir un CIC cuyo
ancho no quepa en vez de dar resultados silenciosamente equivocados:

```python title="model/drx_model/cic.py"
if self.register_bits > 63:
    raise ValueError(
        f"el ancho de registro del CIC ({self.register_bits} bits) no cabe "
        "en int64; el modelo tendría que pasar a enteros de Python"
    )
```

```python title="model/tests/test_bloques.py"
def test_el_cic_rechaza_un_ancho_que_no_cabe_en_int64():
    with pytest.raises(ValueError, match="int64"):
        Cic(stages=8, rate=1024, in_bits=32)
```

## Qué está probado

Los siete tests de `model/tests/test_fixed.py`, todos en verde:

```
model/tests/test_fixed.py::test_limites_con_signo PASSED
model/tests/test_fixed.py::test_wrap_es_complemento_a_dos PASSED
model/tests/test_fixed.py::test_saturate_marca_overflow_por_muestra PASSED
model/tests/test_fixed.py::test_redondeo_es_medio_hacia_arriba PASSED
model/tests/test_fixed.py::test_truncamiento_va_hacia_menos_infinito PASSED
model/tests/test_fixed.py::test_quantize_satura_lo_que_se_sale PASSED
model/tests/test_fixed.py::test_growth_bits PASSED
```

!!! danger "Lo que estos tests todavía no prueban"
    Prueban que el **modelo** es coherente consigo mismo y con lo que dice la documentación de la IP
    de Xilinx. **No** prueban que coincida con la IP real, porque en Z0 no hay Vivado ni IP generada.
    Esa comparación es Z1, y es ahí donde estos modos de redondeo pueden necesitar ajuste. Cuando se
    ajusten, se ajustan **contra la IP**, no contra el resultado que uno quisiera ver.

---

**Anterior:** [1 · El paquete de parámetros](01-parametros.md) ·
**Siguiente:** [3 · La cadena DDC](03-ddc.md)
