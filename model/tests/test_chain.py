"""La cadena DDC completa. Es el oráculo, así que se prueba como un oráculo."""

import hashlib

import numpy as np
import pytest
from drx_model import gating, vectors
from drx_model.chain import MODE_COARSE, MODE_FINE, Ddc
from drx_model.params import load

PARAMS = load("zedboard")

#: Huellas del oráculo. Un cambio en el modelo o en los coeficientes las mueve, y
#: ese es exactamente el aviso que se quiere: el oráculo no puede cambiar de valor
#: sin que alguien lo decida a propósito. Para regenerarlas tras un cambio
#: deliberado, ejecuta el propio test y copia la huella que reporte.
#: 2026-09-06: movidas al añadir `Cic.pipeline_fill` (rate-1 muestras de
#: relleno de tubería, ver `cic.py`) — la IP real de Xilinx tiene latencia de
#: silicio en el transitorio que la recursión de latencia cero no tenía;
#: confirmado bit a bit contra xsim en Z1 para el caso `tono_if__fine`.
#: 2026-09-07: movidas de nuevo al añadir el ajuste de ganancia fina de
#: `chain._decimate` (Z1: «escalado de ganancia y saturación con reporte de
#: overflow») — la cadena ya no se queda corta de fondo de escala por el
#: redondeo de `growth_bits` a la potencia de dos superior.
GOLDEN = {
    MODE_FINE: (192, "2f73511eedfd1cfbe061cd52f35d2fcff6ddd27bd18cb214e12e95bdfb1bb198"),
    MODE_COARSE: (96, "b1ef68bd7352b49950e0ac17672fa4219e9b7f661b7fba765dd3cf58a4c8fba5"),
}


def _fingerprint(result) -> str:
    return hashlib.sha256(
        np.concatenate([result.i, result.q]).astype("<i8").tobytes()
    ).hexdigest()


@pytest.mark.parametrize("mode", [MODE_FINE, MODE_COARSE])
def test_el_diezmado_coincide_con_el_paquete_de_parametros(mode):
    ddc = Ddc(params=PARAMS, mode=mode)
    expected = PARAMS.r1 if mode == MODE_FINE else PARAMS.r2
    assert ddc.decimation == expected


