FUSESOC_CORES := --cores-root cores \
                 --cores-root projects \
                 --cores-root global \
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
	fusesoc $(FUSESOC_CORES) run --build --target test qick:ip:$(IP)

lint:
	. venv/bin/activate; \
	fusesoc $(FUSESOC_CORES) run --build --target lint qick:ip:$(IP)

clean:
	rm -rf build report_pytest vivado* .Xil .fusesoc_libraries
