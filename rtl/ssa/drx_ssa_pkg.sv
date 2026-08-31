// Capa de abstracción de fuente de muestras (SSA) — D-01.
//
// Nada aguas abajo del ADC depende de la fuente concreta de muestras: todo
// consume este interfaz. `jesd204b_source` (solo ZU9) y `vector_source`
// (reproductor de vectores, vive en las dos placas) son intercambiables y nada
// por encima distingue cuál está activo. Sin esto el trabajo en ZedBoard es
// desechable.
//
// Este paquete define ÚNICAMENTE el formato del interfaz. Las implementaciones
// llegan en Z1; Z0 no tiene funcionalidad.

`ifndef DRX_SSA_PKG_SV
`define DRX_SSA_PKG_SV

package drx_ssa_pkg;

  import drx_params_pkg::*;

  // Número total de canales que puede transportar el stream: los 4 Rx más los
  // 2 de burst de Tx.
  localparam int SSA_N_CH = N_RX_CH + N_TX_BURST_CH;

  localparam int SSA_CH_ID_BITS = $clog2(SSA_N_CH);
  localparam int SSA_VALID_MASK_BITS = SSA_N_CH;
  localparam int SSA_SOURCE_TAG_BITS = 2;

  // TDATA: SSA_N_CH muestras de SAMPLE_BITS entrelazadas.
  localparam int SSA_TDATA_BITS = SSA_N_CH * SAMPLE_BITS;

  // Identidad de la implementación que produce el stream. Viaja en TUSER para
  // que el status/BITE pueda reportar de dónde salieron las muestras sin que
  // ninguna etapa de proceso tenga que saberlo.
  typedef enum logic [SSA_SOURCE_TAG_BITS-1:0] {
    SSA_SRC_JESD204B = 2'd0,  // solo ZU9
    SSA_SRC_VECTOR_RT = 2'd1,  // DDR vía MM2S DMA
    SSA_SRC_VECTOR_BRAM = 2'd2,  // bucle en BRAM
    SSA_SRC_VECTOR_THROTTLED = 2'd3  // DDR con backpressure; bit-exacto con RT
  } ssa_source_tag_e;

  // TUSER. El orden de los campos es parte del contrato del interfaz: cambiarlo
  // rompe las dos implementaciones a la vez, que es justo lo que se quiere.
  typedef struct packed {
    logic [SSA_CH_ID_BITS-1:0]     channel_id;
    logic [SSA_VALID_MASK_BITS-1:0] sample_valid_mask;
    ssa_source_tag_e               source_tag;
  } ssa_tuser_t;

  localparam int SSA_TUSER_BITS = $bits(ssa_tuser_t);

endpackage : drx_ssa_pkg

`endif  // DRX_SSA_PKG_SV
