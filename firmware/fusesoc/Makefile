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
	python3 scripts/tests/svunit_test/get_core_name.py && \
	pytest scripts/tests/ -v -m svunit_test \
	  --junitxml=report_pytest/pytest-report.xml

sim:
	. venv/bin/activate; \
	fusesoc $(FUSESOC_CORES) run --target test $(IP)

lint:
	. venv/bin/activate; \
	fusesoc $(FUSESOC_CORES) run --target lint $(IP)

# ----------------------------------------------------------------------------
# IP Packaging (always resolves dependencies from rtl_lib/)
# ----------------------------------------------------------------------------
package:
	@if [ -z "$(IP)" ]; then \
		echo " Usage: make package IP=<ip_name> [VERSION=1.0] [PART=<part>]"; \
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
		--display-name "$(or $(DISPLAY_NAME),$(IP))"

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
