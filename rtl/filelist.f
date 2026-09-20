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
rtl/drx_axil_regs.sv
# drx_top.sv va al final a propósito: desde esta integración instancia
# vector_source + drx_ddc_quad_top + drx_range_gate_quad_top, así que tiene que
# listarse después de sus cuatro dependencias, no antes (D-02: una sola lista,
# orden de compilación real).
rtl/drx_top.sv
