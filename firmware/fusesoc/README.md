# FuseSoC — IP Development and Simulation

This directory provides a [FuseSoC](https://fusesoc.readthedocs.io)-based environment
for developing and simulating QICK IP cores independently of the full Vivado project.

## How it works

RTL sources are organized in two locations:

- **`../rtl_lib/`** — Shared modules (AXI, CDC, interfaces, utilities)
- **`../ip/`** — QICK IP cores that use modules from `rtl_lib`

FuseSoC cores in `cores/` contain symlinks pointing to the RTL sources in `ip/`
and rely on `qick:common:sim_base` to include `rtl_lib/` paths.

```
firmware/
├── rtl_lib/                     ← Shared RTL (source of truth)
│   ├── axi/
│   ├── cdc/
│   ├── interfaces/
│   ├── pkg/
│   │   └── qick_pkg.sv
│   └── utils/
├── ip/
│   └── my_ip/
│       └── src/                 ← IP-specific RTL
│           └── my_ip.sv
└── fusesoc/
    ├── cores/
    │   └── my_ip/
    │       ├── hdl -> ../../../ip/my_ip/src   ← symlink
    │       ├── my_ip.core
    │       └── test/
    │           └── my_ip_tc00.sv
    ├── common/
    │   └── sim/                 ← sim_base.core (includes rtl_lib/)
    ├── Makefile
    └── requirements.txt
```

---

## Prerequisites

- Python 3.8+ (3.10+ recommended)
- Vivado 2023.1 in `$PATH` (required for xsim):

```bash
source /tools/Xilinx/Vivado/2023.1/settings64.sh
export LD_LIBRARY_PATH=/tools/Xilinx/Vivado/2023.1/lib/lnx64.o:$LD_LIBRARY_PATH
```

---

## Setup

Run once after cloning:

```bash
cd firmware/fusesoc
make setup_environment
cd ..
```

This creates:
- Python virtual environment in `venv/`
- Symlinks from `cores/*/hdl` to `../ip/*/src`
- Clones SVUnit library

---

## Daily usage

Activate the virtual environment:

```bash
cd firmware/fusesoc
source venv/bin/activate
```

### Simulate a single IP:

```bash
make sim IP=qick_processor
```

### Run all SVUnit tests:

```bash
make sim_svunit
```

### Lint a single IP:

```bash
make lint IP=qick_processor
```

### List all available cores:

```bash
make list-cores
```

### Show dependencies:

```bash
make deps IP=qick_processor
make deps-recursive IP=qick_processor
```

### Clean build artifacts:

```bash
make clean
```

---

---

## PeakRDL Driver Generation

For generating Python drivers with PeakRDL, see [docs/DRIVER.md](docs/DRIVER.md).

Quick start:
```bash
make driver IP=axis_constant_iq
```

---

## Adding a new IP

### 1. Write the RTL in `../ip/`

```bash
mkdir -p ../ip/my_new_ip/src/
vim ../ip/my_new_ip/src/my_new_ip.sv
```

Your IP can use modules from `rtl_lib/`:

```systemverilog
// my_new_ip.sv
`include "qick_pkg.sv"
import qick_pkg::*;

module my_new_ip (
  input logic clk,
  input logic rstn,
  // Use AXI interface from rtl_lib/interfaces/
  axi4_stream_if.slave s_axis,
  axi4_stream_if.master m_axis
);
  // Use utility from rtl_lib/utils/
  rising_edge_det u_redet ( .clk(clk), .in(signal), .out(edge) );
endmodule
```

### 2. Create the FuseSoC core

```bash
cd firmware/fusesoc
mkdir -p cores/my_new_ip/test

# Create symlink to IP source
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
    depend:
      - qick:common:sim_base   # Provides rtl_lib/ paths and qick_pkg

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
`include "qick_pkg.sv"   // if needed

module my_new_ip_unit_test;
  import svunit_pkg::svunit_testcase;
  import qick_pkg::*;    // if needed

  string name = "my_new_ip_ut";
  svunit_testcase svunit_ut;

  logic clk  = 0;
  logic rstn = 1;
  always #2 clk = ~clk;   // 250 MHz

  // Use interfaces from rtl_lib/interfaces/
  axi4_stream_if #(.DATA_WIDTH(32), .USER_EN(0)) axis_master ();
  axi4_stream_if #(.DATA_WIDTH(32), .USER_EN(0)) axis_slave ();

  // Instantiate DUT
  my_new_ip u_dut (
    .clk(clk),
    .rstn(rstn),
    .s_axis(axis_master),
    .m_axis(axis_slave)
  );

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
    `ASSERT_EQUAL(1, 1)
  `SVTEST_END

  `SVUNIT_TESTS_END

endmodule
```

### 4. Simulate

```bash
make sim IP=my_new_ip
```

---

## Packaging an IP for Vivado Block Design

Once the RTL is ready and tested:

```bash
# Basic packaging
make package IP=my_new_ip

# With dependencies
make package IP=my_new_ip RESOLVE_DEPS=1

# Package all IPs
make package-all
```

This generates:
- `../ip/my_new_ip/component.xml`
- `../ip/my_new_ip/xgui/my_new_ip_v1_0.tcl`

After packaging, the IP is available in HOG projects. Recreate the project:

```bash
cd firmware
./Hog/Do CREATE 216/tpv2_std
```

---

## Port naming conventions for AXI auto-inference

Vivado's `ipx::infer_bus_interfaces` recognizes:

| Interface type | Port prefix |
|---|---|
| AXI4-Lite slave | `s_axi_*` |
| AXI4-Stream slave | `s_axis_*` or `s0_axis_*` |
| AXI4-Stream master | `m_axis_*` or `m0_axis_*` |
| Clock | `*_clk*` or `*_aclk*` |
| Reset | `*_aresetn*` or `*_resetn*` |

---

## Complete IP development workflow

```
1. Write RTL          →  ../ip/my_ip/src/my_ip.sv (uses rtl_lib/)
2. Write testbench    →  cores/my_ip/test/my_ip_tc00.sv
3. Simulate           →  make sim IP=my_ip
4. Fix RTL, re-sim   →  make sim IP=my_ip
5. Package for Vivado →  make package IP=my_ip
6. Recreate project   →  cd ../.. && ./Hog/Do CREATE 216/tpv2_std
7. Open Vivado        →  vivado Projects/tpv2_std/tpv2_std.xpr
8. Instantiate IP     →  drag from IP catalog → Block Design
```

---

## Directory structure

```
fusesoc/
├── common/                  Shared simulation infrastructure
│   ├── sim/                 sim_base.core (includes rtl_lib/)
│   ├── xilinx/              Xilinx glbl module (for XPM)
│   └── lint/                Verible lint rules
├── cores/                   One subdirectory per IP
│   ├── qick_pkg/            Shared QICK package (wrapper for rtl_lib/pkg/)
│   ├── qick_processor/      tProcessor V2 example
│   └── my_new_ip/           Your new IP
├── projects/                Multi-IP simulation projects
├── generators/              FuseSoC code generators
├── scripts/                 Setup and test scripts
├── Makefile
└── requirements.txt
```

---

## Core naming convention

| Namespace | Contents |
|-----------|----------|
| `qick:ip:*` | QICK IP cores (use rtl_lib/) |
| `qick:common:*` | Shared infrastructure (sim_base, clk_gen, lint) |

---

## Notes

- **`rtl_lib/` is the source of truth** for shared RTL modules
- **`qick:common:sim_base`** includes `rtl_lib/` paths automatically
- IPs with Xilinx sub-IPs (DDS, FIR, etc.) require Vivado and cannot be simulated with FuseSoC
- Pure RTL IPs (like `qick_processor`) can be simulated directly

---
