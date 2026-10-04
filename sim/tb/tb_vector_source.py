"""L0 — `vector_source` con la ventana de carga del mapa v11, vía el shim
`sim/tb_sv/vector_source_tb_dut.sv` (ver su cabecera: la VPI de Verilator no
indexa arrays SIN empaquetar en un puerto de TOP).

Hasta Z4.3 este módulo no tenía L0: era solo lectura, precargado en síntesis, y
no había máquina de estados que comprobar. Z4.3 le añadió el modo
Throttled(DDR) y con él los primeros tests. El 4-oct-2026 ese modo se retiró
(P-16: el DDS Compiler no tiene `aclken` y mezclaba a ~N_CH veces el IF con la
fuente a una muestra cada N_CH ciclos) y lo sustituyó la ventana de carga, que
es lo que se comprueba aquí.

Lo que se fija, por orden de lo que costaría más descubrir en placa:

1. **Lo que se escribe es lo que se reproduce, en el orden en que se escribió.**
   Un desplazamiento de una posición en la carga sale en el espectro como una
   fase distinta, no como un error.
2. **`vec_len` manda sobre `DEPTH`.** El puntero envuelve en la longitud
   cargada, no en la capacidad física del banco. Si envolviera en `DEPTH` el
   bucle arrastraría la parte no cargada de la memoria.
3. **La difusión llega a los N_CH bancos y una escritura por banco llega a uno
   solo.** Es lo que hace que una carga cueste una pasada y no N_CH, y lo que
   deja la puerta abierta a un estímulo distinto por canal (Config A).
4. **`vec_load` protege de verdad.** Con el lector corriendo una escritura NO
   entra; al soltarlo, la reproducción empieza en la muestra 0.
5. **`last` pulsa en la última muestra del bucle**, no en la última del banco.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from drx_model.params import load

PARAMS = load("zedboard")
CLK_PERIOD_PS = round(1e12 / PARAMS.fs_hz)  # clock-const-ok: conversión de unidades s->ps

N_CH = 3
DEPTH = 8  # el del shim; ver `sim/tests/test_l0_vector_source.py`
SAMPLE_BITS = 16
SAMPLE_MASK = (1 << SAMPLE_BITS) - 1
ALL_READY = (1 << N_CH) - 1
BANK_ALL = 7


def _unpack(word: int, index: int) -> int:
    """Canal `index` del bus empaquetado, con signo."""
    raw = (int(word) >> (index * SAMPLE_BITS)) & SAMPLE_MASK
    return raw - (1 << SAMPLE_BITS) if raw >= (1 << (SAMPLE_BITS - 1)) else raw


async def _reset(dut):
    dut.rst_n.value = 0
    dut.vec_load.value = 0
    dut.vec_we.value = 0
    dut.vec_addr.value = 0
    dut.vec_bank.value = 0
    dut.vec_data.value = 0
    dut.vec_len.value = DEPTH - 1
    dut.ready.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def _escribir(dut, samples: list[int], bank: int = BANK_ALL, base: int = 0):
    """Escribe `samples` por la ventana, emulando lo que hace `drx_axil_regs`.

    Una muestra por ciclo con `vec_we` en alto y la dirección válida en ESE
    mismo ciclo: es el contrato que `drx_axil_regs` cumple registrando strobe,
    dirección y dato juntos. Deja `vec_load` en ALTO -- quien lo suelta es
    `_cargar`, o el propio caso si quiere escribir el banco entero y
    reproducir solo un trozo.
    """
    dut.vec_load.value = 1
    await RisingEdge(dut.clk)

    for offset, value in enumerate(samples):
        dut.vec_we.value = 1
        dut.vec_addr.value = (base + offset) % DEPTH
        dut.vec_bank.value = bank
        dut.vec_data.value = value & SAMPLE_MASK
        await RisingEdge(dut.clk)
    dut.vec_we.value = 0
    await RisingEdge(dut.clk)


async def _soltar(dut, length: int):
    """Fija `vec_len` y suelta `vec_load`, listo para reproducir.

    `length` tiene que caber en `AddrBits` bits, o sea ser <= DEPTH-1: con
    DEPTH potencia de dos exacta, DEPTH no cabe en `$clog2(DEPTH)` bits. Es la
    misma trampa que documenta `rtl/drx_range_gate.sv:152`, y aquí se
    comprueba en vez de dejarla truncar en silencio.
    """
    assert 0 <= length <= DEPTH - 1, f"vec_len={length} no cabe en {DEPTH - 1}"
    dut.vec_len.value = length
    dut.vec_load.value = 0
    await RisingEdge(dut.clk)


async def _cargar(dut, samples: list[int], bank: int = BANK_ALL, base: int = 0):
    """Escribe el vector y lo deja sonando."""
    await _escribir(dut, samples, bank=bank, base=base)
    await _soltar(dut, len(samples))


async def _reproducir(dut, n: int) -> list[list[int]]:
    """Consume `n` muestras con el consumidor siempre abierto."""
    dut.ready.value = ALL_READY
    out = []
    while len(out) < n:
        await RisingEdge(dut.clk)
        if int(dut.valid.value) == 0:
            continue
        assert int(dut.valid.value) == ALL_READY, (
            "los N_CH bancos leen con el mismo puntero y tienen que presentarse "
            f"a la vez: valid=0b{int(dut.valid.value):0{N_CH}b}"
        )
        word = int(dut.data.value)
        out.append([_unpack(word, c) for c in range(N_CH)])
    dut.ready.value = 0
    return out


@cocotb.test()
async def carga_y_reproduce_en_orden(dut):
    """Lo escrito sale en el mismo orden, y el bucle da la vuelta entero."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    # Valores distintos entre sí y con signo en los dos sentidos: con un patrón
    # monótono, un desplazamiento de una posición sigue pareciendo razonable.
    #
    # DEPTH-1 y no DEPTH: `vec_len` tiene `$clog2(DEPTH)` bits y con DEPTH
    # potencia de dos exacta el propio DEPTH no cabe (ver `_soltar`).
    vector = [(-1) ** k * (k * 7 + 1) for k in range(DEPTH - 1)]
    await _cargar(dut, vector)

    salida = await _reproducir(dut, 2 * len(vector))
    for k, valores in enumerate(salida):
        esperado = vector[k % len(vector)]
        assert valores == [esperado] * N_CH, (
            f"muestra {k}: {valores} != {esperado} en los {N_CH} canales"
        )


