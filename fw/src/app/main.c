/*
 * Copyright (C) 2016 - 2019 Xilinx, Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 * 3. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
 * SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
 * OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
 * IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY
 * OF SUCH DAMAGE.
 *
 * -----------------------------------------------------------------------
 * Base: plantilla "FreeRTOS lwIP Echo Server" de Vitis 2022.2
 * ($XILINX_VITIS/data/embeddedsw/lib/sw_apps/freertos_lwip_echo_server).
 * Z4.2 (LAMULA DRx): un unico cambio funcional sobre el original -- arranca
 * drx_status_task (driver de registros AXI-Lite, fw/include/drx_regs_hw.h)
 * antes de tocar lwIP, para que el bring-up de registros no dependa de que
 * el enlace Ethernet este arriba. echo.c/platform_config.h no cambian.
 */

#include <stdio.h>
#include "xparameters.h"
#include "netif/xadapter.h"
#include "platform_config.h"
#include "xil_printf.h"

#include "drx_afc_app.h"
#include "drx_control_boot.h"
#include "drx_params.h"
#include "drx_ray.h"
#include "drx_status_task.h"
#include "drx_timing_cfg.h"
#include "drx_transport.h"
#include "drx_stimulus.h"
#include "drx_stimulus_catalog.h"

/* A/B espectral del retune (Z4.5). APAGADO por defecto: la medida ya esta
 * hecha y documentada (`fases.md#z4`, 2-oct noche), y dejarlo encendido cuesta
 * dos cosas en cada arranque. Una, los `DRX_AFC_AB_HOLD_MS` de espera van por
 * DELANTE de `lwip_init()`, asi que la red tarda dos minutos en levantar. Dos,
 * el lado B se queda congelado para siempre y el anillo de rayos corre con
 * DRX_RAY_BUFFERS-1 buffers, que es justo el margen que P-17 dice que nadie ha
 * medido.
 *
 * Ponlo a 1 para repetir la medida. El tiempo de espera es para una persona
 * con `tools/dump_ray.py` y una sesion de JTAG, no un parametro del sistema:
 * arrancar xsct y correr el modelo dorado no baja de medio minuto. */
#define DRX_AFC_AB_ON_BOOT 0
#define DRX_AFC_AB_HOLD_MS 120000u

#if LWIP_IPV6==1
#include "lwip/ip.h"
#else
#if LWIP_DHCP==1
#include "lwip/dhcp.h"
#endif
#endif

#ifdef XPS_BOARD_ZCU102
#ifdef XPAR_XIICPS_0_DEVICE_ID
int IicPhyReset(void);
#endif
#endif

int main_thread();
void print_echo_app_header();
void echo_application_thread(void *);

void lwip_init();

#if LWIP_IPV6==0
#if LWIP_DHCP==1
extern volatile int dhcp_timoutcntr;
err_t dhcp_start(struct netif *netif);
#endif
#endif

#define THREAD_STACKSIZE 1024

static struct netif server_netif;
struct netif *echo_netif;

#if LWIP_IPV6==1
void print_ip6(char *msg, ip_addr_t *ip)
{
	print(msg);
	xil_printf(" %x:%x:%x:%x:%x:%x:%x:%x\n\r",
			IP6_ADDR_BLOCK1(&ip->u_addr.ip6),
			IP6_ADDR_BLOCK2(&ip->u_addr.ip6),
			IP6_ADDR_BLOCK3(&ip->u_addr.ip6),
			IP6_ADDR_BLOCK4(&ip->u_addr.ip6),
			IP6_ADDR_BLOCK5(&ip->u_addr.ip6),
			IP6_ADDR_BLOCK6(&ip->u_addr.ip6),
			IP6_ADDR_BLOCK7(&ip->u_addr.ip6),
			IP6_ADDR_BLOCK8(&ip->u_addr.ip6));
}

#else
void
print_ip(char *msg, ip_addr_t *ip)
{
	xil_printf(msg);
	xil_printf("%d.%d.%d.%d\n\r", ip4_addr1(ip), ip4_addr2(ip),
			ip4_addr3(ip), ip4_addr4(ip));
}

void
print_ip_settings(ip_addr_t *ip, ip_addr_t *mask, ip_addr_t *gw)
{

	print_ip("Board IP: ", ip);
	print_ip("Netmask : ", mask);
	print_ip("Gateway : ", gw);
}

