# ============================================================================
# QICK FuseSoC Makefile
# ============================================================================
#
# Central entry point for the QICK FuseSoC environment. All targets run from
# firmware/fusesoc/ and activate the shared project venv (../../.venv/, i.e.
# qick_internal/.venv) internally (no need to `source` it first). This same
# venv is also used to build the Sphinx docs (docs/requirements.txt).
#
# QUICK REFERENCE
#   Setup:
#     make setup_environment              # one-time: submodules + venv + fusesoc env
#   Simulation / lint:
#     make sim         IP=<core>          # run SVUnit test target (single core, xsim)
#     make sim_svunit  [IP=<core>]        # pytest+SVUnit wrapper; all cores if no IP
#     make lint        IP=<core>          # veriblelint / verilator lint-only
#   Registers / drivers (PeakRDL):
#     make gen         IP=<ip>            # generate regmap package from RDL
#     make driver      IP=<ip>            # gen + symlink driver + register tests
#     make driver-test IP=<ip>           # register tests only (scaffolds if needed)
#     make driver-all                    # regenerate drivers for every IP
#     make rdl-docs    IP=<ip>           # HTML register docs
#   RTL library docs:
#     make rtl-docs    [INPUT=<file>]    # Markdown docs for ../rtl_lib (all or one)
#     make rtl-docs-clean
#   Packaging (Vivado):
#     make package     IP=<ip> [VERSION=] [PART=] [DESCRIPTION=] [DISPLAY_NAME=]
#     make package-all
#     make package-dry IP=<ip>
#   Inspection:
#     make list-cores | core-info CORE=<vlnv> | deps IP=<ip> | verify-core IP=<ip>
#   Cleanup:
#     make clean
#
# VARIABLES
#   IP            Core / IP short name, e.g. axis_signal_gen_v4 (most targets).
#   CORE          Full VLNV, e.g. qick:ip:axis_signal_gen_v4 (core-info).
#   TOOL          EDA tool override (default: verilator; xsim used by .core target).
#   VERSION       IP version for packaging (default: 1.0).
#   PART          Target FPGA part (default: xczu49dr-ffvf1760-2-e).
#   INPUT         Single file/dir for rtl-docs (default: whole ../rtl_lib).
#   DESCRIPTION / DISPLAY_NAME   Optional IP metadata for packaging.
#
# GOTCHAS (learned the hard way)
#   * Recipes need TABs, not spaces (else "*** missing separator").
#   * venv activation must be on the SAME logical recipe line as the command
#     that needs it (joined with '\'), because each recipe line is a new shell.
#   * Sub-makes into cores/ip/<ip>/rdl/ (gen, driver, rdl-docs) MUST activate the
#     venv first, or python3 uses the system interpreter and systemrdl is missing.
#   * The venv lives at qick_internal/.venv (shared with the docs build), not
#     under firmware/fusesoc/ — that's why every activation is '../../.venv/...'.
#   * Use '$$VAR' (double $) for shell vars inside recipes; single $ is Make's.
# ============================================================================

FUSESOC_CORES := --cores-root cores \
	         --cores-root projects \
	         --cores-root common \
	         --cores-root generators

# Default tool for simulation and linting.
TOOL ?= verilator

# ----------------------------------------------------------------------------
# Optional testbench knobs. Only appended when set, so 'make sim IP=<any>'
# keeps working for cores that do not declare these parameters.
#   make sim IP=fifo_async MODE=fwft
#   make sim IP=fifo_async MODE=fwft DEPTH=16 WIDTH=24 SWAP_CLK=1
# ----------------------------------------------------------------------------
MODE     ?=
DEPTH    ?=
WIDTH    ?=
SWAP_CLK ?=
ASYNC    ?=
FIFO     ?=
MEM      ?=


SIM_ARGS :=

ifeq ($(MEM),auto)
  SIM_ARGS += --TB_MEM=0
else ifeq ($(MEM),distributed)
  SIM_ARGS += --TB_MEM=1
else ifeq ($(MEM),block)
  SIM_ARGS += --TB_MEM=2
else ifeq ($(MEM),ultra)
  SIM_ARGS += --TB_MEM=3
else ifneq ($(MEM),)
  $(error MEM must be auto, distributed, block or ultra (got '$(MEM)'))
endif

ifneq ($(ASYNC),)
  SIM_ARGS += --ASYNC_CLK=$(ASYNC)
endif

ifeq ($(MODE),fwft)
  SIM_ARGS += --FWFT=1
else ifeq ($(MODE),std)
  SIM_ARGS += --FWFT=0
else ifneq ($(MODE),)
  $(error MODE must be 'std' or 'fwft' (got '$(MODE)'))
