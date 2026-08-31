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
  localparam string PARAMS_SHA256 = "e90ab8bb9c31092b8cab9c74acc55f0c917f5db1e544915f775296748a10b95a";

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
  localparam int N_TX_BURST_CH = 2;
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

endpackage : drx_params_pkg

`endif  // DRX_PARAMS_PKG_SV
