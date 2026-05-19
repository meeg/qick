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
# Usage: make package IP=<ip_name> [VERSION=1.0] [PART=xczu49dr-ffvf1760-2-e]
# Example: make package IP=qick_processor VERSION=2.0
package:
	@if [ -z "$(IP)" ]; then \
		echo "Usage: make package IP=<ip_name> [VERSION=1.0] [PART=xczu49dr-ffvf1760-2-e]"; \
		exit 1; \
	fi
	. venv/bin/activate; \
	mkdir -p build/package_$(IP); \
	cd build/package_$(IP) && \
	python3 ../../generators/ip_gen/ip_packager.py \
		--ip-name    $(IP) \
		--version    $(or $(VERSION),1.0) \
		--part       $(or $(PART),xczu49dr-ffvf1760-2-e) \
		--display-name "$(or $(DISPLAY_NAME),$(IP))"

# Dry-run: generate TCL without running Vivado
package-dry:
	@if [ -z "$(IP)" ]; then echo "Usage: make package-dry IP=<ip_name>"; exit 1; fi
	. venv/bin/activate; \
	mkdir -p build/package_$(IP); \
	cd build/package_$(IP) && \
	python3 ../../generators/ip_gen/ip_packager.py \
		--ip-name $(IP) \
		--dry-run

clean:
	rm -rf build report_pytest vivado* .Xil .fusesoc_libraries