endif

ifneq ($(DEPTH),)
  SIM_ARGS += --TB_N=$(DEPTH)
endif
ifneq ($(WIDTH),)
  SIM_ARGS += --TB_B=$(WIDTH)
endif
ifneq ($(SWAP_CLK),)
  SIM_ARGS += --SWAP_CLK=$(SWAP_CLK)
endif


# RTL library documentation input/output (overridable).
RTL_DOCS_IN  ?= ../rtl_lib
RTL_DOCS_OUT ?= docs/rtl-md

.PHONY: help setup_environment \
	sim sim_svunit lint \
	package package-all package-dry \
	clean \
	list-cores core-info deps verify-core \
	gen new-ip driver driver-test driver-all driver-scaffold \
	rdl-docs rtl-docs rtl-docs-clean sim-streamer-matrix

# Default target: show the quick reference.
help:
	@sed -n '2,60p' $(MAKEFILE_LIST) | sed 's/^# \{0,1\}//'

# ----------------------------------------------------------------------------
# Environment Setup
# ----------------------------------------------------------------------------
# One-time setup after cloning: init submodules, build the shared project venv
# at qick_internal/.venv (installs pyproject.toml deps incl. systemrdl-compiler
# / peakrdl-*, plus docs/requirements.txt so the same venv builds the Sphinx
# docs), build the FuseSoC env, and create source symlinks. Run this before
# any other target on a fresh checkout (e.g. on a new machine).
setup_environment:
	git submodule init && git submodule update
	bash scripts/utils/build_virtualenv.sh
	bash scripts/utils/build_fusesocenv.sh
	bash scripts/utils/create_symlinks.sh

# ----------------------------------------------------------------------------
# Simulation and Testing
# ----------------------------------------------------------------------------
# pytest wrapper around SVUnit. With IP=<core> runs only that core; without IP
# runs all cores that have a 'test' target (CI mode). Emits a JUnit report.
# Requires PYTHONPATH=scripts for the get_core_name.py helper.
sim_svunit: clean
	mkdir -p report_pytest
	. ../../.venv/bin/activate; \
	PYTHONPATH=scripts:$$PYTHONPATH \
	python3 scripts/tests/svunit_test/get_core_name.py $(IP) && \
	pytest scripts/tests/ -v -m svunit_test \
	$(if $(IP),-k "$(IP)",) \
	--junitxml=report_pytest/pytest-report.xml

# Run the FuseSoC 'test' target (SVUnit via xsim) for a single core. Fast path.
#   make sim IP=lfsr
#   make sim IP=fifo_async MODE=fwft DEPTH=16 WIDTH=24
sim:
	. ../../.venv/bin/activate; \
	fusesoc $(FUSESOC_CORES) run --target test $(IP) $(SIM_ARGS)

# Sweep every fifo_async configuration that matters for the streamer swap:
#   read mode x {big/generic, streamer-sized} x clock ratio = 8 runs.
# Keeps going on failure and reports the list of failed configs at the end.
sim-fifo-matrix:
	@fail=0; failed=""; \
	for mode in std fwft; do \
	  for cfg in "2048 32" "16 24"; do \
	    set -- $$cfg; \
	    for swap in 0 1; do \
	      cfgname="MODE=$$mode DEPTH=$$1 WIDTH=$$2 SWAP_CLK=$$swap"; \
	      echo ""; \
	      echo "=============================================================="; \
	      echo "=== fifo_async  $$cfgname"; \
	      echo "=============================================================="; \
	      if ! $(MAKE) --no-print-directory sim IP=fifo_async \
	           MODE=$$mode DEPTH=$$1 WIDTH=$$2 SWAP_CLK=$$swap; then \
	        fail=1; failed="$$failed\n  $$cfgname"; \
	      fi; \
	    done; \
	  done; \
	done; \
	echo ""; \
	if [ $$fail -eq 0 ]; then \
	  echo "*** fifo_async matrix: all 8 configurations passed"; \
	else \
	  printf "*** fifo_async matrix FAILED for:%b\n" "$$failed"; \
	fi; \
	exit $$fail

sim-streamer-matrix:
	@fail=0; failed=""; \
	for ip in streamer axis_streamer; do \
	  for cfg in "16 auto" "1024 block"; do \
	    set -- $$cfg; \
	    echo ""; \
	    echo "=== $$ip  FIFO=$$1 MEM=$$2"; \
	    if ! $(MAKE) --no-print-directory sim IP=$$ip FIFO=$$1 MEM=$$2; then \
	      fail=1; failed="$$failed\n  $$ip FIFO=$$1 MEM=$$2"; \
	    fi; \
	  done; \
	done; \
	echo ""; \
	if [ $$fail -eq 0 ]; then \
	  echo "*** streamer matrix: all configurations passed"; \
	else \
	  printf "*** streamer matrix FAILED for:%b\n" "$$failed"; \
	fi; \
	exit $$fail