#endif
int main()
{
	sys_thread_new("main_thrd", (void(*)(void*))main_thread, 0,
	                THREAD_STACKSIZE,
	                DEFAULT_THREAD_PRIO);
	vTaskStartScheduler();
	while(1);
	return 0;
}

void network_thread(void *p)
{
    struct netif *netif;
    /* the mac address of the board. this should be unique per board */
    unsigned char mac_ethernet_address[] = { 0x00, 0x0a, 0x35, 0x00, 0x01, 0x02 };
#if LWIP_IPV6==0
    ip_addr_t ipaddr, netmask, gw;
#if LWIP_DHCP==1
    int mscnt = 0;
#endif
#endif

    netif = &server_netif;

    xil_printf("\r\n\r\n");
    xil_printf("-----lwIP Socket Mode Echo server Demo Application ------\r\n");

#if LWIP_IPV6==0
#if LWIP_DHCP==0
    /* initialize IP addresses to be used */
    IP4_ADDR(&ipaddr,  192, 168, 1, 10);
    IP4_ADDR(&netmask, 255, 255, 255,  0);
    IP4_ADDR(&gw,      192, 168, 1, 1);
#endif

    /* print out IP settings of the board */

#if LWIP_DHCP==0
    print_ip_settings(&ipaddr, &netmask, &gw);
    /* print all application headers */
#endif

#if LWIP_DHCP==1
	ipaddr.addr = 0;
	gw.addr = 0;
	netmask.addr = 0;
#endif
#endif

#if LWIP_IPV6==0
    /* Add network interface to the netif_list, and set it as default */
    if (!xemac_add(netif, &ipaddr, &netmask, &gw, mac_ethernet_address, PLATFORM_EMAC_BASEADDR)) {
	xil_printf("Error adding N/W interface\r\n");
	return;
    }
#else
    /* Add network interface to the netif_list, and set it as default */
    if (!xemac_add(netif, NULL, NULL, NULL, mac_ethernet_address, PLATFORM_EMAC_BASEADDR)) {
	xil_printf("Error adding N/W interface\r\n");
	return;
    }

    netif->ip6_autoconfig_enabled = 1;

    netif_create_ip6_linklocal_address(netif, 1);
    netif_ip6_addr_set_state(netif, 0, IP6_ADDR_VALID);

    print_ip6("\n\rBoard IPv6 address ", &netif->ip6_addr[0].u_addr.ip6);
#endif

    netif_set_default(netif);

    /* specify that the network if is up */
    netif_set_up(netif);

    /* start packet receive thread - required for lwIP operation */
    sys_thread_new("xemacif_input_thread", (void(*)(void*))xemacif_input_thread, netif,
            THREAD_STACKSIZE,
            DEFAULT_THREAD_PRIO);

#if LWIP_IPV6==0
#if LWIP_DHCP==1
    dhcp_start(netif);
    while (1) {
		vTaskDelay(DHCP_FINE_TIMER_MSECS / portTICK_RATE_MS);
		dhcp_fine_tmr();
		mscnt += DHCP_FINE_TIMER_MSECS;
		if (mscnt >= DHCP_COARSE_TIMER_SECS*1000) {
			dhcp_coarse_tmr();
			mscnt = 0;
		}
	}
#else
    xil_printf("\r\n");
    xil_printf("%20s %6s %s\r\n", "Server", "Port", "Connect With..");
    xil_printf("%20s %6s %s\r\n", "--------------------", "------", "--------------------");

    /* Z4.6: el servidor de eco de la plantilla de Vitis se va, y en su lugar
     * arranca el transporte del contrato DRx<->DSP. El eco sirvio para Z4.2
     * --probar que la pila de red compilaba y enlazaba-- y ya no hace falta:
     * lo que tiene que haber en este puerto es el contrato, no un eco. */
    DrxTransportTask_Create();
    vTaskDelete(NULL);
#endif
#else
    DrxTransportTask_Create();
    vTaskDelete(NULL);
#endif
    return;
}

