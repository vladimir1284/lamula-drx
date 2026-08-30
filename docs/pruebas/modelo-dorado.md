# Modelo dorado: el oráculo del proyecto

## Por qué existe

El plan original apoyaba la corrección en el **loopback DAC→ADC** del FMC213: se sintetiza un IF
conocido en el DAC, se captura en el ADC y se asevera la I/Q diezmada. Es un oráculo excelente y
autocontenido, y la ZedBoard no lo tiene.

El sustituto es un **modelo de referencia en NumPy** de toda la cadena DDC — NCO, mixer, CIC, FIR,
gating — **bit-exacto en aritmética de punto fijo**. Es mejor en precisión y peor en realismo:

- **Mejor:** el oráculo es exacto, no estadístico. No hay ruido de medida entre la expectativa y el
  resultado, así que cualquier discrepancia es un bug real.
- **Peor:** no dice nada sobre el comportamiento del frontal analógico real, el ruido, ni las no
  linealidades. Eso es la entrada [D9](../portabilidad/registro-delta.md) del registro delta y se
  compensa inyectando las degradaciones sintéticamente.

## La regla

**Ninguna prueba pasa por «se ve razonable».** Toda salida del DDC se compara **bit a bit** con el
modelo NumPy. Si hay discrepancia, o el RTL está mal o el modelo está mal; en los dos casos hay un
bug y hay que encontrarlo.

Esto es lo que hace que la sustitución del loopback analógico por un modelo dorado no sea una pérdida
neta: se cambia realismo por exactitud, y la exactitud es lo que atrapa los bugs de aritmética de
punto fijo, que son los que se esconden.

## Qué tiene que reproducir el modelo

- Palabra de fase y truncamiento del NCO, exactamente como el DDS Compiler configurado.
- Aritmética del mixer complejo, incluidos crecimiento de bits y redondeo.
- CIC con N=5 y R=52: crecimiento de bits por etapa y punto de truncamiento.
- FIR compensador de droop del CIC y FIR de diezmado final, con los coeficientes cuantizados que
  realmente se cargan en la IP.
- Escalado de ganancia, saturación y la bandera de overflow.
- Gating de rango: fronteras de bin, conteo de bins y el `TLAST` por rayo.

El modelo consume y produce los **mismos vectores** que el RTL, y como
[`FS_HZ`](../plataforma/dilatacion-temporal.md) dilata todo por igual, esos vectores y los valores
esperados son idénticos en ZedBoard y en ZU9.

## Inyección deliberada de degradaciones

Desde [Z1](../implementacion/fases.md#z1), el generador de vectores inyecta a propósito lo que el
frontal real va a traer: ruido gaussiano a varios SNR, offset DC, desbalance I/Q, y entrada a fondo
de escala y sobre-escala. No es para «hacerlo más realista» como gesto: es para que el
comportamiento del DDC bajo esas condiciones esté caracterizado **antes** de que exista el frontal,
y para que el modelo dorado también las modele y siga siendo el oráculo.
