# Changelog

## Unreleased
### Added
- SG-v6 (`axis_signal_gen_v6`) IP: driver, SVUnit RTL tests, PeakRDL register
  tests, and full documentation (`docs/sg_v6.rst`).
- `make sim_svunit` target: pytest wrapper around SVUnit with per-IP filtering
  (`-k`) and JUnit report.
- `make driver` / `make driver-test`: PeakRDL driver generation + register-layer
  pytest.
- Register-map STATUS/CTRL registers exposing the amplitude-fix saturation
  (`is_saturating()` / `clear_saturation()`).
- Docs: `docs/MAKEFILE.md` (full Makefile reference).

### Changed
- **BREAKING (SG-v6 amplitude fix):** envelope x DDS quantization [31:16] ->
  [30:15] and +/-MAXV saturation. Envelope pulses now output at full scale
  (~2x). Calibrations tuned to the old scale must be revisited; the SW flat_top
  gain/2 workaround must be reverted.
- Renamed SG-v6 cores: `signal_gen_top`->`sgv6_top`, `signal_gen`->`sgv6`,
  `data_writer`->`axis_to_bram_sg_nt`, `fifo_xpm`->`fifo_sync`,
  `bram_dp_xpm`->`bram_tdp`, `ctrl_sg`->`ctrl_sgv6`.
- `get_core_name.py`: import fixed to `utils.cmd_utils`; core filtering by IP.

### Fixed
- `axis_constant_iq` testbench: variable-base part-select `[msb:lsb]` ->
  `[base +: WIDTH]` (xsim constant-range error).
- `sim_svunit` pipeline: `PYTHONPATH=scripts`, `svunit_test` marker registered
  in `pyproject.toml`.

### Deprecated
- SG-v6 `RNDQ_REG` / driver `rndq()` (rounding-select removed).

## v0.1.0
- Initial version.