@pytest.mark.parametrize("mode", [MODE_FINE, MODE_COARSE])
def test_un_tono_en_el_if_baja_a_continua(mode):
    """Amplitud constante y fase constante: la prueba de que el NCO está en fase."""
    x = vectors.tone(PARAMS, 60_000)
    result = Ddc(params=PARAMS, mode=mode).process(x)
    settled = result.iq[result.i.size // 2 :]
    magnitude = np.abs(settled)
    assert magnitude.mean() > 100, "el tono no llegó a la salida"
    assert magnitude.std() / magnitude.mean() < 1e-3, "la amplitud no es constante"
    phase = np.unwrap(np.angle(settled))
    assert np.abs(np.diff(phase)).max() < 1e-3, "queda frecuencia residual"


@pytest.mark.parametrize("mode", [MODE_FINE, MODE_COARSE])
def test_el_oraculo_es_reproducible_bit_a_bit(mode):
    x = vectors.tone(PARAMS, 40_000, dbfs=-3.0)
    first = Ddc(params=PARAMS, mode=mode).process(x)
    second = Ddc(params=PARAMS, mode=mode).process(x)
    assert np.array_equal(first.i, second.i)
    assert np.array_equal(first.q, second.q)

    expected_size, expected_hash = GOLDEN[mode]
    assert first.i.size == expected_size
    assert _fingerprint(first) == expected_hash, (
        f"el oráculo cambió de valor en modo {mode}: huella nueva "
        f"{_fingerprint(first)}. Si el cambio es deliberado, actualiza GOLDEN "
        "y di en el commit por qué."
    )


@pytest.mark.parametrize("mode", [MODE_FINE, MODE_COARSE])
def test_la_ganancia_de_la_cadena_es_unidad_en_continua_dentro_del_redondeo(mode):
    """El ajuste de ganancia fina deshace lo que `growth_bits` deja a medias: un
    escalón de continua tiene que salir de `_decimate` con la amplitud con la que
    entró, no unos dB por debajo (Z1: «escalado de ganancia... a fondo de
    escala»).

    «Unidad» y no «unidad exacta»: los `shift_round` anteriores al ajuste
    redondean a entero, y ese error de ±0,5 LSB por etapa lo amplifica el propio
    ajuste (`_residual_gain`, entre ~2,6 y ~4,2). Una versión anterior de este
    test exigía igualdad exacta con amplitud 10 000 y pasaba por casualidad:
    barriendo amplitudes, el error es de ±2 (fino) y ±3 (grueso) tanto con R₁ =
    208 como con R₁ = 120 (8-oct-2026). Lo que sí tiene que cumplirse es que el
    error esté acotado por esa amplificación y que no haya sesgo, que es lo que
    detectaría un ajuste mal calculado.
    """
    ddc = Ddc(params=PARAMS, mode=mode)
    bound = int(np.ceil(0.5 * ddc._residual_gain())) + 1
    errors = []
    for amplitude in range(500, 32_000, 733):
        step = np.full(ddc.decimation * 20, amplitude, dtype=np.int64)
        settled = ddc._decimate(step)[-1]
        errors.append(int(settled) - amplitude)
    assert max(abs(e) for e in errors) <= bound
    assert abs(np.mean(errors)) < 0.5, "sesgo: el ajuste de ganancia está mal calculado"


def test_el_modo_grueso_diezma_el_doble_que_el_fino():
    x = vectors.tone(PARAMS, 40_000)
    fine = Ddc(params=PARAMS, mode=MODE_FINE).process(x)
    coarse = Ddc(params=PARAMS, mode=MODE_COARSE).process(x)
    assert fine.i.size == 2 * coarse.i.size


def test_una_entrada_fuera_de_banda_se_rechaza():
    """Un tono lejos del IF tiene que salir muy por debajo del tono en banda."""
    in_band = Ddc(params=PARAMS, mode=MODE_FINE).process(vectors.tone(PARAMS, 60_000))
    off_band = Ddc(params=PARAMS, mode=MODE_FINE).process(
        vectors.tone(PARAMS, 60_000, freq_norm=float(PARAMS.if_norm) + 0.10)
    )
    settled = slice(in_band.i.size // 2, None)
    rejection = np.abs(off_band.iq[settled]).max() / np.abs(in_band.iq[settled]).mean()
    # -60 dB expresado como razón lineal: el rechazo puede ser exactamente 0 y
    # log10(0) solo sirve para ensuciar la salida del test.
    assert rejection < 1e-3


def test_el_offset_de_continua_se_rechaza():
    """Un offset a la entrada es una raya en continua, lejos del IF: no debe pasar."""
    clean = vectors.tone(PARAMS, 60_000, dbfs=-6.0)
    dirty = vectors.add_dc_offset(clean, dbfs=-12.0, params=PARAMS)
    settled = slice(30_000 // PARAMS.r1, None)
    a = Ddc(params=PARAMS, mode=MODE_FINE).process(clean).iq[settled]
    b = Ddc(params=PARAMS, mode=MODE_FINE).process(dirty).iq[settled]
    error = np.abs(b - a).max() / np.abs(a).mean()
    assert error < 1e-2


def test_el_ruido_no_rompe_la_cadena_y_es_reproducible():
    x = vectors.add_noise(
        vectors.tone(PARAMS, 40_000), snr_db=10.0, params=PARAMS, seed=7
    )
    y = vectors.add_noise(
        vectors.tone(PARAMS, 40_000), snr_db=10.0, params=PARAMS, seed=7
    )
    assert np.array_equal(x, y), "el generador de ruido no es determinista"
    result = Ddc(params=PARAMS, mode=MODE_FINE).process(x)
    assert result.i.size > 0


def test_una_cadena_inconsistente_con_los_parametros_falla_ruidosamente():
    """Si alguien cambia R1 sin tocar la descomposición, el modelo lo dice."""
    ddc = Ddc(params=PARAMS, mode=MODE_FINE)
    ddc.fir = type(ddc.fir)(coeffs=ddc.fir.coeffs, decim=3)
    with pytest.raises(ValueError, match="paquete de parámetros"):
        ddc.process(vectors.tone(PARAMS, 1_000))


def test_la_salida_se_puede_enrejar_en_rayos():
    x = vectors.tone(PARAMS, PARAMS.r1 * 40)
    result = Ddc(params=PARAMS, mode=MODE_FINE).process(x)
    rays = gating.gate(result.i, result.q, bins=10)
    assert sum(ray.bins for ray in rays) == result.i.size
    assert all(not ray.truncated for ray in rays[:-1])
