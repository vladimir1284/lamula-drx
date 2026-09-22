// D-09, checks AUTOCONTENIDOS de Z2 (los que no necesitan ningún dato externo):
// que `pulse_width` esté en la tabla de `config/params.toml`
// (`PULSE_WIDTH_CYCLES`) y que quepa en su propio PRI (`pulse_width <
// prf_div`). Puro combinacional y sin estado, mismo patrón que
// `drx_saturate.sv` -- si hace falta latchear esto para AXI-Lite, el sticky
// vive en `drx_axil_regs` (mismo motivo que ya documenta OVERFLOW en su
// cabecera), no aquí.
//
// Lo que este módulo NO valida, a propósito: PRF x rango no ambiguo, el
// corazón real de D-09. Ese check compara contra `r_max_required_m`, un
// umbral que hoy no existe como registro ni como constante de
// `config/params.toml` -- ver
// docs/implementacion/registros.md#deliberadamente-fuera-de-v3. Añadirlo es
// alcance nuevo (subir el mapa de registros), no algo que este módulo dejó
// a medias.
//
// Oráculo: `model/drx_model/timing.py::batch_config_valid` (D-03), verificado
// bit a bit en `sim/tb/tb_drx_timing_config_valid.py`.

`ifndef DRX_TIMING_CONFIG_VALID_SV
`define DRX_TIMING_CONFIG_VALID_SV

module drx_timing_config_valid
  import drx_params_pkg::*;
#(
    parameter int PrfDivBits     = 32,
    parameter int PulseWidthBits = 16
) (
    input  logic [ PrfDivBits-1:0] prf_div,
    input  logic [PulseWidthBits-1:0] pulse_width,
    output logic                    valid
);

  logic pulse_width_in_table;

  always_comb begin
    pulse_width_in_table = 1'b0;
    for (int i = 0; i < $size(PULSE_WIDTH_CYCLES); i++) begin
      if (pulse_width == PulseWidthBits'(PULSE_WIDTH_CYCLES[i])) begin
        pulse_width_in_table = 1'b1;
      end
    end
  end

  logic fits_in_pri;
  assign fits_in_pri = (PrfDivBits'(pulse_width) < prf_div);

  assign valid = pulse_width_in_table && fits_in_pri;

endmodule : drx_timing_config_valid

`endif  // DRX_TIMING_CONFIG_VALID_SV
