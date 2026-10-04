"""L0 — `drx_axil_regs`, el mapa de registros AXI-Lite de `drx_top` (Z1, ver
`docs/implementacion/registros.md`).

Sin `cocotbext-axi` en el árbol (`requirements-dev.txt` solo trae `cocotb`
puro) — los write/read de abajo son un maestro AXI-Lite mínimo escrito a mano,
un canal a la vez, sin outstanding: exactamente lo que soporta el slave (ver
la cabecera de `rtl/drx_axil_regs.sv`).

Mismo cuidado de muestreo que ya documenta `sim/tb/tb_drx_range_gate.py`: cada
par valid/ready se lee TAL COMO ESTÁ antes de `await RisingEdge`, no después —
en este slave, `awready`/`wready`/`arready` caen el MISMO flanco en que se
acepta la transferencia (dependen de `have_aw`/`have_w`/`have_ar`, que se
ponen a uno en ese flanco), así que leerlos después de `await RisingEdge` vería
la mayoría de las veces el valor YA bajado por esa misma aceptación, un
desfase de un ciclo que hace parecer que el handshake nunca ocurrió.
"""

import tomllib
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge
from drx_model.params import load

PARAMS = load("zedboard")
CLK_PERIOD_PS = round(1e12 / PARAMS.fs_hz)  # clock-const-ok: conversión de unidades s->ps

N_CH = 3

REG_VERSION_ADDR = 0x00
REG_CTRL_ADDR = 0x04
REG_STATUS_ADDR = 0x08
REG_OVERFLOW_ADDR = 0x0C
REG_TIMING_CTRL_ADDR = 0x10
REG_TIMING_STATUS_ADDR = 0x14
REG_PRF_DIV_LOW_ADDR = 0x18
REG_PRF_DIV_HIGH_ADDR = 0x1C
REG_PULSE_WIDTH_ADDR = 0x20
REG_N_PULSES_ADDR = 0x24
REG_TRIG_DELAY_ADDR = [0x28, 0x2C, 0x30, 0x34]
REG_TRIG_WIDTH_ADDR = [0x38, 0x3C, 0x40, 0x44]
REG_BINS_LOW_ADDR = 0x48
REG_BINS_HIGH_ADDR = 0x4C
REG_GATE_TRUNCATED_ADDR = 0x50
REG_TRIG_COUNT_ADDR = 0x54  # v7, Z4.1
REG_NCO_PINC_ADDR = 0x58  # v9, Z4.5
REG_VEC_ADDR_ADDR = 0x5C  # v11
REG_VEC_DATA_ADDR = 0x60  # v11
REG_VEC_LEN_ADDR = 0x64  # v11
REG_RESERVED_ADDR = 0x68  # primera palabra sin implementar desde v11

#: Ancho del puntero de VEC_ADDR/VEC_LEN, el mismo `$clog2(VECTOR_BRAM_DEPTH)`
#: que usan `drx_axil_regs` y `vector_source`. Derivado, no literal: si la
#: profundidad del banco cambia, el test tiene que seguirla sola.
VEC_ADDR_BITS = (PARAMS.vector_bram_depth - 1).bit_length()
VEC_ADDR_MASK = (1 << VEC_ADDR_BITS) - 1
BANK_SHIFT = 16
BANK_ALL = 7

#: Leída de config/registers.toml, no fijada aquí. Los OFFSETS de arriba sí son
#: literales a propósito -- si alguien mueve un registro, este test tiene que
#: decirlo en voz alta. La VERSIÓN es lo contrario: es un contador que sube con
#: cada cambio del mapa, y clavarlo aquí solo haría que cada bump rompiera el
#: test sin informar de nada. Lo que de verdad se quiere comprobar es que el RTL
#: devuelve la versión que el esquema declara, y eso es esto.
_SCHEMA = Path(__file__).resolve().parents[2] / "config" / "registers.toml"
with _SCHEMA.open("rb") as _handle:
    REGS_VERSION = tomllib.load(_handle)["schema_version"]


async def _reset(dut) -> None:
    dut.rst_n.value = 0
    dut.s_axi_awvalid.value = 0
    dut.s_axi_awaddr.value = 0
    dut.s_axi_wvalid.value = 0
    dut.s_axi_wdata.value = 0
    dut.s_axi_wstrb.value = 0xF
    dut.s_axi_bready.value = 1
    dut.s_axi_arvalid.value = 0
    dut.s_axi_araddr.value = 0
    dut.s_axi_rready.value = 1
    dut.overrun_in.value = 0
    dut.overflow_in.value = 0
    dut.ray_truncated_in.value = 0
    dut.radial_done_in.value = 0
    dut.config_invalid_low_in.value = 0
    dut.config_invalid_high_in.value = 0
    dut.pulse_trig_in.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def axil_write(dut, addr: int, data: int) -> None:
    dut.s_axi_awaddr.value = addr
    dut.s_axi_awvalid.value = 1
    dut.s_axi_wdata.value = data
    dut.s_axi_wvalid.value = 1

    aw_pending = True
    w_pending = True
    while aw_pending or w_pending:
        aw_fires = aw_pending and int(dut.s_axi_awready.value)
        w_fires = w_pending and int(dut.s_axi_wready.value)
        await RisingEdge(dut.clk)
        if aw_fires:
            dut.s_axi_awvalid.value = 0
            aw_pending = False
        if w_fires:
            dut.s_axi_wvalid.value = 0
            w_pending = False

    while True:
        b_fires = int(dut.s_axi_bvalid.value) and int(dut.s_axi_bready.value)
        await RisingEdge(dut.clk)
        if b_fires:
            break