# Run the FuseSoC 'lint' target (veriblelint / verilator lint-only).
# NOTE: IPs instantiating Xilinx primitives (DSP/XPM/DDS) can't be linted by
# Verilator alone.
lint:
	. ../../.venv/bin/activate; \
	fusesoc $(FUSESOC_CORES) run --target lint $(IP)
	#fusesoc $(FUSESOC_CORES) run --target lint --tool $(TOOL) $(IP)

# ----------------------------------------------------------------------------
# IP Packaging (Vivado; always resolves dependencies from rtl_lib/)
# ----------------------------------------------------------------------------
# Package a single IP via the ip_packager generator into build/package_<ip>/.
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
	. ../../.venv/bin/activate; \
	mkdir -p build/package_$(IP); \
	cd build/package_$(IP) && \
	python3 ../../generators/ip_gen/ip_packager.py \
	--ip-name    $(IP) \
	$(if $(VERSION),--version $(VERSION),) \
	--part       $(or $(PART),xczu49dr-ffvf1760-2-e) \
	--display-name "$(or $(DISPLAY_NAME),$(IP))" \
	$(if $(DESCRIPTION),--description "$(DESCRIPTION)",)

# Package every IP under cores/ip/.
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

# Generate the packaging TCL without running Vivado (inspection / debug).
package-dry:
	@if [ -z "$(IP)" ]; then \
	echo " Usage: make package-dry IP=<ip_name>"; \
	exit 1; \
	fi
	. ../../.venv/bin/activate; \
	mkdir -p build/package_$(IP); \
	cd build/package_$(IP) && \
	python3 ../../generators/ip_gen/ip_packager.py \
	--ip-name $(IP) \
	--dry-run

# ----------------------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------------------
# Removes build artifacts and the cloned SVUnit lib (re-cloned next sim_svunit).
# Does NOT touch venv/ or source symlinks.
clean:
	rm -rf build report_pytest vivado* .Xil .fusesoc_libraries

# ----------------------------------------------------------------------------
# Core Information and Inspection
# ----------------------------------------------------------------------------
# List all cores across the four roots.
list-cores:
	. ../../.venv/bin/activate; \
	fusesoc $(FUSESOC_CORES) list-cores

# Show a core's filesets / targets / deps.  make core-info CORE=qick:ip:xcom
core-info:
	@if [ -z "$(CORE)" ]; then \
	echo " Usage: make core-info CORE=<core_name>"; \
	echo "Example: make core-info CORE=qick:ip:xcom"; \
	exit 1; \
	fi
	. ../../.venv/bin/activate; \
	fusesoc $(FUSESOC_CORES) core-info $(CORE)

# Grep the dependency block of qick:ip:<ip>.
deps:
	@if [ -z "$(IP)" ]; then \
	echo " Usage: make deps IP=<ip_name>"; \
	echo "Example: make deps IP=xcom"; \
	exit 1; \
	fi
	. ../../.venv/bin/activate; \
	echo "=== Dependencies for qick:ip:$(IP) ==="; \
	fusesoc $(FUSESOC_CORES) core-info qick:ip:$(IP) 2>&1 | grep -E "depend|depends" -A 20 || \
	echo "No dependencies found or core not found"

# Sanity-check that a core's dir, .core, RTL source and packaged source exist.
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

# ----------------------------------------------------------------------------
# Register map & driver (PeakRDL)
# ----------------------------------------------------------------------------
# Generate the PeakRDL regmap package from the IP's RDL.
# NOTE: activates venv and uses -C so systemrdl is available in the sub-make.
#   make gen IP=axis_constant_iq
gen:
	@if [ -z "$(IP)" ]; then \
	echo "Usage: make gen IP=<ip_name>"; \
	exit 1; \
	fi
	. ../../.venv/bin/activate; \
	$(MAKE) -C cores/ip/$(IP)/rdl gen

# Scaffold cores/ip/<ip>/ (rdl/, driver/, hdl/, tests/).
new-ip:
	@if [ -z "$(IP)" ]; then \
	echo "Usage: make new-ip IP=<ip_name>"; \
	exit 1; \
	fi
	./scripts/create_ip.sh $(IP)

