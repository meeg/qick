# Package xcom without resolving dependencies (uses what is already in ip/xcom/src/)
#make package IP=xcom
#
## Package xcom while resolving dependencies from fusesoc/cores/lib/
#make package IP=xcom RESOLVE_DEPS=1
#
## Use the shortcut
#make package-full IP=xcom VERSION=2.0
#
## Package all IPs
#make package-all
#
## View xcom dependencies
#make deps IP=xcom
#
## List all available cores
#make list-cores

FUSESOC_CORES := --cores-root cores \
                 --cores-root projects \
                 --cores-root common \
                 --cores-root generators

setup_environment:
	git submodule init && git submodule update
	bash scripts/utils/build_virtualenv.sh
	bash scripts/utils/build_fusesocenv.sh
	bash scripts/utils/create_symlinks.sh

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

# Package an IP for Vivado Block Design
# Usage: make package IP=<ip_name> [VERSION=1.0] [PART=xczu49dr-ffvf1760-2-e] [RESOLVE_DEPS=1]
# Example: make package IP=xcom VERSION=2.0 RESOLVE_DEPS=1
package:
	@if [ -z "$(IP)" ]; then \
		echo "Usage: make package IP=<ip_name> [VERSION=1.0] [PART=xczu49dr-ffvf1760-2-e] [RESOLVE_DEPS=1]"; \
		echo ""; \
		echo "Examples:"; \
		echo "  make package IP=xcom"; \
		echo "  make package IP=xcom VERSION=2.0"; \
		echo "  make package IP=xcom RESOLVE_DEPS=1  # Copy dependencies from fusesoc/cores/lib/"; \
		exit 1; \
	fi
	. venv/bin/activate; \
	mkdir -p build/package_$(IP); \
	cd build/package_$(IP) && \
	python3 ../../generators/ip_gen/ip_packager.py \
		--ip-name    $(IP) \
		--version    $(or $(VERSION),1.0) \
		--part       $(or $(PART),xczu49dr-ffvf1760-2-e) \
		--display-name "$(or $(DISPLAY_NAME),$(IP))" \
		$(if $(RESOLVE_DEPS),--resolve-deps)

# Package an IP and automatically resolve dependencies (shortcut)
package-full:
	@if [ -z "$(IP)" ]; then \
		echo "Usage: make package-full IP=<ip_name> [VERSION=1.0]"; \
		exit 1; \
	fi
	$(MAKE) package IP=$(IP) VERSION=$(VERSION) RESOLVE_DEPS=1

# Package all IPs that have a .core file in cores/ip/
package-all:
	@echo "Packaging all IPs in cores/ip/..."
	@for ip_dir in cores/ip/*/; do \
		ip=$$(basename $$ip_dir); \
		echo ""; \
		echo "=== Packaging $$ip ==="; \
		$(MAKE) package IP=$$ip RESOLVE_DEPS=1; \
	done
	@echo ""
	@echo "All IPs packaged successfully!"

# Dry-run: generate TCL without running Vivado
package-dry:
	@if [ -z "$(IP)" ]; then \
		echo "Usage: make package-dry IP=<ip_name>"; \
		exit 1; \
	fi
	. venv/bin/activate; \
	mkdir -p build/package_$(IP); \
	cd build/package_$(IP) && \
	python3 ../../generators/ip_gen/ip_packager.py \
		--ip-name $(IP) \
		--dry-run \
		$(if $(RESOLVE_DEPS),--resolve-deps)

clean:
	rm -rf build report_pytest vivado* .Xil .fusesoc_libraries

# Show information about an IP core
info:
	@if [ -z "$(IP)" ]; then \
		echo "Usage: make info IP=<ip_name>"; \
		exit 1; \
	fi
	. venv/bin/activate; \
	fusesoc $(FUSESOC_CORES) info qick:ip:$(IP)

# List all available cores
list-cores:
	. venv/bin/activate; \
	fusesoc $(FUSESOC_CORES) list-cores

# Show dependency tree for an IP
deps:
	@if [ -z "$(IP)" ]; then \
		echo "Usage: make deps IP=<ip_name>"; \
		exit 1; \
	fi
	. venv/bin/activate; \
	fusesoc $(FUSESOC_CORES) info qick:ip:$(IP) | grep -A 50 "Dependencies:"