async def axil_read(dut, addr: int) -> int:
    dut.s_axi_araddr.value = addr
    dut.s_axi_arvalid.value = 1

    while True:
        ar_fires = int(dut.s_axi_arready.value)
        await RisingEdge(dut.clk)
        if ar_fires:
            dut.s_axi_arvalid.value = 0
            break

    while True:
        r_fires = int(dut.s_axi_rvalid.value)
        data = int(dut.s_axi_rdata.value)
        await RisingEdge(dut.clk)
        if r_fires:
            return data


async def _escribe_contando_strobe(dut, addr: int, data: int) -> tuple[int, list[int]]:
    """Escribe en `addr`; devuelve los ciclos con `nco_pinc_we` alto y qué valía
    `nco_pinc` en cada uno de ellos.

    Muestrea DESPUÉS del flanco, al revés que los `*_clear` de este mismo
    fichero. No es una inconsistencia: aquellos son combinacionales desde
    `write_commit`, y `nco_pinc_we` va registrado desde que se corrigió el
    desfase de un ciclo (ver la cabecera del bloque NCO_PINC en
    `rtl/drx_axil_regs.sv`).

    Devolver además el DATO es el punto de la corrección. Contar pulsos no
    bastaba: el strobe duraba un ciclo y el registro acababa en el valor
    correcto, las dos cosas que este test comprobaba, y aun así el consumidor se
    llevaba la palabra de la escritura anterior porque el pulso llegaba un ciclo
    antes que el dato.
    """
    return await _escribe_muestreando(
        dut, addr, data, lambda: int(dut.nco_pinc.value), dut.nco_pinc_we
    )


async def _escribe_muestreando(dut, addr, data, leer, strobe) -> tuple[int, list]:
    """Escribe en `addr` y muestrea `leer()` en cada ciclo con `strobe` alto.

    Mismo mecanismo que usaba `_escribe_contando_strobe` para NCO_PINC, sacado
    aparte porque la ventana de carga del vector (v11) tiene exactamente el
    mismo problema y la misma solucion: el consumidor escribe la BRAM en el
    flanco en que ve el strobe, asi que la direccion y el dato tienen que
    valer lo nuevo EN ESE ciclo.
    """
    pulsos = 0
    vistos: list = []
    corriendo = True

    async def muestreador() -> None:
        nonlocal pulsos
        while corriendo:
            await RisingEdge(dut.clk)
            await ReadOnly()
            if int(strobe.value):
                pulsos += 1
                vistos.append(leer())

    tarea = cocotb.start_soon(muestreador())
    await axil_write(dut, addr, data)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    corriendo = False
    tarea.kill()
    return pulsos, vistos


@cocotb.test()
async def test_version_de_solo_lectura(dut):
    """VERSION lee la constante del mapa; escribir ahí no tiene efecto."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert await axil_read(dut, REG_VERSION_ADDR) == REGS_VERSION

    await axil_write(dut, REG_VERSION_ADDR, 0xFFFF_FFFF)
    assert await axil_read(dut, REG_VERSION_ADDR) == REGS_VERSION, (
        "escribir en VERSION no debe cambiar nada"
    )


@cocotb.test()
async def test_ctrl_mode_coarse_rw(dut):
    """CTRL bit 0 controla `mode_coarse`; el bit 1 y los 31:3 leen 0."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert int(dut.mode_coarse.value) == 0, "mode_coarse arranca en fino"
    assert await axil_read(dut, REG_CTRL_ADDR) == 0

    await axil_write(dut, REG_CTRL_ADDR, 0xFFFF_FFFF)
    assert int(dut.mode_coarse.value) == 1, "mode_coarse no siguió a CTRL bit 0"
    # 0b101: bit 0 (mode_coarse) y bit 2 (vector_load, v11). El bit 1 fue
    # `vector_source_ddr` entre v8 y v10 y volvió a reservado al retirarse el
    # modo Throttled(DDR); el resto nunca estuvo implementado.
    assert await axil_read(dut, REG_CTRL_ADDR) == 0b101, (
        "los bits reservados de CTRL deben leer 0"
    )

    await axil_write(dut, REG_CTRL_ADDR, 0x0)
    assert int(dut.mode_coarse.value) == 0


