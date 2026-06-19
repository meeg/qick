RDL_FILE = axis_constant_iq_regmap.rdl
GEN_SCRIPT = ../../../../generators/systemrdl/rdl_tools.py

gen:
	python3 $(GEN_SCRIPT) $(RDL_FILE) --output . --hdl --python

clean:
	rm -rf axis_constant_iq_regmap_pkg axis_constant_iq_regmap*.sv axis_constant_iq_regmap*.svh

.PHONY: gen clean
