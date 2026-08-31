# 7 · Resultados

Todo lo de esta página es salida real de una ejecución sobre el árbol limpio. Reproducible con:

```sh
make venv && make check
```

## Resumen

| Gate | Herramienta | Estado |
|---|---|---|
| Paquete de parámetros al día | `tools/gen_params.py --check` | verde |
| Coeficientes congelados al día | `tools/gen_coeffs.py --check` | verde |
| Contrato al día | `tools/gen_contract.py --check` | verde |
| Sin constantes de reloj | `tools/check_hardcoded_clock.py` | verde |
| Lint de Python | Ruff 0.14.5 | verde |
| Lint de HDL | Verilator 5.006, `-Wall` | verde |
| Regresión | pytest 8.4.2 | **69 tests, verde** |
| Síntesis e implementación | Vivado | **no ejecutado**, falta la herramienta |
| `BOOT.BIN` reproducible | bootgen | **no ejecutado**, falta la herramienta |

## Los gates de generación y lint

```sh
$ .venv/bin/python tools/gen_params.py --check
parámetros generados al día

$ .venv/bin/python tools/gen_coeffs.py --check
coeficientes al día

$ .venv/bin/python tools/gen_contract.py --check
contrato generado al día

$ .venv/bin/python tools/check_hardcoded_clock.py
sin constantes de reloj hardcodeadas

$ .venv/bin/ruff check .
All checks passed!

$ make lint-hdl
verilator --lint-only -Wall --timing sim/verilator_waivers.vlt \
  rtl/generated/drx_params_pkg.sv rtl/ssa/drx_ssa_pkg.sv \
  rtl/drx_heartbeat.sv rtl/drx_top.sv --top-module drx_top
```

El lint de HDL no imprime nada cuando pasa. Verilator con `-Wall` trata los avisos como errores, así
que salida vacía y código 0 significa cero avisos.

### El gate de reloj, comprobado en las dos direcciones

Un gate que nunca ha fallado no se sabe si funciona. Este se probó con una constante plantada:

```sh
$ echo 'localparam int FS = 100_000_000;' > /tmp/bad.sv
$ .venv/bin/python tools/check_hardcoded_clock.py /tmp/bad.sv
/tmp/bad.sv:1: constante de reloj hardcodeada: 100_000_000
    localparam int FS = 100_000_000;

1 constante(s) sospechosa(s). ...
$ echo $?
1
```

## Medidas del modelo dorado

Números producidos por el propio modelo, no estimaciones.

### CIC · N=5, R=52, M=1

| Magnitud | Valor | De dónde sale |
|---|---|---|
| Ganancia en continua | 380 204 032 = 52⁵ | Medida sobre entrada constante |
| Bits de crecimiento | 29 | ⌈5·log₂52⌉ |
| Ancho de registro | **45 bits** | 16 de entrada + 29 |
| Caída en el borde de banda de paso (0,09) | −0,580 dB | `Cic.response` |

### FIR compensador · 63 taps, coeficientes de 18 bits

| Magnitud | Valor |
|---|---|
| Ganancia de continua entera | 552 725 |
| Coeficiente mínimo / máximo | −23 885 / 131 071 |
| Rizado de la cascada CIC+FIR en 0…0,06 | **0,006 dB** |
| Rizado de la cascada CIC+FIR en 0…0,09 | 0,909 dB |
| Atenuación en la banda que pliega (≥0,16) | **−58,7 dB** |

El compensador reduce el rizado en un factor 40 en los dos tercios interiores de la banda y lo empeora
en el borde. Es un punto de diseño mejorable, documentado en [la página del DDC](03-ddc.md), no un
bug: los 63 taps y la ventana de Hamming son un compromiso que Z1 revisará contra el cierre de
recursos real.

### Semibanda del modo grueso · 23 taps

| Magnitud | Valor |
|---|---|
| Ganancia de continua entera | 328 067 |
| Atenuación en la banda que pliega (≥0,35) | **−69,4 dB** |
| Rizado de banda de paso (0…0,15) | 1,20 dB |

### NCO

| Magnitud | Valor |
|---|---|
| Palabra de fase | 1 030 792 151 (idéntica en las dos plataformas) |
| Peor espurio de truncamiento | **−86,4 dBc** |

### Cadena completa

Tono de −3 dBFS, 60 000 muestras, pico de entrada 23 197:

| Modo | R | Muestras de salida | \|I+jQ\| medio | Desviación relativa |
|---|---|---|---|---|
| fino | 208 | 288 | 4330,0 | **0,00e+00** |
| grueso | 416 | 144 | 2709,0 | **0,00e+00** |

Desviación exactamente cero: la amplitud es constante bit a bit.

### Huella del oráculo

```
fine    192 muestras  edf20575a4b82e3b96a2bd4333b60e0922e69cd1554ab7504154eb2aadcd6cca
coarse   96 muestras  d51dee4c0b61b30ea7a93dd6dd3aa5ca0d1c56e2f37b8979913d5ec4bef76feb
```

## Simulación L0

