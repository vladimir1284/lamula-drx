/* Implementacion de fw/include/drx_dma.h. */
#include "drx_dma.h"

#include "xil_printf.h"
#include "xparameters.h"

static XAxiDma g_dma;
static bool g_ready;

bool DrxDma_Init(void)
{
    if (g_ready) {
        return true;
    }

    XAxiDma_Config *config = XAxiDma_LookupConfig(XPAR_AXIDMA_0_DEVICE_ID);

    if (config == NULL) {
        xil_printf("drx_dma: el XSA no declara el AXI DMA\r\n");
        return false;
    }
    if (XAxiDma_CfgInitialize(&g_dma, config) != XST_SUCCESS) {
        xil_printf("drx_dma: XAxiDma_CfgInitialize fallo\r\n");
        return false;
    }
    if (!XAxiDma_HasSg(&g_dma)) {
        xil_printf("drx_dma: el DMA no es scatter-gather\r\n");
        return false;
    }

    g_ready = true;
    return true;
}

XAxiDma *DrxDma_Get(void)
{
    return g_ready ? &g_dma : NULL;
}