@cocotb.test()
async def test_ctrl_vector_load_rw(dut):
    """CTRL bit 2 (v11) controla `vector_load`, y es independiente del bit 0.

    Que sean independientes no es obvio ni gratis: los dos salen de la MISMA
    escritura a CTRL, así que un desplazamiento de un bit en el RTL dejaría a
    `mode_coarse` siguiendo al bit de carga. En placa eso se vería como "la
    decimación cambia sola al cargar un vector", un síntoma que no apunta a
    este registro.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert int(dut.vector_load.value) == 0, "arranca reproduciendo"

    await axil_write(dut, REG_CTRL_ADDR, 0b100)
    assert int(dut.vector_load.value) == 1, "no siguió a CTRL bit 2"
    assert int(dut.mode_coarse.value) == 0, "el bit 2 arrastró al bit 0"
    assert await axil_read(dut, REG_CTRL_ADDR) == 0b100

    await axil_write(dut, REG_CTRL_ADDR, 0b001)
    assert int(dut.vector_load.value) == 0, "el bit 0 arrastró al bit 2"
    assert int(dut.mode_coarse.value) == 1
    assert await axil_read(dut, REG_CTRL_ADDR) == 0b001


@cocotb.test()
async def test_ctrl_bit1_es_reservado_desde_v11(dut):
    """El bit 1 fue `vector_source_ddr` entre v8 y v10; en v11 lee 0 y no hace nada.

    No se reutiliza para otra cosa a propósito: un firmware de v8..v10 que lo
    escriba tiene que no activar NADA, en vez de activar algo distinto en
    silencio. Este test es lo que impide que un bit nuevo acabe ahí por
    comodidad.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    await axil_write(dut, REG_CTRL_ADDR, 0b010)
    assert await axil_read(dut, REG_CTRL_ADDR) == 0, "CTRL bit 1 tiene que leer 0"
    assert int(dut.mode_coarse.value) == 0
    assert int(dut.vector_load.value) == 0

    # Y escribirlo junto a los bits vivos no los perturba.
    await axil_write(dut, REG_CTRL_ADDR, 0b111)
    assert await axil_read(dut, REG_CTRL_ADDR) == 0b101
    assert int(dut.mode_coarse.value) == 1
    assert int(dut.vector_load.value) == 1


@cocotb.test()
async def test_vec_len_arranca_en_vector_loop_len(dut):
    """VEC_LEN resetea a la longitud que `$readmemh` precarga de verdad.

    Es la condición que hace que un sistema que nunca escriba aquí reproduzca
    exactamente el bucle de v10 y anteriores -- y por tanto que los -9,03 dBFS
    ya medidos en placa sigan siendo la línea base contra la que comparar.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert int(dut.vec_len.value) == PARAMS.vector_loop_len
    assert await axil_read(dut, REG_VEC_LEN_ADDR) == PARAMS.vector_loop_len

    nuevo = PARAMS.vector_loop_len // 2
    await axil_write(dut, REG_VEC_LEN_ADDR, nuevo)
    assert int(dut.vec_len.value) == nuevo
    assert await axil_read(dut, REG_VEC_LEN_ADDR) == nuevo

    # Los bits por encima del puntero son reservados y no se guardan.
    await axil_write(dut, REG_VEC_LEN_ADDR, 0xFFFF_FFFF)
    assert int(dut.vec_len.value) == VEC_ADDR_MASK
    assert await axil_read(dut, REG_VEC_LEN_ADDR) == VEC_ADDR_MASK


@cocotb.test()
async def test_vec_addr_autoincrementa_y_conserva_el_banco(dut):
    """Cada escritura de VEC_DATA incrementa el puntero y deja el banco quieto.

    El autoincremento es lo que hace que cargar un vector sea una escritura de
    VEC_ADDR y N de VEC_DATA. Si el banco se perdiera por el camino, la
    difusión dejaría de serlo a partir de la segunda muestra y solo se
    cargaría el canal 0 -- en placa, dos canales en silencio.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    base = 0x12
    await axil_write(dut, REG_VEC_ADDR_ADDR, (BANK_ALL << BANK_SHIFT) | base)
    assert await axil_read(dut, REG_VEC_ADDR_ADDR) == (BANK_ALL << BANK_SHIFT) | base
    assert int(dut.vec_bank.value) == BANK_ALL

    for k in range(4):
        await axil_write(dut, REG_VEC_DATA_ADDR, 0x1000 + k)
        esperado = (base + k + 1) & VEC_ADDR_MASK
        leido = await axil_read(dut, REG_VEC_ADDR_ADDR)
        assert leido & VEC_ADDR_MASK == esperado, (
            f"tras {k + 1} escrituras el puntero tiene que estar en {esperado}"
        )
        assert leido >> BANK_SHIFT == BANK_ALL, "el banco se perdió al incrementar"
        assert int(dut.vec_bank.value) == BANK_ALL

    # El puntero envuelve dentro de su ancho y no para en la profundidad: es
    # una decisión, no un descuido -- ver el comentario del bloque en
    # `rtl/drx_axil_regs.sv`.
    await axil_write(dut, REG_VEC_ADDR_ADDR, VEC_ADDR_MASK)
    await axil_write(dut, REG_VEC_DATA_ADDR, 0x7FFF)
    assert await axil_read(dut, REG_VEC_ADDR_ADDR) & VEC_ADDR_MASK == 0


