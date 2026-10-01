/* Escalones 4 y 4b del bring-up: un contador en software que mueve los LEDs de
 * la placa, y la lectura de vuelta de los switches.
 *
 * Es el primer código de este repositorio que cruza la frontera PS -> PL. Cada
 * `XGpio_DiscreteWrite` es una escritura AXI-Lite del A9 a un registro que vive
 * en la lógica programable, y el efecto es visible sin instrumentación: los LEDs
 * cuentan en binario.
 *
 * Por qué importa más que la demo: ese es exactamente el mecanismo de
 * `fw/src/app/drx_regs_hw.c` (`Xil_In32`/`Xil_Out32` sobre
 * `XPAR_M_AXI_REGS_BASEADDR`) contra el mapa de registros del DRx, y nadie lo ha
 * visto funcionar nunca en silicio. Si falla aquí, falla con cuatro IP en el
 * diseño en vez de con el datapath entero encima.
 *
 * El canal 2 (switches) valida el camino de LECTURA, del que depende
 * `DrxReg_SelfTest()`. Trátalo como una puerta aparte: si la escritura va y la
 * lectura no, el síntoma en el DRx sería "VERSION devuelve basura".
 */

#include "xparameters.h"
#include "xgpio.h"
#include "xil_printf.h"
#include "sleep.h"

#define LED_CHANNEL 1U
#define SW_CHANNEL  2U

/* Periodo del contador. 200 ms hace que LD0 sea seguible a ojo y que el
 * terminal no se inunde. */
#define TICK_US 200000U

int main(void)
{
	XGpio gpio;
	int status;

	xil_printf("\r\n");
	xil_printf("=== LAMULA DRx :: bring-up escalon 4 ===\r\n");

	status = XGpio_Initialize(&gpio, XPAR_AXI_GPIO_0_DEVICE_ID);
	if (status != XST_SUCCESS) {
		xil_printf("FALLO: XGpio_Initialize devolvio %d\r\n", status);
		return XST_FAILURE;
	}

	XGpio_SetDataDirection(&gpio, LED_CHANNEL, 0x00000000U); /* todo salida  */
	XGpio_SetDataDirection(&gpio, SW_CHANNEL,  0xFFFFFFFFU); /* todo entrada */

	xil_printf("AXI GPIO listo. LEDs = canal %u, switches = canal %u.\r\n",
		   LED_CHANNEL, SW_CHANNEL);
	xil_printf("Mueve los switches: la columna sw= tiene que seguirlos.\r\n");

	for (u32 n = 0;; n++) {
		u32 led = n & 0xFFU;
		u32 sw;

		XGpio_DiscreteWrite(&gpio, LED_CHANNEL, led);
		sw = XGpio_DiscreteRead(&gpio, SW_CHANNEL) & 0xFFU;

		xil_printf("count=%3u  led=0x%02x  sw=0x%02x\r\n",
			   (unsigned)led, (unsigned)led, (unsigned)sw);

		usleep(TICK_US);
	}

	return 0;
}
