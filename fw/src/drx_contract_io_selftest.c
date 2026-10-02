/* Arnes de host para fw/src/app/drx_contract_io.c (Z4.3).
 *
 * El framer del contrato es el sitio donde un desacuerdo de formato con el
 * lado DSP se convierte en bytes mal puestos en el cable, y ahi no se detecta
 * solo: las dos lecturas producen tramas que parsean. Este programa expone el
 * framer por stdin/stdout en hexadecimal para que fw/tests/test_contract_io.py
 * lo contraste contra `contract/generated/drx_dsp_v0_1.py`, que sale del mismo
 * esquema por otro generador.
 *
 * Compila para el HOST, igual que drx_params_selftest.c: el gate corre sin
 * toolchain cruzada. El fichero que prueba es el MISMO que Vitis compila para
 * el Cortex-A9, no una copia.
 *
 *   drx_contract_io_selftest encode            vuelca las tramas "up"
 *   drx_contract_io_selftest parse <trozo>     parsea el hex de stdin
 *
 * `<trozo>` es el tamano de los empujones al parser: 0 significa todo de una
 * vez. Darle 1 prueba el caso que de verdad ocurre en TCP -- un mensaje
 * partido en cualquier punto -- y que es justo el que una implementacion
 * ingenua pasa por alto.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "drx_contract_io.h"

/* Valores fijos y distintos entre campos: si el codegen intercambia dos campos
 * del mismo ancho, con ceros o con todo iguales no se notaria. El test de
 * Python usa estos mismos numeros. */
#define SAMPLE_SEQ 0x11223344u
#define SAMPLE_ERROR 7u
#define SAMPLE_UPTIME 0x0A0B0C0Du

static void print_hex(const char *label, const uint8_t *data, size_t n) {
  printf("%s=", label);
  for (size_t i = 0; i < n; i++) {
    printf("%02x", data[i]);
  }
  printf("\n");
}

static int do_encode(void) {
  uint8_t out[256];

  drx_dsp_config_ack_t ack = {0};
  ack.seq = SAMPLE_SEQ;
  ack.error = (uint8_t)SAMPLE_ERROR;
  size_t n = DrxFrame_Encode(out, sizeof(out), DRX_DSP_MSG_CONFIG_ACK, &ack,
                             sizeof(ack), NULL, 0);
  if (n == 0) {
    fprintf(stderr, "DrxFrame_Encode fallo para config_ack\n");
    return 1;
  }
  print_hex("config_ack", out, n);

  drx_dsp_status_t status = {0};
  status.uptime_s = SAMPLE_UPTIME;
  status.bite_flags = 0x40u;
  status.ssa_underruns = 1u;
  status.dma_overruns = 2u;
  status.ssi_errors = 3u;
  status.ddc_overflows = 4u;
  status.last_error = 5u;
  n = DrxFrame_Encode(out, sizeof(out), DRX_DSP_MSG_STATUS, &status,
                      sizeof(status), NULL, 0);
  if (n == 0) {
    fprintf(stderr, "DrxFrame_Encode fallo para status\n");
    return 1;
  }
  print_hex("status", out, n);

  /* Un `ray` con carga variable: dos bins de un canal, pares (I,Q) de int16.
   * Es el unico mensaje cuyo payload_len no es el tamano del struct, asi que
   * es el que distingue las dos lecturas de payload_len. */
  drx_dsp_ray_t ray = {0};
  ray.seq = SAMPLE_SEQ;
  ray.timestamp_ns = 0x0102030405060708ull;
  ray.trigger_count = 0x99u;
  ray.bins = 2u;
  ray.n_channels = 1u;
  ray.channel_mask = (uint8_t)DRX_DSP_CHANNEL_RX_0;
  const int16_t iq[4] = {1, -1, 2, -2};
  n = DrxFrame_Encode(out, sizeof(out), DRX_DSP_MSG_RAY, &ray, sizeof(ray), iq,
                      sizeof(iq));
  if (n == 0) {
    fprintf(stderr, "DrxFrame_Encode fallo para ray\n");
    return 1;
  }
  print_hex("ray", out, n);

  /* Rechazos del emisor: un `body_len` equivocado no debe producir trama. */
  printf("rechaza_body_corto=%zu\n",
         DrxFrame_Encode(out, sizeof(out), DRX_DSP_MSG_CONFIG_ACK, &ack,
                         sizeof(ack) - 1, NULL, 0));
  printf("rechaza_tipo_desconocido=%zu\n",
         DrxFrame_Encode(out, sizeof(out), 99, &ack, sizeof(ack), NULL, 0));
  printf("rechaza_carga_en_mensaje_fijo=%zu\n",
         DrxFrame_Encode(out, sizeof(out), DRX_DSP_MSG_CONFIG_ACK, &ack,
                         sizeof(ack), iq, sizeof(iq)));
  printf("rechaza_buffer_corto=%zu\n",
         DrxFrame_Encode(out, DRX_FRAME_HEADER_SIZE, DRX_DSP_MSG_CONFIG_ACK,
                         &ack, sizeof(ack), NULL, 0));
  return 0;
}

static void on_message(const drx_dsp_header_t *header, const uint8_t *body,
                       uint32_t body_len, void *user) {
  (void)user;
  /* El primer campo de los tres mensajes "down" es `seq`, en el offset 0. Se
   * imprime para que el test compruebe que el cuerpo llego entero y alineado,
   * no solo que el contador subio. */
  uint32_t seq = 0;
  if (body_len >= sizeof(uint32_t)) {
    memcpy(&seq, body, sizeof(seq));
  }
  printf("msg type=%u payload_len=%u seq=0x%08x\n", header->msg_type,
         header->payload_len, seq);
}

static int hex_nibble(int c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

static int do_parse(size_t chunk) {
  static uint8_t wire[65536];
  static uint8_t scratch[65536];
  size_t n = 0;
  int hi = -1;
  int c;

  while ((c = getchar()) != EOF) {
    int v = hex_nibble(c);
    if (v < 0) continue; /* espacios y saltos de linea */
    if (hi < 0) {
      hi = v;
    } else {
      if (n >= sizeof(wire)) {
        fprintf(stderr, "entrada mas larga que el buffer de prueba\n");
        return 1;
      }
      wire[n++] = (uint8_t)((hi << 4) | v);
      hi = -1;
    }
  }
  if (hi >= 0) {
    fprintf(stderr, "numero impar de digitos hexadecimales\n");
    return 1;
  }

  DrxParser parser;
  DrxParser_Init(&parser, scratch, sizeof(scratch));

  size_t offset = 0;
  while (offset < n) {
    size_t step = (chunk == 0u) ? (n - offset) : chunk;
    if (step > n - offset) step = n - offset;

    size_t used = DrxParser_Push(&parser, wire + offset, step, on_message, NULL);
    offset += used;
    if (used < step) break; /* parada dura: el parser no avanza mas */
  }

  printf("accepted=%u rejected=%u status=%d consumed=%zu\n", parser.accepted,
         parser.rejected, (int)parser.status, offset);
  printf("error_code=%u\n", (unsigned)DrxFrame_ErrorCode(parser.status));
  return 0;
}

int main(int argc, char **argv) {
  if (argc >= 2 && strcmp(argv[1], "encode") == 0) {
    return do_encode();
  }
  if (argc >= 3 && strcmp(argv[1], "parse") == 0) {
    return do_parse((size_t)strtoul(argv[2], NULL, 10));
  }
  fprintf(stderr, "uso: %s encode | %s parse <trozo>\n", argv[0], argv[0]);
  return 2;
}
