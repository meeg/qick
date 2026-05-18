# QICK Firmware

This directory contains the FPGA firmware for the
[QICK (Quantum Instrumentation Control Kit)](https://github.com/openquantumhardware/qick) project.

For a full description of the firmware architecture see the
[QICK documentation](https://qick-docs.readthedocs.io/latest/firmware.html).

---

## Quick start — build a standard bitfile

### Prerequisites

- Vivado 2023.1 installed and licensed for your board.
- Git with submodule support.

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

### 2. Pick your project

| Board | Project name | Vivado version |
|-------|-------------|----------------|
| ZCU216 | `qick_tprocv2_216_standard` | 2023.1 |
| ZCU216 (demo) | `qick_tprocv2_216_demo` | 2023.1 |
| ZCU111 | `qick_tprocv2_111_standard` | 2023.1 |
| RFSoC4x2 | `qick_tprocv2_4x2_standard` | 2023.1 |

### 3. Recreate the Vivado project

```bash
./Hog/Do CREATE qick_tprocv2_216_standard
```

This recreates the project from scratch in `firmware/Projects/`.
Open it in Vivado to inspect the design:

```bash
vivado Projects/qick_tprocv2_216_standard/qick_tprocv2_216_standard.xpr
```

### 4. Build the bitfile

```bash
./Hog/Do W qick_tprocv2_216_standard
```

The bitfile appears in `firmware/bin/`.

---

## Saving changes to the block design

After modifying the block design in Vivado, export the TCL script before closing:

```
File → Export → Export Block Design → save to Top/<project>/bd_2023-1.tcl
```

Then commit it:

```bash
git add Top/qick_tprocv2_216_standard/bd_2023-1.tcl
git commit -m "Update BD with <description of change>"
```

> HOG only processes committed files. Always commit before running
> `./Hog/Do W`.

---

## HOG commands

| Command | Description |
|---------|-------------|
| `./Hog/Do CREATE <project>` | Recreate Vivado project from scratch |
| `./Hog/Do W <project>` | Full build: synthesis + implementation + bitstream |
| `./Hog/Do S <project>` | Synthesis only |
| `./Hog/Do I <project>` | Implementation only |
| `./Hog/Do B <project>` | Bitstream only |

---

## Directory structure

```
firmware/
├── Hog/           HOG submodule — build system
├── Top/           HOG project definitions (source of truth for each project)
├── ip/            Custom QICK IP cores (RTL source)
├── projects/      Original project scripts (reference, not used by HOG)
├── Projects/      Vivado generated projects — gitignored, recreated with HOG
├── bin/           Bitfile outputs — gitignored
└── fusesoc/       IP development and simulation environment
```

---

## IP development and simulation

The `fusesoc/` directory provides a [FuseSoC](https://fusesoc.readthedocs.io)-based
environment for developing and simulating individual IP cores with
[SVUnit](https://svunit.github.io) unit tests, independently of the full Vivado project.

RTL sources live in `ip/` and are shared between HOG and FuseSoC — no duplication.

→ See [`fusesoc/README.md`](fusesoc/README.md) for setup and usage.

---

## Advanced topics

For detailed instructions on adding new projects to HOG, troubleshooting,
and the full development workflow, see:

→ [`HOG_QICK_Integration_Guide.md`](HOG_QICK_Integration_Guide.md)
