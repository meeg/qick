# QICK Firmware

This directory contains the FPGA firmware for the
[QICK (Quantum Instrumentation Control Kit)](https://github.com/openquantumhardware/qick) project.

For a full description of the firmware architecture see the
[QICK documentation](https://qick-docs.readthedocs.io/latest/firmware.html).

---

## Repository structure

```
firmware/
├── Hog/              HOG submodule — build system
├── Top/              HOG project definitions (source of truth for each project)
│   ├── 111/          ZCU111 projects
│   ├── 216/          ZCU216 projects
│   ├── 4x2/          RFSoC4x2 projects
│   └── qick_testbench/ Simulation testbench project
├── rtl_lib/          Source of truth for shared RTL modules
│   ├── axi/          AXI4/AXI4-Lite/AXI4-Stream utilities
│   ├── cdc/          Clock domain crossing modules
│   ├── constraints/  Shared XDC constraint files
│   ├── ctrl/         Control-plane blocks (streamer, ramp/DDS control, etc.)
│   ├── dsp/          DSP datapath blocks (signal gen, IQ correction, etc.)
│   ├── encoders/     Link-layer / 8b10b / framing blocks
│   ├── interfaces/   SystemVerilog interfaces (AXI, BRAM, etc.)
│   ├── ip/           Top-level packaged-IP RTL (axis_tprocv1.sv, etc.)
│   ├── math/         ALUs and other math blocks
│   ├── mem/          Memories, FIFOs, register files
│   ├── misc/         Miscellaneous shared blocks
│   ├── pkg/          Shared packages (qick_pkg.sv, tproc_pkg.sv, alu_pkg.sv, ...)
│   ├── processors/   tProcessor cores (tprocv1.sv, ...)
│   ├── utils/        Utility modules (FIFOs, buffers, command handlers)
│   └── xci/          Xilinx-IP (.xci) sources used by dsp/ behavioural pairs
├── ip/               Custom QICK IP cores (use modules from rtl_lib)
├── Projects/         Vivado generated projects — gitignored, recreated with HOG
├── bin/              Bitfile outputs — gitignored
└── fusesoc/          IP development and simulation environment
```

---

## Quick start — build a standard bitfile

### Prerequisites

- Vivado 2023.1 installed and licensed for your board.
- Git with submodule support.
- Python 3.8+ with venv (for FuseSoC simulation).

### 1. Clone the repo

```bash
git clone --recursive <url_of_qick_internal>
cd qick_internal/firmware
```

The `--recursive` flag is required to initialize the HOG submodule.
If you already cloned without it:

```bash
git submodule update --init --recursive
```

### 2. Set up the Python environment (for FuseSoC simulation, optional)

```bash
cd fusesoc
make setup_environment
cd ..
```

### 3. Pick your project

Projects are organized by board type in `Top/`:

| Board | Project path | Vivado version |
|-------|-------------|----------------|
| ZCU216 | `Top/216/tpv2_std` | 2023.1 |
| ZCU216 (demo) | `Top/216/tpv2_demo` | 2023.1 |
| ZCU111 | `Top/111/tpv2_std` | 2023.1 |
| RFSoC4x2 | `Top/4x2/tpv2_std` | 2023.1 |
| ZCU111 (RFBv1) | `Top/111/tpv1_rfbv1_std` | 2023.1 |
| ZCU111 (RFBv2) | `Top/111/tpv1_rfbv2_std` | 2023.1 |

### 4. Recreate the Vivado project

```bash
./Hog/Do CREATE 216/tpv2_std
```

This recreates the project from scratch in `firmware/Projects/`.
Open it in Vivado to inspect the design:

```bash
vivado Projects/tpv2_std/tpv2_std.xpr
```

### 5. Build the bitfile

```bash
./Hog/Do W 216/tpv2_std
```

The bitfile appears in `firmware/bin/`.

---

## Saving changes to the block design

After modifying the block design in Vivado, export the TCL script before closing:

```
File → Export → Export Block Design → save to Top/<project_path>/bd_2023-1.tcl
```

For example:
```
File → Export → Export Block Design → save to Top/216/tpv2_std/bd_2023-1.tcl
```

Then commit it:

```bash
git add Top/216/tpv2_std/bd_2023-1.tcl
git commit -m "Update BD with <description of change>"
```

> **IMPORTANT**: HOG only processes committed files. Always commit before running `./Hog/Do W`.

---

## HOG commands

| Command | Description |
|---------|-------------|
| `./Hog/Do CREATE <project_path>` | Recreate Vivado project from scratch |
| `./Hog/Do W <project_path>` | Full build: synthesis + implementation + bitstream |
| `./Hog/Do S <project_path>` | Synthesis only |
| `./Hog/Do I <project_path>` | Implementation only |
| `./Hog/Do B <project_path>` | Bitstream only |

**Note:** `<project_path>` is relative to `firmware/Top/`. Examples:
- `216/tpv2_std`
- `111/tpv2_std`
- `4x2/tpv2_std`

---

## IP development and simulation with FuseSoC

The `fusesoc/` directory provides a [FuseSoC](https://fusesoc.readthedocs.io)-based
environment for developing and simulating individual IP cores.

RTL sources are organized as:
- `rtl_lib/` — Shared modules (AXI, CDC, interfaces, utilities)
- `ip/` — QICK IP cores that use modules from `rtl_lib`

> **In progress**: `qick:ip:qick_processor` (tProcessor v2) is being ported
> from `firmware/ip/qick_processor/src/` into `rtl_lib/` bottom-up, the same
> way `axis_tprocv1` was. Its `.core` file describes the target layout but
> `hdl/` is not populated yet, so `make sim IP=qick_processor` does not work
> until that port is further along.

### Available Makefile commands in `fusesoc/`

| Command | Description |
|---------|-------------|
| `make setup_environment` | Initialize submodules, create venv, install dependencies |
| `make sim IP=<ip_name>` | Run simulation for a specific IP |
| `make sim_svunit` | Run all SVUnit unit tests |
| `make lint IP=<ip_name>` | Run linter on an IP |
| `make list-cores` | List all available cores |
| `make core-info CORE=<core_name>` | Show detailed core information |
| `make deps IP=<ip_name>` | Show dependencies of an IP |
| `make package IP=<ip_name>` | Package an IP for Vivado Block Design |

**Examples:**
```bash
cd firmware/fusesoc
source venv/bin/activate

# Simulate an IP
make sim IP=tpv2_alu

# Run all tests
make sim_svunit

# Package an IP for Vivado
make package IP=xcom RESOLVE_DEPS=1
```

For detailed FuseSoC documentation, see `fusesoc/README.md`.

---

## Two workflows: HOG vs FuseSoC

| Task | Tool | Command |
|------|------|---------|
| Full bitstream build | HOG | `./Hog/Do W 216/tpv2_std` |
| Single IP simulation | FuseSoC | `cd fusesoc && make sim IP=tpv2_alu` |
| Unit tests | FuseSoC | `cd fusesoc && make sim_svunit` |
| IP packaging | FuseSoC | `cd fusesoc && make package IP=xcom` |

The RTL sources are shared:
- `rtl_lib/` → common modules used by both HOG and FuseSoC
- `ip/` → QICK IP cores

---

## Troubleshooting

**"Git working directory not clean" critical warning**
HOG cannot embed a valid SHA if there are uncommitted changes. Commit all
files under `Top/<project>/` before running `./Hog/Do W`.

**"Invalid Top Module" dialog when opening in Vivado**
Verify that `post-creation.tcl` exists and is committed. It should contain:
```tcl
set_property top "d_1_wrapper" [get_filesets sources_1]
```

**VHDL modules not found in Block Design**
Make sure VHDL files are listed in `list/src.src` with the library name:
```
../../hdl/lo_spi_mux_v2.vhd work
```

**HOG ignores my files**
HOG only processes committed files. Run `git status` and commit any untracked
files in `Top/<project>/` before running HOG commands.

---
