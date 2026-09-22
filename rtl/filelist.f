# Lista de fuentes del RTL, en orden de compilación.
#
# La consumen los DOS flujos: `verilator -f` en sim/ y el flujo Vivado de tcl/.
# Una sola lista, dos consumidores: si diverge, un backend compila algo que el
# otro no.
rtl/generated/drx_params_pkg.sv
rtl/generated/drx_ddc_ip_pkg.sv
rtl/generated/drx_regs_pkg.sv
rtl/ssa/drx_ssa_pkg.sv
rtl/vector_source.sv
rtl/drx_heartbeat.sv
rtl/drx_round.sv
rtl/drx_saturate.sv
rtl/drx_ddc_mixer.sv
rtl/drx_ddc_top.sv
rtl/drx_ddc_quad_top.sv
rtl/drx_range_gate.sv
rtl/drx_range_gate_quad_top.sv
# Z2 (D-13): secuenciador de 2 lotes de PRF/ancho de pulso por radial.
rtl/drx_prf_batch_seq.sv
# Z2: generador de N_TRIGGERS triggers independientes (retardo+ancho por
# canal).
rtl/drx_trigger_one_shot.sv
rtl/drx_trigger_gen.sv
# La composición de las dos piezas de arriba en un solo bloque -- ver su propia
# cabecera. Desde v3 del mapa de registros (22-sep-2026) ya lo instancia
# drx_top (config vía AXI-Lite, ver docs/implementacion/registros.md), pero
# deliberadamente SIN conectar a drx_range_gate/vector_source todavía -- ver
# la cabecera de drx_top.sv.
rtl/drx_timing_engine.sv
rtl/drx_axil_regs.sv
# drx_top.sv va al final a propósito: desde esta integración instancia
# vector_source + drx_ddc_quad_top + drx_range_gate_quad_top, así que tiene que
# listarse después de sus cuatro dependencias, no antes (D-02: una sola lista,
# orden de compilación real).
rtl/drx_top.sv
# `drx_top_tieoff.sv` es el `-top` por defecto de `tcl/build.tcl` (sin PS7):
# ata el AXI-Lite de `drx_top` a valores inertes, mismo comportamiento medido
# que antes del puente PS7 (`rtl/drx_zynq_top.sv`, que NO entra en esta lista
# porque instancia `processing_system7`, IP que Verilator no puede elaborar —
# ese fichero solo lo lee `tcl/gen_zynq_bd.tcl`).
rtl/drx_top_tieoff.sv
