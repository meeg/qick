This directory provides a [FuseSoC](https://fusesoc.readthedocs.io)-based
environment for developing and simulating QICK IP cores independently of the
full Vivado project.

## How it works

RTL sources live in `../rtl_lib/`, organized by category. FuseSoC cores in
`cores/` are thin wrappers: each core has a `hdl/<name>.sv` symlink pointing to
the real source in `rtl_lib/<category>/`, a `.core` description, and SVUnit
testbenches. Cores depend on `qick:common:sim_base` (which sets up include
paths) and, when needed, on shared packages (`qick:pkg:*`).

```
firmware/
├── rtl_lib/                      ← Shared RTL (SOURCE OF TRUTH), by category
│   ├── axi/
│   ├── cdc/
│   ├── dsp/
│   ├── interfaces/
│   ├── ip/                       ← top-level IP RTL (e.g. axis_signal_gen_v6.sv)
│   ├── math/
│   ├── mem/
│   ├── misc/
│   ├── pkg/                      ← packages (alu_pkg, tproc_pkg, qick_pkg, ...)
│   ├── processors/               ← tprocv1.sv, ...
│   └── utils/
└── fusesoc/
    ├── cores/
    │   ├── ip/                   ← packaged IP cores (with rdl/, driver/)
    │   │   ├── axis_constant_iq/
    │   │   ├── axis_signal_gen_v6/
    │   │   ├── axis_tprocv1/
    │   │   └── ...
    │   ├── lib/                  ← library cores, by category
    │   │   ├── axi/
    │   │   ├── cdc/
    │   │   ├── dsp/
    │   │   ├── interfaces/
    │   │   ├── math/
    │   │   ├── mem/
    │   │   ├── processors/
    │   │   └── utils/
    │   └── pkg/                  ← package cores (alu_pkg, tproc_pkg, ...)
    ├── common/                   ← sim_base, lint rules, xilinx glbl
    ├── generators/               ← FuseSoC generators (systemrdl, svunit)
    ├── scripts/                  ← setup and core-creation scripts
    ├── docs/                     ← documentation (DRIVER.md, NEW_CORE.md, MAKEFILE_DOC.md)
    ├── pyproject.toml            ← pytest config (markers, pythonpath)
    ├── Makefile
    └── requirements.txt
```

A typical library core looks like:

```
cores/lib/<category>/<core>/
├── <core>.core                  ← FuseSoC description
├── data/                        ← aux files (waveforms, vectors)
├── hdl/
│   └── <core>.sv -> ../../../../../../rtl_lib/<category>/<core>.sv
├── lint/                        ← lint config / waivers
└── tests/
    ├── <core>_tc00.sv           ← SVUnit testbench top
    └── <core>_tests.sv          ← SVUnit test cases (included)
```

> Two kinds of cores:
>   - `cores/lib/<category>/<core>/`  — reusable building blocks (RTL + tests).
>   - `cores/ip/<name>/`              — packaged IPs (add `rdl/` + `driver/`).

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
```

This creates the shared Python virtual environment at `qick_internal/.venv`
(also used to build the Sphinx docs), sets up symlinks, and clones the SVUnit
library.

---

## Daily usage

Activate the virtual environment:

```bash
cd firmware/fusesoc
source ../../.venv/bin/activate
```

### Simulate a core

Two flows are available (see **docs/MAKEFILE.md** for the full comparison):

```bash
# Single core, direct FuseSoC 'test' target (SVUnit via xsim)
make sim IP=tpv2_alu
make sim IP=lfsr

# pytest wrapper around SVUnit (JUnit report; filter with IP=, or run all in CI)
make sim_svunit IP=axis_signal_gen_v6   # only this core
make sim_svunit                          # all cores with a 'test' target (CI)
```

`sim_svunit` produces `report_pytest/pytest-report.xml`. It requires the
`svunit_test` marker registered in `pyproject.toml` and `PYTHONPATH=scripts`
(both already wired in the Makefile).

### Lint a core

```bash
make lint IP=tpv2_alu
```

### List / inspect cores

```bash
make list-cores
make core-info CORE=qick:math:tpv2_alu
make deps IP=tpv2_alu
make verify-core IP=axis_signal_gen_v6
```

### Clean build artifacts

```bash
make clean
```

> `make clean` also removes `.fusesoc_libraries/`, so the next `sim_svunit`
> re-clones the SVUnit library (slower first run). It does not touch `../../.venv/` or
> the source symlinks.

---

## Creating new cores

Two helpers automate core creation. See **docs/NEW_CORE.md** for details.

- **Library core** (reusable block, RTL already in `rtl_lib/<category>/`):

  ```bash
  ./scripts/new_lib_core.sh <category> <core_name> [pkg_depend]
  # e.g.
  ./scripts/new_lib_core.sh utils lfsr
  ./scripts/new_lib_core.sh math  tpv2_alu  qick:pkg:alu_pkg
  ```

- **Packaged IP** (with register map + driver, PeakRDL flow):

  ```bash
  make new-ip IP=my_new_ip
  ```

---

## PeakRDL: register definition & driver generation

Packaged IPs use [PeakRDL](https://peakrdl.readthedocs.io) for register maps and
driver/doc generation. Full documentation: **docs/DRIVER.md**.

Quick reference:

```bash
make driver      IP=axis_constant_iq   # RDL -> Python package + driver symlink + reg tests
make driver-test IP=axis_constant_iq   # run only the register-layer pytest (no regen)
make rdl-docs    IP=axis_constant_iq   # generate HTML register documentation
make new-ip      IP=my_new_ip          # create a new IP from template
```

---

## Packaging an IP for Vivado

Once the RTL is tested:

```bash
make package IP=my_new_ip
make package-all
```

This generates the Vivado IP packaging artifacts. After packaging, recreate the
HOG project as usual.

---

## Port naming conventions for AXI auto-inference

Vivado's `ipx::infer_bus_interfaces` recognizes ports by prefix:

| Interface type     | Port prefix                 |
|--------------------|-----------------------------|
| AXI4-Lite slave    | `s_axi_*`                   |
| AXI4-Stream slave  | `s_axis_*` or `s0_axis_*`   |
| AXI4-Stream master | `m_axis_*` or `m0_axis_*`   |
| Clock              | `*_clk*` or `*_aclk*`       |
| Reset              | `*_aresetn*` or `*_resetn*` |

### Clock / reset domains (MANDATORY for multi-clock cores)

QICK cores typically use **two clock domains**: a slow AXI-Lite
configuration domain and a fast AXI-Stream datapath domain. Use these
**exact** port names on the top-level module:

| Domain            | Clock port    | Reset port       | Associated interfaces        |
|-------------------|---------------|------------------|------------------------------|
| Config (AXI-Lite) | `s_axi_aclk`  | `s_axi_aresetn`  | `s_axi`                      |
| Datapath (AXIS)   | `aclk`        | `aresetn`        | all `*_axis` (`s_axis`, `m_axis`, `m_axis_*`) |

Rules:
- The AXI-Lite interface **must** be named `s_axi` (clock `s_axi_aclk`,
  reset `s_axi_aresetn`).
- All AXI-Stream interfaces share the single datapath clock `aclk` /
  reset `aresetn`.
- Internal helper clocks/resets (e.g. `i_clk` / `i_rstn` inside
  `cdc/` blocks or pipelines) are **internal signals**, wired to `aclk` /
  `aresetn` inside the core. Do **not** expose them as top-level ports.

> ⚠️ **Why this matters — auto-inference is not enough.**
> `ipx::infer_bus_interfaces` guesses which clock drives which interface
> by heuristics. For a core with **two** clock domains it frequently
> attaches the AXI-Lite `s_axi` interface to `aclk` (the datapath clock)
> instead of `s_axi_aclk`. In the block design this surfaces as:
>
> ```
> CRITICAL WARNING [BD 41-1363] ... M0x_ACLK and <core>/aclk must be the same source
> ERROR [BD 41-237] FREQ_HZ / CLK_DOMAIN does not match between <core>/s_axi and .../M0x_AXI
> ```
>
> because Vivado now believes `s_axi` runs at the datapath frequency
> (e.g. 307.2 MHz) while the AXI interconnect master runs at the PS clock
> (e.g. 100 MHz).

### How the packager enforces this

`make package` (`scripts/ip_packager.py` + `package_ip.tcl.j2`) does **not**
rely on auto-inference for clock association. After
`ipx::infer_bus_interfaces` it explicitly re-associates, per the table above:

- `s_axi_aclk` → `ASSOCIATED_BUSIF = s_axi`, `ASSOCIATED_RESET = s_axi_aresetn`
- `aclk`       → `ASSOCIATED_BUSIF = <all AXI-Stream ifaces>`, `ASSOCIATED_RESET = aresetn`

It scans `BUS_TYPE_VLNV` for `*:axis:*` to collect every stream interface
automatically, and **overwrites** (not adds) `ACLK.ASSOCIATED_BUSIF` to
strip any `s_axi` the inferencer may have attached. This is generic: any
new core that follows the naming table above packages correctly with no
per-core configuration.

Verify a packaged core with:

```bash
grep -A1 "ACLK.ASSOCIATED_BUSIF\|S_AXI_ACLK.ASSOCIATED_BUSIF" ip/<name>/component.xml
# expected:
#   ACLK.ASSOCIATED_BUSIF        -> m_axis:s_axis   (NO s_axi)
#   S_AXI_ACLK.ASSOCIATED_BUSIF  -> s_axi
```

### Single-clock cores

If a core genuinely uses one clock for everything, name it aclk /
aresetn and let all interfaces (including s_axi) associate to it. The
packager handles this too (no s_axi_aclk present → only the aclk
association runs).

---

## Conventions

- **Clock/reset port names are fixed** for multi-clock cores: AXI-Lite uses
  `s_axi_aclk`/`s_axi_aresetn` (interface `s_axi`); the AXI-Stream datapath uses
  `aclk`/`aresetn` (all `*_axis`). Internal CDC/pipeline clocks are not exposed.
  See "Port naming conventions for AXI auto-inference". This is what makes
  `make package` produce correct `ASSOCIATED_BUSIF` for two clock domains.
- **rtl_lib/ is the source of truth** for all RTL; cores symlink into it.
- **Ports and signals are lowercase** (linter requirement), e.g. `a_i`, `z_o`.
- **Module naming**: processor-specific blocks use a `tpv2_*` / `tpv1_*` prefix;
  generic reusable blocks have no prefix (e.g. `lfsr`, `sync_nxm`).
- **Constants / opcodes live in packages** (`cores/pkg/*`, `rtl_lib/pkg/*`),
  e.g. `alu_pkg`, `tproc_pkg`.
- **Test directory is `tests/`** (plural) for BOTH library cores and packaged
  IPs, with `<core>_tc00.sv` (top) and `<core>_tests.sv` (included cases).
- **VLNV pattern**: `qick:<category>:<core>:<version>` for library cores,
  `qick:ip:<name>:<version>` for packaged IPs.
- PeakRDL-generated files (`*_regmap_pkg/`, generated `.sv`, `docs/`) are
  **never committed**.
- IPs that instantiate Xilinx primitives (DSP, XPM, DDS, FIR) require Vivado/xsim
  and cannot be linted/simulated with Verilator alone.
- **When a real RTL bug is found, fix it in `rtl_lib/`** (not in the testbench)
  and document it in the module header. Example: the SG-v6 amplitude fix
  ([31:16] -> [30:15] quantization + ±MAXV saturation) is documented in the
  `axis_signal_gen_v6` / `sgv6` headers.
- **A single driver can serve several IP versions** via multiple `bindto`
  strings. Example: `AxisSignalGen` binds v4/v5/v6. When you change the RTL of
  one, check the shared driver against the others.

---

## Documentation index

| Document            | Purpose                                            |
|---------------------|----------------------------------------------------|
| README.md (this)    | Environment overview, setup, daily usage           |
| docs/MAKEFILE_DOC.md    | Full Makefile target reference and pitfalls        |
| docs/NEW_CORE.md    | How to create new library cores and IPs            |
| docs/DRIVER.md      | PeakRDL register maps and Python driver generation |