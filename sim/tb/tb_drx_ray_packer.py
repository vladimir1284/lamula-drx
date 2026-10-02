"""L0 — `drx_ray_packer` (Z4.0 + Z4.4, fases.md#z4), vía el shim
`sim/tb_sv/drx_ray_packer_tb_dut.sv` (ver su cabecera: la VPI de Verilator no
indexa arrays SIN empaquetar en un puerto de TOP, así que el DUT real de este
test es el shim, que solo reempaqueta puerto a puerto).

El módulo no tiene oráculo propio -- no hace aritmética, solo entrelaza en el
tiempo lo que ya entró -- así que el criterio de corrección es estructural:
por cada muestra donde los N_CH canales están `valid` a la vez, el stream de
salida tiene que traer, en orden (canal 0, 1, ..., N_CH-1), exactamente los
(i, q) que entraron ese ciclo, con `m_last` en alto SOLO en el último beat
(canal N_CH-1) de la muestra en la que TODOS los `s_last` de entrada estaban
altos a la vez.

Z4.4 añade una cabecera de metadato EN BANDA al principio de cada rayo
(`META_BEATS` palabras, ver la cabecera del módulo). Lo que estos tests
comprueban de ella, y que es lo que costaría descubrir de otra forma:

1. Va DELANTE de los datos y no lleva `m_last`, así que el descriptor de
   scatter-gather cubre cabecera y datos en una sola transferencia.
2. El metadato se congela al EMPEZAR el rayo. Si se leyera al terminarlo, un
   rayo que cruza el borde entre los dos lotes del radial (D-13) saldría
   etiquetado con el lote equivocado -- el único caso que el metadato existe
   para distinguir.
3. `ray_index` cuenta rayos emitidos y avanza de uno en uno, independiente de
   `trig_count`: si los dos divergen, la diferencia dice cuántos rayos se
   perdieron.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from drx_model.params import load

PARAMS = load("zedboard")
CLK_PERIOD_PS = round(1e12 / PARAMS.fs_hz)  # clock-const-ok: conversión de unidades s->ps

N_CH = 3
IQ_BITS = 16
MASK1 = (1 << N_CH) - 1
IQ_MASK = (1 << IQ_BITS) - 1

#: Palabras de metadato por rayo y su marca de inicio. Tienen que coincidir con
#: `MetaBeats`/`RayMagic` de `rtl/drx_ray_packer.sv` y con `DRX_RAY_MAGIC` del
#: firmware: son el mismo formato de cable visto desde los tres lados.
META_BEATS = 4
RAY_MAGIC = 0x52590001


def _pack_channels(values: list[int]) -> int:
    """Empaqueta N_CH valores de IQ_BITS bits, canal 0 en el grupo bajo — ver
    la cabecera del shim sobre el convenio de orden."""
    word = 0
    for c, v in enumerate(values):
        word |= (v & IQ_MASK) << (c * IQ_BITS)
    return word


def _pack_bits(flags: list[bool]) -> int:
    word = 0
    for c, f in enumerate(flags):
        if f:
            word |= 1 << c
    return word


def _split_word(word: int) -> tuple[int, int]:
    """`m_data` es `{cap_i, cap_q}` -- deshace el empaquetado, con signo."""
    i_raw = (word >> IQ_BITS) & IQ_MASK
    q_raw = word & IQ_MASK
    if i_raw >= (1 << (IQ_BITS - 1)):
        i_raw -= 1 << IQ_BITS
    if q_raw >= (1 << (IQ_BITS - 1)):
        q_raw -= 1 << IQ_BITS
    return i_raw, q_raw


def _set_meta(dut, trig_count: int, bin_count: int, batch_high: bool, mode_coarse: bool) -> None:
    dut.meta_trig_count.value = trig_count
    dut.meta_bin_count.value = bin_count
    dut.meta_batch_high.value = 1 if batch_high else 0
    dut.meta_mode_coarse.value = 1 if mode_coarse else 0


def _decode_header(words: list[int]) -> dict:
    """Deshace las `META_BEATS` palabras de cabecera."""
    assert len(words) == META_BEATS
    flags_word = words[3]
    return {
        "magic": words[0],
        "trig_count": words[1],
        "ray_index": words[2],
        "bin_count": flags_word & 0xFFFF,
        "batch_high": bool((flags_word >> 16) & 1),
        "mode_coarse": bool((flags_word >> 17) & 1),
        "n_ch": (flags_word >> 24) & 0xFF,
    }


def _split_rays(beats: list[tuple[int, bool]]) -> list[dict]:
    """Parte el stream crudo en rayos: cabecera, datos y si cerró con TLAST.

    Hace lo mismo que tendrá que hacer el firmware al recorrer el buffer de
    DDR, y por el mismo camino: confiar en la cabecera para saber dónde
    empieza cada rayo en vez de en una cuenta de beats calculada aparte.
    """
    rays: list[dict] = []
    idx = 0
    while idx < len(beats):
        header_words = [w for w, _ in beats[idx : idx + META_BEATS]]
        assert len(header_words) == META_BEATS, "stream cortado dentro de una cabecera"
        assert not any(last for _, last in beats[idx : idx + META_BEATS]), (
            "m_last no puede caer en un beat de cabecera: cerraría el descriptor antes de los datos"
        )
        idx += META_BEATS

        data: list[tuple[int, int, bool]] = []
        closed = False
        while idx < len(beats):
            word, last = beats[idx]
            idx += 1
            i_val, q_val = _split_word(word)
            data.append((i_val, q_val, last))
            if last:
                closed = True
                break
        rays.append({"header": _decode_header(header_words), "data": data, "closed": closed})
    return rays


async def _reset(dut) -> None:
    dut.rst_n.value = 0
    dut.s_valid.value = 0
    dut.s_i.value = 0
    dut.s_q.value = 0
    dut.s_last.value = 0
    dut.m_ready.value = 1
    _set_meta(dut, trig_count=0, bin_count=0, batch_high=False, mode_coarse=False)
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def _drive_and_collect(dut, samples, ready_sequence=None, on_sample=None):
    """`samples[n][c] = (i, q, last)` -- una muestra por ciclo, un (i,q,last) por canal.

    Devuelve el stream CRUDO: `(palabra, m_last)` por beat, cabeceras de
    metadato incluidas. Quien llama lo trocea con `_split_rays`.

    Cuando los N_CH `s_valid` están altos a la vez (siempre, en este test --
    ver la cabecera del módulo sobre por qué no hace falta desincronizarlos
    para cubrir el contrato real), el empaquetador captura y sirve N_CH beats
    de salida antes de aceptar la siguiente muestra -- así que el estímulo de
    entrada se mantiene fijo hasta que `s_ready` confirma la captura.

    `on_sample(n)` se llama ANTES de presentar la muestra `n`, para poder
    mover las entradas de metadato a mitad del estímulo.
    """
    received: list[tuple[int, bool]] = []

    def next_ready(i: int) -> int:
        if ready_sequence is None:
            return 1
        return ready_sequence[i % len(ready_sequence)]

    cycle = 0
    for n, sample in enumerate(samples):
        if on_sample is not None:
            on_sample(n)

        i_vals = [s[0] for s in sample]
        q_vals = [s[1] for s in sample]
        last_vals = [s[2] for s in sample]

        dut.s_valid.value = MASK1
        dut.s_i.value = _pack_channels(i_vals)
        dut.s_q.value = _pack_channels(q_vals)
        dut.s_last.value = _pack_bits(last_vals)

        # Mantiene el estímulo estable hasta que `s_ready` confirma la
        # captura -- puede tardar varios ciclos si `m_ready` no está siempre
        # alto (todavía sirviendo la muestra anterior) o si todavía está
        # saliendo la cabecera del rayo.
        captured = False
        while not captured:
            dut.m_ready.value = next_ready(cycle)
            if int(dut.m_valid.value) and int(dut.m_ready.value):
                received.append((int(dut.m_data.value), bool(dut.m_last.value)))
            captured = int(dut.s_ready.value) == MASK1
            cycle += 1
            await RisingEdge(dut.clk)

        dut.s_valid.value = 0

        # Drena los N_CH-1 beats restantes de esta muestra antes de pasar a
        # la siguiente -- si no, el estímulo de la próxima muestra podría
        # capturarse mezclado con datos todavía en vuelo del anterior.
        while int(dut.m_valid.value):
            dut.m_ready.value = next_ready(cycle)
            if int(dut.m_valid.value) and int(dut.m_ready.value):
                received.append((int(dut.m_data.value), bool(dut.m_last.value)))
            cycle += 1
            await RisingEdge(dut.clk)

    return received


def _ramp(n_rays: int, bin_count: int, base: int):
    """Muestras con un valor distinto por (canal, muestra), y `last` por rayo."""
    samples = []
    expected_data = []
    for n in range(n_rays * bin_count):
        ray_last = (n % bin_count) == (bin_count - 1)
        sample = []
        for c in range(N_CH):
            i_val = base * c + n
            q_val = 1000 + base * c + n
            sample.append((i_val, q_val, ray_last))
            expected_data.append((i_val, q_val, ray_last and (c == N_CH - 1)))
        samples.append(sample)
    return samples, expected_data


@cocotb.test()
async def test_orden_entrelazado_y_tlast_por_muestra(dut):
    """Orden canal 0..N_CH-1 y `m_last` solo en el último beat del último rayo."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)
    _set_meta(dut, trig_count=7, bin_count=4, batch_high=False, mode_coarse=False)

    bin_count, n_rays = 4, 3
    samples, expected_data = _ramp(n_rays, bin_count, base=100)

    received = await _drive_and_collect(dut, samples)
    rays = _split_rays(received)

    assert len(rays) == n_rays, f"rayos recibidos {len(rays)} != {n_rays}"
    plano = [beat for ray in rays for beat in ray["data"]]
    assert len(plano) == len(expected_data), (
        f"beats de datos {len(plano)} != esperados {len(expected_data)}"
    )
    assert plano == expected_data, "orden entrelazado o TLAST no coincide con lo esperado"
    for ray in rays:
        assert ray["closed"], "un rayo salió sin TLAST"
        assert len(ray["data"]) == bin_count * N_CH


