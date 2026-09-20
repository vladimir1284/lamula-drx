"""L0 — `drx_axil_regs`, el mapa de registros AXI-Lite de `drx_top` (v1,
congelado para Z1, ver `docs/implementacion/registros.md`).

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
REG_RESERVED_ADDR = 0x0C

REGS_VERSION = 1


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
    """CTRL bit 0 controla `mode_coarse`; bits altos son reservados (leen 0)."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert int(dut.mode_coarse.value) == 0, "mode_coarse arranca en fino"
    assert await axil_read(dut, REG_CTRL_ADDR) == 0

    await axil_write(dut, REG_CTRL_ADDR, 0xFFFF_FFFF)
    assert int(dut.mode_coarse.value) == 1, "mode_coarse no siguió a CTRL bit 0"
    assert await axil_read(dut, REG_CTRL_ADDR) == 1, "los bits reservados de CTRL deben leer 0"

    await axil_write(dut, REG_CTRL_ADDR, 0x0)
    assert int(dut.mode_coarse.value) == 0


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
async def test_direccion_reservada_lee_cero_y_escritura_sin_efecto(dut):
    """Fuera de VERSION/CTRL/STATUS, todo lee 0 (reservado para Z2, sin implementar)."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    assert await axil_read(dut, REG_RESERVED_ADDR) == 0

    await axil_write(dut, REG_RESERVED_ADDR, 0xFFFF_FFFF)
    assert await axil_read(dut, REG_RESERVED_ADDR) == 0
    assert int(dut.mode_coarse.value) == 0
