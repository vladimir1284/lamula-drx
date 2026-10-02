// Blackboxes de los cuatro cores de Xilinx que instancia `rtl/drx_ddc_top.sv`,
// SOLO para que el lint estructural de `--top-module drx_top` resuelva ahora
// que de verdad lo alcanza (antes de esta integración ningún top lintado
// llegaba a `drx_ddc_top`, así que el problema no existía).
//
// Estos cores son cajas negras de Xilinx que este linter no puede elaborar —
// la misma razón por la que L1 corre en xsim y no en cocotb (P-09). Esto no
// cambia eso: solo da un módulo con el nombre y los puertos correctos para
// que la conexión estructural resuelva, sin cuerpo real. NINGÚN simulador
// ejecuta lógica de aquí — L0 nunca llega a esta parte del diseño (los
// testbenches de L1 no pasan por este lint) y L1/xsim usa la IP real
// generada en `ip/*.xci`, no esto.
//
// PELIGRO SI SE MUEVE: este fichero vive en `sim/tb_sv/`, fuera de
// `rtl/filelist.f`, a propósito — el flujo de Vivado (`tcl/build.tcl`,
// `tcl/sim_l1.tcl`) NUNCA debe leerlo. Si esto sustituyera por accidente a la
// IP real en una síntesis, el DDC completo sintetizaría a silencio sin que
// ningún gate lo note. Solo se pasa a mano en las invocaciones de
// `verilator --lint-only` del Makefile, igual que el resto de `sim/tb_sv/`.
//
// Anchos tomados de `rtl/generated/drx_ddc_ip_pkg.sv` (generado de la IP
// real), no inventados, para que el lint no arrastre además una avalancha de
// warnings de ancho.
//
// Las salidas se derivan con una reducción XOR de TODAS las entradas, en vez
// de una constante fija: una salida constante (p. ej. `1'b0`) se propaga como
// constante de compilación a través de `drx_ddc_mixer`/`drx_ddc_top` reales,
// y eso dispara warnings de "señal sin usar" en RTL de verdad y ya verificado
// (`branch_valid`, ver el hallazgo que motivó este comentario) que no tiene
// nada que ver con este stub. Una reducción de las entradas evita el plegado
// a constante sin fingir comportamiento real — sigue sin ejecutar nada con
// sentido, solo dejar de ser trivialmente constante.

`ifndef XILINX_IP_VERILATOR_STUBS_SV
`define XILINX_IP_VERILATOR_STUBS_SV

module dds_compiler_nco
  import drx_ddc_ip_pkg::*;
(
    input  logic                              aclk,
    input  logic                              aresetn,
    // Z4.5: `Phase_Increment {Programmable}` anade este canal de
    // configuracion. Sin TREADY -- la IP real se genera con
    // `Has_TREADY {false}`.
    input  logic                              s_axis_config_tvalid,
    input  logic [DDS_CONFIG_TDATA_BITS-1:0]  s_axis_config_tdata,
    output logic                              m_axis_data_tvalid,
    output logic [DDS_TDATA_BITS-1:0]         m_axis_data_tdata
);
  logic cfg_mix;
  assign cfg_mix = ^{aclk, aresetn, s_axis_config_tvalid, s_axis_config_tdata};
  assign m_axis_data_tvalid = cfg_mix;
  assign m_axis_data_tdata  = {DDS_TDATA_BITS{cfg_mix}};
endmodule : dds_compiler_nco

module cic_compiler_ddc
  import drx_ddc_ip_pkg::*;
(
    input  logic                      aclk,
    input  logic                      aresetn,
    input  logic                      s_axis_data_tvalid,
    output logic                      s_axis_data_tready,
    input  logic [CIC_IN_BITS-1:0]    s_axis_data_tdata,
    output logic                      m_axis_data_tvalid,
    input  logic                      m_axis_data_tready,
    output logic [CIC_TDATA_BITS-1:0] m_axis_data_tdata
);
  logic mix;
  assign mix = ^{aclk, aresetn, s_axis_data_tvalid, s_axis_data_tdata, m_axis_data_tready};
  assign s_axis_data_tready = mix;
  assign m_axis_data_tvalid = mix;
  assign m_axis_data_tdata  = {CIC_TDATA_BITS{mix}};
endmodule : cic_compiler_ddc

module fir_compiler_droop
  import drx_ddc_ip_pkg::*;
(
    input  logic                            aclk,
    input  logic                            aresetn,
    input  logic                            s_axis_data_tvalid,
    output logic                            s_axis_data_tready,
    input  logic [FIR_DROOP_IN_BITS-1:0]    s_axis_data_tdata,
    output logic                            m_axis_data_tvalid,
    input  logic                            m_axis_data_tready,
    output logic [FIR_DROOP_TDATA_BITS-1:0] m_axis_data_tdata
);
  logic mix;
  assign mix = ^{aclk, aresetn, s_axis_data_tvalid, s_axis_data_tdata, m_axis_data_tready};
  assign s_axis_data_tready = mix;
  assign m_axis_data_tvalid = mix;
  assign m_axis_data_tdata  = {FIR_DROOP_TDATA_BITS{mix}};
endmodule : fir_compiler_droop

module fir_compiler_halfband
  import drx_ddc_ip_pkg::*;
(
    input  logic                               aclk,
    input  logic                               aresetn,
    input  logic                               s_axis_data_tvalid,
    output logic                               s_axis_data_tready,
    input  logic [FIR_HALFBAND_IN_BITS-1:0]    s_axis_data_tdata,
    output logic                               m_axis_data_tvalid,
    input  logic                               m_axis_data_tready,
    output logic [FIR_HALFBAND_TDATA_BITS-1:0] m_axis_data_tdata
);
  logic mix;
  assign mix = ^{aclk, aresetn, s_axis_data_tvalid, s_axis_data_tdata, m_axis_data_tready};
  assign s_axis_data_tready = mix;
  assign m_axis_data_tvalid = mix;
  assign m_axis_data_tdata  = {FIR_HALFBAND_TDATA_BITS{mix}};
endmodule : fir_compiler_halfband

`endif  // XILINX_IP_VERILATOR_STUBS_SV
