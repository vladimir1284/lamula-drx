#!/usr/bin/env python3
"""Vigila la captura de UART de una corrida nocturna y marca el atasco de P-21.

    tools/vigia_uart.py <dir-de-la-corrida>

Hace dos trabajos que van juntos:

  1. Le pone marca de tiempo de pared a cada línea, en `uart-ts.log`. La UART no
     lleva hora propia -- solo `uptime=Ns` una vez por segundo -- y sin una hora
     común no se puede cruzar una línea de UART con el nombre de un CSV del ILA.
     El `uart.log` crudo no se toca, para que los `grep -a 'drx_status: BITE'`
     de siempre sigan valiendo byte a byte.

  2. Busca dos cadenas y reacciona distinto a cada una.

Lectura propia en vez de `tail -F | grep`: `tail -F` sin `-n +1` empieza por el
final del fichero y se saltaría un atasco anterior a su arranque, y la cadena
`tail | grep` añade buffering que no controlamos.

Por qué el vigía NO es el detector principal: en el atasco permanente el ILA
dispara solo. `set_modo_ddr(true)` corre ANTES de `submit_pass()` y el fallo no
lo baja (fw/src/app/drx_stimulus.c:283), así que queda `ddr_mode = 1` con
`s_vec_valid = 0`, la sonda sigue armada y `stalled` sube a los 16,78 ms. Y hay
un camino peor: cuando `submit_pass()` falla dentro del bucle normal de
`DrxStimulusTask` (drx_stimulus.c:391) no se imprime NADA por UART. Ahí el ILA
es el único testigo. Este vigía es la red de seguridad, no el instrumento.
"""
import os
import sys
import time
from datetime import datetime

# El fallo duro: `DrxStimulus_Select` no pudo encolar. Levanta la bandera.
DURO = "no se pudo encolar la primera pasada"
# Más temprano y más sensible, pero puede ser transitorio: solo se anota.
BLANDO = "pasada sin completar tras"

# Durante el arranque, DURO significa otra cosa: es el síntoma documentado de
# una recarga en caliente mal hecha (docs/implementacion/ila.md, "las tres
# trampas"). Con arranque en frío no debe salir, y si sale es que el arranque
# está mal -- eso lo cubre la puerta de `noche_p21.sh`, no una bandera.
GRACIA_S = 60.0


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    d = argv[1]
    uart = os.path.join(d, "uart.log")
    salida = os.path.join(d, "uart-ts.log")
    bandera = os.path.join(d, "bandera-ila")
    parar = os.path.join(d, "parar-conductor")

    t0 = time.monotonic()
    # Esperar a que exista: el orquestador arranca el `cat` justo antes.
    while not os.path.exists(uart):
        if time.monotonic() - t0 > 30.0:
            print(f"no apareció {uart} en 30 s", file=sys.stderr)
            return 1
        time.sleep(0.2)

    blandos = 0
    with open(uart, "rb") as f, open(salida, "a", buffering=1) as out:
        resto = b""
        while True:
            trozo = f.read(65536)
            if not trozo:
                if os.path.exists(parar):
                    # El conductor ya terminó; una última pasada y fuera.
                    if not f.read(1):
                        return 0
                time.sleep(0.2)
                continue
            resto += trozo
            *lineas, resto = resto.split(b"\n")
            for cruda in lineas:
                linea = cruda.decode("utf-8", "replace").rstrip("\r")
                ahora = datetime.now().isoformat(timespec="seconds")
                out.write(f"{ahora} {linea}\n")
                if BLANDO in linea:
                    blandos += 1
                    out.write(f"{ahora} === VIGIA: precursor #{blandos} ===\n")
                if DURO in linea:
                    if time.monotonic() - t0 < GRACIA_S:
                        out.write(f"{ahora} === VIGIA: DURO en la gracia, "
                                  f"arranque sospechoso, NO se levanta bandera ===\n")
                        continue
                    out.write(f"{ahora} === VIGIA: ATASCO PERMANENTE ===\n")
                    with open(bandera, "w") as b:
                        b.write(f"{ahora} {linea}\n")
                    with open(parar, "w") as p:
                        p.write(f"{ahora} atasco visto por el vigia\n")
                    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
