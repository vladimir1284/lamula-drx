// GENERADO por tools/gen_params.py a partir de config/params.toml. NO EDITAR A MANO.
// Cambia config/params.toml y vuelve a generar; el CI comprueba que coinciden.
//
// Fuente única de verdad temporal (D-02). Ningún otro fichero de rtl/ puede
// contener una constante de frecuencia: el gate `tools/check_hardcoded_clock.py`
// falla la build si aparece.

`ifndef DRX_PARAMS_PKG_SV
`define DRX_PARAMS_PKG_SV

package drx_params_pkg;

  localparam int SCHEMA_VERSION = 1;
  localparam string PARAMS_SHA256 = "f2334247721b95ee52e4145a7483c02aa3f37e82a56d73068af822f53d5ad391";

  // -------------------------------------------------------------------------
  // Plataforma seleccionada. Se sobreescribe en la línea de comandos de síntesis
  // con -generic o redefiniendo DRX_PLATFORM_* ; el valor por defecto es la
  // plataforma de desarrollo.
  // -------------------------------------------------------------------------
`ifdef DRX_PLATFORM_ZU9
  localparam longint FS_HZ = FS_HZ_ZU9;
  localparam longint IF_HZ = IF_HZ_ZU9;
  localparam string  PLATFORM = "zu9";
`else
  localparam longint FS_HZ = FS_HZ_ZEDBOARD;
  localparam longint IF_HZ = IF_HZ_ZEDBOARD;
  localparam string  PLATFORM = "zedboard";
`endif

  // --- zedboard: Digilent ZedBoard rev. D ---
  localparam longint FS_HZ_ZEDBOARD = 100000000;
  localparam longint IF_HZ_ZEDBOARD = 24000000;
  // --- zu9: portadora ZU9 + 2x VadaTech FMC213 (no comprada) ---
  localparam longint FS_HZ_ZU9 = 250000000;
  localparam longint IF_HZ_ZU9 = 60000000;

  // -------------------------------------------------------------------------
  // Invariantes de dilatación: idénticos en las dos plataformas.
  // -------------------------------------------------------------------------
  localparam int IF_NORM_NUM = 6;
  localparam int IF_NORM_DEN = 25;

  // Incremento de fase del NCO: round(IF_NORM * 2**NCO_PHASE_BITS). Invariante,
  // que es justamente el punto de D-02.
  localparam longint NCO_PHASE_INC = 1030792151;

  localparam int R1 = 208;
  localparam int R2 = 416;
  localparam int BINS_MODE_FINE = 3689;
  localparam int BINS_MODE_COARSE = 1844;

  localparam int N_RX_CH = 4;
  localparam int N_TX_BURST_CH = 1;
  localparam int N_TRIGGERS = 4;

  localparam int SAMPLE_BITS = 16;
  localparam int IQ_BITS = 16;
  localparam int NCO_PHASE_BITS = 32;
  localparam int NCO_OUT_BITS = 16;

  localparam int PRF_DIV_MIN = 208333;
  localparam int PRF_DIV_MAX = 1250000;
  localparam int PULSE_WIDTH_CYCLES [0:2] = '{200, 415, 825};

  // -------------------------------------------------------------------------
  // Descomposición de la cadena de diezmado (Z1 es dueña de estos valores).
  // -------------------------------------------------------------------------
  localparam int CIC_STAGES = 5;
  localparam int CIC_RATE = 52;
  localparam int CIC_DIFF_DELAY = 1;
  localparam int FIR_DECIM = 4;
  localparam int FIR_TAPS = 63;
  localparam int COARSE_EXTRA_DECIM = 2;

  // Anchos derivados de Hogenauer y de la ganancia de continua de cada FIR,
  // calculados por `model/drx_model/chain.py`: Z1 los consume en
  // `drx_round_sat` para que el punto de recorte de cada etapa sea el mismo
  // número que usa el oráculo, no una copia a mano de la fórmula.
  localparam longint CIC_GAIN = 380204032;
  localparam int CIC_GROWTH_BITS = 29;
  localparam int CIC_REGISTER_BITS = 45;
  localparam int FIR_COEFF_BITS = 18;
  localparam longint FIR_DC_GAIN = 552725;
  localparam int FIR_GROWTH_BITS = 20;
  localparam int HALFBAND_COEFF_BITS = 18;
  localparam longint HALFBAND_DC_GAIN = 328067;
  localparam int HALFBAND_GROWTH_BITS = 19;

  // Ajuste de ganancia fina (Z1: escalado a fondo de escala), un residuo
  // distinto por modo — ver model/drx_model/chain.py::Ddc._residual_gain.
  // Un único multiplicador de coeficiente constante por rama deshace lo que
  // CIC_GROWTH_BITS/FIR_GROWTH_BITS(/HALFBAND_GROWTH_BITS) dejan a medias.
  localparam int GAIN_TRIM_BITS = 18;
  localparam longint FINE_GAIN_COEFF = 43890;
  localparam int FINE_GAIN_FRAC_BITS = 14;
  localparam longint COARSE_GAIN_COEFF = 35070;
  localparam int COARSE_GAIN_FRAC_BITS = 13;

endpackage : drx_params_pkg

`endif  // DRX_PARAMS_PKG_SV
