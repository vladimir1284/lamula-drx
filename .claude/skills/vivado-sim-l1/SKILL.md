---
name: vivado-sim-l1
description: Corre la simulación L1 sobre xsim (tcl/sim_l1.tcl) para un caso de tools/gen_l1_vectors.py, comparando el DDC contra el oráculo del modelo dorado bit a bit. Usar cuando pidan correr L1, validar el DDC en RTL contra el modelo, o avanzar P-09.
---

# vivado-sim-l1

Ejecuta `tcl/sim_l1.tcl`: elabora `sim/tb_sv/tb_l1_ddc.sv` sobre xsim y compara la salida del DDC
contra los `.hex` que genera el modelo dorado en NumPy. Es la contraparte de L0 (que corre en
Verilator/cocotb): L1 no pasa por cocotb porque los cores del DDC son cajas negras que Verilator
no elabora y cocotb no tiene backend para xsim (P-09, ya decidido).

## Antes de correrlo

1. Comprobar `command -v vivado`. A fecha de este repo no hay Vivado instalado en el entorno de
   desarrollo — este flujo está escrito y revisado, con el arnés ya verificado sobre Verilator
   (`sim/tests/test_l1_harness.py`), pero **sin correr una sola vez sobre xsim real**.
2. Generar (o confirmar que existen) los vectores del caso pedido:
   ```sh
   python3 tools/gen_l1_vectors.py
   ```
   El script de Vivado falla explícitamente (`error "no hay vectores en ..."`) si no están.
3. Si `drx_ddc_top.sv` todavía no está en `rtl/filelist.f` (trabajo de Z1, no hecho en Z0): la
   elaboración va a abortar **a propósito**. Eso no es un bug del flujo de simulación — es el
   testbench diciendo qué falta. No lo trates como fallo a arreglar sin más contexto; repórtalo
   como "esperado hasta que exista el DDC".

## Comando

```sh
vivado -mode batch -source tcl/sim_l1.tcl -tclargs \
       -platform <zedboard|zu9> -case <nombre-del-caso>
```

Los nombres de caso los define `tools/gen_l1_vectors.py`, no se inventan aquí.

## Gate que el propio script aplica

El script compara `params_sha256` del manifiesto contra `$::drx::PARAMS_SHA256` generado desde
`config/params.toml` y para con `error` si no coinciden — es la defensa contra comparar RTL de un
config contra vectores de otro. Si falla ahí, la solución es regenerar vectores
(`python3 tools/gen_l1_vectors.py`), no forzar la comparación.

## Al reportar el resultado

- "Terminado" en el log no significa passed silenciosamente: revisa qué compara
  `sim/tb_sv/drx_l1_checker.sv` y si el conteo de muestras esperado (`+expected_count`) se cumplió.
- El modelo dorado es el oráculo, no una comprobación de apoyo (regla de `AGENTS.md`): si RTL y
  modelo discrepan, hay un bug en uno de los dos. **No** propongas ajustar el modelo para que
  pase.