@cocotb.test()
async def test_vec_we_llega_alineado_con_direccion_y_dato(dut):
    """El strobe de escritura trae la dirección y el dato de ESA escritura.

    Es el mismo fallo que NCO_PINC tuvo y que costó una sesión de placa el
    2-oct-2026: `vector_source` graba la memoria en el flanco en que ve
    `vec_we`, así que un strobe combinacional sobre `write_commit` grabaría el
    dato de la escritura anterior. Y la dirección tiene que ser la de ANTES de
    incrementar, o el vector entero sale desplazado una posición -- que en el
    espectro solo se ve como una fase distinta.

    Quitar el registro de un ciclo de `vec_we_r`, o usar `vec_addr_r` en vez
    de `vec_addr_q`, tiene que hacer fallar este test.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    base = 0x30
    await axil_write(dut, REG_VEC_ADDR_ADDR, (2 << BANK_SHIFT) | base)

    def _muestra():
        return (
            int(dut.vec_addr.value),
            int(dut.vec_bank.value),
            int(dut.vec_data.value),
        )

    for k, dato in enumerate([0x0ABC, 0x7FFF, 0x8000, 0x0001]):
        pulsos, vistos = await _escribe_muestreando(
            dut, REG_VEC_DATA_ADDR, dato, _muestra, dut.vec_we
        )
        assert pulsos == 1, f"vec_we tiene que pulsar un solo ciclo, pulsó {pulsos}"
        assert vistos == [(base + k, 2, dato)], (
            f"escritura {k}: con el strobe alto se esperaba "
            f"{(base + k, 2, dato)} y se vio {vistos}"
        )

    # Ninguna otra dirección genera el strobe.
    pulsos, _ = await _escribe_muestreando(
        dut, REG_CTRL_ADDR, 0x1, _muestra, dut.vec_we
    )
    assert pulsos == 0, "solo VEC_DATA genera vec_we"

    pulsos, _ = await _escribe_muestreando(
        dut, REG_VEC_ADDR_ADDR, 0x7, _muestra, dut.vec_we
    )
    assert pulsos == 0, "escribir VEC_ADDR no graba nada"


@cocotb.test()
async def test_status_lee_overrun_in_directo(dut):
    """STATUS refleja `overrun_in` bit a bit, canal a canal."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert await axil_read(dut, REG_STATUS_ADDR) == 0

    dut.overrun_in.value = 0b010
    await RisingEdge(dut.clk)
    assert await axil_read(dut, REG_STATUS_ADDR) == 0b010

    dut.overrun_in.value = 0b111
    await RisingEdge(dut.clk)
    assert await axil_read(dut, REG_STATUS_ADDR) == 0b111


@cocotb.test()
async def test_status_write_1_to_clear_pulsa_overrun_clear(dut):
    """Escribir 1 en un bit de STATUS pulsa `overrun_clear` UN ciclo en ese canal."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert int(dut.overrun_clear.value) == 0

    dut.s_axi_awaddr.value = REG_STATUS_ADDR
    dut.s_axi_awvalid.value = 1
    dut.s_axi_wdata.value = 0b101  # limpiar canales 0 y 2, dejar el 1 intacto
    dut.s_axi_wvalid.value = 1

    # Sondea un margen generoso de ciclos: no hace falta acertar el ciclo
    # exacto del pulso, `overrun_clear` está en 0 el resto del tiempo, así que
    # basta con haber capturado un 1 en algún momento de la ventana.
    pulsed = {c: False for c in range(N_CH)}
    aw_pending = True
    w_pending = True
    for _ in range(8):
        aw_fires = aw_pending and int(dut.s_axi_awready.value)
        w_fires = w_pending and int(dut.s_axi_wready.value)
        await RisingEdge(dut.clk)
        if aw_fires:
            dut.s_axi_awvalid.value = 0
            aw_pending = False
        if w_fires:
            dut.s_axi_wvalid.value = 0
            w_pending = False
        clear_val = int(dut.overrun_clear.value)
        for c in range(N_CH):
            if clear_val & (1 << c):
                pulsed[c] = True

    assert pulsed == {0: True, 1: False, 2: True}, (
        f"overrun_clear no pulsó exactamente en los canales escritos: {pulsed}"
    )

    await RisingEdge(dut.clk)
    assert int(dut.overrun_clear.value) == 0, "el pulso de clear dura un solo ciclo"


@cocotb.test()
async def test_gate_truncated_lee_ray_truncated_in_directo(dut):
    """GATE_TRUNCATED (BITE de D-14, v6) refleja `ray_truncated_in` bit a bit,
    canal a canal -- mismo patrón que STATUS/overrun, registro propio."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert await axil_read(dut, REG_GATE_TRUNCATED_ADDR) == 0

    dut.ray_truncated_in.value = 0b010
    await RisingEdge(dut.clk)
    assert await axil_read(dut, REG_GATE_TRUNCATED_ADDR) == 0b010

    dut.ray_truncated_in.value = 0b111
    await RisingEdge(dut.clk)
    assert await axil_read(dut, REG_GATE_TRUNCATED_ADDR) == 0b111


