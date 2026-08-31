# Build del firmware del PS.
#
# FASE Z0: aquí solo se construye la auto-comprobación del paquete de parámetros,
# y se construye PARA EL HOST. El firmware de verdad —FreeRTOS sobre el Cortex-A9,
# ensamblado de rayos, lwIP sobre GEM0— es Z4 y necesita Vitis y un BSP generado
# desde el XSA, que este repositorio todavía no produce.
#
# Cuando llegue Z4, `CROSS_COMPILE` y `BSP_DIR` son los dos únicos puntos de
# entrada que hay que rellenar; el resto de la estructura ya vale.
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

.PHONY: all check clean

all: check

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(SELFTEST): src/drx_params_selftest.c include/drx_params.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $< -o $@

check: $(SELFTEST)
	@$(SELFTEST) > /dev/null && echo "auto-comprobación de parámetros: OK"

clean:
	rm -rf $(BUILD_DIR)
