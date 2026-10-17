---
name: vivado-boot-package
description: Empaqueta BOOT.BIN con bootgen (tools/make_boot.sh) a partir del bitstream de vivado-build y comprueba reproducibilidad byte a byte. Usar cuando pidan empaquetar el boot, cerrar ZM0, o verificar que el build es determinista.
---

# vivado-boot-package

Ejecuta `tools/make_boot.sh`, que empaqueta `BOOT.BIN` con `bootgen` y verifica que empaquetar dos
veces con el mismo `.bif` da el mismo fichero byte a byte. El hito ZM0 es exactamente eso: "un git
push produce un BOOT.BIN reproducible byte a byte".

## Antes de correrlo

1. Comprobar `command -v bootgen`. A fecha de este repo no hay Vivado/Vitis (ni por tanto
   bootgen) instalado en el entorno de desarrollo — el script está escrito y revisado, su primera
   ejecución real cierra ZM0.
2. Confirmar que `build/gw/<platform>_zynq/drx_zynq_top.bit` existe — lo produce `vivado-build`
   (`-top zynq`). Se empaqueta el `.bit`, NO el `.bin` crudo: bootgen solo reconoce un bitstream por la
   extensión `.bit`, y con `.bin` el FSBL nunca configura la PL (medido el 16-oct-2026).
   Diagnóstico: `bootgen -arch zynq -read BOOT.BIN` debe mostrar el bitstream con `attributes 0x20`.
3. El script también exige `fsbl.elf` y `drx_app.elf` en el mismo directorio de salida. **Esos
   son artefactos de Z4, no de Z0** — si faltan, el script termina con exit code 2 y un mensaje
   que ya lo dice ("lo produce Z4, no Z0"). No es un error a investigar en fase Z0, es el estado
   esperado.

## Comando

```sh
tools/make_boot.sh <zedboard|zu9> [outdir]
```

Por defecto `outdir` es `build/boot/<platform>`.

## Qué hace el gate de reproducibilidad

Corre `bootgen` dos veces y compara con `cmp -s`; si difieren, sale con exit code 3 y el mensaje
"BOOT.BIN NO es reproducible". Si eso pasa, las tres causas típicas son (documentadas en el propio
script): versión de Vivado/Vitis sin pinar, uso del `.bit` en vez del `.bin` crudo, o una semilla
de implementación (`-seed`) no fijada en `vivado-build`. No lo resuelvas reintentando sin más —
identifica cuál de las tres es.

## Al reportar el resultado

Si termina limpio con `BOOT.BIN.sha256` impreso: esto cierra el último punto pendiente de ZM0
(junto con la primera ejecución real de `vivado-build` y `vivado-sim-l1`). Dilo así explícitamente
— es un hito, no un paso de rutina.