@cocotb.test()
async def test_gate_truncated_write_1_to_clear_pulsa_ray_truncated_clear(dut):
    """Escribir 1 en un bit de GATE_TRUNCATED pulsa `ray_truncated_clear` UN
    ciclo en ese canal -- mismo patrón que STATUS/overrun_clear, sin pisar ese
    registro (son puertos y direcciones distintos)."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert int(dut.ray_truncated_clear.value) == 0

    dut.s_axi_awaddr.value = REG_GATE_TRUNCATED_ADDR
    dut.s_axi_awvalid.value = 1
    dut.s_axi_wdata.value = 0b101  # limpiar canales 0 y 2, dejar el 1 intacto
    dut.s_axi_wvalid.value = 1

    pulsed = {c: False for c in range(N_CH)}
    aw_pending = True
    w_pending = True
    for _ in range(8):
        aw_fires = aw_pending and int(dut.s_axi_awready.value)
        w_fires = w_pending and int(dut.s_axi_wready.value)
        await RisingEdge(dut.clk)
        if aw_fires:
            dut.s_axi_awvalid.value = 0
            aw_pending = False
        if w_fires:
            dut.s_axi_wvalid.value = 0
            w_pending = False
        clear_val = int(dut.ray_truncated_clear.value)
        for c in range(N_CH):
            if clear_val & (1 << c):
                pulsed[c] = True

    assert pulsed == {0: True, 1: False, 2: True}, (
        f"ray_truncated_clear no pulsó exactamente en los canales escritos: {pulsed}"
    )

    await RisingEdge(dut.clk)
    assert int(dut.ray_truncated_clear.value) == 0, "el pulso de clear dura un solo ciclo"


@cocotb.test()
async def test_trig_count_incrementa_por_pulso_y_es_solo_lectura(dut):
    """TRIG_COUNT (v7, Z4.1) incrementa un pulso de `pulse_trig_in` por ciclo,
    sin sticky ni W1C -- a diferencia de STATUS/OVERFLOW/GATE_TRUNCATED, no
    tiene ningún puerto de limpieza: escribir ahí no debe cambiar nada."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert await axil_read(dut, REG_TRIG_COUNT_ADDR) == 0

    for expected in range(1, 4):
        dut.pulse_trig_in.value = 1
        await RisingEdge(dut.clk)
        dut.pulse_trig_in.value = 0
        assert await axil_read(dut, REG_TRIG_COUNT_ADDR) == expected

    await axil_write(dut, REG_TRIG_COUNT_ADDR, 0xFFFF_FFFF)
    assert await axil_read(dut, REG_TRIG_COUNT_ADDR) == 3, (
        "TRIG_COUNT es RO -- escribir ahí no debe tener ningún efecto"
    )

    # Varios ciclos sin pulso: el contador no se mueve solo.
    for _ in range(5):
        await RisingEdge(dut.clk)
    assert await axil_read(dut, REG_TRIG_COUNT_ADDR) == 3


@cocotb.test()
async def test_overflow_es_sticky_y_write_1_to_clear_rearma(dut):
    """OVERFLOW, a diferencia de STATUS, LATCHEA `overflow_in`: sigue en 1
    aunque la fuente vuelva a 0 (sticky vive en `drx_axil_regs`, no en la
    fuente — ver la cabecera del módulo). W1C lo limpia, y un overflow
    genuino posterior se vuelve a ver (rearme).
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert await axil_read(dut, REG_OVERFLOW_ADDR) == 0

    # Un pulso de un ciclo en el canal 1 basta para que quede latcheado.
    dut.overflow_in.value = 0b010
    await RisingEdge(dut.clk)
    dut.overflow_in.value = 0b000
    await RisingEdge(dut.clk)
    assert await axil_read(dut, REG_OVERFLOW_ADDR) == 0b010, (
        "OVERFLOW debe seguir en 1 aunque overflow_in ya haya vuelto a 0 (sticky)"
    )

    await axil_write(dut, REG_OVERFLOW_ADDR, 0b010)
    assert await axil_read(dut, REG_OVERFLOW_ADDR) == 0, "write-1-to-clear no limpió OVERFLOW"

    # Rearme: un segundo evento en el mismo canal, tras limpiar el primero,
    # se tiene que volver a ver.
    dut.overflow_in.value = 0b010
    await RisingEdge(dut.clk)
    dut.overflow_in.value = 0b000
    await RisingEdge(dut.clk)
    assert await axil_read(dut, REG_OVERFLOW_ADDR) == 0b010, "OVERFLOW no se rearmó tras el clear"


@cocotb.test()
async def test_overflow_set_gana_sobre_clear_concurrente(dut):
    """Un overflow genuino el mismo ciclo que el W1C no se debe perder."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    dut.s_axi_awaddr.value = REG_OVERFLOW_ADDR
    dut.s_axi_awvalid.value = 1
    dut.s_axi_wdata.value = 0b1
    dut.s_axi_wvalid.value = 1
    dut.overflow_in.value = 0b1  # mantenido durante toda la ventana del write

    aw_pending = True
    w_pending = True
    for _ in range(8):
        aw_fires = aw_pending and int(dut.s_axi_awready.value)
        w_fires = w_pending and int(dut.s_axi_wready.value)
        await RisingEdge(dut.clk)
        if aw_fires:
            dut.s_axi_awvalid.value = 0
            aw_pending = False
        if w_fires:
            dut.s_axi_wvalid.value = 0
            w_pending = False

    dut.overflow_in.value = 0
    await RisingEdge(dut.clk)
    assert await axil_read(dut, REG_OVERFLOW_ADDR) == 0b1, (
        "el set debe ganar sobre un clear concurrente"
    )


