---
name: vivado-ip
description: Regenera la IP de Xilinx versionada como XCI (tcl/ip.tcl) antes de sintetizar o simular. Usar cuando haya XCI nuevos o modificados en ip/, o antes de un vivado-build/vivado-sim-l1 si la IP pudo quedar desincronizada.
---

# vivado-ip

Ejecuta `tcl/ip.tcl`, que regenera los productos de `generate_target` a partir de los `.xci`
versionados en `ip/`. La regla del repo: `ip/` guarda XCI y nada más — los productos de
generación son artefactos de build, no se commitean, y no se editan a mano en la GUI (eso rompe
la reproducibilidad del bitstream en otra máquina).

## Antes de correrlo

1. Comprobar `command -v vivado`. Igual que en `vivado-build`: a fecha de este repo no hay
   Vivado instalado en el entorno de desarrollo, así que este flujo está escrito y revisado pero
   sin ejecución real todavía.
2. Comprobar si hay algo en `ip/*.xci`. **En Z0 no hay ninguno** — el script lo detecta y hace
   no-op ("no hay XCI en ip/: nada que regenerar (esperado en Z0)"). Eso no es un fallo, es el
   estado esperado de fase. La IP real (DDS/CIC/FIR Compiler) es trabajo de Z1.

## Comando

```sh
vivado -mode batch -source tcl/ip.tcl -tclargs -platform <zedboard|zu9>
```

## Al reportar el resultado

- Si no había XCI: reportarlo como estado esperado de Z0, no como error.
- Si regeneró IP: correr `vivado-build` y `vivado-sim-l1` después usa la IP fresca — no asumas
  que un build o una simulación previos siguen siendo válidos si `ip/` cambió.
