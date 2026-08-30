# Dilatación temporal uniforme mediante `FS_HZ`

El reloj de fabric objetivo en ZedBoard es **100 MHz**. El XC7Z020 es grado -1 y 250 MHz no cierra
con un datapath DSP no trivial.

La regla es: **se dilata todo por igual, nunca solo una parte**. Un único genérico o paquete de
parámetros define `FS_HZ`, y todos los divisores, anchos de contador, palabras de fase del NCO,
factores de diezmado y valores de registro se derivan de él o se mantienen literalmente idénticos.

## Correspondencia de parámetros

Se preserva la frecuencia normalizada del IF: 60/250 = **0,24**.

| Parámetro | ZU9 (real) | ZedBoard | Relación |
|---|---|---|---|
| Reloj de fabric / fs | 250 MHz | 100 MHz | ÷2,5 |
| IF de entrada | 60 MHz | 24 MHz | ÷2,5 |
| IF normalizado | 0,24 | 0,24 | **idéntico** |
| Palabra de fase del NCO | X | X | **idéntica** |
| Factor de diezmado | R | R | **idéntico** |
| Coeficientes FIR | C[] | C[] | **idénticos** |
| Valor de registro de PRF | P | P | **idéntico** |
| PRF en tiempo de pared | 200–1200 Hz | 80–480 Hz | ÷2,5 |
| Ancho de pulso (registro) | 200 clk | 200 clk | **idéntico** |
| Ancho de pulso real | 0,8 µs | 2,0 µs | ×2,5 |

## Por qué esto es la decisión que salva el trabajo

Todo lo que aparece como «idéntico» en la columna de la derecha es una línea de test que no hay que
reescribir. **Los testbenches, los vectores de estímulo y los valores esperados son bit a bit los
mismos en ambas plataformas**, y la migración a la ZU9 consiste en cambiar `FS_HZ` y volver a cerrar
timing.

La disciplina se protege en CI: **si aparece una constante de reloj hardcodeada, la build falla.** Un
solo `100_000_000` suelto en el RTL convierte la migración en una auditoría manual.

## Plan de contingencia

Si el 7Z020-1 no cierra a 100 MHz con 4 canales, se baja a **62,5 MHz** (dilatación 4×) o se reduce
a **2 canales**. Numéricamente sigue siendo idéntico: la dilatación es un parámetro, no un rediseño.

## Lo que la dilatación rompe

Los ensayos de throughput sobre el camino de fabric dejan de ser representativos. A 100 MHz la
salida es:

```
100e6 / 208 × 4 B × 4 ch = 7,69 MB/s = 61,5 Mbps
```

frente a los 154 Mbps reales. Hay que tratar el throughput como una **campaña aparte** en la que el
PS genera rayos sintéticos a la tasa real; ver [Fases,
Z5](../implementacion/fases.md#throughput). Es la única consecuencia mala de la
dilatación, y es acotada y conocida.
