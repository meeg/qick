# ============================================================================
# QICK FuseSoC Makefile
# ============================================================================
#
# Usage examples:
#   make package IP=xcom                    # Package IP (always resolves deps)
#   make package IP=xcom VERSION=2.0        # Package with specific version
#   make package-all                        # Package all IPs
#   make sim IP=xcom                        # Simulate IP
#   make lint IP=xcom                       # Lint IP
#   make list-cores                         # List all available cores
#   make core-info CORE=qick:ip:xcom        # Show core info
#   make deps IP=xcom                       # Show dependencies
#
# ============================================================================

FUSESOC_CORES := --cores-root cores \
                 --cores-root projects \
                 --cores-root common \
                 --cores-root generators

# Default tool for simulation and linting
TOOL ?= verilator

# ----------------------------------------------------------------------------
# Environment Setup
# ----------------------------------------------------------------------------
setup_environment:
	git submodule init && git submodule update
	bash scripts/utils/build_virtualenv.sh
	bash scripts/utils/build_fusesocenv.sh
	bash scripts/utils/create_symlinks.sh

# ----------------------------------------------------------------------------
# Simulation and Testing
# ----------------------------------------------------------------------------
sim_svunit: clean
	mkdir -p report_pytest
	. venv/bin/activate; \
	PYTHONPATH=scripts:$$PYTHONPATH \
	python3 scripts/tests/svunit_test/get_core_name.py $(IP) && \
	pytest scripts/tests/ -v -m svunit_test \
		$(if $(IP),-k "$(IP)",) \
		--junitxml=report_pytest/pytest-report.xml

sim:
	. venv/bin/activate; \
	fusesoc $(FUSESOC_CORES) run --target test $(IP)
	#fusesoc $(FUSESOC_CORES) run --target test --tool $(TOOL) $(IP)

lint:
	. venv/bin/activate; \
	fusesoc $(FUSESOC_CORES) run --target lint $(IP)
	#fusesoc $(FUSESOC_CORES) run --target lint --tool $(TOOL) $(IP)

# ----------------------------------------------------------------------------
# IP Packaging (always resolves dependencies from rtl_lib/)
# ----------------------------------------------------------------------------
package:
	@if [ -z "$(IP)" ]; then \
		echo " Usage: make package IP=<ip_name> [DESCRIPTION=<description>] [VERSION=1.0] [PART=<part>]"; \
		echo ""; \
		echo "Examples:"; \
		echo "  make package IP=xcom"; \
		echo "  make package IP=xcom VERSION=2.0"; \
		echo "  make package IP=xcom PART=xczu28dr-ffvg1517-2-e"; \
		exit 1; \
	fi
	@echo " Packaging IP: $(IP)"
	. venv/bin/activate; \
	mkdir -p build/package_$(IP); \
	cd build/package_$(IP) && \
	python3 ../../generators/ip_gen/ip_packager.py \
		--ip-name    $(IP) \
		--version    $(or $(VERSION),1.0) \
		--part       $(or $(PART),xczu49dr-ffvf1760-2-e) \
		--display-name "$(or $(DISPLAY_NAME),$(IP))" \
		$(if $(DESCRIPTION),--description "$(DESCRIPTION)",)

