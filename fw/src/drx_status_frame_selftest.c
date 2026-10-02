/* Arnes de host para fw/src/app/drx_status_frame.c.
 *
 * Imprime en hexadecimal la trama `status` que el firmware mandaria con un
 * conjunto conocido de contadores. El test de Python monta la misma con la
 * implementacion generada del mismo esquema y compara byte a byte.
 */
#include "drx_status_frame.h"

#include <stdio.h>

int main(void)
{
    DrxStatusInputs in = {
        .uptime_s = 0x01020304u,
        .ssa_underruns = 7u,
        .dma_overruns = 0u, /* a cero a proposito: su bandera NO debe levantarse */
        .ssi_errors = 3u,
        .ddc_overflows = 11u,
        .config_rejects = 2u,
        .last_error = 12u, /* afc_out_of_range */
        .link_down = true,
        .mmcm_unlocked = false,
    };

    uint8_t out[256];
    size_t len = DrxStatus_Encode(out, sizeof(out), &in);

    if (len == 0u) {
        printf("len=0\n");
        return 1;
    }

    printf("bite=%08x\n", (unsigned)DrxStatus_BiteFlags(&in));
    printf("status=");
    for (size_t i = 0; i < len; i++) {
        printf("%02x", out[i]);
    }
    printf("\n");

    /* Todo a cero no levanta ninguna bandera: un BITE que siempre dice algo no
     * dice nada. */
    DrxStatusInputs limpio = {0};
    printf("bite_limpio=%08x\n", (unsigned)DrxStatus_BiteFlags(&limpio));

    return 0;
}
