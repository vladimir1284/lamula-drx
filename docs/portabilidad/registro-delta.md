# Registro delta ZedBoard → ZU9

**Documento vivo desde [Z0](../implementacion/fases.md#z0).** Análogo al «bench-vs-radar delta
register» del plan original, pero para el salto de plataforma. Se actualiza en cada PR y **nada se
cierra sin una entrada aquí**. Se lee en voz alta en cada demo de sprint, para que nadie confunda
«validado en ZedBoard» con «validado».

| # | Delta | Severidad | Compensación |
|---|---|---|---|
| D1 | JESD204B / GTH / SYSREF / latencia determinista / sync multi-dispositivo | **Crítica** | **Ninguna posible.** Requiere hardware con MGTs |
| D2 | Cierre de temporización a 250 MHz frente a 100 MHz | Alta | Diseñar con margen; ejecutar los reportes de temporización con el `FS_HZ` real en CI aunque no haya placa |
| D3 | Artix-7 frente a UltraScale+: DSP48E1 vs E2, BRAM vs URAM, versiones de IP | Media | XCI versionados, regeneración guionizada, revisión de parámetros de IP en el dossier de migración |
| D4 | R5 + TCM frente a A9 + OCM: latencia de interrupción, arranque AMP, coherencia | Media | El PS no está en el camino del trigger. Las latencias medidas en A9 **no** transfieren |
| D5 | AXI HP de 64 bits frente a 128 bits; sin CCI | Media | Parametrizar anchos de bus; no asumir ancho de banda |
| D6 | SSI: LVCMOS 3,3 V frente a RS-422 diferencial | Media | Aislar la capa PHY tras un wrapper; **confirmar transceptores en la portadora ZU9** ([P-02](../alcance/pendientes.md#p-02)) |
| D7 | Drivers de salida de trigger, skew y jitter reales | Media | Caracterizar en ZedBoard como cota inferior; recaracterizar en ZU9 |
| D8 | Camino del DAC AD9129 / referencia de Tx | Media | Solo la síntesis NCO es portable; la interfaz del DAC es trabajo nuevo |
| D9 | Frontal analógico: ruido, offset, desbalance I/Q, nivel de IF, clipping | Alta | Inyectar estas degradaciones sintéticamente en los vectores desde [Z1](../implementacion/fases.md#z1) |
| D10 | DDR de 512 MB frente a varios GB, y su ancho de banda | Baja | Dimensionar buffers por parámetro, no por constante |
| D11 | Throughput no representativo por la dilatación temporal | Media | [Campaña sintética separada](../implementacion/fases.md#throughput) |

## Cómo se usa este registro

- **En cada PR:** si el cambio toca algo que se comporta distinto en la ZU9, la entrada
  correspondiente se actualiza en el mismo PR. Una revisión de portabilidad es obligatoria.
- **En cada hito:** ningún hito Z se declara cerrado sin repasar el registro y anotar qué evidencia
  se aportó por entrada.
- **En [Z5](../implementacion/fases.md#z5):** cada entrada se cierra con evidencia y alimenta el
  **dossier de migración** — qué cambia exactamente al pasar a ZU9, fichero por fichero, con la
  lista de regeneraciones de IP.

## D1 merece una nota aparte

D1 no tiene compensación técnica. No es un delta que se gestione; es un riesgo que se traslada
íntegro al día en que llegue el hardware. La única acción que lo reduce es de compra, no de
ingeniería — ver [P-03](../alcance/pendientes.md#p-03).