@cocotb.test()
async def test_direccion_reservada_lee_cero_y_escritura_sin_efecto(dut):
    """Fuera del mapa implementado, todo lee 0 (reservado, sin implementar)."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert await axil_read(dut, REG_RESERVED_ADDR) == 0

    await axil_write(dut, REG_RESERVED_ADDR, 0xFFFF_FFFF)
    assert await axil_read(dut, REG_RESERVED_ADDR) == 0
    assert int(dut.mode_coarse.value) == 0


@cocotb.test()
async def test_nco_pinc_arranca_en_nco_phase_inc_y_pulsa_al_escribir(dut):
    """NCO_PINC (v9, Z4.5): valor de reset, lectura/escritura y strobe.

    Las tres cosas importan por separado. El VALOR DE RESET es lo que mantiene
    válida la matriz de D-12 como oráculo del camino sin AFC: si no fuera
    NCO_PHASE_INC, un sistema que nunca escribe aquí mezclaría a otra
    frecuencia. El STROBE tiene que durar UN ciclo y pulsar en CADA escritura,
    incluso si el valor no cambia -- el canal S_AXIS_CONFIG del DDS Compiler no
    tiene TREADY y un pulso largo le metería la misma configuración varias
    veces.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert int(dut.nco_pinc.value) == PARAMS.nco_phase_inc, (
        "NCO_PINC tiene que arrancar en NCO_PHASE_INC, el mismo PINC1 de la IP"
    )
    assert await axil_read(dut, REG_NCO_PINC_ADDR) == PARAMS.nco_phase_inc
    assert int(dut.nco_pinc_we.value) == 0

    nuevo = (PARAMS.nco_phase_inc + 0x0010_0000) & 0xFFFF_FFFF
    pulsos, vistos = await _escribe_contando_strobe(dut, REG_NCO_PINC_ADDR, nuevo)

    assert pulsos == 1, f"nco_pinc_we tiene que pulsar un solo ciclo, pulsó {pulsos}"
    assert vistos == [nuevo], (
        f"con el strobe alto, nco_pinc tiene que valer ya {nuevo}; valía {vistos}. "
        "Un desfase aquí hace que el DDC se lleve la palabra de la escritura "
        "anterior, que es el bug medido en placa el 2-oct-2026"
    )
    assert int(dut.nco_pinc.value) == nuevo
    assert await axil_read(dut, REG_NCO_PINC_ADDR) == nuevo

    # Reescribir el MISMO valor también pulsa: quien decide si reprogramar es el
    # par remoto (mensaje `afc`), no este módulo.
    pulsos, vistos = await _escribe_contando_strobe(dut, REG_NCO_PINC_ADDR, nuevo)
    assert pulsos == 1, "una escritura del mismo valor también tiene que pulsar"
    assert vistos == [nuevo]

    # Y una escritura de OTRO valor también llega alineada: el dato nuevo tiene
    # que acompañar al pulso, no al siguiente.
    otro = (nuevo ^ 0x0F0F_0F0F) & 0xFFFF_FFFF
    pulsos, vistos = await _escribe_contando_strobe(dut, REG_NCO_PINC_ADDR, otro)
    assert pulsos == 1
    assert vistos == [otro], (
        f"segunda escritura: el strobe tiene que venir con {otro}, vino con {vistos}"
    )

    # Y ninguna otra dirección lo mueve.
    pulsos, vistos = await _escribe_contando_strobe(dut, REG_CTRL_ADDR, 0x1)
    assert pulsos == 0, "solo NCO_PINC genera el strobe"
    assert vistos == []
    assert int(dut.nco_pinc.value) == otro