```
     0.00ns INFO  cocotb  Running on Verilator version 5.006 2023-01-22
     0.00ns INFO  cocotb  Running tests with cocotb v1.9.2
   350.00ns INFO  cocotb.regression  test_periodo_del_latido passed
   460.00ns INFO  cocotb.regression  test_reset_asincrono passed
  ** tb_drx_heartbeat.test_periodo_del_latido   PASS         350.00           0.00      81042.87  **
  ** tb_drx_heartbeat.test_reset_asincrono      PASS         110.00           0.00      81732.09  **
```

Desde limpio tarda unos 17 s, casi todo compilando el C++ que genera Verilator.

## Contrato: C y Python, byte a byte

```sh
$ ./dump                       # programa en C con la cabecera generada
52 44 4d 4c 00 01 01 00 64 73 00 00
sizeof header=12 ray=36 status=28 config=48 config_ack=8 afc=16

$ .venv/bin/python dump.py     # implementación de Python generada
52 44 4d 4c 00 01 01 00 64 73 00 00
```

## Firmware

```sh
$ make -C fw check
auto-comprobación de parámetros: OK

$ make -C fw check PLATFORM=zu9
auto-comprobación de parámetros: OK
```

Compila y pasa para las dos plataformas, con `gcc` de host. La toolchain cruzada y el BSP llegan en
Z4.

## La regresión completa

69 tests, todos en verde:

```
model/tests/test_bloques.py::test_nco_emite_en_la_frecuencia_normalizada_del_if PASSED
model/tests/test_bloques.py::test_nco_respeta_el_fondo_de_escala PASSED
model/tests/test_bloques.py::test_el_acumulador_de_fase_envuelve PASSED
model/tests/test_bloques.py::test_el_nco_es_determinista PASSED
model/tests/test_bloques.py::test_ganancia_en_continua_del_cic PASSED
model/tests/test_bloques.py::test_ancho_de_registro_de_hogenauer PASSED
model/tests/test_bloques.py::test_el_cic_diezma_por_r PASSED
model/tests/test_bloques.py::test_el_cic_rechaza_un_ancho_que_no_cabe_en_int64 PASSED
model/tests/test_bloques.py::test_la_respuesta_del_cic_cae_monotona_en_la_banda_de_paso PASSED
model/tests/test_bloques.py::test_los_coeficientes_congelados_estan_al_dia PASSED
model/tests/test_bloques.py::test_el_fir_tiene_los_taps_del_paquete_de_parametros PASSED
model/tests/test_bloques.py::test_el_fir_compensa_el_droop_del_cic PASSED
model/tests/test_bloques.py::test_el_fir_atenua_lo_que_pliega_sobre_la_banda_de_paso PASSED
model/tests/test_bloques.py::test_el_semibanda_diezma_por_dos PASSED
model/tests/test_bloques.py::test_el_semibanda_atenua_lo_que_pliega PASSED
model/tests/test_bloques.py::test_faltan_coeficientes_da_un_error_util PASSED
model/tests/test_chain.py::test_el_diezmado_coincide_con_el_paquete_de_parametros[fine] PASSED
model/tests/test_chain.py::test_el_diezmado_coincide_con_el_paquete_de_parametros[coarse] PASSED
model/tests/test_chain.py::test_un_tono_en_el_if_baja_a_continua[fine] PASSED
model/tests/test_chain.py::test_un_tono_en_el_if_baja_a_continua[coarse] PASSED
model/tests/test_chain.py::test_el_oraculo_es_reproducible_bit_a_bit[fine] PASSED
model/tests/test_chain.py::test_el_oraculo_es_reproducible_bit_a_bit[coarse] PASSED
model/tests/test_chain.py::test_el_modo_grueso_diezma_el_doble_que_el_fino PASSED
model/tests/test_chain.py::test_una_entrada_fuera_de_banda_se_rechaza PASSED
model/tests/test_chain.py::test_el_offset_de_continua_se_rechaza PASSED
model/tests/test_chain.py::test_el_ruido_no_rompe_la_cadena_y_es_reproducible PASSED
model/tests/test_chain.py::test_una_cadena_inconsistente_con_los_parametros_falla_ruidosamente PASSED
model/tests/test_chain.py::test_la_salida_se_puede_enrejar_en_rayos PASSED
model/tests/test_fixed.py::test_limites_con_signo PASSED
model/tests/test_fixed.py::test_wrap_es_complemento_a_dos PASSED
model/tests/test_fixed.py::test_saturate_marca_overflow_por_muestra PASSED
model/tests/test_fixed.py::test_redondeo_es_medio_hacia_arriba PASSED
model/tests/test_fixed.py::test_truncamiento_va_hacia_menos_infinito PASSED
model/tests/test_fixed.py::test_quantize_satura_lo_que_se_sale PASSED
model/tests/test_fixed.py::test_growth_bits PASSED
model/tests/test_gating_y_vectores.py::test_conteo_de_bins_por_modo PASSED
model/tests/test_gating_y_vectores.py::test_los_rayos_completos_no_se_marcan_truncados PASSED
model/tests/test_gating_y_vectores.py::test_un_rayo_corto_se_marca_en_vez_de_descartarse PASSED
model/tests/test_gating_y_vectores.py::test_tlast_cae_en_la_ultima_muestra_de_cada_rayo PASSED
model/tests/test_gating_y_vectores.py::test_gating_rechaza_entradas_descuadradas PASSED
model/tests/test_gating_y_vectores.py::test_el_tono_por_defecto_sale_en_el_if PASSED
model/tests/test_gating_y_vectores.py::test_la_amplitud_en_dbfs_es_la_pedida PASSED
model/tests/test_gating_y_vectores.py::test_la_entrada_sobre_escala_satura_en_vez_de_envolver PASSED
model/tests/test_gating_y_vectores.py::test_los_vectores_son_identicos_en_las_dos_plataformas PASSED
model/tests/test_gating_y_vectores.py::test_el_desbalance_iq_cambia_la_señal_y_es_determinista PASSED
model/tests/test_gating_y_vectores.py::test_el_ruido_exige_semilla PASSED
model/tests/test_params.py::test_hay_dos_plataformas PASSED
model/tests/test_params.py::test_if_normalizado_identico_en_las_dos_plataformas PASSED
model/tests/test_params.py::test_palabra_de_fase_del_nco_es_invariante PASSED
model/tests/test_params.py::test_el_if_cae_en_un_entero_de_hz PASSED
model/tests/test_params.py::test_la_descomposicion_de_la_cadena_reproduce_r1_y_r2 PASSED
model/tests/test_params.py::test_tamano_de_celda_en_la_plataforma_objetivo PASSED
model/tests/test_params.py::test_prf_de_pared_se_dilata_y_el_registro_no PASSED
model/tests/test_params.py::test_los_ficheros_generados_estan_al_dia PASSED
model/tests/test_params.py::test_el_toml_no_declara_frecuencias_fuera_de_platform PASSED
sim/tests/test_l0_heartbeat.py::test_l0_heartbeat_verilator PASSED
sim/tests/test_l0_heartbeat.py::test_l1_declara_su_bloqueo PASSED
contract/tests/test_contract.py::test_los_ficheros_generados_estan_al_dia PASSED
contract/tests/test_contract.py::test_los_tres_lados_declaran_el_mismo_tamano PASSED
contract/tests/test_contract.py::test_c_y_python_producen_los_mismos_bytes PASSED
contract/tests/test_contract.py::test_ida_y_vuelta_en_python PASSED
contract/tests/test_contract.py::test_el_codigo_de_error_de_d09_existe PASSED
contract/tests/test_contract.py::test_los_tipos_de_mensaje_son_unicos PASSED
fw/tests/test_params_header.py::test_el_firmware_ve_los_mismos_parametros_que_el_modelo PASSED
fw/tests/test_params_header.py::test_el_firmware_compila_tambien_para_la_plataforma_objetivo PASSED
```

