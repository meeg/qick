RDL_FILE = axis_constant_iq_regmap.rdl
GEN_SCRIPT = ../../../../generators/systemrdl/rdl_tools.py

gen:
	python3 $(GEN_SCRIPT) $(RDL_FILE) --output . --hdl --python

docs:
	python3 -c "\
	from systemrdl import RDLCompiler; \
	from peakrdl_html import HTMLExporter; \
	rdlc = RDLCompiler(); \
	rdlc.compile_file('$(RDL_FILE)'); \
	root = rdlc.elaborate(); \
	HTMLExporter().export(root, './docs'); \
	print('✓ Docs generated in docs/')"

clean:
	rm -rf $(shell basename $(RDL_FILE) .rdl)_pkg $(shell basename $(RDL_FILE) .rdl)*.sv $(shell basename $(RDL_FILE) .rdl)*.svh docs

.PHONY: gen docs clean