# Package all IPs found in cores/ip/
package-all:
	@echo " Packaging all IPs in cores/ip/..."
	@for ip_dir in cores/ip/*/; do \
		ip=$$(basename $$ip_dir); \
		echo ""; \
		echo "=== Packaging $$ip ==="; \
		$(MAKE) package IP=$$ip; \
	done
	@echo ""
	@echo " All IPs packaged successfully!"

# Dry-run: generate TCL without running Vivado
package-dry:
	@if [ -z "$(IP)" ]; then \
		echo " Usage: make package-dry IP=<ip_name>"; \
		exit 1; \
	fi
	. venv/bin/activate; \
	mkdir -p build/package_$(IP); \
	cd build/package_$(IP) && \
	python3 ../../generators/ip_gen/ip_packager.py \
		--ip-name $(IP) \
		--dry-run

# ----------------------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------------------
clean:
	rm -rf build report_pytest vivado* .Xil .fusesoc_libraries

# ----------------------------------------------------------------------------
# Core Information and Inspection
# ----------------------------------------------------------------------------
list-cores:
	. venv/bin/activate; \
	fusesoc $(FUSESOC_CORES) list-cores

core-info:
	@if [ -z "$(CORE)" ]; then \
		echo " Usage: make core-info CORE=<core_name>"; \
		echo "Example: make core-info CORE=qick:ip:xcom"; \
		exit 1; \
	fi
	. venv/bin/activate; \
	fusesoc $(FUSESOC_CORES) core-info $(CORE)

deps:
	@if [ -z "$(IP)" ]; then \
		echo " Usage: make deps IP=<ip_name>"; \
		echo "Example: make deps IP=xcom"; \
		exit 1; \
	fi
	. venv/bin/activate; \
	echo "=== Dependencies for qick:ip:$(IP) ==="; \
	fusesoc $(FUSESOC_CORES) core-info qick:ip:$(IP) 2>&1 | grep -E "depend|depends" -A 20 || \
	echo "No dependencies found or core not found"

verify-core:
	@if [ -z "$(IP)" ]; then \
		echo " Usage: make verify-core IP=<ip_name>"; \
		exit 1; \
	fi
	@echo "=== Verifying core: qick:ip:$(IP) ==="
	@if [ -d "cores/ip/$(IP)" ]; then \
		echo " Core directory exists: cores/ip/$(IP)"; \
	else \
		echo " Core directory missing: cores/ip/$(IP)"; \
	fi
	@if [ -f "cores/ip/$(IP)/$(IP).core" ]; then \
		echo " Core file exists: cores/ip/$(IP)/$(IP).core"; \
	else \
		echo " Core file missing: cores/ip/$(IP)/$(IP).core"; \
	fi
	@if [ -d "../rtl_lib/ip/$(IP)" ]; then \
		echo " RTL source exists: ../rtl_lib/ip/$(IP)/"; \
	else \
		echo "  RTL source missing: ../rtl_lib/ip/$(IP)/ (create it!)"; \
	fi
	@if [ -d "../ip/$(IP)/src" ]; then \
		echo " Packaged IP source exists: ../ip/$(IP)/src"; \
	else \
		echo "  IP not packaged yet (run 'make package IP=$(IP)')"; \
	fi
	@echo ""
	@echo "=== Dependencies ==="
	$(MAKE) --no-print-directory deps IP=$(IP)

# Generate regmap for any IP
# Use: make gen IP=axis_constant_iq
gen:
	@if [ -z "$(IP)" ]; then \
		echo "Usage: make gen IP=<ip_name>"; \
		exit 1; \
	fi
	cd cores/ip/$(IP)/rdl && $(MAKE) gen

# Create new IP
new-ip:
	@if [ -z "$(IP)" ]; then \
		echo "Usage: make new-ip IP=<ip_name>"; \
		exit 1; \
	fi
	./scripts/create_ip.sh $(IP)

# Generate driver + run register tests
driver:
	@if [ -z "$(IP)" ]; then echo "Usage: make driver IP=<ip_name>"; exit 1; fi
	@echo "Generating driver for $(IP)..."
	cd cores/ip/$(IP)/rdl && $(MAKE) gen
	@if [ -f cores/ip/$(IP)/driver/$(IP).py ]; then \
		ln -sf ../../../firmware/fusesoc/cores/ip/$(IP)/driver/$(IP).py \
		../../qick_lib/qick/drivers/$(IP).py; \
		echo "  Symlink created"; \
	fi
	@$(MAKE) --no-print-directory driver-test IP=$(IP)

# Run driver register tests only (no regeneration)
driver-test:
	@if [ -z "$(IP)" ]; then echo "Usage: make driver-test IP=<ip_name>"; exit 1; fi
	@if [ -d cores/ip/$(IP)/driver/tests ]; then \
		echo "Running driver register tests for $(IP)..."; \
		mkdir -p report_pytest; \
		. venv/bin/activate; \
		pytest cores/ip/$(IP)/driver/tests/ -v \
		--junitxml=report_pytest/driver-$(IP)-report.xml; \
	else \
		echo "No driver/tests/ for $(IP)"; \
	fi

# Generate drivers for all IPs
driver-all:
	@for ip in $$(ls -d cores/ip/*/); do \
		ip_name=$$(basename $$ip); \
		if [ -f $$ip/rdl/Makefile ]; then \
			echo "Generating $$ip_name..."; \
			cd $$ip/rdl && $(MAKE) gen && cd ../../../..; \
			if [ -f $$ip/driver/$$ip_name.py ]; then \
				ln -sf ../../../firmware/fusesoc/$$ip/driver/$$ip_name.py \
					../../qick_lib/qick/drivers/$$ip_name.py; \
			fi; \
		fi; \
	done

# Generate HTML documentation from RDL
# Usage: make rdl-docs IP=axis_constant_iq
rdl-docs:
	cd cores/ip/$(IP)/rdl && $(MAKE) docs
	@echo "✓ Docs: cores/ip/$(IP)/rdl/docs/index.html"

## ----------------------------------------------------------------------------
## RTL Library Documentation (Doxygen over ../rtl_lib)
## ----------------------------------------------------------------------------
## Generate HTML docs for the whole RTL library.
##   make rtl-docs                     # document all of ../rtl_lib
##   make rtl-docs INPUT=../rtl_lib/dsp/ctrl_sgv4.sv   # single file/dir
#rtl-docs:
#	@command -v doxygen >/dev/null 2>&1 || { echo "doxygen not found (sudo apt install doxygen graphviz)"; exit 1; }
#	@mkdir -p docs/rtl
#	@if [ -n "$(INPUT)" ]; then \
#		( cat docs/Doxyfile; echo "INPUT = $(INPUT)" ) | doxygen -; \
#	else \
#		doxygen docs/Doxyfile; \
#	fi
#	@echo "✓ RTL docs: docs/rtl/html/index.html"
#
#rtl-docs-clean:
#	@rm -rf docs/rtl
#	@echo "✓ Cleaned docs/rtl"

# ----------------------------------------------------------------------------
# RTL Library Documentation (custom Markdown generator over ../rtl_lib)
# ----------------------------------------------------------------------------
# Generate Markdown docs (TerosHDL-style tables) for the RTL library.
#   make rtl-docs                                  # document all of ../rtl_lib
#   make rtl-docs INPUT=../rtl_lib/dsp/sgv4_top.sv # single file
RTL_DOCS_IN  ?= ../rtl_lib
RTL_DOCS_OUT ?= docs/rtl-md

rtl-docs:
	. venv/bin/activate; \
  python3 scripts/gen_docs.py \
      --input  $(if $(INPUT),$(INPUT),$(RTL_DOCS_IN)) \
      --outdir $(RTL_DOCS_OUT) \
      --index
	@echo "✓ RTL docs: $(RTL_DOCS_OUT)/README.md"

rtl-docs-clean:
	@rm -rf $(RTL_DOCS_OUT) docs/rtl
	@echo "✓ Cleaned RTL docs"
