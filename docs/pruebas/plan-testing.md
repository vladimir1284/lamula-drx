# Plan de testing

El oráculo de todo lo que sigue es el [modelo dorado](modelo-dorado.md). La métrica de rigor es
única: **comparación bit a bit**, nunca inspección visual.

## Niveles

| Nivel | Qué | Herramienta | Cuándo corre |
|---|---|---|---|
| **L0** | Unidades del RTL custom | cocotb + Verilator | Cada push |
| **L1** | Integración con IP de Xilinx | SystemVerilog nativo + xsim | Cada push (nocturno si es lento) |
| **L2** | Hardware-in-the-loop: vector → placa → comparación bit-exacta con NumPy | Runner sobre ZedBoard | Cada merge a `main` |
| **L3** | Subsistema: matriz de timing, perfiles SSI, throughput | Scripts + osciloscopio | Por hito |
| **L4** | Sistema: rayos end-to-end hasta un stub de DSP | Banco completo | Por hito |

L0 usa Verilator porque es gratis y rápido; L1 usa xsim porque los cores del DDC son cajas negras
que Verilator no puede elaborar.

**Los dos niveles no comparten runner.** D-05 decía que un único runner de cocotb cubría los dos
backends, y eso resultó ser falso: cocotb no tiene backend para xsim
([P-09](../alcance/pendientes.md#p-09)). Lo que comparten es el **oráculo**, que sigue siendo el
modelo dorado, y la métrica, que sigue siendo la comparación bit a bit. Cambia solo cómo llega el
oráculo al simulador:

| | L0 | L1 |
|---|---|---|
| Testbench | Python, `sim/tb/` | SystemVerilog, `sim/tb_sv/` |
| Simulador | Verilator | xsim |
| Cómo llega el oráculo | En proceso, vía cocotb | Por fichero `$readmemh`, de `tools/gen_l1_vectors.py` |
| Cómo se lanza | `make sim` | `vivado -mode batch -source tcl/sim_l1.tcl` |

Los vectores de L1 llevan un manifiesto con la huella SHA-256 de `config/params.toml`, y tanto el
cargador de Python como `tcl/sim_l1.tcl` rechazan un caso cuya huella no coincida: comparar contra
un oráculo generado con otros parámetros es peor que no comparar.

El arnés de L1 —el lector de vectores y el comparador— se prueba a sí mismo en L0, sobre Verilator,
en `sim/tests/test_l1_harness.py`: con vectores limpios tiene que dar cero discrepancias, y con un
único bit cambiado tiene que dar exactamente una. Esa segunda mitad es la que importa, porque un
comparador roto falla en verde.

## Suite de aceptación del DDC

**Autoría de los especialistas de dominio.** Cada caso se ejecuta en L0/L1 (simulación) y en L2
(placa), y los dos resultados deben coincidir con el modelo NumPy bit a bit.

- Tono puro en el centro de banda: amplitud, fase y frecuencia de salida dentro de tolerancia.
- Barrido de tono a lo largo de toda la banda de Nyquist, incluyendo los bordes y el punto de
  aliasing.
- Dos tonos: verificación de rechazo de imagen y de productos de intermodulación.
- Respuesta al impulso y respuesta al escalón de la cadena completa.
- Respuesta de banda de paso y atenuación de banda eliminada frente a la plantilla.
- Compensación de droop del CIC dentro de tolerancia.
- Comportamiento en saturación: entrada a fondo de escala, entrada sobre-escala, reporte de
  overflow.
- Robustez: offset DC, desbalance I/Q inyectado, ruido gaussiano a varios SNR.
- Conmutación 125 ↔ 250 m: continuidad y ausencia de artefactos en el rayo de transición.
- Retune del NCO en caliente (camino AFC): amplitud del transitorio y tiempo de asentamiento.
- Conteo de bins correcto en ambos modos y en todas las extensiones de rango.

## Suite de timing

- Producto cartesiano completo: 4 triggers × 3 anchos de pulso × PRF {200, 326, 500, 651, 999,
  1200} × modos de pulso.
- Jitter de trigger medido en fabric y con osciloscopio; **los dos deben concordar** — si no
  concuerdan, uno de los dos métodos está mal y hay que saber cuál.
- Estabilidad del periodo sobre 10⁶ PRIs.
- Alineación entre el trigger y el primer bin de rango.
- Cambio de PRF en caliente: sin PRI corta ni larga espuria.
- Rechazo de combinaciones ilegales de PRF × rango con el código de error correcto
  ([D-09](../alcance/decisiones.md#d-09)).

## Suite SSI

Tres implementaciones independientes, porque una sola no da confianza — ver
[Z3](../implementacion/fases.md#z3). Los cinco perfiles de movimiento de antena: rotación constante,
aceleración, wrap de 360°, parada y glitch.

El criterio de aceptación no es «az/el correcto» sino **az/el correcto con error temporal acotado y
medido**, porque la parte sutil es la latencia de la lectura SSI frente al instante del trigger.

## Inyección de fallos { #inyeccion-de-fallos }

El catálogo original lista pérdida de link JESD, que aquí no existe. Los sustitutos tienen la misma
**forma** de fallo, que es lo que importa para validar la respuesta del sistema:

| Fallo del plan original | Sustituto en ZedBoard | Comportamiento esperado |
|---|---|---|
| Pérdida de link JESD204B | Underrun de la fuente de muestras (SSA) | BITE lo reporta, el gating se detiene limpiamente, recuperación sin reset |
| Overrun de DMA | Idéntico: consumidor del PS ralentizado a propósito | Descarte contabilizado, sin corrupción, BITE |
| Glitch de encoder | Timeout SSI, trama corta, salto de Gray | Rayo marcado como az/el inválido, **no descartado** |
| Pérdida de reloj | Pérdida de lock de MMCM | BITE, parada segura |
| — | Pérdida de link Ethernet y reconexión | Reconexión sin reset de la placa |
| — | Configuración inválida desde el par remoto | Rechazo con código, estado anterior preservado |

Las dos últimas filas son fallos que el plan original no cubría y que esta plataforma sí permite
ejercitar, porque el 1GbE y el plano de control son reales.

## Endurecimiento

- **Soak de 72 h** a peor caso de PRF y rango.
- **Campaña de throughput sintética**, desacoplada del fabric dilatado — ver
  [Fases, Z5](../implementacion/fases.md#throughput).

## Métrica de rigor

Ninguna prueba pasa por «se ve razonable». Toda salida del DDC se compara **bit a bit** con el
modelo NumPy. Si hay discrepancia, o el RTL está mal o el modelo está mal; en los dos casos hay un
bug real y hay que encontrarlo. Este es el beneficio concreto de sustituir el loopback analógico por
un modelo dorado: **el oráculo es exacto, no estadístico.**