# Full driver flow: regmap gen -> create driver if missing -> symlink into qick_lib -> register tests.
driver:
	@if [ -z "$(IP)" ]; then echo "Usage: make driver IP=<ip_name>"; exit 1; fi
	@echo "Generating driver for $(IP)..."
	. ../../.venv/bin/activate; \
	$(MAKE) -C cores/ip/$(IP)/rdl gen
	@./scripts/gen_driver.sh $(IP)
	@if [ -f cores/ip/$(IP)/driver/$(IP).py ]; then \
		ln -sf ../../../firmware/fusesoc/cores/ip/$(IP)/driver/$(IP).py \
			     ../../qick_lib/qick/drivers/$(IP).py; \
			echo "  Symlink created"; \
	fi
	@if [ -d cores/ip/$(IP)/rdl/$(IP)_regmap_pkg ]; then \
		mkdir -p ../../qick_lib/qick/rdl_pkgs; \
		rm -rf ../../qick_lib/qick/rdl_pkgs/$(IP)_regmap_pkg; \
		cp -r cores/ip/$(IP)/rdl/$(IP)_regmap_pkg ../../qick_lib/qick/rdl_pkgs/; \
		echo "  regmap_pkg copied to rdl_pkgs/"; \
	fi
	@$(MAKE) --no-print-directory driver-test IP=$(IP)

# Run the register-layer pytest only (no regeneration). Scaffolds tests if
# absent. Writes report_pytest/driver-<ip>-report.xml.
driver-test:
	@if [ -z "$(IP)" ]; then echo "Usage: make driver-test IP=<ip_name>"; exit 1; fi
	@if [ ! -f cores/ip/$(IP)/driver/tests/test_$(IP)_regs.py ]; then \
     echo "No driver tests for $(IP) — scaffolding from RDL..."; \
     $(MAKE) --no-print-directory driver-scaffold IP=$(IP); \
	fi
	@echo "Running driver register tests for $(IP)..."; \
	mkdir -p report_pytest; \
	. ../../.venv/bin/activate; \
	pytest cores/ip/$(IP)/driver/tests/ -v \
	  --junitxml=report_pytest/driver-$(IP)-report.xml

# Regenerate drivers + symlinks for every IP under cores/ip/ that has rdl/Makefile.
# NOTE: activates venv once and uses -C (no fragile cd ../../../..).
driver-all:
	. ../../.venv/bin/activate; \
	for ip in $$(ls -d cores/ip/*/); do \
	ip_name=$$(basename $$ip); \
	if [ -f $$ip/rdl/Makefile ]; then \
	    echo "Generating $$ip_name..."; \
	    $(MAKE) -C $$ip/rdl gen; \
	    if [ -f $$ip/driver/$$ip_name.py ]; then \
	        ln -sf ../../../firmware/fusesoc/$$ip/driver/$$ip_name.py \
	            ../../qick_lib/qick/drivers/$$ip_name.py; \
	    fi; \
	fi; \
	done

# Scaffold driver/tests/ from the generated RDL package (idempotent).
driver-scaffold:
	@if [ -z "$(IP)" ]; then echo "Usage: make driver-scaffold IP=<ip_name>"; exit 1; fi
	. ../../.venv/bin/activate; \
	python3 scripts/gen_driver_tests.py $(IP)

# Generate HTML register documentation from RDL.
# NOTE: activates venv for the sub-make (PeakRDL needs systemrdl/peakrdl-html).
#   make rdl-docs IP=axis_constant_iq
rdl-docs:
	@if [ -z "$(IP)" ]; then echo "Usage: make rdl-docs IP=<ip_name>"; exit 1; fi
	. ../../.venv/bin/activate; \
	$(MAKE) -C cores/ip/$(IP)/rdl docs
	@echo "✓ Docs: cores/ip/$(IP)/rdl/docs/index.html"

# ----------------------------------------------------------------------------
# RTL Library Documentation (custom Markdown generator over ../rtl_lib)
# ----------------------------------------------------------------------------
# Generate Markdown docs (TerosHDL-style Generics/Ports tables) for the RTL
# library. Reads doc from //! blocks and legacy /** @port/@param */ headers.
# Excludes come from ../rtl_lib/.docsignore.
#   make rtl-docs                                   # document all of ../rtl_lib
#   make rtl-docs INPUT=../rtl_lib/dsp/sgv4_top.sv  # single file
rtl-docs:
	. ../../.venv/bin/activate; \
	python3 scripts/gen_docs.py \
	--input  $(if $(INPUT),$(INPUT),$(RTL_DOCS_IN)) \
	--outdir $(RTL_DOCS_OUT) \
	--index
	@echo "✓ RTL docs: $(RTL_DOCS_OUT)/README.md"

# Remove generated RTL docs (and any stale Doxygen output).
rtl-docs-clean:
	@rm -rf $(RTL_DOCS_OUT) docs/rtl
	@echo "✓ Cleaned RTL docs"