@cocotb.test()
async def test_cada_rayo_empieza_por_su_cabecera_de_metadato(dut):
    """Magic, `n_ch`, `bin_count` y banderas, y `ray_index` avanzando de uno."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)
    _set_meta(dut, trig_count=41, bin_count=5, batch_high=True, mode_coarse=True)

    bin_count, n_rays = 5, 3
    samples, _ = _ramp(n_rays, bin_count, base=3)

    rays = _split_rays(await _drive_and_collect(dut, samples))
    assert len(rays) == n_rays

    for n, ray in enumerate(rays):
        header = ray["header"]
        assert header["magic"] == RAY_MAGIC, f"rayo {n}: magic {header['magic']:#010x}"
        assert header["n_ch"] == N_CH
        assert header["bin_count"] == bin_count
        assert header["batch_high"] is True
        assert header["mode_coarse"] is True
        assert header["trig_count"] == 41
        assert header["ray_index"] == n, "ray_index tiene que contar rayos emitidos"


@cocotb.test()
async def test_el_metadato_se_congela_al_empezar_el_rayo(dut):
    """Cambiar el metadato a mitad de un rayo NO cambia la cabecera ya emitida.

    Es el motivo entero de meter el metadato en banda. En la placa,
    `trig_count` y `batch_sel` se mueven con el siguiente disparo de PRF, que
    llega unos cientos de ciclos después de que el rayo empiece a vaciarse; si
    la cabecera tomara el valor de ese momento, el último rayo del lote bajo
    saldría etiquetado como del lote alto.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    bin_count, n_rays = 3, 3
    samples, _ = _ramp(n_rays, bin_count, base=11)

    # Metadato del rayo k: trig_count = 100+k, batch_high alterno. Se mueve en
    # la SEGUNDA muestra de cada rayo, es decir, con la cabecera ya emitida.
    def on_sample(n: int) -> None:
        ray = n // bin_count
        dentro = n % bin_count
        k = ray if dentro == 0 else ray + 1
        _set_meta(
            dut,
            trig_count=100 + k,
            bin_count=bin_count,
            batch_high=bool(k % 2),
            mode_coarse=False,
        )

    rays = _split_rays(await _drive_and_collect(dut, samples, on_sample=on_sample))

    assert len(rays) == n_rays
    for k, ray in enumerate(rays):
        assert ray["header"]["trig_count"] == 100 + k, (
            f"rayo {k}: la cabecera tomó el metadato de después de empezar"
        )
        assert ray["header"]["batch_high"] is bool(k % 2)


