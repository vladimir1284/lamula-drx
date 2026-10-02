"""L0 — `vector_source` en sus dos modos (Z4.3, fases.md#z4), vía el shim
`sim/tb_sv/vector_source_tb_dut.sv` (ver su cabecera: la VPI de Verilator no
indexa arrays SIN empaquetar en un puerto de TOP).

Hasta Z4.3 este módulo no tenía L0 por ese motivo, solo entraba en P&R. El modo
Throttled(DDR) añade una máquina de estados de verdad —llenar un conjunto de
N_CH muestras, presentarlo, retirarlo cuando todos lo han tomado— y eso sí hay
que comprobarlo con un oráculo, no mirándolo.

Lo que se fija aquí, por orden de lo que costaría más descubrir en placa:

1. **Los canales van en bloque.** El conjunto se presenta con los N_CH canales
   válidos a la vez y no se retira hasta que TODOS los consumidores lo han
   tomado. Es más estricto de lo que exige AXI4-Stream y es el punto del modo:
   un canal adelantado convertiría un desfase de muestra en un resultado
   distinto sin ningún error visible.
2. **El reparto por canal es el declarado**: beat k va al canal k mod N_CH.
   Un giro de ese reparto produce salida plausible y comparaciones bit a bit
   que fallan sin decir por qué.
3. **`last` se propaga a los N_CH canales** del conjunto que contiene el
   `tlast`, no solo al canal donde llegó.
4. **Backpressure de verdad**: con un consumidor que frena, `s_axis_ready` baja
   y ningún beat se pierde ni se duplica.
5. **BRAM-loop no cambió.** Con `ddr_mode` en 0 el módulo se comporta
   exactamente como antes, y el stream de entrada no lo toca.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from drx_model.params import load

PARAMS = load("zedboard")
CLK_PERIOD_PS = round(1e12 / PARAMS.fs_hz)  # clock-const-ok: conversión de unidades s->ps

N_CH = 3
SAMPLE_BITS = 16
SAMPLE_MASK = (1 << SAMPLE_BITS) - 1
ALL_READY = (1 << N_CH) - 1


def _unpack(word: int, index: int) -> int:
    """Canal `index` del bus empaquetado, con signo."""
    raw = (int(word) >> (index * SAMPLE_BITS)) & SAMPLE_MASK
    return raw - (1 << SAMPLE_BITS) if raw >= (1 << (SAMPLE_BITS - 1)) else raw


async def _reset(dut):
    dut.rst_n.value = 0
    dut.ddr_mode.value = 0
    dut.s_axis_valid.value = 0
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0
    dut.ready.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def _drive_stream(dut, samples: list[int], gaps: bool, seed: int = 0):
    """Empuja `samples` por el AXI4-Stream, con `tlast` en el último beat.

    `gaps` intercala ciclos sin `tvalid`: un maestro real no mantiene el stream
    pegado, y una máquina de estados que supone un beat por ciclo pasa el test
    sin ellos.
    """
    rng = random.Random(seed)
    i = 0
    while i < len(samples):
        if gaps and rng.random() < 0.4:
            dut.s_axis_valid.value = 0
            await RisingEdge(dut.clk)
            continue
        dut.s_axis_valid.value = 1
        dut.s_axis_data.value = samples[i] & SAMPLE_MASK
        dut.s_axis_last.value = 1 if i == len(samples) - 1 else 0
        await RisingEdge(dut.clk)
        if dut.s_axis_ready.value == 1:
            i += 1
    dut.s_axis_valid.value = 0
    dut.s_axis_last.value = 0


async def _collect_sets(dut, n_sets: int, stall: bool, seed: int = 0) -> list[tuple]:
    """Consume `n_sets` conjuntos. Devuelve (valores por canal, last por canal).

    `stall` hace que los consumidores frenen a ratos, que es lo que ejercita el
    "no se retira hasta que todos lo han tomado".
    """
    rng = random.Random(seed + 1)
    out = []
    while len(out) < n_sets:
        frenar = stall and rng.random() < 0.5
        dut.ready.value = 0 if frenar else ALL_READY
        await RisingEdge(dut.clk)
        if frenar:
            continue
        if int(dut.valid.value) == 0:
            continue
        assert int(dut.valid.value) == ALL_READY, (
            "los N_CH canales tienen que presentarse válidos a la vez: "
            f"valid=0b{int(dut.valid.value):0{N_CH}b}"
        )
        word = int(dut.data.value)
        out.append(
            (
                [_unpack(word, c) for c in range(N_CH)],
                int(dut.last.value),
            )
        )
    dut.ready.value = 0
    return out


@cocotb.test()
async def ddr_mode_reparte_por_canal_y_va_en_bloque(dut):
    """Beat k -> canal k mod N_CH, y los N_CH salen a la vez."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)
    dut.ddr_mode.value = 1
    await RisingEdge(dut.clk)

    n_sets = 6
    # Valores distintos entre sí y con signo en ambos sentidos: con un patrón
    # monótono, un reparto girado por un canal sigue pareciendo razonable.
    samples = [(-1) ** k * (k * 7 + 1) for k in range(n_sets * N_CH)]

    cocotb.start_soon(_drive_stream(dut, samples, gaps=False))
    sets = await _collect_sets(dut, n_sets, stall=False)

    for s, (valores, _last) in enumerate(sets):
        esperado = samples[s * N_CH : (s + 1) * N_CH]
        assert valores == esperado, f"conjunto {s}: {valores} != {esperado}"


