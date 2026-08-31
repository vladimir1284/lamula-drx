"""Modelo dorado del LAMULA DRx.

Es el oráculo del proyecto (D-03), no una comprobación de apoyo. Si el RTL y este
modelo discrepan, hay un bug en uno de los dos — no se ajusta el modelo para que
el test pase.
"""

from drx_model import chain, cic, fir, fixed, gating, nco, params, vectors
from drx_model.params import Params, load, load_all

__all__ = [
    "Params",
    "chain",
    "cic",
    "fir",
    "fixed",
    "gating",
    "load",
    "load_all",
    "nco",
    "params",
    "vectors",
]
