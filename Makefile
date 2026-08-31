# Atajos de los gates de CI, para correrlos en local antes de commitear.
#
#   make check     todo lo que corre el CI en el job de substrato
#   make gen       regenera lo generado (parámetros, coeficientes, contrato)
#   make figures   regenera las gráficas del tutorial desde el modelo dorado
#   make sim       solo la suite L0 sobre Verilator
#   make clean

PY := .venv/bin/python
RUFF := .venv/bin/ruff

.PHONY: check gen figures lint lint-hdl test sim clean venv

venv:
	uv venv .venv
	uv pip install --python .venv/bin/python -r requirements-dev.txt

gen:
	$(PY) tools/gen_params.py
	$(PY) tools/gen_coeffs.py
	$(PY) tools/gen_contract.py

# Las figuras del tutorial salen del propio modelo. No hay gate de CI sobre los
# SVG —matplotlib no garantiza salida byte a byte entre versiones— pero sí hay
# tests que comprueban numéricamente lo que las figuras enseñan.
figures:
	$(PY) tools/gen_docs_figures.py

lint:
	$(PY) tools/gen_params.py --check
	$(PY) tools/gen_coeffs.py --check
	$(PY) tools/gen_contract.py --check
	$(PY) tools/check_hardcoded_clock.py
	$(RUFF) check .

lint-hdl:
	verilator --lint-only -Wall --timing \
	  sim/verilator_waivers.vlt \
	  $$(grep -v '^\s*\#' rtl/filelist.f | grep -v '^\s*$$') \
	  --top-module drx_top

test:
	$(PY) -m pytest -q

sim:
	$(PY) -m pytest sim/tests -q

check: lint lint-hdl test

clean:
	rm -rf build
	$(MAKE) -C fw clean
