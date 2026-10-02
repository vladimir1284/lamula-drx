/* Arnes de host para fw/src/app/drx_control.c (Z4.3).
 *
 * Mete por el parser el hex que llega por stdin, deja que el plano de control
 * despache, y vuelca en texto QUE accion se invoco y con que argumentos, mas
 * las respuestas que produjo en hexadecimal. `fw/tests/test_control.py` monta
 * los mensajes de entrada y desmonta las respuestas con la implementacion de
 * Python generada del esquema, asi que lo que se comprueba es el camino
 * completo bytes -> accion -> bytes contra la otra implementacion.
 *
 *   drx_control_selftest <mascara>
 *
 * `<mascara>` dice que acciones existen en este receptor, bit a bit:
 * 1 = select_stimulus, 2 = apply_config, 4 = apply_afc. Lo que no esta en la
 * mascara se deja a NULL, que es como el firmware real declara "esto es Z4.4,
 * todavia no" -- y lo que el plano de control contesta con `unimplemented`.
 *
 * Compila para el HOST. El `drx_control.c` que ejercita es el MISMO que Vitis
 * compila cruzado para el Cortex-A9.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "drx_control.h"

/* Codigo que devuelven las acciones falsas. Distinto de 0 en una de ellas para
 * comprobar que el plano de control propaga el codigo de la accion y no uno
 * inventado por el. */
#define FAKE_STIMULUS_ERROR DRX_DSP_ERROR_VECTOR_UNKNOWN

static uint8_t g_out[4096];
static size_t g_out_len;

static size_t fake_send(const uint8_t *frame, size_t len, void *user) {
  (void)user;
  if (g_out_len + len > sizeof(g_out)) return 0;
  memcpy(g_out + g_out_len, frame, len);
  g_out_len += len;
  return len;
}

static drx_dsp_error_t fake_select(uint8_t vector_id, uint16_t repeat, void *user) {
  (void)user;
  printf("accion select_stimulus vector_id=%u repeat=%u\n", vector_id, repeat);
  /* El vector 99 no existe en ningun catalogo: sirve para comprobar que un
   * codigo de error de la ACCION llega al cable tal cual. */
  return (vector_id == 99u) ? FAKE_STIMULUS_ERROR : DRX_DSP_ERROR_OK;
}

static drx_dsp_error_t fake_config(const drx_dsp_config_t *config, void *user) {
  (void)user;
  printf("accion apply_config seq=%u prf_div=%u range_bins=%u\n", config->seq,
         config->prf_div, config->range_bins);
  return DRX_DSP_ERROR_OK;
}

static drx_dsp_error_t fake_afc(const drx_dsp_afc_t *afc, void *user) {
  (void)user;
  printf("accion apply_afc apply_at_seq=%u\n", afc->apply_at_seq);
  return DRX_DSP_ERROR_OK;
}

static int hex_nibble(int c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "uso: %s <mascara de acciones>\n", argv[0]);
    return 2;
  }
  unsigned mask = (unsigned)strtoul(argv[1], NULL, 0);

  DrxControlOps ops;
  memset(&ops, 0, sizeof(ops));
  if (mask & 1u) ops.select_stimulus = fake_select;
  if (mask & 2u) ops.apply_config = fake_config;
  if (mask & 4u) ops.apply_afc = fake_afc;

  DrxControl ctl;
  DrxControl_Init(&ctl, &ops, fake_send, NULL);

  static uint8_t wire[65536];
  static uint8_t scratch[65536];
  size_t n = 0;
  int hi = -1;
  int c;

  while ((c = getchar()) != EOF) {
    int v = hex_nibble(c);
    if (v < 0) continue;
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

  DrxParser parser;
  DrxParser_Init(&parser, scratch, sizeof(scratch));
  size_t used = DrxParser_Push(&parser, wire, n, DrxControl_OnMessage, &ctl);

  printf("handled=%u replied=%u send_fails=%u consumed=%zu accepted=%u\n",
         ctl.handled, ctl.replied, ctl.send_fails, used, parser.accepted);
  printf("respuestas=");
  for (size_t i = 0; i < g_out_len; i++) printf("%02x", g_out[i]);
  printf("\n");
  return 0;
}