@cocotb.test()
async def vec_len_manda_sobre_depth(dut):
    """El puntero envuelve en `vec_len`, no en la capacidad del banco."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    # Se llena el banco ENTERO con un centinela y luego se escribe un bucle más
    # corto encima. Si el envolvente fuera `DEPTH`, los centinelas saldrían.
    # El relleno usa `_escribir` y no `_cargar` porque DEPTH no cabe en
    # `vec_len` (ver `_soltar`), y aquí no hace falta reproducirlo.
    await _escribir(dut, [-999] * DEPTH)

    corto = [11, 22, 33]
    await _escribir(dut, corto)
    await _soltar(dut, len(corto))

    salida = await _reproducir(dut, 3 * len(corto))
    planos = [valores[0] for valores in salida]
    assert planos == corto * 3, f"el bucle no envolvió en vec_len={len(corto)}: {planos}"
    assert -999 not in planos, "se leyó por encima de vec_len: el envolvente es DEPTH"


@cocotb.test()
async def last_pulsa_en_la_ultima_del_bucle(dut):
    """`last` marca el fin de la ventana en `vec_len-1`, en los N_CH canales."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    vector = [5, 6, 7, 8]
    await _cargar(dut, vector)

    dut.ready.value = ALL_READY
    lasts = []
    while len(lasts) < 2 * len(vector):
        await RisingEdge(dut.clk)
        if int(dut.valid.value) == 0:
            continue
        lasts.append(int(dut.last.value))
    dut.ready.value = 0

    esperado = [0] * (len(vector) - 1) + [ALL_READY]
    assert lasts == esperado * 2, f"patrón de `last` equivocado: {lasts}"


@cocotb.test()
async def difusion_contra_escritura_por_banco(dut):
    """`vec_bank` = 7 escribe los N_CH; `vec_bank` = c escribe solo el c."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    base = [100, 200, 300, 400]
    await _cargar(dut, base)

    # Ahora solo el canal 1, con valores distintos. Los otros dos tienen que
    # seguir con `base`: es lo que hace posible Config A (Tx + H + V con formas
    # distintas) sin tocar el diseño.
    solo_ch1 = [-1, -2, -3, -4]
    await _cargar(dut, solo_ch1, bank=1)

    salida = await _reproducir(dut, len(base))
    for k, valores in enumerate(salida):
        assert valores[0] == base[k], f"canal 0 contaminado en {k}: {valores[0]}"
        assert valores[2] == base[k], f"canal 2 contaminado en {k}: {valores[2]}"
        assert valores[1] == solo_ch1[k], (
            f"canal 1 no recibió la escritura dirigida en {k}: {valores[1]}"
        )


@cocotb.test()
async def banco_fuera_de_rango_no_escribe(dut):
    """Un `vec_bank` entre N_CH y 6 no toca ningún banco."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    base = [7, 8, 9, 10]
    await _cargar(dut, base)
    await _cargar(dut, [-50, -51, -52, -53], bank=N_CH)  # 3, que no es un canal

    salida = await _reproducir(dut, len(base))
    for k, valores in enumerate(salida):
        assert valores == [base[k]] * N_CH, (
            f"un banco inexistente escribió en {k}: {valores}"
        )