@cocotb.test()
async def ddr_mode_last_llega_a_todos_los_canales(dut):
    """`tlast` marca la ventana de los N_CH, no solo la del canal de ese beat."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)
    dut.ddr_mode.value = 1
    await RisingEdge(dut.clk)

    n_sets = 4
    samples = list(range(1, n_sets * N_CH + 1))
    cocotb.start_soon(_drive_stream(dut, samples, gaps=False))
    sets = await _collect_sets(dut, n_sets, stall=False)

    lasts = [last for _valores, last in sets]
    assert lasts[:-1] == [0] * (n_sets - 1), f"`last` antes de tiempo: {lasts}"
    assert lasts[-1] == ALL_READY, (
        "el último conjunto tiene que marcar `last` en los N_CH canales, "
        f"no en 0b{lasts[-1]:0{N_CH}b}"
    )


@cocotb.test()
async def ddr_mode_aguanta_huecos_y_backpressure(dut):
    """Ni se pierde ni se duplica un beat cuando los dos lados frenan a ratos."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)
    dut.ddr_mode.value = 1
    await RisingEdge(dut.clk)

    n_sets = 8
    samples = [(k * 13) % 1000 - 500 for k in range(n_sets * N_CH)]

    cocotb.start_soon(_drive_stream(dut, samples, gaps=True, seed=7))
    sets = await _collect_sets(dut, n_sets, stall=True, seed=7)

    recibido = [v for valores, _ in sets for v in valores]
    assert recibido == samples, "el stream no sobrevivió a los huecos/backpressure"


@cocotb.test()
async def bram_loop_no_mira_el_stream(dut):
    """Con `ddr_mode` en 0, el módulo es el de antes de Z4.3.

    Se empuja un stream entero mientras tanto: si algo de él se colara en la
    salida, los valores no serían los de la BRAM. La BRAM del shim arranca sin
    `INIT_FILE`, así que su contenido es X/0 según el simulador -- lo que se
    comprueba aquí NO es el dato, es que el módulo sigue entregando a su propio
    ritmo (un `valid` por ciclo con el consumidor abierto) y que `s_axis_ready`
    se queda en bajo, que es lo que dice que el stream está ignorado.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)
    dut.ddr_mode.value = 0
    dut.s_axis_valid.value = 1
    dut.s_axis_data.value = 0x1234
    await RisingEdge(dut.clk)

    dut.ready.value = ALL_READY
    entregas = 0
    for _ in range(20):
        await RisingEdge(dut.clk)
        assert dut.s_axis_ready.value == 0, (
            "en BRAM-loop el módulo no puede aceptar beats del stream"
        )
        if int(dut.valid.value) != 0:
            assert int(dut.valid.value) == ALL_READY
            entregas += 1

    assert entregas >= 15, (
        f"BRAM-loop dejó de entregar a ritmo: {entregas} muestras en 20 ciclos"
    )
