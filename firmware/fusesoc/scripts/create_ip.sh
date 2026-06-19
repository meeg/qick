#!/bin/bash
# create_ip.sh - Crea la estructura para un nuevo IP core con soporte PeakRDL
# Uso: ./scripts/create_ip.sh <ip_name>

IP_NAME=$1

if [ -z "$IP_NAME" ]; then
    echo "Uso: $0 <ip_name>"
    exit 1
fi

IP_DIR="cores/ip/$IP_NAME"

echo "Creando IP: $IP_NAME"

# Crear directorios
mkdir -p $IP_DIR/{hdl,rdl,driver,test,data}

# Crear symlink al HDL (asumiendo que está en rtl_lib/ip/)
ln -s ../../../../../rtl_lib/ip/${IP_NAME}.sv $IP_DIR/hdl/${IP_NAME}.sv 2>/dev/null || echo "  ⚠ No se encontró rtl_lib/ip/${IP_NAME}.sv"

# Crear Makefile para el RDL
cat > $IP_DIR/rdl/Makefile << EOF
IP_NAME = \$(shell basename \$(shell dirname \$(shell dirname \$(CURDIR))))
RDL_FILE = \$(IP_NAME)_regmap.rdl
GEN_SCRIPT = ../../../../generators/systemrdl/rdl_tools.py

gen:
	python3 \$(GEN_SCRIPT) \$(RDL_FILE) --output . --hdl --python

clean:
	rm -rf \$(IP_NAME)_regmap_pkg \$(IP_NAME)_regmap*.sv \$(IP_NAME)_regmap*.svh

.PHONY: gen clean
EOF

# Crear .gitignore para RDL
cat > $IP_DIR/rdl/.gitignore << 'GITIGNORE'
*_regmap_pkg/
*_regmap.sv
*_regmap_pkg.sv
*_regmap.svh
*.pyc
__pycache__/
GITIGNORE

# Crear template del .rdl
cat > $IP_DIR/rdl/${IP_NAME}_regmap.rdl << EOF
// ${IP_NAME}_regmap.rdl
// SystemRDL register definition for ${IP_NAME} IP core

addrmap ${IP_NAME} {
    name = "${IP_NAME} Registers";
    desc = "Registers for the ${IP_NAME} IP core.";

    default regwidth = 32;
    default accesswidth = 32;
    default addressing = compact;

    // TODO: Define your registers here
    reg {
        name = "CTRL_REG";
        desc = "Control register";
        field {
            name = "ENABLE";
            desc = "Enable bit";
            sw = rw;
            hw = r;
        } ENABLE[0:0] = 0;
    } CTRL_REG @0x00;

    reg {
        name = "STATUS_REG";
        desc = "Status register";
        field {
            name = "READY";
            desc = "Ready flag";
            sw = r;
            hw = w;
        } READY[0:0] = 0;
    } STATUS_REG @0x04;
};
EOF

# Crear template del .core para el regmap
cat > $IP_DIR/rdl/${IP_NAME}_regmap.core << EOF
CAPI=2:
name: qick:ip:${IP_NAME}_regmap:0.1.0

filesets:
  rdl:
    files:
        - ${IP_NAME}_regmap.rdl : {file_type: user }
        - ${IP_NAME}_regmap.sv : {file_type: systemVerilogSource, is_include_file: true}
        - ${IP_NAME}_regmap_pkg.sv : {file_type: systemVerilogSource, is_include_file: true}
EOF

# Crear template del .core principal
cat > $IP_DIR/${IP_NAME}.core << EOF
CAPI=2:
name: qick:ip:${IP_NAME}:1.0.0
description: ${IP_NAME} IP core

filesets:
  hdl:
    files:
      - hdl/${IP_NAME}.sv
    file_type: systemVerilogSource
    depend:
      - qick:common:sim_base
      - qick:ip:${IP_NAME}_regmap

  tb:
    files:
      - test/${IP_NAME}_tc00.sv
      - test/${IP_NAME}_tests.sv: {is_include_file: true}
    file_type: systemVerilogSource
    depend:
      - qick:common:sim_base

generate:
  testrunner_gen:
    generator: svunit_gen
    parameters:
        test_files: 
          - test/${IP_NAME}_tc00.sv

targets:
  default:
    filesets: [hdl]
    toplevel: ${IP_NAME}

  test:
    filesets: [hdl, tb]
    default_tool: xsim
    generate: [testrunner_gen]
    toplevel: testrunner
    tools:
      xsim:
        xelab_options: [-timescale=1ns/1ns -debug all -L XPM]
        xsim_options: [-testplusarg SVUNIT_FILTER="*" -onerror stop]
EOF

# Crear template del driver
cat > $IP_DIR/driver/${IP_NAME}.py << EOF
"""
Driver for ${IP_NAME} IP core.
Uses PeakRDL-generated register model.
"""
import sys
from pathlib import Path
import numpy as np

_REGMAP_DIR = Path(__file__).parent.parent / "rdl"
if str(_REGMAP_DIR) not in sys.path:
    sys.path.insert(0, str(_REGMAP_DIR))

from ${IP_NAME}_regmap_pkg.reg_model.${IP_NAME} import ${IP_NAME}_cls
from ${IP_NAME}_regmap_pkg.lib import NormalCallbackSet
from ${IP_NAME}_regmap_pkg.sim.${IP_NAME} import ${IP_NAME}_simulator_cls

def to_unsigned(val, bits=16):
    return val & ((1 << bits) - 1)

def to_signed(val, bits=16):
    half = 1 << (bits - 1)
    return val - (1 << bits) if val >= half else val

class ${IP_NAME^}:
    """Driver for ${IP_NAME} IP core."""
    
    def __init__(self):
        self._reg_model = None

    def configure(self, read_cb, write_cb):
        self._callbacks = NormalCallbackSet(
            read_callback=read_cb,
            write_callback=write_cb
        )
        self._reg_model = ${IP_NAME}_cls(
            callbacks=self._callbacks,
            address=0
        )

    @property
    def regs(self):
        return self._reg_model

    def create_test_model(self):
        sim = ${IP_NAME}_simulator_cls(address=0)
        return ${IP_NAME}_cls(
            callbacks=NormalCallbackSet(
                read_callback=sim.read,
                write_callback=sim.write
            ),
            address=0
        )
EOF

# Crear template de testbench
cat > $IP_DIR/test/${IP_NAME}_tc00.sv << EOF
\`include "svunit_defines.svh"

module ${IP_NAME}_unit_test;
    import svunit_pkg::svunit_testcase;

    string name = "${IP_NAME}_ut";
    svunit_testcase svunit_ut;

    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    \`SVUNIT_TESTS_BEGIN

    \`SVTEST(test_reset)
        \`FAIL_IF(0);
    \`SVTEST_END

    \`SVUNIT_TESTS_END
endmodule
EOF

cat > $IP_DIR/test/${IP_NAME}_tests.sv << EOF
\`include "${IP_NAME}_tc00.sv"
EOF

echo ""
echo "✓ IP '$IP_NAME' creado en $IP_DIR"
echo ""
echo "Siguientes pasos:"
echo "  1. Editar rdl/${IP_NAME}_regmap.rdl con tus registros"
echo "  2. cd rdl && make gen"
echo "  3. cd .. && fusesoc run --target=test qick:ip:${IP_NAME}"