@cocotb.test()
async def test_ray_last_requiere_los_n_ch_a_la_vez(dut):
    """Si un solo canal no marca `s_last`, la muestra entera NO cierra rayo."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)
    _set_meta(dut, trig_count=1, bin_count=1, batch_high=False, mode_coarse=False)

    # Canal 1 nunca marca `last`: ningún beat de esta muestra debe salir con
    # m_last en alto, ni siquiera el del canal N_CH-1.
    sample = [(1, 2, True), (3, 4, False), (5, 6, True)]
    received = await _drive_and_collect(dut, [sample])
    (ray,) = _split_rays(received)

    assert len(ray["data"]) == N_CH
    assert not ray["closed"], "m_last no debe depender de un solo canal"


@cocotb.test()
async def test_backpressure_intermitente_no_pierde_ni_reordena(dut):
    """`m_ready` intermitente retrasa los beats de salida, no los pierde ni reordena."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)
    _set_meta(dut, trig_count=9, bin_count=5, batch_high=False, mode_coarse=False)

    random.seed(0)
    ready_sequence = [random.choice([0, 1, 1]) for _ in range(23)]

    bin_count, n_rays = 5, 3
    samples, expected_data = _ramp(n_rays, bin_count, base=7)

    received = await _drive_and_collect(dut, samples, ready_sequence=ready_sequence)
    rays = _split_rays(received)

    plano = [beat for ray in rays for beat in ray["data"]]
    assert len(plano) == len(expected_data), (
        f"se perdieron/duplicaron beats bajo backpressure: {len(plano)} de {len(expected_data)}"
    )
    assert plano == expected_data
    for n, ray in enumerate(rays):
        assert ray["header"]["ray_index"] == n, "la contrapresión no puede alterar ray_index"
