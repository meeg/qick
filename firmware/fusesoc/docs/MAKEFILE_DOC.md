# Makefile Reference

Complete reference for the `firmware/fusesoc/Makefile`. Every target, the
variables it consumes, and the gotchas learned in practice.

All targets are run from `firmware/fusesoc/`. Most activate the shared `../../.venv/` internally,
but for interactive work do `source ../../.venv/bin/activate` first.

## Variables

| Variable | Default | Used by | Meaning |
|----------|---------|---------|---------|
| `IP`      | (none)  | most targets | Core / IP short name, e.g. `axis_signal_gen_v6`. Required by sim/lint/driver/package. |
| `CORE`    | (none)  | `core-info` | Full VLNV, e.g. `qick:ip:axis_signal_gen_v6`. |
| `TOOL`    | `verilator` | `sim`, `lint` (commented alt) | EDA tool override. Default flow uses `xsim` via the `.core` target. |
| `VERSION` | `1.0`   | `package` | IP version for packaging. |
| `PART`    | `xczu49dr-ffvf1760-2-e` | `package` | Target FPGA part. |
| `DESCRIPTION` / `DISPLAY_NAME` | (opt) | `package` | IP metadata. |

`FUSESOC_CORES` adds four roots: `--cores-root cores/projects/common/generators`.
NOTE: the SVUnit helper `get_core_name.py` historically used only
`--cores-root .`; keep the roots consistent or cores may not be found.

---

## Environment

### `make setup_environment`
Run once after cloning. Does: `git submodule init/update`, builds the shared `../../.venv/`
(`build_virtualenv.sh`), the FuseSoC env (`build_fusesocenv.sh`), and the
symlinks (`create_symlinks.sh`). Clones the SVUnit library on first sim.

---

## Simulation & test

### `make sim IP=<core>`
Runs the FuseSoC `test` target directly (SVUnit via xsim) for a single core.
Fast path for one core. Example: `make sim IP=lfsr`.

### `make sim_svunit IP=<core>`   ← multi-core / CI wrapper
pytest wrapper around SVUnit. Steps:
1. `make clean`.
2. `python3 scripts/tests/svunit_test/get_core_name.py <IP>` builds
   `tmp/cores_list.txt` (all cores with a `test` target, optionally filtered by
   `<IP>`).
3. pytest runs `test_rtl_svunit.py`, parametrized over that list, filtered with
   `-k "<IP>"`, emitting `report_pytest/pytest-report.xml` (JUnit).

Behavior:
- `make sim_svunit IP=axis_signal_gen_v6` → only that core.
- `make sim_svunit` (no IP) → all cores with a `test` target (CI mode).

Requirements / gotchas (learned the hard way):
- Needs `PYTHONPATH=scripts` so `get_core_name.py` can `from utils.cmd_utils
  import shell_cmd` (the import must be `utils.*`, NOT the legacy `models.*`).
- The `svunit_test` marker must be registered in `pyproject.toml`:
  `[tool.pytest.ini_options]` → `markers = ["svunit_test: ..."]` (and optionally
  `pythonpath = ["scripts"]`). Otherwise you get `PytestUnknownMarkWarning`.
- `get_core_name.py` filters cores by keyword; a stale keyword (`:rts`) that
  matches nothing makes `grep` exit 1 and abort — pass the IP or use `qick:`.
- Expect some sibling cores to FAIL if their testbenches are legacy (e.g.
  `axis_constant` port/interface drift). That does not affect your IP.

### `make lint IP=<core>`
Runs the FuseSoC `lint` target (veriblelint / verilator lint-only).
NOTE: IPs instantiating Xilinx primitives (DSP/XPM/DDS) cannot be linted by
Verilator alone.

---

## Register map & driver (PeakRDL)

