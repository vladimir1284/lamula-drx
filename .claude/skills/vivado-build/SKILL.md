---
name: vivado-build
description: Corre el flujo NO-PROJECT de Vivado (tcl/build.tcl) para sintetizar, implementar y generar el bitstream del DRx en zedboard o zu9. Usar cuando pidan compilar el gateware, correr synth/impl/bitstream, o avanzar el cierre de ZM0.
---

# vivado-build

Ejecuta `tcl/build.tcl`, el flujo cero-clicks (D-07: sin `.xpr`, todo por argumentos) que
sintetiza, implementa y genera el bitstream del `drx_top`.

## Antes de correrlo

1. **Comprobar que Vivado existe en el entorno**: `command -v vivado`. A fecha de este repo
   (30 ago 2026, ver `CLAUDE.md`) **no hay Vivado instalado** en el entorno de desarrollo — el
   flujo está escrito y revisado pero nunca ejecutado. Si `vivado` no está en el PATH, dilo
   explícitamente y para ahí; no hay manera de simular esto.
2. Confirmar que `tcl/generated/drx_params.tcl` existe y está al día (`make gen` si no).
3. Si el usuario pide tocar `R₁`, `R₂` o `fs` antes de compilar: **no** — P-01 y P-08 siguen
   abiertos y ese cambio requiere un ADR que sustituya a D-04 (ver `docs/alcance/pendientes.md`).

## Comando

```sh
vivado -mode batch -source tcl/build.tcl -tclargs \
       -platform <zedboard|zu9> -step <synth|impl|bitstream> -outdir build/gw/<platform>
```

- `-step` es acumulativo: `impl` incluye `synth`; `bitstream` incluye los dos.
- Salida por defecto: `build/gw/<platform>/` con `post_synth_utilization.rpt`,
  `post_synth_timing.rpt`, `post_route_utilization.rpt`, `post_route_timing.rpt`,
  `clock_generated.xdc` y, en el paso `bitstream`, `drx_top.bit` + `drx_top.bin` (el `.bin`
  crudo, sin cabecera con timestamp, es el que alimenta `tools/make_boot.sh`).

## Gate que no hay que saltarse

El propio script para con `error` si el cierre de temporización falla:

```tcl
set wns [get_property SLACK [get_timing_paths -delay_type max]]
if {$wns < 0} { error "temporización no cerrada..." }
```

Si el comando termina en ese `error`, **no** es un fallo del flujo — es el flujo haciendo su
trabajo. Reporta el WNS exacto y los informes de utilización/timing; no reintentes bajando el
periodo sin decírselo al usuario (el periodo sale de `FS_HZ` vía `config/params.toml`, no se
edita a mano en el XDC).

## Al reportar el resultado

- Si terminó con bitstream: esta es la primera ejecución real que cierra parte de ZM0. Dilo así,
  no como "una build más".
- Recuerda la advertencia de `AGENTS.md`/`CLAUDE.md`: un bitstream limpio en ZedBoard **no**
  valida JESD204B, clocking/SYSREF, 250 MSPS, frontal analógico, DAC AD9129 ni RS-422. No escribas
  "validado" donde corresponde "validado en ZedBoard".