## Lo que estos 69 tests no demuestran

Merece un apartado propio, porque la diferencia entre «CI verde» y «funciona» es donde se pierden los
proyectos.

**No demuestran que el modelo coincida con la IP de Xilinx.** El modelo está escrito contra la
configuración *pretendida* del DDS/CIC/FIR Compiler, no contra la IP real: en Z0 no hay Vivado. Esa
comparación es Z1, y puede obligar a ajustar modos de redondeo.

**No demuestran que el RTL haga el DDC.** El RTL de Z0 es un divisor de reloj. Lo que la simulación
prueba es que el substrato está cerrado, no que el receptor funcione — no existe todavía.

**No demuestran nada sobre temporización.** No se ha sintetizado nunca. Que el 7Z020-1 cierre a
100 MHz con cuatro canales es una **hipótesis**, y está listada como riesgo con su mitigación (bajar a
62,5 MHz o a dos canales).

**No demuestran que el `BOOT.BIN` sea reproducible.** Nunca se ha construido uno.

**No dicen nada sobre JESD204B, clocking, SYSREF, 250 MSPS, el frontal analógico, el DAC AD9129 ni
RS-422.** Ese es el riesgo número uno del proyecto y **no se reduce con trabajo de software**. Ver
[P-03](../alcance/pendientes.md#p-03).

Y el recordatorio que `AGENTS.md` repite: **no escribas «validado» donde corresponde «validado en
ZedBoard»** — y ahora mismo, ni siquiera eso: corresponde «validado en simulación».

## Lo siguiente

1. Una máquina con Vivado, y ejecutar `tcl/build.tcl` para las dos plataformas.
2. Decidir [P-09](../alcance/pendientes.md#p-09): qué hace L1 ahora que se sabe que cocotb no habla
   con xsim.
3. Empaquetar el `BOOT.BIN` cuando Z4 dé los ELF, y comprobar que se repite byte a byte.

Con eso, ZM0 se cierra y empieza Z1 — el DDC de verdad, contra este oráculo.

---

**Anterior:** [6 · Gateware](06-gateware.md) · **Volver al** [índice del tutorial](index.md)