@cocotb.test()
async def test_timing_ctrl_enable_rw(dut):
    """TIMING_CTRL bit 0 = `timing_enable`, bit 1 (v10) = `timing_paced`; el
    resto siguen siendo reservados."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert int(dut.timing_enable.value) == 0, "timing_enable arranca detenido"
    # El valor de reset de `timing_paced` es 0 y eso NO es un detalle: con 0
    # el motor cuenta ciclos, o sea un sistema que nunca escriba aqui se
    # comporta exactamente como v3..v9 (P-16).
    assert int(dut.timing_paced.value) == 0, "timing_paced arranca sin pacear"
    assert await axil_read(dut, REG_TIMING_CTRL_ADDR) == 0

    await axil_write(dut, REG_TIMING_CTRL_ADDR, 0xFFFF_FFFF)
    assert int(dut.timing_enable.value) == 1
    assert int(dut.timing_paced.value) == 1
    assert await axil_read(dut, REG_TIMING_CTRL_ADDR) == 0b11, (
        "bits 31:2 de TIMING_CTRL leen 0"
    )

    # Los dos bits son independientes: pacear sin arrancar el secuenciador es
    # una combinacion util -- es como se aisla un fallo del pacer de un fallo
    # del modo (ver la cabecera de drx_sample_pacer.sv).
    await axil_write(dut, REG_TIMING_CTRL_ADDR, 0b10)
    assert int(dut.timing_enable.value) == 0
    assert int(dut.timing_paced.value) == 1

    await axil_write(dut, REG_TIMING_CTRL_ADDR, 0x0)
    assert int(dut.timing_enable.value) == 0
    assert int(dut.timing_paced.value) == 0


@cocotb.test()
async def test_timing_status_es_sticky_y_write_1_to_clear_rearma(dut):
    """TIMING_STATUS bit 0 latchea `radial_done_in` (pulso de un ciclo), mismo
    patrón sticky + W1C + set-gana que OVERFLOW."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert await axil_read(dut, REG_TIMING_STATUS_ADDR) == 0

    dut.radial_done_in.value = 1
    await RisingEdge(dut.clk)
    dut.radial_done_in.value = 0
    await RisingEdge(dut.clk)
    assert await axil_read(dut, REG_TIMING_STATUS_ADDR) == 1, (
        "TIMING_STATUS debe seguir en 1 aunque radial_done_in ya haya vuelto a 0"
    )

    await axil_write(dut, REG_TIMING_STATUS_ADDR, 0x1)
    assert await axil_read(dut, REG_TIMING_STATUS_ADDR) == 0, "W1C no limpió TIMING_STATUS"

    dut.radial_done_in.value = 1
    await RisingEdge(dut.clk)
    dut.radial_done_in.value = 0
    await RisingEdge(dut.clk)
    assert await axil_read(dut, REG_TIMING_STATUS_ADDR) == 1, (
        "TIMING_STATUS no se rearmó tras el clear"
    )


@cocotb.test()
async def test_timing_status_config_invalid_low_high_son_sticky_e_independientes(dut):
    """TIMING_STATUS bits 1/2 (v4, D-09): mismo patrón sticky + W1C que bit 0,
    pero uno por lote -- un evento en `config_invalid_low_in` no debe tocar el
    bit del lote alto ni viceversa."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert await axil_read(dut, REG_TIMING_STATUS_ADDR) == 0

    dut.config_invalid_low_in.value = 1
    await RisingEdge(dut.clk)
    dut.config_invalid_low_in.value = 0
    await RisingEdge(dut.clk)
    assert await axil_read(dut, REG_TIMING_STATUS_ADDR) == 0b010, (
        "bit 1 (config_invalid_low) debe quedar sticky en 1, bit 2 intacto"
    )

    dut.config_invalid_high_in.value = 1
    await RisingEdge(dut.clk)
    dut.config_invalid_high_in.value = 0
    await RisingEdge(dut.clk)
    assert await axil_read(dut, REG_TIMING_STATUS_ADDR) == 0b110, (
        "bit 2 (config_invalid_high) también sticky, bit 1 no se pisó"
    )

    await axil_write(dut, REG_TIMING_STATUS_ADDR, 0b010)
    assert await axil_read(dut, REG_TIMING_STATUS_ADDR) == 0b100, (
        "W1C solo limpió el bit escrito (1), el bit 2 sigue en 1"
    )

    await axil_write(dut, REG_TIMING_STATUS_ADDR, 0b100)
    assert await axil_read(dut, REG_TIMING_STATUS_ADDR) == 0


@cocotb.test()
async def test_timing_status_config_invalid_set_gana_sobre_clear_concurrente(dut):
    """Mismo argumento que OVERFLOW: un `config_invalid_low_in` genuino el
    mismo ciclo que el W1C no se puede perder."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    dut.s_axi_awaddr.value = REG_TIMING_STATUS_ADDR
    dut.s_axi_awvalid.value = 1
    dut.s_axi_wdata.value = 0b010
    dut.s_axi_wvalid.value = 1
    dut.config_invalid_low_in.value = 1  # mantenido durante toda la ventana del write

    aw_pending = True
    w_pending = True
    for _ in range(8):
        aw_fires = aw_pending and int(dut.s_axi_awready.value)
        w_fires = w_pending and int(dut.s_axi_wready.value)
        await RisingEdge(dut.clk)
        if aw_fires:
            dut.s_axi_awvalid.value = 0
            aw_pending = False
        if w_fires:
            dut.s_axi_wvalid.value = 0
            w_pending = False

    dut.config_invalid_low_in.value = 0
    await RisingEdge(dut.clk)
    assert await axil_read(dut, REG_TIMING_STATUS_ADDR) == 0b010, (
        "el set debe ganar sobre un clear concurrente"
    )


