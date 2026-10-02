# Build del firmware del PS.
#
# Aquí solo se construye la auto-comprobación del paquete de parámetros, y se
# construye PARA EL HOST -- esto no cambia con Z4. El firmware de verdad
# —FreeRTOS sobre el Cortex-A9, ensamblado de rayos, lwIP sobre GEM0— vive en
# fw/src/app/ desde Z4.2 y se compila cruzado dentro del flujo de Vitis/xsct
# (tcl/gen_bsp.tcl), no con este Makefile: el toolchain de Vitis no es un
# `$(CC)` de línea de comandos independiente, así que `CROSS_COMPILE`/
# `BSP_DIR` de abajo nunca llegaron a rellenarse ni hace falta que lo hagan.
#
#   make            construye y ejecuta la auto-comprobación
#   make check      solo la ejecuta
#   make clean

CROSS_COMPILE ?=
CC := $(CROSS_COMPILE)gcc
BUILD_DIR := ../build/fw

CFLAGS := -std=c11 -Wall -Wextra -Werror -O2
CFLAGS += -Iinclude -I../contract/generated

# Selecciona la plataforma igual que el RTL: por defecto la de desarrollo.
ifeq ($(PLATFORM),zu9)
CFLAGS += -DDRX_PLATFORM_ZU9
endif

SELFTEST := $(BUILD_DIR)/drx_params_selftest

# El framer del contrato (Z4.3) se compila también para el host: es el MISMO
# fichero que Vitis compila cruzado para el Cortex-A9 (tcl/gen_bsp.tcl), no una
# copia. Eso es lo que permite contrastarlo contra la implementación de Python
# generada del mismo esquema sin una placa de por medio. Por eso src/app/ entra
# aquí pese a ser código de FreeRTOS: `drx_contract_io.c` no depende de Xilinx
# ni del planificador, y la mitad de host deja de compilar si alguien le añade
# esa dependencia — que es exactamente el aviso que se quiere.
CONTRACT_IO := $(BUILD_DIR)/drx_contract_io_selftest
CONTROL := $(BUILD_DIR)/drx_control_selftest

.PHONY: all check clean

all: check

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(SELFTEST): src/drx_params_selftest.c include/drx_params.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $< -o $@

$(CONTRACT_IO): src/drx_contract_io_selftest.c src/app/drx_contract_io.c \
                include/drx_contract_io.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) src/drx_contract_io_selftest.c src/app/drx_contract_io.c -o $@

$(CONTROL): src/drx_control_selftest.c src/app/drx_control.c src/app/drx_contract_io.c \
            include/drx_control.h include/drx_contract_io.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) src/drx_control_selftest.c src/app/drx_control.c \
	      src/app/drx_contract_io.c -o $@

check: $(SELFTEST) $(CONTRACT_IO) $(CONTROL)
	@$(SELFTEST) > /dev/null && echo "auto-comprobación de parámetros: OK"
	@$(CONTRACT_IO) encode > /dev/null && echo "framer del contrato: compila y codifica"
	@echo | $(CONTROL) 7 > /dev/null && echo "plano de control: compila y despacha"

clean:
	rm -rf $(BUILD_DIR)