### `make rdl-gen IP=<ip>`
`cd cores/ip/<ip>/rdl && make gen`. Generates the PeakRDL Python package (and
regblock SV only if the IP's rdl/Makefile keeps `--hdl`). No symlink.

### `make driver IP=<ip>`
Full driver flow:
1. `make gen` in `rdl/` (same step as `make rdl-gen`, called directly).
2. Symlinks `cores/ip/<ip>/driver/<ip>.py` into `qick_lib/qick/drivers/<ip>.py`.
3. Automatically calls `make driver-test IP=<ip>`.

### `make driver-test IP=<ip>`
Runs the register-layer pytest in `cores/ip/<ip>/driver/tests/` (PeakRDL
reg-model + in-memory Simulator, no hardware). Writes
`report_pytest/driver-<ip>-report.xml`. Skips gracefully if `driver/tests/`
is absent.

### `make driver-all`
Regenerates drivers + symlinks for every IP under `cores/ip/` that has an
`rdl/Makefile`.

### `make rdl-docs IP=<ip>`
`cd cores/ip/<ip>/rdl && make docs` → HTML register docs at
`cores/ip/<ip>/rdl/docs/index.html`.

---

## RTL library documentation

### `make rtl-docs [INPUT=<file>]`
Generates Markdown documentation for every module in `../rtl_lib` (the RTL
source of truth), mirroring TerosHDL's Generics/Ports tables. Output goes to
`docs/rtl-md/` (one `.md` per module + a `README.md` index).

- `make rtl-docs` — document the whole library.
- `make rtl-docs INPUT=../rtl_lib/dsp/sgv4_top.sv` — a single file.

Driven by `scripts/gen_docs.py`. Reads doc from BOTH styles:
- Modern: `//!` block above `module`, `//!` adjacent to each port/param.
- Legacy: `/** ... */` header with `@brief`/`@description`/`@port`/`@param`
  (a fallback fills port/param descriptions from `@port`/`@param` tags).

Excludes are read from `../rtl_lib/.docsignore` (globs; e.g.
`*_entity_declarations.sv`, `ssr_*.sv`) plus a built-in default.

### `make rtl-docs-clean`
Removes `docs/rtl-md/` (and the old `docs/rtl/` if present).

**Gotchas (learned the hard way):**
- Doxygen is NOT used for HDL: with `sv=C++` it renders ports as functions and
  chokes on `generate`. The custom generator replaces it.
- `teroshdl` pip 3.0.0 has no documentation CLI (only the VS Code extension),
  hence the in-house generator.
- Single-file `INPUT=` and full-tree runs must anchor output at the `rtl_lib`
  root, or a file lands in `docs/rtl-md/<name>.md` (root) while you read the
  stale `docs/rtl-md/dsp/<name>.md`. (Anchoring fix in `gen_docs.py:main`.)
- The index flags modules with 0 parsed ports (!) as documentation debt.

## Core creation

### `make new-ip IP=<name>`
`./scripts/create_ip.sh <name>` — scaffolds `cores/ip/<name>/` (rdl/, driver/,
hdl/, tests/). See docs/DRIVER.md for the two RTL strategies (generated regblock
vs custom AXI slave) and the rdl/Makefile gotchas (single `dirname`, TABs).

(Library cores are NOT a Makefile target — use `./scripts/new_lib_core.sh`.)

---

## Packaging (Vivado)

### `make package IP=<ip> [VERSION=] [PART=] [DESCRIPTION=] [DISPLAY_NAME=]`
Runs `generators/ip_gen/ip_packager.py` in `build/package_<ip>/`. Prints usage
if `IP` is missing.

### `make package-all`
Packages every IP under `cores/ip/`.

### `make package-dry IP=<ip>`
Generates the packaging TCL without running Vivado (inspection / debug).

---

## Inspection

| Target | Purpose |
|--------|---------|
| `make list-cores` | List all cores across the four roots. |
| `make core-info CORE=<vlnv>` | Show a core's filesets/targets/deps. |
| `make deps IP=<ip>` | Grep the dependency block of `qick:ip:<ip>`. |
| `make verify-core IP=<ip>` | Sanity-check that core dir, `.core`, RTL source and packaged source exist; prints deps. |

---

## Cleanup

### `make clean`
`rm -rf build report_pytest vivado* .Xil .fusesoc_libraries`.
NOTE: this also deletes the cloned `.fusesoc_libraries/svunit_lib`, so the next
`sim_svunit` re-clones SVUnit (slower first run). It does NOT touch `../../.venv/` or
the source symlinks.

---

## Typical workflows

**New IP end-to-end:**
```
make new-ip     IP=my_ip
# edit rdl/my_ip_regmap.rdl and rtl_lib/ip/my_ip.sv
make driver     IP=my_ip      # gen + symlink + driver-test
make sim_svunit IP=my_ip      # RTL verification
make rdl-docs   IP=my_ip
make package    IP=my_ip
make rtl-docs                 # complete RTL documentation from RTL modules
```

**Close an IP (what we did for SG-v6):**
```
make driver     IP=axis_signal_gen_v6   # driver + reg tests green
make sim_svunit IP=axis_signal_gen_v6   # SVUnit PASSED
make rdl-docs   IP=axis_signal_gen_v6
```

---

## Makefile pitfalls (repo-wide)

- **TABs, not spaces** in every recipe line, or `*** missing separator`.
- **`$$VAR` inside recipes** (double `$`) to pass a shell var, e.g.
  `PYTHONPATH=scripts:$$PYTHONPATH`. A single `$` is expanded by Make.
- **`$(if $(IP),-k "$(IP)",)`** is how `sim_svunit` conditionally filters by IP
  while still supporting the no-IP CI run.
- **Line continuations**: every non-final line of a multi-line recipe needs a
  trailing `\`; dropping one silently truncates the command (we lost a
  `--junitxml` flag this way once).
