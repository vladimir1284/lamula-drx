"""Enrejado en rango: fronteras de bin, conteo y `TLAST` por rayo.

Un bin de rango es exactamente una muestra a la salida del DDC: el diezmado ya
hizo el promediado. Lo que hace el gating es cortar el flujo continuo en rayos de
`bins` muestras y marcar el último.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from drx_model.params import Params


@dataclass(frozen=True)
class Ray:
    """Un rayo enrejado en rango."""

    i: np.ndarray
    q: np.ndarray
    bins: int
    truncated: bool  # el flujo se acabó antes de completar el rayo

    def __post_init__(self) -> None:
        if self.i.size != self.q.size:
            raise ValueError("I y Q tienen que tener el mismo número de bins")


def bins_for_mode(params: Params, mode: str) -> int:
    """Conteo de bins del modo, tal como sale del paquete de parámetros."""
    key = {"fine": "bins_mode_fine", "coarse": "bins_mode_coarse"}[mode]
    return int(params.invariant[key])


def gate(i: np.ndarray, q: np.ndarray, bins: int) -> list[Ray]:
    """Trocea en rayos de `bins` muestras.

    El último rayo puede quedar incompleto si el vector se acaba; se devuelve
    marcado como truncado en vez de descartarlo en silencio, porque un rayo corto
    en la placa es un fallo que el BITE tiene que ver.
    """
    if bins < 1:
        raise ValueError("bins tiene que ser >= 1")
    i = np.asarray(i, dtype=np.int64)
    q = np.asarray(q, dtype=np.int64)
    if i.size != q.size:
        raise ValueError("I y Q tienen que tener el mismo tamaño")

    rays: list[Ray] = []
    for start in range(0, i.size, bins):
        chunk_i = i[start : start + bins]
        chunk_q = q[start : start + bins]
        rays.append(
            Ray(i=chunk_i, q=chunk_q, bins=chunk_i.size, truncated=chunk_i.size < bins)
        )
    return rays


def tlast_mask(n_samples: int, bins: int) -> np.ndarray:
    """Máscara booleana de `TLAST`: True en la última muestra de cada rayo."""
    mask = np.zeros(n_samples, dtype=bool)
    mask[bins - 1 :: bins] = True
    return mask
