# Atajos de los gates de CI, para correrlos en local antes de commitear.
#
#   make check     todo lo que corre el CI en el job de substrato
#   make gen       regenera lo generado (parámetros, coeficientes, contrato)
#   make figures   regenera las gráficas del tutorial desde el modelo dorado
#   make sim       solo la suite L0 sobre Verilator
#   make l1-vectors  regenera los vectores del oráculo de L1
#   make clean

PY := .venv/bin/python
RUFF := .venv/bin/ruff

.PHONY: check gen figures l1-vectors lint lint-hdl lint-hdl-tb lint-hdl-tb-quad test sim clean venv

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

# El arnés de L1 y su testbench son SystemVerilog que hoy no puede ejecutar
# ningún simulador de este entorno (P-09: hace falta xsim). Lo que sí se puede
# hacer es lintarlo, y así el fichero no se pudre entre Z0 y Z1.
lint-hdl-tb:
	verilator --lint-only -Wall --timing --timescale 1ps/1ps \
	  sim/verilator_waivers.vlt \
	  $$(grep -v '^\s*\#' rtl/filelist.f | grep -v '^\s*$$') \
	  sim/tb_sv/drx_l1_file_source.sv \
	  sim/tb_sv/drx_l1_checker.sv \
	  sim/tb_sv/tb_l1_ddc.sv \
	  --top-module tb_l1_ddc

# Réplica de lint-hdl-tb para tb_l1_ddc_quad.sv (Z1, los cuatro canales de
# ZM1): mismo principio, que el fichero no se pudra sin que make check lo
# note.
lint-hdl-tb-quad:
	verilator --lint-only -Wall --timing --timescale 1ps/1ps \
	  sim/verilator_waivers.vlt \
	  $$(grep -v '^\s*\#' rtl/filelist.f | grep -v '^\s*$$') \
	  sim/tb_sv/drx_l1_file_source.sv \
	  sim/tb_sv/drx_l1_checker.sv \
	  sim/tb_sv/tb_l1_ddc_quad.sv \
	  --top-module tb_l1_ddc_quad

# Los vectores de L1 son salida de build, no fuente: se regeneran, no se
# versionan. Lo que se versiona es el generador.
l1-vectors:
	$(PY) tools/gen_l1_vectors.py

test:
	$(PY) -m pytest -q

sim:
	$(PY) -m pytest sim/tests -q

check: lint lint-hdl lint-hdl-tb lint-hdl-tb-quad test

clean:
	rm -rf build
	$(MAKE) -C fw clean