@cocotb.test()
async def test_prf_div_low_high_rw_32_bits_completos(dut):
    """PRF_DIV_LOW/HIGH son registros RW de 32 bits completos, sin empaquetar."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert int(dut.prf_div_low.value) == 0
    assert int(dut.prf_div_high.value) == 0

    await axil_write(dut, REG_PRF_DIV_LOW_ADDR, 0x0000_1234)
    await axil_write(dut, REG_PRF_DIV_HIGH_ADDR, 0xABCD_0000)
    assert int(dut.prf_div_low.value) == 0x0000_1234
    assert int(dut.prf_div_high.value) == 0xABCD_0000
    assert await axil_read(dut, REG_PRF_DIV_LOW_ADDR) == 0x0000_1234
    assert await axil_read(dut, REG_PRF_DIV_HIGH_ADDR) == 0xABCD_0000


@cocotb.test()
async def test_bins_low_high_rw_32_bits_completos(dut):
    """D-15: BINS_LOW/HIGH son registros RW de 32 bits completos, sin
    empaquetar -- mismo patrón que PRF_DIV_LOW/HIGH."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert int(dut.bins_low.value) == 0
    assert int(dut.bins_high.value) == 0

    await axil_write(dut, REG_BINS_LOW_ADDR, 0x0000_0E71)
    await axil_write(dut, REG_BINS_HIGH_ADDR, 0x0000_00E4)
    assert int(dut.bins_low.value) == 0x0000_0E71
    assert int(dut.bins_high.value) == 0x0000_00E4
    assert await axil_read(dut, REG_BINS_LOW_ADDR) == 0x0000_0E71
    assert await axil_read(dut, REG_BINS_HIGH_ADDR) == 0x0000_00E4


@cocotb.test()
async def test_pulse_width_y_n_pulses_empaquetan_low_high_en_una_palabra(dut):
    """PULSE_WIDTH/N_PULSES: bits 15:0 = lote bajo, bits 31:16 = lote alto."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    await axil_write(dut, REG_PULSE_WIDTH_ADDR, (0x0102 << 16) | 0x0304)
    assert int(dut.pulse_width_low.value) == 0x0304
    assert int(dut.pulse_width_high.value) == 0x0102
    assert await axil_read(dut, REG_PULSE_WIDTH_ADDR) == (0x0102 << 16) | 0x0304

    await axil_write(dut, REG_N_PULSES_ADDR, (0x0506 << 16) | 0x0708)
    assert int(dut.n_pulses_low.value) == 0x0708
    assert int(dut.n_pulses_high.value) == 0x0506
    assert await axil_read(dut, REG_N_PULSES_ADDR) == (0x0506 << 16) | 0x0708


@cocotb.test()
async def test_trig_delay_y_trig_width_rw_por_canal(dut):
    """Los 4 canales de TRIG_DELAY/TRIG_WIDTH son registros RW independientes."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    delay_signals = [dut.trig_delay_0, dut.trig_delay_1, dut.trig_delay_2, dut.trig_delay_3]
    width_signals = [dut.trig_width_0, dut.trig_width_1, dut.trig_width_2, dut.trig_width_3]

    for ch in range(4):
        delay_val = 0x1000 + ch
        width_val = 0x2000 + ch
        await axil_write(dut, REG_TRIG_DELAY_ADDR[ch], delay_val)
        await axil_write(dut, REG_TRIG_WIDTH_ADDR[ch], width_val)
        assert int(delay_signals[ch].value) == delay_val, f"trig_delay_{ch}"
        assert int(width_signals[ch].value) == width_val, f"trig_width_{ch}"
        assert await axil_read(dut, REG_TRIG_DELAY_ADDR[ch]) == delay_val
        assert await axil_read(dut, REG_TRIG_WIDTH_ADDR[ch]) == width_val

    # Ningún canal pisa a otro: los 4 valores siguen intactos al final.
    for ch in range(4):
        assert int(delay_signals[ch].value) == 0x1000 + ch
        assert int(width_signals[ch].value) == 0x2000 + ch
