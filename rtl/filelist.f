# Lista de fuentes del RTL, en orden de compilación.
#
# La consumen los DOS flujos: `verilator -f` en sim/ y el flujo Vivado de tcl/.
# Una sola lista, dos consumidores: si diverge, un backend compila algo que el
# otro no.
rtl/generated/drx_params_pkg.sv
rtl/ssa/drx_ssa_pkg.sv
rtl/drx_heartbeat.sv
rtl/drx_top.sv
