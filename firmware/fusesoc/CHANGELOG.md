# Changelog

All notable changes to the QICK FuseSoC environment are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

### Added
- **SG-v6 IP** (`axis_signal_gen_v6`): full close-out — Python driver
  (`AxisSignalGen`, shared v4/v5/v6), SVUnit RTL testbench, PeakRDL
  register-layer tests, and documentation (`docs/sg_v6.rst`).
- **`make sim_svunit`**: pytest wrapper around SVUnit with per-IP filtering
  (`-k "$(IP)"`) and JUnit report (`report_pytest/pytest-report.xml`). Runs all
  cores with a `test` target when `IP` is omitted (CI mode).
- **`make driver` / `make driver-test`**: PeakRDL driver generation (RDL ->
  Python package + symlink) plus register-layer pytest (no hardware).
- **SG-v6 STATUS/CTRL registers**: `STATUS_REG.SATURATING` (0x0C) and
  `CTRL_REG.SAT_CLEAR` (0x10), exposing the amplitude-fix saturation to software
  (`is_saturating()` / `clear_saturation()`).
- **Docs**: `docs/MAKEFILE.md` (full Makefile reference); README, NEW_CORE.md
  and DRIVER.md updated for the sim_svunit / driver-test flow.
- Dependencies consolidated into `pyproject.toml` (single source of truth);
  added `numpy`, `peakrdl-python==3.1.2`, `peakrdl-regblock`, `peakrdl-html`.

### Changed
- **BREAKING — SG-v6 amplitude fix** (`sgv6` datapath): envelope x DDS product
  quantization changed `[31:16]` -> `[30:15]` (recovers a factor of 2), removed
  the baseband `>>1`, and added `+/-MAXV` saturation on the gain stage.
  Envelope pulses (arb, flat_top ramps) now output at full scale (~2x vs before).
  - Calibrations/experiments tuned to the old scale MUST be revisited.
  - The SW flat_top `gain/2` workaround MUST be reverted (use `gain=1.0`).
- **SG-v6 core/module renames**: `signal_gen_top`->`sgv6_top`,
  `signal_gen`->`sgv6`, `data_writer`->`axis_to_bram_sg_nt`,
  `fifo_xpm`->`fifo_sync`, `bram_dp_xpm`->`bram_tdp`, `ctrl_sg`->`ctrl_sgv6`;
  RTL files `.v` -> `.sv`.
- `scripts/tests/svunit_test/get_core_name.py`: import fixed to
  `from utils.cmd_utils import shell_cmd`; core selection now filters by IP.
- `pyproject.toml`: registered `svunit_test` marker and `pythonpath = ["scripts"]`;
  `requirements.txt` reduced to `-e .`.

### Fixed
- `axis_constant_iq` testbench: replaced variable-base part-select `[msb:lsb]`
  with indexed part-select `[base +: WIDTH]` (fixes xsim "range index value is
  not constant").
- `sim_svunit` pipeline: `PYTHONPATH=scripts` for the SVUnit helper; removed the
  stale `:rts` keyword filter that matched no cores and aborted the run.
- RTL header of `axis_signal_gen_v6.sv`: documented the full register map
  (previously omitted STATUS_REG/CTRL_REG).

### Deprecated
- SG-v6 `RNDQ_REG` and driver `rndq()` (rounding-select removed from the IP).

## [0.1.0]
- Initial version.
