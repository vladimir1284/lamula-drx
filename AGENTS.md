# Instrucciones para el agente de desarrollo

## Antes de escribir código

Lee, en este orden:

1. `docs/alcance/contexto.md` — qué es y qué no es este receptor, y cómo se relaciona con los
   proyectos LAMULA DSP y LAMULA RCP.
2. `docs/alcance/decisiones.md` — decisiones ya congeladas. **Ninguna se revierte sin discutirlo**, y
   cada reversión obliga a revisar el registro delta.
3. `docs/alcance/pendientes.md` — huecos abiertos, incluidos los dos que afectan a qué hardware hay
   que comprar.
4. `docs/implementacion/fases.md` — el plan de trabajo.

## Lo primero que hay que hacer

La **fase Z0**: repositorio, flujo Vivado no-project en Tcl, paquete único de parámetros con
`FS_HZ`, runner cocotb de doble backend, modelo dorado en NumPy, y el congelado del esquema DRx↔DSP
v0.1. Nada de funcionalidad. El hito es CI verde sobre un diseño vacío que produce un `BOOT.BIN`
reproducible byte a byte.

No empieces por el DDC. El substrato primero no es burocracia: sin flujo guionizado y sin regresión,
el modelo de entrega acelerado por agentes no funciona, y reconstruirlo al final cuesta un mes.

## Reglas que no se negocian

- **Nada aguas abajo depende de la fuente concreta de muestras.** Todo consume la SSA
  (`sample_stream` AXI4-Stream con backpressure). `jesd204b_source` y `vector_source` son
  intercambiables; nada por encima distingue cuál está activo. Sin esto el trabajo en ZedBoard es
  desechable.
- **`FS_HZ` es la única fuente de verdad temporal.** Ninguna frecuencia literal en `rtl/`, `fw/`,
  `sim/` ni `model/`. **El CI falla si aparece una constante de reloj hardcodeada** — es la única
  defensa contra que la deuda de portabilidad se acumule en silencio.
- **Se dilata todo por igual, nunca solo una parte.** Si un cambio dilata un divisor pero deja otro
  al valor de la ZU9, los vectores dejan de ser comunes a las dos plataformas y se pierde el
  beneficio entero.
- **El modelo dorado es el oráculo, no una comprobación de apoyo.** Toda salida del DDC se compara
  bit a bit contra `model/`. Si RTL y modelo discrepan, hay un bug en uno de los dos — **no ajustes
  el modelo para que el test pase.**
- **El PS no está en el camino del trigger.** Tiempo real duro en la PL; el PS solo mueve datos
  diezmados y metadatos. Las latencias medidas en el A9 de la ZedBoard **no** transfieren al R5 de
  la ZU9.
- **Xilinx-IP-first.** JESD204B, DDS/CIC/FIR Compiler, AXI DMA, AXI Timer/GPIO. El HDL custom se
  reserva para el motor de timing, los lectores SSI, el gating/framing y lo que ninguna IP cubra. No
  reimplementes conversores.
- **El contrato DRx↔DSP es la única interfaz externa.** El DRx no habla con el RCP ni con ORPG. El
  esquema vive en `contract/` como fuente única y genera código para los dos lados; no escribas las
  dos implementaciones a mano.
- **Cada PR que cambie algo que se comporta distinto en la ZU9 actualiza
  `docs/portabilidad/registro-delta.md` en el mismo PR.**

## Lo que esta plataforma no valida

No hay JESD204B, ni clocking/SYSREF, ni 250 MSPS, ni frontal analógico real, ni DAC AD9129, ni
RS-422. El riesgo número uno del proyecto sigue abierto y **no se reduce con trabajo de software**.
No escribas «validado» donde corresponde «validado en ZedBoard».

## Documentación

`docs/` se publica con mkdocs-material y se despliega a Cloudflare Pages en cada push a `main` que
toque `docs/**` o `mkdocs.yml`. Antes de commitear cambios de documentación, comprueba localmente:

```sh
uvx --with mkdocs-material==9.* mkdocs build --strict
```

Los dos documentos de `docs/referencia/` se conservan íntegros y sin editar. Si una decisión cambia,
se actualiza la página derivada correspondiente, **no** el documento de referencia.
