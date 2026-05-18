# FuseSoC — IP Development and Simulation

This directory provides a [FuseSoC](https://fusesoc.readthedocs.io)-based environment
for developing and simulating QICK IP cores independently of the full Vivado project.

## How it works

RTL sources live in `ip/` and are **shared** between HOG (for bitfile builds) and
FuseSoC (for simulation). No files are duplicated — each IP core in `fusesoc/cores/`
contains a symlink `hdl/ → ../../../ip/<name>/src/` pointing to the single RTL source.

```
firmware/
├── ip/
│   └── my_ip/
│       └── src/          ← single source of truth for RTL
│           └── my_ip.sv
└── fusesoc/
    └── cores/
        └── my_ip/
            ├── hdl -> ../../../ip/my_ip/src   ← symlink, not a copy
            ├── my_ip.core                      ← FuseSoC descriptor
            └── test/
                └── my_ip_tc00.sv              ← SVUnit testbench
```

---

## Prerequisites

- Python 3.10+
- Vivado 2023.1 in `$PATH` (required for xsim):

```bash
source /path/to/Vivado/2023.1/settings64.sh
export LD_LIBRARY_PATH=/path/to/Vivado/2023.1/lib/lnx64.o
```

---

## Setup

Run once after cloning:

```bash
cd firmware/fusesoc
make setup_environment
```

This creates a Python virtual environment in `venv/`, installs FuseSoC and
dependencies, clones the SVUnit library, and creates symlinks from
`fusesoc/cores/*/hdl` to `ip/*/src`.

---

## Daily usage

Activate the virtual environment first:

```bash
cd firmware/fusesoc
source venv/bin/activate
```

**Simulate a single IP:**

```bash
make sim IP=qick_processor
```

**Run all SVUnit tests across all IPs:**

```bash
make sim_svunit
```

**Lint a single IP:**

```bash
make lint IP=qick_processor
```

**List all available cores:**

```bash
fusesoc --cores-root cores --cores-root common --cores-root generators list-cores
```

---

## Adding a new IP

### 1. Write the RTL in `ip/`

```bash
mkdir -p ../ip/my_new_ip/src/
vim ../ip/my_new_ip/src/my_new_ip.sv
```

HOG will pick it up from `ip/` automatically when you add it to a project.

### 2. Create the FuseSoC core

```bash
mkdir -p cores/my_new_ip/{test,data}

# Create symlink to RTL — no duplication
ln -s ../../../ip/my_new_ip/src cores/my_new_ip/hdl
```

Create `cores/my_new_ip/my_new_ip.core`:

```yaml
CAPI=2:
name: qick:ip:my_new_ip:1.0.0
description: Brief description

filesets:
  hdl:
    files:
      - hdl/my_new_ip.sv
    file_type: systemVerilogSource

  tb:
    files:
      - test/my_new_ip_tc00.sv
      - test/tests.sv: {is_include_file: true}
    file_type: systemVerilogSource
    depend:
      - qick:common:sim_base

generate:
  testrunner_gen:
    generator: svunit_gen
    parameters:
      test_files:
        - test/my_new_ip_tc00.sv

targets:
  default: &default
    filesets: [hdl]
    toplevel: my_new_ip

  lint:
    <<: *default
    filesets_append: [lint_files]
    default_tool: veriblelint

  test:
    <<: *default
    filesets_append: [tb]
    default_tool: xsim
    generate: [testrunner_gen]
    toplevel: testrunner
    tools:
      xsim:
        xelab_options: [-debug all -L XPM]
        xsim_options: [-testplusarg SVUNIT_FILTER="*" -onerror stop]
```

### 3. Write the SVUnit testbench

`cores/my_new_ip/test/my_new_ip_tc00.sv`:

```systemverilog
`include "svunit_defines.svh"

module my_new_ip_unit_test;
  import svunit_pkg::svunit_testcase;

  string name = "my_new_ip_ut";
  svunit_testcase svunit_ut;

  logic clk  = 0;
  logic rstn = 1;
  always #2 clk = ~clk;   // 250 MHz

  // instantiate DUT here
  // my_new_ip u_dut ( .clk(clk), .rstn(rstn), ... );

  function void build();
    svunit_ut = new(name);
  endfunction

  task setup();
    svunit_ut.setup();
    rstn = 0; repeat(4) @(posedge clk);
    rstn = 1; repeat(4) @(posedge clk);
  endtask

  task teardown();
    svunit_ut.teardown();
  endtask

  `SVUNIT_TESTS_BEGIN

  `SVTEST(test00_reset)
    repeat(10) @(posedge clk);
    `ASSERT_EQUAL(1, 1)   // replace with real assertions
  `SVTEST_END

  `SVUNIT_TESTS_END

endmodule
```

`cores/my_new_ip/test/tests.sv`:

```systemverilog
`include "my_new_ip_unit_test.sv"
```

### 4. Simulate

```bash
make sim IP=my_new_ip
```

---

## Directory structure

```
fusesoc/
├── common/                  Shared simulation infrastructure
│   ├── sim/                 SVUnit runner, clk_gen module
│   │   ├── sim_base.core
│   │   ├── include/svunit_assert_macros/
│   │   └── modules/clk_gen/
│   ├── xilinx/              Xilinx glbl module (needed for XPM simulation)
│   └── lint/                Verible lint rules
├── cores/                   One subdirectory per IP
│   ├── qick_pkg/            Shared QICK package (dependency for most cores)
│   └── qick_processor/      tProcessor V2 example core
├── projects/                Multi-IP simulation projects
├── generators/              FuseSoC code generators (SVUnit runner, IP gen)
├── scripts/
│   ├── tests/svunit_test/   pytest runner for CI
│   └── utils/               setup scripts
├── Makefile
├── requirements.txt
└── fusesoc.conf             Auto-generated by make setup_environment
```

---

## Core naming convention

All QICK cores follow the namespace `qick:<group>:<name>:<version>`:

| Namespace | Contents |
|-----------|----------|
| `qick:ip:*` | QICK IP cores (`qick_processor`, `qick_pkg`, …) |
| `qick:common:*` | Shared sim infrastructure (`sim_base`, `clk_gen`, `lint`, …) |

---

## Notes on IPs with Xilinx sub-IPs

Some IPs in `ip/` contain Vivado-generated sub-IPs (directories like `dds_compiler_0/`,
`fir_compiler_0/`) that require Vivado to generate their sources before simulation.
These IPs can only be built through HOG/Vivado and do not have a FuseSoC `test` target.
Purely RTL IPs (like `qick_processor`) can be simulated directly with FuseSoC.
