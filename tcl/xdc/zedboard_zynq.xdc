# Restricciones físicas de `drx_zynq_bd_wrapper` (ZedBoard rev. D,
# XC7Z020-CLG484-1) -- top-level distinto de `drx_top_tieoff`/`zedboard.xdc`:
# `clk`/`rst_n` ya no son puertos de este top (el reloj/reset son internos al
# block design, FCLK_CLK0/peripheral_aresetn del PS7). `DDR`/`FIXED_IO` no
# necesitan PACKAGE_PIN aquí: son pines dedicados del PS7, fijos por el propio
# part, resueltos por Vivado a partir del preset de placa aplicado en
# `tcl/gen_zynq_bd.tcl` — no por XDC.

# LD0. Mismo pin que en zedboard.xdc: sigue siendo el mismo LED físico.
set_property -dict {PACKAGE_PIN T22 IOSTANDARD LVCMOS33} [get_ports led_heartbeat]

# `debug_probe` se deja sin restringir a propósito, igual que en el flujo sin
# PS7 (zedboard.xdc tampoco lo restringe): es un bit de depuración sin
# significado externo, Vivado le asigna un pin libre.
