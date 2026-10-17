# Registro delta ZedBoard → ZU9

**Documento vivo desde [Z0](../implementacion/fases.md#z0).** Análogo al «bench-vs-radar delta
register» del plan original, pero para el salto de plataforma. Se actualiza en cada PR y **nada se
cierra sin una entrada aquí**. Se lee en voz alta en cada demo de sprint, para que nadie confunda
«validado en ZedBoard» con «validado».

| # | Delta | Severidad | Compensación | Estado y evidencia (16-oct-2026) |
|---|---|---|---|---|
| D1 | JESD204B / GTH / SYSREF / latencia determinista / sync multi-dispositivo | **Crítica** | **Ninguna posible.** Requiere hardware con MGTs | **Abierto, sin evidencia posible.** Ninguna medida de ZedBoard lo toca. Ver [P-03](../alcance/pendientes.md#p-03) |
| D2 | Cierre de temporización a 250 MHz frente a 100 MHz | Alta | Diseñar con margen; ejecutar los reportes de temporización con el `FS_HZ` real en CI aunque no haya placa | **Abierto.** Lo único medido es WNS = 1,618 ns a 62,5 MHz en la ZedBoard (4-oct-2026); no extrapola a 250 MHz ni a UltraScale+. La ZU9 nunca se sintetizó (sin device pack, A11) y `zu9` está fuera de la matriz de CI, así que la compensación escrita aquí **hoy no se ejecuta** |
| D3 | Artix-7 frente a UltraScale+: DSP48E1 vs E2, BRAM vs URAM, versiones de IP | Media | XCI versionados, regeneración guionizada, revisión de parámetros de IP en el dossier de migración | **Parcial.** XCI versionados y regeneración guionizada y verificada solo en 7-series: `ensure_ip` en `tcl/gen_ip.tcl` (idempotente) y matriz D-12 16/16 tras regenerar el DDS (2-oct-2026). La lista de regeneraciones del [dossier](dossier-migracion.md) es inferencia; nada se probó contra UltraScale+ |
| D4 | R5 + TCM frente a A9 + OCM: latencia de interrupción, arranque AMP, coherencia | Media | El PS no está en el camino del trigger. Las latencias medidas en A9 **no** transfieren | **Abierto, no transfiere.** Todo está medido en A9: 0 `dma_overruns` en 72 h (15-oct-2026) es una observación, no un presupuesto de latencia de ISR ([P-17](../alcance/pendientes.md#p-17)). Sin medida de latencia de interrupción |
| D5 | AXI HP de 64 bits frente a 128 bits; sin CCI | Media | Parametrizar anchos de bus; no asumir ancho de banda | **Sin evidencia.** El camino S2MM corre a 28,9 Mbps por HP0; no se midió el ancho de banda máximo ni se comprobó en esta revisión que los anchos de bus estén parametrizados |
| D6 | SSI: LVCMOS 3,3 V frente a RS-422 diferencial | Media | Aislar la capa PHY tras un wrapper; **confirmar transceptores en la portadora ZU9** ([P-02](../alcance/pendientes.md#p-02)) | **Abierto.** No hay lectores SSI (Z3) y la capa física sigue sin confirmar ([P-02](../alcance/pendientes.md#p-02)) |
| D7 | Drivers de salida de trigger, skew y jitter reales | Media | Caracterizar en ZedBoard como cota inferior; recaracterizar en ZU9 | **Parcial, sin jitter.** `trig_out` sale por pines reales (Pmod JA) y `TRIG_COUNT` midió 223,7 pulsos/s contra 223,47 predichos (1-oct-2026): cuenta pulsos, no caracteriza jitter. Falta el osciloscopio |
| D8 | Camino del DAC AD9129 / referencia de Tx | Media | Solo la síntesis NCO es portable; la interfaz del DAC es trabajo nuevo | **Sin evidencia.** El camino del DAC no se construyó |
| D9 | Frontal analógico: ruido, offset, desbalance I/Q, nivel de IF, clipping | Alta | Inyectar estas degradaciones sintéticamente en los vectores desde [Z1](../implementacion/fases.md#z1) | **Cubierto en sintético.** Catálogo de 8 vectores con ruido, offset de continua, desbalance I/Q y sobre-escala: 8/8 contra rayos reales (4-oct-2026) y 267 pasadas encadenadas sin atasco. Ningún estímulo satura el DDC ([P-22](../alcance/pendientes.md#p-22): máximo 0,927 fs), así que `overflow` → trama `ray` solo lo cubre L0. No es un frontal real |
| D10 | DDR de 512 MB frente a varios GB, y su ancho de banda | Baja | Dimensionar buffers por parámetro, no por constante | **Parcial.** `vector_bram_depth` y `n_ch_top` salen de `config/params.toml`. No se revisaron en esta pasada los buffers de rayos en DDR |
| D11 | Throughput no representativo por la dilatación temporal | Media | [Campaña sintética separada](../implementacion/fases.md#throughput) | **Abierto.** La campaña de throughput sintético a 19,23 MB/s no se ejecutó ni existe el generador. Solo hay medida del camino real: 28,9 Mbps |
| D12 | Ancho del acumulador de fase del NCO: 32 bits aquí (`NCO_PHASE_BITS`), potencialmente más en la ZU9 | Baja | El mensaje `afc` del contrato manda `nco_phase_inc` como **u64** desde v0.1, así que un acumulador más ancho no toca el formato de cable. Lo que sí es local es el registro `NCO_PINC`, de 32 bits: el firmware rechaza con `afc_out_of_range` (contrato v0.7) lo que no quepa, en vez de truncar. Al portar, el ancho del registro y el de `s_axis_config_tdata` del DDS Compiler tienen que subir juntos | **Cerrado en ZedBoard.** `afc_out_of_range` en silicio (`BITE=0x40`, `last_error=12`, 2-oct-2026), inyección de `afc` inválido 5/5 (12-oct-2026) y test que muestrea `nco_pinc` con el strobe alto. Al portar queda subir juntos el registro y `s_axis_config_tdata` |

## Revisión de Z5, 16-oct-2026

De 12 entradas, **una cierra con evidencia (D12)**. D9 cierra solo en sintético, D3, D7 y D10 quedan
parciales, y D1, D2, D4, D5, D6, D8 y D11 siguen abiertas o sin evidencia. Esto es lo esperable
sin hardware de la ZU9 y no un fallo de Z5, pero **no autoriza a escribir «validado»**: lo que hay
es «validado en ZedBoard». Dos cosas pesan más que el resto: D2, cuya compensación en CI no corre, y
D11, que depende de una campaña que no existe.

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