@cocotb.test()
async def sin_vec_load_la_escritura_no_entra(dut):
    """Con el lector corriendo, `vec_we` no puede corromper el vector vivo.

    Es la protección que evita que medio vector viejo y medio nuevo suenen a la
    vez -- un fallo que en placa no da ningún error, solo un espectro raro.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    base = [21, 22, 23, 24]
    await _cargar(dut, base)

    # `vec_load` en bajo (lo dejó así `_cargar`) y se intenta escribir igual.
    dut.ready.value = ALL_READY
    for offset in range(len(base)):
        dut.vec_we.value = 1
        dut.vec_addr.value = offset
        dut.vec_bank.value = BANK_ALL
        dut.vec_data.value = 0x7FFF
        await RisingEdge(dut.clk)
    dut.vec_we.value = 0
    dut.ready.value = 0
    await RisingEdge(dut.clk)

    salida = await _reproducir(dut, 2 * len(base))
    for k, valores in enumerate(salida):
        esperado = base[k % len(base)]
        assert valores == [esperado] * N_CH, (
            f"una escritura sin vec_load entró en {k}: {valores} != {esperado}"
        )


@cocotb.test()
async def vec_load_rearma_el_puntero(dut):
    """Al soltar `vec_load`, la reproducción empieza en la muestra 0.

    Sin esto, una carga nueva empezaría donde el bucle anterior se quedó, y el
    rayo que se compara contra el modelo dorado arrancaría en un punto distinto
    en cada selección de vector.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    vector = [41, 42, 43, 44]
    await _cargar(dut, vector)

    # Se consume un número de muestras que NO es múltiplo de la longitud, para
    # dejar el puntero a mitad del bucle.
    await _reproducir(dut, len(vector) + 1)

    dut.vec_load.value = 1
    for _ in range(3):
        await RisingEdge(dut.clk)
    assert int(dut.valid.value) == 0, "con vec_load en alto no puede haber salida válida"
    dut.vec_load.value = 0
    await RisingEdge(dut.clk)

    salida = await _reproducir(dut, len(vector))
    planos = [valores[0] for valores in salida]
    assert planos == vector, f"no rearmó en la muestra 0: {planos}"


@cocotb.test()
async def vec_len_cero_es_un_bucle_de_una_muestra(dut):
    """0 no significa 'parado' -- parar es `vec_load`.

    Dejar `0-1` envolver a todo unos haría que el puntero recorriera el banco
    entero, incluida la parte que `$readmemh` deja a cero: silencio en vez de
    tono, y sin ninguna pista de por qué.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    await _escribir(dut, [61, 62, 63, 64])
    await _soltar(dut, 0)

    salida = await _reproducir(dut, 6)
    planos = [valores[0] for valores in salida]
    assert planos == [61] * 6, f"vec_len=0 no se comportó como bucle de 1: {planos}"


@cocotb.test()
async def acortar_vec_len_en_caliente_resincroniza_ya(dut):
    """Un `vec_len` más corto entra en el ciclo siguiente, sin dar la vuelta.

    El envolvente es `rd_ptr >= last_idx`, no `==`. Con una igualdad estricta,
    acortar el bucle con el puntero ya más allá del nuevo final obligaría a
    recorrer el banco entero antes de resincronizar -- y ese recorrido pasa
    por la parte no cargada de la memoria.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, units="ps").start())
    await _reset(dut)

    await _escribir(dut, [71, 72, 73, 74, -888, -888, -888, -888])
    await _soltar(dut, 7)

    # Se avanza hasta dejar el puntero por encima de lo que durará el bucle
    # nuevo, y solo entonces se acorta.
    await _reproducir(dut, 6)
    dut.vec_len.value = 3
    await RisingEdge(dut.clk)

    salida = await _reproducir(dut, 7)
    planos = [valores[0] for valores in salida]
    # La primera puede ser la muestra fuera de rango con la que se cierra el
    # bucle viejo; a partir de ahi tiene que ser el bucle de tres, limpio.
    assert planos[1:] == [71, 72, 73, 71, 72, 73], (
        f"no resincronizo en el ciclo siguiente: {planos}"
    )
