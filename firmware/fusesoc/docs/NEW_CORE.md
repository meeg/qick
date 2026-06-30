# Creating New Cores

This guide explains how to create new FuseSoC cores in the QICK environment.
There are two kinds:

  1. **Library cores** — reusable building blocks (ALU, FIFO, sync, LFSR, ...).
     Created with `scripts/new_lib_core.sh`. RTL lives in `rtl_lib/<category>/`.
  2. **Packaged IPs** — top-level IPs with a register map and Python driver.
     Created with `make new-ip` (PeakRDL flow). See docs/DRIVER.md.

---

## 1. Library cores  (scripts/new_lib_core.sh)

### What it does

Creates `cores/lib/<category>/<core>/` with:

```
<core>/
├── <core>.core                  ← FuseSoC description (anchors-based)
├── data/
├── hdl/
│   └── <core>.sv -> (relative symlink to rtl_lib/<category>/<core>.sv)
├── lint/
└── tests/
    ├── <core>_tc00.sv           ← SVUnit testbench top (stub)
    └── <core>_tests.sv          ← SVUnit test cases (stub)
```

The symlink's relative path is computed automatically (no manual `../../..`
counting), and every file is named consistently with `<core>`.

### Usage

```bash
cd firmware/fusesoc
./scripts/new_lib_core.sh <category> <core_name> [pkg_depend]
```

- `<category>` : one of `utils | math | cdc | mem | axi | interfaces | processors`
- `<core_name>`: the module name (must match the file in rtl_lib/<category>/)
- `[pkg_depend]` (optional): a package the RTL needs, e.g. `qick:pkg:alu_pkg`

### Examples

```bash
# Generic utility (no package dependency)
./scripts/new_lib_core.sh utils lfsr

# Math block that imports alu_pkg
./scripts/new_lib_core.sh math tpv2_alu qick:pkg:alu_pkg

# Control unit that imports tproc_pkg
./scripts/new_lib_core.sh utils tpv1_ctrl qick:pkg:tproc_pkg

# CDC synchronizer
./scripts/new_lib_core.sh cdc sync_nxm
```

### Prerequisites

The RTL must already exist at `rtl_lib/<category>/<core>.sv`. If it does not, the
script still creates the core and a (dangling) symlink, and warns you — add the
RTL afterward.

### After running

1. Edit `tests/<core>_tc00.sv` and `tests/<core>_tests.sv` with real tests
   (the script writes a `tc_smoke` placeholder).
2. Run the test target:
   ```bash
   make sim IP=<core>
   ```
3. Lint:
   ```bash
   make lint IP=<core>
   ```

### Generated .core

The `.core` uses YAML anchors and includes `default`, `lint`, and `test`
targets:

```yaml
CAPI=2:
name: qick:<category>:<core>:1.0.0
description: <core> (<category> library core).

filesets:
  hdl:
    files:
      - hdl/<core>.sv
    file_type: systemVerilogSource
    depend:
      - <pkg_depend>            # only if provided
  tb:
    files:
      - tests/<core>_tc00.sv
      - tests/<core>_tests.sv: {is_include_file: true}
    file_type: systemVerilogSource
    depend:
      - qick:common:sim_base
  lint_files:
    depend:
      - qick:common:lint

generate:
  testrunner_gen:
    generator: svunit_gen
    parameters:
        test_files:
          - tests/<core>_tc00.sv

targets:
  default: &default
    filesets: [hdl]
    toplevel: <core>
  lint:
    <<: *default
    filesets_append: [lint_files]
    default_tool: veriblelint
    toplevel: <core>
    tools:
      verilator:
        mode: lint-only
        verilator_options: [-Wall]
  test:
    <<: *default
    description: Simulate the design
    filesets_append: [tb]
    default_tool: xsim
    generate: [testrunner_gen]
    toplevel: testrunner
    tools:
      xsim:
        xelab_options: [-timescale=1ns/1ns -debug all -L XPM]
        xsim_options: [-testplusarg SVUNIT_FILTER="*" -onerror stop]
```

---

## 2. SVUnit testbench template

Both stubs follow the SVUnit pattern used across the repo. A typical top:

```systemverilog
`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module <core>_unit_test;
    import svunit_pkg::svunit_testcase;
    // import <pkg>::*;   // if the DUT needs a package

    string name = "<core>_ut";
    svunit_testcase svunit_ut;

    localparam real CLOCK_FREQUENCY = 200e6;

    logic tb_clk  = 1'b0;
    logic tb_rstn = 1'b1;
    clk_gen #(.FREQ (CLOCK_FREQUENCY)) u_clk (.i_enable(1'b1), .o_clk(tb_clk));

    // DUT signals ...
    // DUT instance: <core> dut ( ... );

    function void build(); svunit_ut = new(name); endfunction
    task setup();    svunit_ut.setup();    endtask
    task teardown(); svunit_ut.teardown(); endtask

    `SVUNIT_TESTS_BEGIN
    `include "<core>_tests.sv"
    `SVUNIT_TESTS_END
endmodule
```

### Verification guidelines (lessons learned)

- For combinational blocks, drive inputs and settle with `#1` before checking;
  use `clk_gen` only to sequence assertions.
- For memories, model them faithfully (synchronous, registered, write-first if
  the real BRAM is like `bram_tdp`); idealized combinational models hide
  read-latency bugs.
- For AXIS producers/consumers, advance counters only on accepted beats
  (`tvalid && tready`), not on `tvalid` alone.
- Do not sample combinational outputs of single-cycle FSM states right after a
  `wait_state`; use a concurrent `fork` monitor or settle one cycle.
- Synchronize multi-step / multi-transaction tests on real state (`ready`,
  `busy`, `tready`) rather than fixed `repeat` delays.
- When a real RTL bug is found, fix it in `rtl_lib/` (not in the testbench) and
  document it in the module header.

---

## 3. Packaged IPs  (make new-ip)

For top-level IPs that expose an AXI register map and a Python driver, use the
PeakRDL flow:

```bash
make new-ip IP=my_new_ip
```

This creates `cores/ip/my_new_ip/` with `rdl/`, `driver/`, `hdl/`, and `test/`.
Then:

1. Edit `cores/ip/my_new_ip/rdl/my_new_ip_regmap.rdl` (the register map).
2. Write/adjust the RTL in `rtl_lib/ip/my_new_ip.sv` and the symlink.
3. Generate the driver/register layer:
   ```bash
   make driver IP=my_new_ip
   ```
4. Generate docs:
   ```bash
   make rdl-docs IP=my_new_ip
   ```

See **docs/DRIVER.md** for the full PeakRDL workflow, register access API, the
register-layer pytest tests, and the two RTL strategies (generated regblock vs
custom AXI slave).

> Note: `make new-ip` historically had two bugs in its Makefile template
> (duplicated `RDL_FILE` line and a double `dirname` in `IP_NAME`). These are
> fixed; if you create an IP and `make driver` complains about `_regmap.rdl` or
> `ip_regmap.rdl`, check `scripts/create_ip.sh` against docs/DRIVER.md.

---

## 4. Quick checklist for a new library core

```
1. Write/place RTL          ->  rtl_lib/<category>/<core>.sv  (lowercase ports)
2. Create the core          ->  ./scripts/new_lib_core.sh <category> <core> [pkg]
3. Write the testbench       ->  edit tests/<core>_tc00.sv + tests/<core>_tests.sv
4. Simulate                 ->  make sim IP=<core>
5. Lint                     ->  make lint IP=<core>
6. Fix RTL bugs in rtl_lib/ ->  document them in the module header
7. Re-run until green
```