int main_thread()
{
#if LWIP_DHCP==1
	int mscnt = 0;
#endif

#ifdef XPS_BOARD_ZCU102
#ifdef XPAR_XIICPS_0_DEVICE_ID
	IicPhyReset();
#endif
#endif

	/* Z4.2: bring-up del driver de registros AXI-Lite (drx_regs_hw.c), antes
	 * de lwIP y sin depender de el -- si el enlace Ethernet no esta arriba
	 * todavia se puede seguir viendo por UART que el PS7 llega al mapa de
	 * registros de drx_top.
	 *
	 * El motor de timing se arranca ANTES y de forma sincrona, no como tarea:
	 * en reset los registros de timing valen 0, D-09 marca los dos lotes
	 * invalidos y TIMING_STATUS vale 0x6. Si la tarea de estado arrancase
	 * primero imprimiria ese 0x6 de reset como si fuese un fallo. Ver
	 * fw/src/app/drx_timing_cfg.c. */
	(void)DrxTiming_Start();

	/* Z4.3: el camino DDR -> AXI DMA MM2S -> vector_source. La tarea tiene
	 * que existir antes de la comprobacion: es la que rearma el DMA entre
	 * pasadas, y la comprobacion cuenta pasadas completas. */
	if (DrxStimulus_Init()) {
		DrxStimulusTask_Create();
		/* Dos vectores y no uno: el primero es el tono nominal y el
		 * ultimo del catalogo es el de +6 dBFS, pensado para saturar.
		 * Que una pasada se complete ya prueba que los BYTES llegaron a
		 * la PL; que OVERFLOW salga distinto entre los dos probaria
		 * ademas que llego el DATO, porque lo unico que cambia entre las
		 * dos corridas es el contenido del buffer. */
		(void)DrxStimulus_SelfTest(0u);
		(void)DrxStimulus_SelfTest(DRX_STIMULUS_COUNT - 1u);
	}

	/* Z4.4: el camino de vuelta. La tarea tiene que existir antes de la
	 * comprobacion: la interrupcion de fin de descriptor solo suelta un
	 * semaforo, y es la tarea la que recoge los rayos y los cuenta.
	 *
	 * Esto es lo que por fin da un consumidor a `s_axis_ray_tready`. Hasta
	 * aqui STATUS (overrun) y GATE_TRUNCATED estaban en 0x7 a proposito
	 * porque nadie programaba descriptores; que caigan a cero es el criterio
	 * de que el camino entero funciona. */
	/* Los rayos EXIGEN el modo BRAM-loop, y esto no es una preferencia.
	 *
	 * En Throttled(DDR) `vector_source` presenta un conjunto de N_CH
	 * muestras cada N_CH+1 ciclos como mucho (llena el conjunto muestra a
	 * muestra desde un stream de 16 bits y lo presenta un ciclo), asi que el
	 * `s_valid` que ve el DDC esta alto ~1 de cada 4 ciclos. La cadena solo
	 * avanza con `valid`, asi que una muestra decimada sale cada ~4*R1
	 * ciclos en vez de cada R1. Un rayo de `bins_for_pri(prf_div)` bins
	 * necesitaria entonces unas cuatro veces el PRI, y `ray_start` lo
	 * truncaria antes de completarse: GATE_TRUNCATED subiria y no saldria
	 * NINGUN rayo entero. El nombre del modo ya lo dice -- es throttled.
	 *
	 * Para elegir vector en caliente a tasa plena hace falta que el DMA
	 * entregue N_CH muestras por ciclo, es decir un stream de N_CH*16 bits;
	 * hoy es de 16. Queda anotado, no es Z4.4. */
	DrxStimulus_Stop();

	if (DrxRay_Init()) {
		DrxRayTask_Create();
		(void)DrxRay_SelfTest(DRX_RAY_SELFTEST_MS);
	}

	/* Z4.4: framing y plano de control contra el contrato, ejercitados con
	 * una trama sintetica. No sustituye al DSP real (Z4.6): prueba que una
	 * trama que entra por donde entrara el cable acaba cambiando registros
	 * del motor de timing, sin necesitar enlace Ethernet. */
	DrxControlBoot_SelfTest();

	/* Z4.5: actuacion AFC. Hasta v8 del mapa de registros esto era imposible
	 * -- el incremento de fase del NCO estaba congelado en la IP del DDS
	 * Compiler. Se manda un `afc` sintetico por el mismo parser por el que
	 * entrara el del DSP y se comprueba que NCO_PINC cambia; lo que esto NO
	 * prueba es que el NCO mezcle a la frecuencia nueva, que se ve en el
	 * espectro de un rayo, no en un registro. */
	DrxAfcApp_Init();
	(void)DrxAfcApp_SelfTest();

	/* Z4.4: congela un rayo entero para que `tools/dump_ray.py` pueda leerlo
	 * por JTAG y compararlo contra el modelo dorado. Es la primera medida del
	 * DATO en esta cadena: Z4.3 solo pudo probar que los BYTES llegaban a la
	 * PL.
	 *
	 * El estimulo es el de la BRAM, que `tools/gen_vector_source_init.py`
	 * carga con `vectors.tone()` -- exactamente el mismo array que el caso
	 * `tono_if` del catalogo, comprobado. Es el tono que el NCO tiene que
	 * llevar a continua, asi que la salida esperada no necesita
	 * interpretacion: el pico tiene que caer en continua. */
	if (DrxRay_Freeze()) {
		vTaskDelay(pdMS_TO_TICKS(100));
		DrxRay_DumpLast(0u);
		(void)DrxControlBoot_RaySelfTest();

		/* Z4.5: A/B espectral del retune. Lo que falta por medir no es que
		 * NCO_PINC cambie --eso ya lo dijo la autoprueba de arriba-- sino
		 * que el NCO mezcle de verdad a la frecuencia nueva.
		 *
		 * La palabra se deriva de los parametros generados, no se clava:
		 * se baja el NCO en un cuarto de la banda decimada, asi que el pico
		 * tiene que salir de continua y caer cerca de -0,25 de fs_dec. Un
		 * desplazamiento mas grande se saldria de la banda y uno mas
		 * pequeno no se distinguiria de la resolucion del espectro.
		 *
		 * `1u << 30` es 2^32/4, con lo que el calculo entero no desborda en
		 * 32 bits: (2^32/4)/R1 == (2^32 * (0,25/R1)). */
#if DRX_AFC_AB_ON_BOOT
		DrxAfcApp_RetuneAB(
			(uint32_t)DRX_NCO_PHASE_INC - ((1u << 30) / DRX_R1),
			DRX_AFC_AB_HOLD_MS);
#else
		/* Sin el A/B, el rayo congelado de arriba sobra: devolverlo al anillo
		 * deja los DRX_RAY_BUFFERS completos para el transporte. */
		DrxRay_Thaw();
#endif
	}

	DrxStatusTask_Create();

	/* initialize lwIP before calling sys_thread_new */
    lwip_init();

    /* any thread using lwIP should be created using sys_thread_new */
    sys_thread_new("NW_THRD", network_thread, NULL,
		THREAD_STACKSIZE,
            DEFAULT_THREAD_PRIO);

#if LWIP_IPV6==0
#if LWIP_DHCP==1
    while (1) {
	vTaskDelay(DHCP_FINE_TIMER_MSECS / portTICK_RATE_MS);
		if (server_netif.ip_addr.addr) {
			xil_printf("DHCP request success\r\n");
			print_ip_settings(&(server_netif.ip_addr), &(server_netif.netmask), &(server_netif.gw));
			DrxTransportTask_Create();
			break;
		}
		mscnt += DHCP_FINE_TIMER_MSECS;
		if (mscnt >= DHCP_COARSE_TIMER_SECS * 2000) {
			xil_printf("ERROR: DHCP request timed out\r\n");
			xil_printf("Configuring default IP of 192.168.1.10\r\n");
			IP4_ADDR(&(server_netif.ip_addr),  192, 168, 1, 10);
			IP4_ADDR(&(server_netif.netmask), 255, 255, 255,  0);
			IP4_ADDR(&(server_netif.gw),  192, 168, 1, 1);
			print_ip_settings(&(server_netif.ip_addr), &(server_netif.netmask), &(server_netif.gw));
			/* print all application headers */
			xil_printf("\r\n");
			xil_printf("%20s %6s %s\r\n", "Server", "Port", "Connect With..");
			xil_printf("%20s %6s %s\r\n", "--------------------", "------", "--------------------");

			DrxTransportTask_Create();
			break;
		}
	}
#endif
#endif
    vTaskDelete(NULL);
    return 0;
}
