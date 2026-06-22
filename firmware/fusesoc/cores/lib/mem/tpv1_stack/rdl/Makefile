IP_NAME = $(shell basename $(shell dirname $(shell dirname $(CURDIR))))
RDL_FILE = $(IP_NAME)_regmap.rdl
GEN_SCRIPT = ../../../../generators/systemrdl/rdl_tools.py
RDL_FILE = _regmap.rdl

gen:
	python3 $(GEN_SCRIPT) $(RDL_FILE) --output . --hdl --python

clean:
	rm -rf $(IP_NAME)_regmap_pkg $(IP_NAME)_regmap*.sv $(IP_NAME)_regmap*.svh

.PHONY: gen clean
