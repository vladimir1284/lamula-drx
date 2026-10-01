/* Escalón 3 del bring-up: la primera línea de software que corre en esta placa.
 *
 * No hace nada útil a propósito. Lo que prueba es la capa, no la función: que el
 * PS arranca, que `ps7_init` deja los relojes y el MIO usables, que el `stdout`
 * del BSP sale de verdad por el UART1 que el board preset habilita
 * (`PCW_UART1_PERIPHERAL_ENABLE = 1` en el `preset.xml` del board file), y que
 * la descarga de ELF por JTAG funciona.
 *
 * La sonda de DDR de abajo nació como diagnóstico: el 1-oct-2026 esta placa
 * devolvía basura al escribir en DDR aunque `ps7_init` reportara el controlador
 * en modo normal, y el ELF hubo que enlazarlo a OCM para poder arrancar. La
 * causa resultó ser `PCW_UIPARAM_DDR_USE_INTERNAL_VREF` sin fijar en el block
 * design (ver `bringup/README.md`). Con eso corregido el ELF se enlaza a DDR
 * como es normal, y la sonda se queda como comprobación positiva: la ejecuta la
 * CPU, no el depurador, así que cubre el camino que de verdad usa el firmware.
 *
 * El contador lento existe para distinguir "arrancó y se colgó" de "arrancó y
 * sigue vivo": una sola línea impresa no permite distinguir esos dos casos.
 */

#include "xparameters.h"
#include "xil_printf.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "sleep.h"

/* Direcciones repartidas por el mapa de DDR: una sola dirección no distingue
 * "la DDR no responde" de "ese banco concreto está mal". */
static const u32 kProbeAddr[] = {
	0x00100000U, 0x00200000U, 0x01000000U, 0x08000000U, 0x1F000000U,
};
#define PROBE_N (sizeof(kProbeAddr) / sizeof(kProbeAddr[0]))

static void probe_ddr(void)
{
	xil_printf("sonda de DDR (la ejecuta la CPU, no el depurador):\r\n");

	for (unsigned i = 0; i < PROBE_N; i++) {
		const u32 addr = kProbeAddr[i];
		const u32 pattern = 0xA5A5A5A5U ^ addr;

		Xil_Out32(addr, pattern);
		/* Sin esto, un acierto puede venir de la cache y no de la DDR. */
		Xil_DCacheFlushRange((INTPTR)addr, 4);
		Xil_DCacheInvalidateRange((INTPTR)addr, 4);

		const u32 readback = Xil_In32(addr);
		xil_printf("  0x%08x  escrito=0x%08x  leido=0x%08x  %s\r\n",
			   addr, pattern, readback,
			   (readback == pattern) ? "OK" : "FALLA");
	}
}

int main(void)
{
	xil_printf("\r\n");
	xil_printf("=== LAMULA DRx :: bring-up escalon 3 ===\r\n");
	xil_printf("PS arrancado, UART viva, ELF corriendo desde DDR.\r\n");

	/* Tres ticks ANTES de la sonda: si la sonda cuelga el bus -- que es lo que
	 * pasa hoy en esta placa -- el silencio posterior no se puede confundir con
	 * "el ELF nunca arranco". */
	for (unsigned n = 0; n < 3U; n++) {
		xil_printf("tick %u\r\n", n);
		sleep(1);
	}

	probe_ddr();
	xil_printf("sonda de DDR terminada sin colgarse\r\n");

	for (unsigned n = 3U;; n++) {
		xil_printf("tick %u\r\n", n);
		sleep(1);
	}

	return 0;
}
