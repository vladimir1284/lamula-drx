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
from cocotb.triggers import RisingEdge
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
REG_RESERVED_ADDR = 0x58  # primera palabra sin implementar desde v7

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
    """CTRL bit 0 controla `mode_coarse`; bits 31:2 son reservados (leen 0)."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert int(dut.mode_coarse.value) == 0, "mode_coarse arranca en fino"
    assert await axil_read(dut, REG_CTRL_ADDR) == 0

    await axil_write(dut, REG_CTRL_ADDR, 0xFFFF_FFFF)
    assert int(dut.mode_coarse.value) == 1, "mode_coarse no siguió a CTRL bit 0"
    # 0b11: bits 0 y 1 implementados desde v8, el resto reservados y a 0.
    assert await axil_read(dut, REG_CTRL_ADDR) == 0b11, (
        "los bits reservados de CTRL deben leer 0"
    )

    await axil_write(dut, REG_CTRL_ADDR, 0x0)
    assert int(dut.mode_coarse.value) == 0


@cocotb.test()
async def test_ctrl_vector_source_ddr_rw(dut):
    """CTRL bit 1 (v8) controla `vector_source_ddr`, y es independiente del bit 0.

    Que sean independientes no es obvio ni gratis: los dos salen de la MISMA
    escritura a CTRL, así que un desplazamiento de un bit en el RTL dejaría a
    `mode_coarse` siguiendo al selector de fuente. En placa eso se vería como
    "la decimación cambia sola al activar el modo DDR", que es un síntoma que
    no apunta a este registro.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert int(dut.vector_source_ddr.value) == 0, "arranca en BRAM-loop"

    await axil_write(dut, REG_CTRL_ADDR, 0b10)
    assert int(dut.vector_source_ddr.value) == 1, "no siguió a CTRL bit 1"
    assert int(dut.mode_coarse.value) == 0, "el bit 1 arrastró al bit 0"
    assert await axil_read(dut, REG_CTRL_ADDR) == 0b10

    await axil_write(dut, REG_CTRL_ADDR, 0b01)
    assert int(dut.vector_source_ddr.value) == 0, "el bit 0 arrastró al bit 1"
    assert int(dut.mode_coarse.value) == 1
    assert await axil_read(dut, REG_CTRL_ADDR) == 0b01


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
async def test_timing_ctrl_enable_rw(dut):
    """TIMING_CTRL bit 0 controla `timing_enable`; bits altos son reservados."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert int(dut.timing_enable.value) == 0, "timing_enable arranca detenido"
    assert await axil_read(dut, REG_TIMING_CTRL_ADDR) == 0

    await axil_write(dut, REG_TIMING_CTRL_ADDR, 0xFFFF_FFFF)
    assert int(dut.timing_enable.value) == 1
    assert await axil_read(dut, REG_TIMING_CTRL_ADDR) == 1, "bits reservados de TIMING_CTRL leen 0"

    await axil_write(dut, REG_TIMING_CTRL_ADDR, 0x0)
    assert int(dut.timing_enable.value) == 0


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
