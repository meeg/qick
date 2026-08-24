# Changelog

All notable changes to the QICK FuseSoC environment are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

### Added
- **tprocv2 bottom-up port** (in progress, mirroring the completed tprocv1
  port under `qick:processors:tprocv1`): faithful ports of
  `firmware/ip/qick_processor/src/` into `rtl_lib/` + fusesoc lib cores,
  reusing already-ported primitives instead of the legacy monolithic source.
  - **tpv2_pkg** (`qick:pkg:tpv2_pkg`): tprocv2 package — `CTRL_REG`,
    `CTRL_FLOW`, `PORT_DT`, `QTP_CTRL` and the instruction HEADER opcodes,
    ported from `_qproc_defines.svh` (the AXI-Lite/DMEM SV interfaces from
    that header are not ported — covered by the generic
    `qick:interfaces:axi4_lite_if` / `qick:interfaces:bram_if` cores instead).
  - **qcore_reg_bank** (`qick:mem:qcore_reg_bank`): tprocv2 register bank
    (SFR/data/wave register pages), faithful port of `qcore_reg_bank.sv`
    using the generic `qick:utils:lfsr` core in place of the private `LFSR`.
  - **qcore_ctrl_hazard** (`qick:utils:qcore_ctrl_hazard`): tprocv2 pipeline
    data-hazard forwarding/stalling unit, faithful port of
    `qcore_ctrl_hazard.sv` against the new `tpv2_pkg::CTRL_REG` type.
  - **qcore_cpu** (`qick:processors:qcore_cpu`): the 5-stage tprocv2 CPU
    datapath (IF/ID/RD/X1/X2), faithful port of `qcore_cpu.sv` assembled
    entirely from already-ported pieces (`qcore_ctrl_hazard`,
    `qcore_reg_bank`, `tpv2_alu`, `tpv2_stack`) — no more legacy `AB_alu`/
    `LIFO` instances. SVUnit exercises it with hand-encoded instruction words
    (store-immediate-to-DMEM, branch) against a tiny combinational
    program-memory model, end to end through the real pipeline.
  - **qproc_time_ctrl** (`qick:utils:qproc_time_ctrl`): tprocv2 absolute
    time counter FSM, faithful port of `qproc_time_ctrl.sv`. The Xilinx
    `ADDSUB_MACRO` (7SERIES, WIDTH=48, LATENCY=1) primitive was replaced by
    a plain synthesizable adder with the same sync-reset/CE/carry-in
    semantics, so the core lints/sims without Vivado's UNISIM library --
    this also fixes a real discrepancy the legacy file's dead, commented-out
    RTL-inference alternative had flagged as unverified (it dropped the
    carry-in added during the ST_UPDATE state).
  - **qproc_ctrl** (`qick:utils:qproc_ctrl`): tprocv2 start/stop/reset and
    time-base control (two FSMs, one per clock domain, linked by a CDC
    synchronizer), faithful port of `qproc_ctrl.sv` on top of
    `qproc_time_ctrl` and the already-ported `cdc_reg_sync` (replaces the
    legacy `sync_reg`) / `sync_ab_en`. `PS_TPROC_CTRL`/`PS_TPROC_CFG`/
    `xreg_TPROC_*` renamed to the lowercase convention
    (`ps_tproc_ctrl_i`/`ps_tproc_cfg_i`/`xreg_tproc_*`); the dead
    `core_rst_prev_p` (assigned, never read anywhere in the legacy tree) was
    dropped.
  - `axi_slv_qproc.vhd` does NOT need a SystemVerilog port: unlike
    `axi_slv_tprocv1` (custom slave with a DMEM window + exec/exec_ack
    handshake), it is a plain 16-register AXI4-Lite bank with no memory
    window (tprocv2's bulk PMEM/DMEM/WMEM access goes over a separate
    AXI-Stream path via `qproc_mem_ctrl`) -- already-ported `qproc_axi_reg`
    replaced the whole VHDL engine with the shared `axil_slv` generic
    register-bank core (`AUTO_CLEAR_BIT0` covers the TPROC_CTRL auto-clear
    pulse). Confirmed still 10/10 tests, lint clean.
  - **qproc_dispatcher** (`qick:utils:qproc_dispatcher`): tprocv2's timed
    output dispatcher (trigger/data/wave channels, each an async FIFO +
    time comparator + pop generator), faithful port of
    `qproc_dispatcher.sv`. `BRAM_FIFO_DC_2` (an `xpm_fifo_async` wrapper
    with `push_i`/`pop_i`/`flush_i`) -> the already-ported `fifo_async` core
    (same `xpm_fifo_async`, READ_MODE="fwft"); `flush_i` (`core_rst`) has no
    equivalent on `fifo_async`, so it is folded into `wr_rstn` instead
    (`c_rst_ni & ~core_rst`), which reproduces the original
    `rst = ~wr_rst_ni | flush_i` exactly. The hand-rolled 2-flop empty-flag
    CDC synchronizer was also replaced by the shared `cdc_reg_sync` core
    (same one used by `qproc_ctrl`) rather than re-hand-rolling it. SVUnit
    exercises real `xpm_fifo_async` behavior (Vivado-only; the same 16-entry
    minimum depth and post-reset `wr_rst_busy` settling window `fifo_async`
    itself documents apply here). NOTE (carried over from the legacy file):
    the debug buses `c_fifo_do`/`t_fifo_do` hard-code indices `[1]`/`[0]`,
    i.e. only make sense for the default `OUT_*_QTY=2`.
  - **qproc_core** (`qick:processors:qproc_core`): ties `qcore_cpu` to
    `qcore_mem` plus the input-port-read capture register, faithful port of
    `qproc_core.sv` -- pure wiring, no new primitives (both sub-cores were
    already ported). This closes the bottom-up port: every non-composition
    piece of the legacy `firmware/ip/qick_processor/src/` tree now has an
    `rtl_lib/` + fusesoc equivalent. SVUnit drives it through the PS-side
    memory port (load a program into PMEM, run it, read the DMEM result
    back), the same integration loop `axis_qick_processor` will need.
  - **qick_processor** (`qick:processors:qick_processor`): the full tprocv2
    composition -- AXI-Lite registers (`qproc_axi_reg`), start/stop/time
    FSMs (`qproc_ctrl`), one or two `qproc_core` CPUs (`DUAL_CORE`), bulk
    memory DMA (`qproc_mem_ctrl`), the timed dispatcher (`qproc_dispatcher`),
    input-port capture (`qproc_inport_reg`), and the internal arith/divider
    peripherals (`tpv2_arith`/`restoring_divider`), all wired together.
    Faithful port of `qick_processor.sv`; `sync_reg` -> `cdc_reg_sync`, the
    legacy `TYPE_IF_AXI_REG` interface -> `axi4_lite_if` (matching
    `qproc_axi_reg`). Fixed two pre-existing bugs surfaced by actually
    elaborating the full composition (neither module had been exercised
    this way before): `qproc_inport_reg` included a nonexistent
    `_qproc_defines.svh` it never used (its own `make sim`/`make lint` were
    silently broken); `qproc_mem_ctrl` had leftover uppercase
    `MEM_CTRL`/`MEM_ADDR`/`MEM_LEN`/`MEM_DT_I`/`MEM_DT_O`/`DEBUG_O` ports
    (now lowercase). SVUnit drives it end-to-end through the real
    `axi4_lite_if` (DATA_WIDTH=32, ADDR_WIDTH=6) and the real
    `qproc_dispatcher` FIFOs: an AXI write to TPROC_CTRL's START bit rides
    the actual FIFO wr_rst_busy handshake through to `core_st_ds == C_RUN`.
  - Note: `qick:processors:qick_processor` and the pre-existing, broken
    `qick:ip:qick_processor:2.0.0` share the short IP name `qick_processor`
    -- `fusesoc ... run --target <t> qick_processor` is now ambiguous; use
    the full VLNV (`qick:processors:qick_processor`) until the legacy `ip/`
    core is retired in favor of the eventual `axis_qick_processor` package.
  - **axis_qick_processor** (`qick:ip:axis_qick_processor`): the packaged
    IP -- flattens `qick_processor`'s unpacked-array AXI-Stream/trigger/
    data-port interfaces into fixed, individually-named pins (s0..s15_axis,
    m0..m15_axis, trig_0..31_o, port_0..3_dt_o, qnet/qcom/qp1/qp2 dt1/dt2
    pairs) for Vivado's IP packager, following the `axis_tprocv1` packaging
    pattern. Faithful port of `axis_qick_processor.sv`; the legacy
    `TYPE_IF_AXI_REG` interface -> `axi4_lite_if`; `proc_start_i`/
    `proc_stop_i`'s hand-rolled synchronizer -> `cdc_reg_sync` for its first
    two (CDC) stages. This closes the full tprocv2 port: every file under
    the legacy `firmware/ip/qick_processor/src/` tree now has an
    `rtl_lib/` + fusesoc equivalent. 7/7 SVUnit tests, lint clean, including
    the external `proc_start_i` pin path (gated by TPROC_CFG[10], the same
    external-start-source bit the production driver's `start_src('external')`
    sets).
  - **Driver**: `Axis_QICK_Proc` (`qick_lib/qick/drivers/tproc.py`) is the
    existing, full-featured production driver for tprocv2 (already correct
    for the ported register map) -- extended its `bindto` with
    `qick:ip:axis_qick_processor:1.0` so it loads for the new fusesoc VLNV
    too. `cores/ip/axis_qick_processor/driver/axis_qick_processor.py` is a
    symlink to it (single source of truth), matching Style A ("manual
    driver") from docs/DRIVER.md. Restored 5 parameters the initial pass
    had dropped as dead code (`QNET`/`QCOM`/`CUSTOM_PERIPH`/`IO_CTRL`/
    `CALL_DEPTH`): they are inert in the RTL, but the driver reads them via
    Vivado's IP parameter metadata for its `cfg`/`__str__` reporting --
    `CALL_DEPTH` unconditionally, so dropping it would have KeyError'd at
    driver load time. `TIME_CTRL`/`CORE_CTRL`/`OUT_TIME` stayed dropped
    (neither the RTL body nor the driver reference them).
  - **RDL**: `cores/ip/axis_qick_processor/rdl/axis_qick_processor_regmap.rdl`
    documents the full TPROC_CTRL/CFG/MEM_*/CORE_CFG/READ_SEL/status
    register map (strategy 2, driver/docs only -- no `--hdl`, since
    `qproc_axi_reg`'s `axil_slv`-based decode already handles TPROC_CTRL's
    whole-word self-clear that `peakrdl regblock` can't express).
  - **Constraints**: `constraints/axis_qick_processor.xdc`/`_ooc.xdc`
    adapted from the legacy `qick_processor.xdc`/`_ooc.xdc`. The OOC clocks
    file ported directly (unchanged). The false-paths file's hierarchy-
    literal rules were re-derived against the new (renamed) instance
    hierarchy by tracing each legacy-preserved *signal* name; the generic
    CDC rule was upgraded from a name-pattern match (`*_cdc_reg*`, which
    would NOT have matched `cdc_bit_sync`'s actual `sync_r` register) to an
    `ASYNC_REG`-property-based match, which is robust to future renaming.
    NOT validated against an actual synthesized netlist (no Vivado
    synthesis run available in this port) -- the file's header flags two
    lower-confidence rules and instructs verifying every `get_cells`
    pattern resolves before relying on it in production.
  - Remaining follow-up (not blocking): a `driver/tests/` PeakRDL
    register-layer pytest suite for `axis_qick_processor` (DRIVER.md
    documents the RDL as optional-but-useful for this even with a Style A
    manual driver); retiring the broken `qick:ip:qick_processor:2.0.0`
    leftover now that a real replacement exists.
  - **Naming/backward-compat note**: the legacy Vivado-packaged component
    is identified as `QICK:QICK:qick_processor:2.0` (component name
    "qick_processor", cell name `qick_processor_0`) and is hard-coded into
    several HOG block-design scripts (`firmware/Top/{111,4x2,216}/tpv2_*/
    bd_2023-1.tcl`). The fusesoc core stays named `axis_qick_processor`
    (matching the `tprocv1`/`axis_tprocv1` inner/outer naming split -- the
    inner bare-processor lib core is separately `qick:processors:
    qick_processor`, so renaming the outer IP to the same short name would
    reintroduce the ambiguous-short-name problem). Backward compatibility
    with those scripts is a **packaging-time** concern: when `make package
    IP=axis_qick_processor` is eventually run, pass `--ip-name
    qick_processor` (vendor/library `QICK`/`QICK`, version `2.0`) to
    reproduce the exact VLNV the HOG scripts expect, per the technique
    DRIVER.md already documents for this scenario.
- **axis_sg_mux8_v1 bottom-up port** (mux8 signal generator, first of the
  4 signal-generator IPs the user asked to keep): faithful ports of
  `firmware/ip/axis_sg_mux8_v1/src/` into `rtl_lib/` + fusesoc lib cores,
  using the already-ported `axis_signal_gen_v6` as a structural reference
  and reusing existing lib cores wherever the legacy hand-rolled logic had
  an equivalent (`cdc_bit_sync` for `synchronizer_n`, `delay_line` for
  `latency_reg`, `fifo_sync` for the private `fifo`, `axil_slv` for
  `axi_slv.v`, and the pre-existing `dds_compiler_signal_gen_mux` --
  already documented as "used by axis_sg_mux4_v3, axis_sg_mux8_v1" from an
  earlier session).
  - **mult_32x32** (`qick:dsp:mult_32x32`): pipelined 32x32 unsigned
    multiplier (6-cycle latency, 4 DSP48 slices), faithful port of
    `mult_32x32.v`.
  - **phase_ctrl_sgmux8** (`qick:ctrl:phase_ctrl_sgmux8`): phase-coherent
    per-channel phase/increment generator for N_DDS interleaved lanes,
    faithful port of `phase_ctrl.sv` (renamed to avoid a short-name
    collision with the unrelated `dds_phase_ctrl` used by
    `axis_kidsim_v3`). Deviation: the legacy `always` block had no reset
    branch at all (relied on Verilog `reg = 0` initial values for a defined
    state at time 0); this port adds an explicit synchronous active-low
    reset to every register in the block, matching the rest of the repo's
    convention -- a robustness fix, not a behavior change once out of
    reset.
  - **ctrl_sgmux8** (`qick:ctrl:ctrl_sgmux8`): waveform-descriptor
    sequencer (mask FIFO pop -> mask/en_o playback timing), faithful port
    of `ctrl.sv`, including its dangling-else semantics for `en_reg`
    (only updated in READ_ST, held through CNT0_ST/CNT_ST) preserved
    explicitly rather than relying on Verilog's dangling-else rule.
  - **dds_top_sgmux8** (`qick:dsp:dds_top_sgmux8`): N_DDS-lane DDS + signed
    Q1.15 gain stage for one output channel, faithful port of `dds_top.v`,
    composed from `phase_ctrl_sgmux8` + `dds_compiler_signal_gen_mux` +
    `delay_line`.
  - **sg_mux8** (`qick:dsp:sg_mux8`): the full 8-channel datapath --
    descriptor FIFO, 8x `dds_top_sgmux8`, per-channel mask mux, and a
    3-stage binary adder tree with popcount-based output quantization,
    faithful port of `sg_mux8.v`. Fixed a pre-existing legacy inefficiency
    (not a behavior change): the post-gain `dds_dout` latency_reg was sized
    `B=N_DDS*32` against an actual `N_DDS*16`-bit signal (silently
    zero-extended in Verilog); ported at the correct `N_DDS*16` width.
    Needs `qick:common:xilinx` + `-top work.glbl -timescale=1ns/1ps` (via
    `fifo_sync`'s `XPM_FIFO_SYNC`), same as every other XPM-based core in
    this port.
  - **axis_sg_mux8_v1** (`qick:ip:axis_sg_mux8_v1`): the packaged IP --
    `axil_slv`-backed AXI4-Lite register bank (25 registers: PINC0-7 @
    0x00-0x1C, POFF0-7 @ 0x20-0x3C, GAIN0-7 @ 0x40-0x5C, WE_REG @ 0x60,
    matching the legacy `axi_slv.v` addressing exactly) wrapping `sg_mux8`.
    WE_REG is a plain level (not self-clearing) -- software pulses it
    0->1->0 around a PINC/POFF/GAIN update, same as the legacy design and
    the production driver's `update()`. 6/6 SVUnit tests, lint clean.
  - **Driver**: the production `AxisSgMux8V1` (`qick_lib/qick/drivers/
    generator.py`) already computes the exact same register layout
    dynamically from `N_TONES`/`HAS_PHASE`/`HAS_GAIN` -- extended its
    `bindto` with `qick:ip:axis_sg_mux8_v1:1.0`.
    `cores/ip/axis_sg_mux8_v1/driver/axis_sg_mux8_v1.py` is a symlink to
    it. `make driver IP=axis_sg_mux8_v1`: 4/4 register-layer tests pass.
  - **RDL**: `cores/ip/axis_sg_mux8_v1/rdl/axis_sg_mux8_v1_regmap.rdl`
    documents the PINC/POFF/GAIN register files and WE_REG (strategy 2,
    driver/docs only -- RTL decode is the generic `axil_slv`, no field
    needs anything `peakrdl regblock` can't already do trivially, but this
    IP still doesn't generate RTL from the RDL to stay consistent with the
    rest of this port).
  - **Constraints**: `constraints/axis_sg_mux8_v1.xdc`/`_ooc.xdc` are
    NEW, not ported -- the legacy IP never had packaged-IP-level
    constraints (its only synth XDC, `top_sg_mux8.xdc`, constrained the
    bare `sg_mux8` sub-block in isolation with a blanket
    `set_false_path -to [all_outputs]`, not suitable for a real AXI-Lite
    IP boundary). Re-derived for the two-clock (`s_axi_aclk`/`aclk`)
    boundary: `ASYNC_REG`-based CDC rule for the 8x `cdc_bit_sync`
    instances (same pattern as `axis_qick_processor.xdc`), plus a
    false-path rule for the un-synchronized PINC/POFF multi-bit crossing
    (inherited quasi-static CDC from the legacy design -- software holds
    the value stable across the WE_REG pulse, not a defect introduced by
    this port). NOT validated against an actual synthesized netlist (no
    Vivado synthesis run available in this port).
- **axis_sg_mixmux8_v1 bottom-up port** (mux8 signal generator with digital
  mixer, second of the 4 signal-generator IPs): the legacy source is
  byte-for-byte identical to `axis_sg_mux8_v1`'s for `phase_ctrl.sv`,
  `ctrl.sv`, and `axi_slv.v` -- only `dds_top.v`/`sg_mux8.v` differ, doubling
  every lane/adder-tree from a single 16-bit real sample to a 32-bit I/Q
  pair. Reused `phase_ctrl_sgmux8`, `ctrl_sgmux8`, `axil_slv`, `fifo_sync`,
  `delay_line`, and the pre-existing `dds_compiler_signal_gen_mixmux`
  (`DUAL_OUTPUT=1`, packs `{sin/Q[31:16], cos/I[15:0]}`) unchanged; only
  the DDS+gain stage and the full-width datapath needed new cores.
  - **dds_top_mixmux8** (`qick:dsp:dds_top_mixmux8`): N_DDS-lane I/Q DDS +
    independent per-component gain multiply, faithful port of mixmux8's
    `dds_top.v`, built on the SAME `phase_ctrl_sgmux8` instance as
    `dds_top_sgmux8` (no mixmux8-specific phase controller needed).
  - **sg_mixmux8** (`qick:dsp:sg_mixmux8`): the full 8-channel I/Q datapath
    -- descriptor FIFO, 8x `dds_top_mixmux8`, mask mux, and a duplicated
    (real + imaginary) 3-stage binary adder tree with shared popcount
    quantization, faithful port of mixmux8's `sg_mux8.v`. Reuses
    `ctrl_sgmux8` unchanged (legacy `ctrl.sv` is identical between the two
    IPs).
  - **axis_sg_mixmux8_v1** (`qick:ip:axis_sg_mixmux8_v1`): the packaged
    IP -- byte-identical register map to `axis_sg_mux8_v1` (25 regs, same
    addresses), only `m_axis_tdata` widens to `N_DDS*32` (I/Q per lane).
    6/6 SVUnit tests, lint clean.
  - **Driver**: `AxisSgMixMux8V1` (`qick_lib/qick/drivers/generator.py`,
    same `AbsMuxSignalGen` base, `HAS_MIXER=True`) already computes the
    identical register layout -- extended its `bindto` with
    `qick:ip:axis_sg_mixmux8_v1:1.0`. `make driver
    IP=axis_sg_mixmux8_v1`: 4/4 register-layer tests pass.
  - **RDL/constraints**: `cores/ip/axis_sg_mixmux8_v1/rdl/
    axis_sg_mixmux8_v1_regmap.rdl` mirrors `axis_sg_mux8_v1`'s regmap
    exactly. Constraints are NEW (the legacy IP had no synth XDC at all),
    written mirroring `axis_sg_mux8_v1.xdc`/`_ooc.xdc`'s CDC rules (same
    `phase_ctrl_sgmux8`/`cdc_bit_sync` scheme, reused unchanged). NOT
    validated against an actual synthesized netlist.
- **axis_sg_int4_v2 bottom-up port** (interpolated x4 signal generator,
  last of the 4 signal-generator IPs): unlike mux8/mixmux8, this IP is
  architecturally closer to axis_signal_gen_v4 (envelope BRAM + descriptor
  FIFO + AXI-Lite writer control) but with ONE envelope sample per address
  instead of N_DDS parallel banks, reconstructed to N_DDS=4 interpolated
  samples via a real Xilinx interpolate-by-4 FIR (fir_0.xci, 21-tap
  symmetric lowpass). Reused `ctrl_sgv4` UNCHANGED -- diffing the legacy
  ctrl.sv files showed it is already a faithful port of int4_v2's own
  (phrst-capable, 7-stage sync_reg) controller, not v4's simpler one, so
  the entire control/sequencing layer needed no new code. Also reused
  `dds_compiler_dyn_readout` (32-bit phase, matches int4_v2's actual 72-bit
  descriptor width; the pre-existing `dds_compiler_signal_gen_int` core
  turned out to be sized for a different, unrelated 16-bit-phase consumer
  and was NOT used here), `axis_to_bram_sg` (single-table writer, NT-less
  variant of the one v4 uses), `bram_tdp` (dual-clock, dual-port -- reused
  directly for the legacy `bram_dp` role since a dedicated `bram_dp` core
  turned out to be an unpopulated stub), `fifo_sync`, and `delay_line`.
  - **fir_interp4_sgint** (`qick:dsp:fir_interp4_sgint`): behavioural model
    of fir_0.xci (for sim/lint only, real .xci for synth -- same two-tier
    pattern as the DDS compiler wrappers). Implements the actual 21-tap
    polyphase interpolate-by-4 convolution in real arithmetic using the
    exact fir_0.coe coefficients (NOT bit/cycle-exact to the Vivado core's
    internal MAC/rounding, same disclaimer tier as dds_compiler_model).
    5/5 SVUnit tests (reset, tready/tvalid tied high, impulse response
    spans multiple output beats, I/Q channel independence).
  - **sg_int4** (`qick:dsp:sg_int4`): the per-lane datapath -- FIR
    interpolation, DDS x envelope complex product, gain, output-source mux
    (product/DDS-only/envelope-only/zero), faithful port of int4_v2's
    signal_gen.v with every legacy delay_line length carried over
    unchanged (ctrl_sgv4's timing is identical for both IPs). **Deviation
    tracking**: sgv4/sgv6 received a documented fix in an earlier session
    (product quantized at [30:15] instead of [31:16], plus +/-MAXV
    saturation) -- that fix was deliberately NOT applied here, preserving
    int4_v2's original unfixed [31:16] quantization with no saturation,
    matching the real deployed firmware exactly. Applying the same
    family-wide fix to int4 is a candidate follow-up. 6/6 SVUnit tests.
  - **sg_int4_top** (`qick:dsp:sg_int4_top`): assembles the descriptor
    FIFO, envelope writer/memory (single bank pair, not N_DDS-wide), and
    sg_int4, mirroring sgv4_top's structure. 4/4 SVUnit tests, including a
    full s0_axis-write -> BRAM -> FIR -> DDS-product -> m_axis integration
    path.
  - **axis_sg_int4_v2** (`qick:ip:axis_sg_int4_v2`): the packaged IP --
    only 2 AXI-Lite registers (START_ADDR_REG @0x00, WE_REG @0x04; this
    IP's legacy axi_slv.vhd never grew v4's RNDQ/STATUS/CTRL saturation
    registers), matching the production driver's `AbsIntSignalGen.
    REGISTERS = {'start_addr_reg': 0, 'we_reg': 1}` exactly. 5/5 SVUnit
    tests, lint clean.
  - **Driver**: `AxisSgInt4V2` (`qick_lib/qick/drivers/generator.py`,
    `AbsIntSignalGen` base, B_DDS=32/B_PHASE=32 matching this IP's 32-bit
    phase width) already computes the correct register layout -- extended
    its `bindto` with `qick:ip:axis_sg_int4_v2:1.0`. `make driver
    IP=axis_sg_int4_v2`: 4/4 register-layer tests pass.
  - **RDL/constraints**: `cores/ip/axis_sg_int4_v2/rdl/
    axis_sg_int4_v2_regmap.rdl` documents the 2-register map (strategy 2,
    driver/docs only). Constraints mirror `axis_signal_gen_v4.xdc`/`_ooc.xdc`
    unchanged (identical 3-clock-domain boundary and CDC scheme -- async
    clock groups + a false-path on the descriptor input; every CDC crossing
    goes through the same ASYNC_REG synchronizers or bram_tdp). NOT
    validated against an actual synthesized netlist.
  - This closes the 4-IP signal-generator group the user asked to keep
    (axis_sg_mux8_v1, axis_sg_mixmux8_v1, axis_sg_int4_v2, plus the
    already-ported axis_signal_gen_v6).
- **axis_dyn_readout_v1 bottom-up port** (tProc-controlled dynamic readout,
  first of the 5 readout IPs): 8 parallel real-ADC-sample x complex-DDS
  demodulators feeding an 8x decimating lowpass FIR. Unlike every signal
  generator ported so far, this IP has NO AXI-Lite register block at all --
  configuration (freq/phase/nsamp/outsel/mode/phrst, 88-bit descriptor)
  arrives entirely over an s0_axis stream pushed by the tProc at run time,
  matching the production driver (`AbsDynReadout` in
  `qick_lib/qick/drivers/readout.py`), which is a connectivity-only
  `DummyIP` with no register I/O -- confirmed no `bindto`/register work was
  needed for this port. Also confirmed the legacy source tree's
  `down_conversion.v` (an N_DDS-parametric predecessor) is dead code,
  superseded by `down_conversion_fir.v`; only the latter's chain is
  instantiated by the real top level, and only it was ported.
  - **ctrl_dyn_ro** (`qick:ctrl:ctrl_dyn_ro`): phase-coherent DDS
    controller, faithful port of `ctrl_dyn_ro_v1.sv` (88-bit descriptor,
    no gain/stdy/en outputs -- a continuous demodulator, not a pulsed
    generator, so that whole side of the legacy file was already commented
    out). Same phase-coherent pinc*N / pinc*cnt_n construction as
    `phase_ctrl_sgmux8`/`ctrl_sgv4`, ported fresh since the descriptor
    layout and lane count (N=8) don't match either.
  - **down_conversion_dynro** (`qick:dsp:down_conversion_dynro`): the
    per-lane demodulator (real sample x complex DDS, round-to-nearest,
    output-source mux product/DDS-only/raw-input/zero), faithful port of
    `down_conversion.v`, built on `ctrl_dyn_ro` + `dds_compiler_dyn_readout`
    (the same 32-bit-phase DDS model reused from `sgv4`/`axis_sg_int4_v2`).
  - **fir_decim8_dynro** (`qick:dsp:fir_decim8_dynro`): behavioural model
    of `fir_compiler_0.xci` (for sim/lint only, real .xci for synth -- same
    two-tier pattern as `fir_interp4_sgint`). Implements the actual 120-tap
    direct-form decimate-by-8 convolution in real arithmetic using the
    exact `fir.coe` coefficients (NOT bit/cycle-exact to the Vivado core's
    internal polyphase/MAC/rounding structure). Confirmed the legacy
    `fir_compiler_0.v` in the source tree is itself only a simulation
    placeholder (`assign m_axis_data_tdata = s_axis_data_tdata[31:0]` --
    lane-0 passthrough, no filtering at all), NOT the real IP; the real
    120-tap/decimate-8/2-path Xilinx core lives in the sibling
    `fir_compiler_0/fir_compiler_0.xci`, which is what got renamed and
    wired into the `synth_xci` fileset here. 6/6 SVUnit tests.
  - **readout_top_dynro** (`qick:dsp:readout_top_dynro`): assembles the
    88-bit descriptor FIFO (depth bumped 8->16: `fifo_sync`'s
    `XPM_FIFO_SYNC` backend has a hard 16-entry minimum, harmless), the
    demodulator, and the decimating FIR, mirroring `readout_top.v`. 4/4
    SVUnit tests, including a full ADC-in -> demod -> decimate ->
    m1_axis integration path.
  - **axis_dyn_readout_v1** (`qick:ip:axis_dyn_readout_v1`): the packaged
    IP -- single clock domain (`aclk`), three AXI-Stream ports (s0
    descriptor push, s1 ADC data in, m0 undecimated / m1 decimated out),
    no AXI-Lite. 4/4 SVUnit tests, lint clean.
  - **Driver**: no `bindto` change -- `AxisDynReadoutV1`
    (`qick_lib/qick/drivers/readout.py`) is resolved by IP-type string via
    connectivity tracing (`trace_back`/`trace_bus`), not the usual
    bindto-scan mechanism, and has no registers to match. Symlinked
    `cores/ip/axis_dyn_readout_v1/driver/axis_dyn_readout_v1.py` to it
    anyway for documentation consistency with every other IP in this port.
    `make driver`/PeakRDL generation does not apply (no registers); the
    RDL file is kept as an empty addrmap purely so the standard rdl/
    scaffold stays consistent with the rest of the repo.
  - **Constraints**: both files are NEW (the legacy IP had no XDC at all).
    `_ooc.xdc` defines just the single `aclk`; `.xdc` has one false-path
    rule for the descriptor input (`s0_axis_t*`, mirroring
    `axis_sg_int4_v2.xdc`'s equivalent `s1_axis_t*` rule) -- there is no
    AXI-Lite domain and therefore no CDC clock-group declaration needed,
    unlike every signal-generator IP so far. NOT validated against an
    actual synthesized netlist.
  - Remaining: `axis_pfb_readout_v2`, `axis_pfb_readout_v4`,
    `axis_readout_v2`, `axis_readout_v3` (the other 4 readout IPs).
- **tpv2_alu** (`qick:math:tpv2_alu`): tProcessor v2 combinational ALU,
  faithful port of `AB_alu` from `firmware/ip/qick_processor/src/_qproc_ips.sv`.
  First bottom-up piece of the tprocv2 port (rest of the processor still
  lives only in `firmware/ip/qick_processor/src/`).
- **tpv2_arith**, **tpv2_stack**, **tpv2_dsp_macro**, **restoring_divider**,
  **sync_ab_en**, **qcore_mem**, **qproc_mem_ctrl**, **qproc_axi_reg**,
  **qproc_inport_reg**: further bottom-up tprocv2 ports added after
  `tpv2_alu` (`arith`, `LIFO`, the DSP macro, `div_r`, `sync_ab_en` from
  `_qproc_ips.sv`; `qcore_mem.v`, `qproc_mem_ctrl.v` + `axis_read.v`/
  `axis_write.v`/`data_mem_ctrl.v`/`mem_rw.v`, `qproc_axi_reg.sv`,
  `qproc_inport_reg.sv`).
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
- **RTL library documentation pipeline**: `make rtl-docs` (+ `rtl-docs-clean`)
  generates per-module Markdown (TerosHDL-style Generics/Ports tables) for all
  of `rtl_lib`, via `scripts/gen_docs.py`. Supports both `//!` and legacy
  `/** */` `@port`/`@param` headers; excludes autogenerated IP via
  `rtl_lib/.docsignore`. Output in `docs/rtl-md/` with a module index.
- **SG-v4 IP** (`axis_signal_gen_v4`): `sgv4_top` corrected to the real `sgv4`
  interface — output narrowed to `N_DDS*16` (was erroneously `N_DDS*32`), added
  `outsel_reg` port wired to `sgv4.i_outsel_reg` (static real/imag select,
  legacy OUTSEL_REG); RNDQ dropped (deprecated in the IP).

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
- **`ctrl_sgv4`**: `en_reg` dangling-if refactored with `begin/end` (o_en is the
  datapath tvalid); FSM exit `cnt_nsamp_r == 2` → `<= 2` to prevent a ~65k-cycle
  hang on small `nsamp` (0/1/2). SVUnit: added `tc_en_deasserts`,
  `tc_nsamp_small` (19/19 passing).

### Deprecated
- SG-v6 `RNDQ_REG` and driver `rndq()` (rounding-select removed from the IP).
- SG-v4 legacy `RNDQ_REG` (removed from the datapath, matching SG-v6).

## [0.1.0]
- Initial version.
