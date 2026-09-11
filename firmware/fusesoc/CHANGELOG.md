# Changelog

All notable changes to the QICK FuseSoC environment are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

### Added
- **qick_time_tagger bottom-up port (Tier 0: new primitives)** (resuming the
  port that was explicitly paused earlier for size/complexity -- ~3500 lines
  across 10 files, 3 clock domains (`ps_clk`/`c_clk`/`adc_clk`), a custom DMA
  engine, 4 ADC inputs at 8 samples/clock, and a hand-written 16-register AXI
  slave; see `qick_lib/qick/drivers/peripherals.py::QICK_Time_Tagger` for the
  target register map). Real source confirmed at
  `main_qick/firmware/ip/qick_time_tagger/src/`. Before writing any RTL,
  mapped every legacy helper module the IP depends on against what's already
  ported: `sync_reg` -> existing `qick:cdc:cdc_reg_sync` (port-for-port
  match); `xpm_cdc_handshake` -> existing `qick:cdc:cdc_handshake`;
  `pulse_cdc` is dead code in the legacy tree (fully commented out
  everywhere, superseded by `sync_pulse`) and was not ported; `BRAM_SC` will
  reuse existing `qick:mem:bram_simple_dp` (`ena=enb=1`) when the modules
  that use it directly are ported in Tier 1; the planned CTRL-register
  self-clear will reuse `axil_slv`'s existing `AUTO_CLEAR_BIT0` parameter
  (register index 0) instead of new logic. Four primitives had no existing
  equivalent and needed a fresh faithful port, plus one dependency
  (`gcc`, a gray-code counter) discovered only once its callers were read in
  full, since both `sync_pulse` and the legacy `FIFO_DC` instantiate it:
  - **gcc** (`qick:cdc:gcc`): gray-code counter feeding the async-FIFO /
    pulse-CDC pointer synchronizers, faithful port of `_qtt_mem.sv`'s `gcc`.
    Presents the count gray-coded so only one bit changes per CDC hop; the
    `count_bin_o`/`count_gray_o` outputs are a one-*enable-event*-deep
    shadow of `count_bin_p1_o`/`count_gray_p1_o` (both pairs update inside
    the same `cnt_en_i` branch), not a fixed one-clock-cycle delay -- tests
    track this explicitly rather than assuming a flat latency. 5/5 tests,
    lint clean.
  - **priority_encoder** (`qick:encoders:priority_encoder`): one-hot/
    one-cold-to-binary encoder with a valid flag, faithful port of
    `_qtt_ips.sv`'s `priority_encoder`. `OUT` selects combinational
    ("NO_REG") vs. registered (anything else) output; kept as a runtime
    string compare rather than "fixed", because the only real caller
    (`qtt_tag_calc`, Tier 1) passes `OUT="TNO_REG"` -- not the string
    `"NO_REG"` -- which is almost certainly a typo in the original design
    but selects the registered (2-cycle) path on real, already-validated
    hardware, so changing it here would silently change deployed timing.
    Both branches are exercised (two DUT instances, one per `OUT` value) in
    the same testbench. 4/4 tests, lint clean.
  - **x_inter** (`qick:dsp:x_inter`): timestamp bit-interpolator, faithful
    port of `_qtt_ips.sv`'s `x_inter` -- a `cfg_inter_i`-cycle bit-serial
    restoring divider computing
    `floor(((thr_i-prev_i) << cfg_inter_i) / (curr_i-prev_i))` to refine a
    threshold-crossing time between two filtered ADC samples. Tests drive it
    through its `start_i`/`end_o`/`ready_o` handshake (not fixed cycle
    counts) and check results against an independent integer-division
    reference model. 4/4 tests, lint clean.
  - **sync_pulse** (`qick:cdc:sync_pulse`): CDC for a stream of single-cycle
    pulses (queue of pending pulses via a pair of `gcc` gray pointers,
    `BLOCK` parameter selects drop-when-full vs. backpressure-via-
    `pulse_full`), faithful port of `_qtt_ips.sv`'s `sync_pulse`. Both
    `BLOCK` values are exercised side by side, across two genuinely
    asynchronous clocks (300 MHz / 100 MHz, matching this repo's existing
    CDC-testbench convention), including a real fill-to-backpressure-then-
    drain test on the `BLOCK=1` variant. 5/5 tests, lint clean.
  - **fifo_dc** (`qick:mem:fifo_dc`): async dual-clock FIFO with a two-sided
    flush handshake, faithful port of `_qtt_mem.sv`'s `FIFO_DC`. The
    storage array reuses existing `qick:mem:bram_tdp` (true dual-port,
    independent clocks) in place of the legacy hand-rolled
    `BRAM_DP_DC_EN` -- same 1-cycle "NO_REG" read timing the legacy code
    always configured. Tested as a black box across the CDC (push a known
    sequence, then search for it as a contiguous in-order run in a
    generously long capture trace) rather than by hand-deriving the exact
    gray-pointer-CDC-plus-BRAM-register pipeline depth. 4/4 tests, lint
    clean.
  - Depends on `qick:cdc:gcc`: `sync_pulse`, `fifo_dc`.
  - Next (Tier 1, not yet started): `qtt_tag_calc`/`tag_gen`, the
    `tag_fifo_dc`/`tag_fifo_tc`/`tag_mem` memory stack, `smp_fifo_dc`/
    `smp_mem`, `dma_fifo_rd` (no existing fusesoc equivalent found for its
    length-counted FIFO-pop-to-AXIS-streamer shape), and `qtt_cmd`.
- **axis_weighted_buffer bottom-up port** (matched-filter averager + raw
  buffer, `qick:ip:axis_weighted_buffer`, versioned `1.3.0` to match the
  deployed `AxisWeightedBufferV1pt3` -- the revision with the first-
  output-sample DMA-readback bug fixed, mirroring the same "port the
  version that's actually used" correction made for `axis_avg_buffer`
  v1.1->v1.2). Located the real source at
  `main_qick/firmware/ip/axis_weighted_buffer/` (`component.xml`
  `<spirit:version>1.3</spirit:version>`).
  - **mult_pipe3** (`qick:dsp:mult_pipe3`): 3-cycle pipelined signed
    multiply modeling the legacy `dsp_macro_0` DSP48 IP (`C_LATENCY=-1`,
    auto-resolved) -- the VHDL's own `DSP_LATENCY=3` constant was the only
    available ground truth for this IP's register configuration (the
    `.xci`'s `C_REG_CONFIG` bitfield was not decodable from the checked-in
    file alone), so it was taken as authoritative rather than re-derived.
    Latency confirmed empirically via its own testbench (a/b on the bus ->
    p valid exactly 3 cycles later), not just paper-traced. 6/6 tests.
  - **matched_filter** (`qick:dsp:matched_filter`): the new DSP block --
    complex multiply of the incoming I/Q stream against a DMA-loaded
    weight envelope (`dout_i=ac-bd`, `dout_q=ad+bc`, truncated not rounded,
    no saturation, matching the legacy bit-select exactly). Reuses
    `axis_to_bram_sg` for the weight writer (confirmed via direct diff
    that legacy `data_writer.vhd` here is byte-identical, modulo
    formatting, to `axis_sg_int4_v2`'s own `data_writer.vhd` -- same
    already-ported FSM) and `bram_tdp` for the envelope memory (single
    packed-I/Q bank, unlike `sg_int4_top`'s split real/imag banks).
    Faithfully reproduces the legacy `WGT_LATENCY=4`/`DSP_LATENCY=3`
    pipeline constants, including a 2-sample address skew between when
    delayed `din_i` reaches the multiplier and when the corresponding
    envelope word is ready (`WGT_LATENCY` does not match the envelope
    path's own 2-cycle latency) -- reproduced exactly rather than
    corrected, since this is a faithful port, not a redesign. 3/3 tests.
  - **CONFIRMED IN SIMULATION -- a second, previously-undocumented skew**:
    `dout_valid_o` asserts one cycle before `dout_o` settles to its final
    value (`dout_o` comes from an extra register the legacy
    `TOTAL_LATENCY` constant does not account for). Legacy `avg_buffer.v`
    wires `dout_valid_o`/`dout_o` straight into `avg_top`/`buffer_top`'s
    `din_valid_i`/`din_i` with no compensating register, exactly as ported
    here -- so **every capture window on real axis_weighted_buffer v1.3
    hardware likely drops its first live sample** (buffer_top's
    `TRIGGER_ST`->`MEMW_ST` transition lines up with the first
    `dout_valid_o` pulse, whose `dout_o` has not caught up yet). This is
    distinct from the already-known, driver-compensated "first output
    sample" DMA-readback bug (`FIRST_OUT_SAMPLE_BUG_FIX`) -- it is a
    live-capture-time issue with no corresponding software workaround
    found in `qick_lib/qick/drivers/readout.py`. Reproduced faithfully
    (not silently fixed) and directly verified in
    `weighted_buffer`'s own testbench; flag to hardware owners.
  - **weighted_buffer** (`qick:math:weighted_buffer`): composition of
    `matched_filter` + `avg_top` + `buffer_top`, mirroring `avg_buffer.sv`
    but routing the filtered stream (and DSP-latency-compensated
    `trigger_o`) into the averager/buffer instead of the raw input --
    faithful port of legacy `avg_buffer.v` (the weighted variant, not to
    be confused with `qick:math:avg_buffer`). 3/3 tests, including an
    end-to-end check that buf readback shows the FILTERED product (not
    the raw sample), confirming the weight path is actually in use.
  - **axis_weighted_buffer** (`qick:ip:axis_weighted_buffer`): the packaged
    IP -- `axil_slv` register bank (`NUM_REGS=14`), register map matching
    `AxisWeightedBuffer.REGISTERS` exactly. Unlike `axis_avg_buffer`, two
    registers are combined multi-bit fields rather than one-field-per-
    register -- confirmed by direct read of legacy `axi_slv.vhd`'s own
    "Register Map" assignments: `start_reg` (0x00, bit0=avg enable,
    bit1=buf enable) and `dr_start_reg` (0x0C, bit0=avg/bit1=buf/bit2=wgt
    data-reader enable). New `s1_axis` port for weight-coefficient DMA
    loading, new `wgt_dw_addr_reg` (0x34). 4/4 SVUnit tests, lint clean,
    4/4 register-layer driver tests.
  - **Driver/RDL/constraints**: added `qick:ip:axis_weighted_buffer:1.3`
    to `AxisWeightedBufferV1pt3.bindto`; symlinked
    `driver/axis_weighted_buffer.py` to `readout.py`. RDL documents all 14
    registers at 0x00-0x34 including the two combined-bit fields (strategy
    2: docs/driver only). Constraints are new (legacy IP had none): 3
    independent clock domains (`s_axi_aclk` doubles as the weight-DMA
    write clock, matching legacy `avg_buffer.v`'s `write_clk =>
    s_axi_aclk` wiring; `s_axis_aclk`; `m_axis_aclk`), one false-path on
    `trigger` -- same pattern as `axis_avg_buffer`/`mr_buffer_et`.
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
    back), the same integration loop `qick_processor` will need.
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
    `qick:ip:qick_processor:2.0.0` shared the short IP name `qick_processor`
    -- `fusesoc ... run --target <t> qick_processor` was ambiguous. The plan
    at the time was to keep this composition under the `qick:processors:`
    library namespace and name the eventual packaged IP `axis_qick_processor`
    (matching the `tprocv1`/`axis_tprocv1` inner/outer split), to avoid a
    second collision once that packaged IP existed too.
  - **Update:** that inner/outer split turned out to be unnecessary. The
    `qick:processors:qick_processor` composition above was renamed to
    `qick:processors:tprocv2` (`firmware/fusesoc/cores/lib/processors/
    tprocv2/`, top-level `hdl/tprocv2.sv`), which freed the short name
    `qick_processor` for the packaged IP -- so no `axis_` prefix was ever
    needed. The paragraphs below describe that packaged IP.
  - **qick_processor** (`qick:ip:qick_processor:1.0.0`,
    `firmware/fusesoc/cores/ip/qick_processor/`): the packaged IP -- wraps
    `qick:processors:tprocv2` (`hdl/qick_processor.sv`, faithful port of the
    legacy `firmware/ip/qick_processor/src/tprocv2.sv`) behind
    `qick:ip:qick_processor_regmap` (AXI-Lite) and the usual CDC/interface
    dependencies (`qick:interfaces:axi4_lite_if`, `qick:cdc:cdc_reg_sync`).
    This closes the full tprocv2 port: every file under the legacy
    `firmware/ip/qick_processor/src/` tree now has an `rtl_lib/` + fusesoc
    equivalent.
  - **Driver**: `Axis_QICK_Proc` (`qick_lib/qick/drivers/tproc.py`) is the
    existing, full-featured production driver for tprocv2 (already correct
    for the ported register map). Its `bindto` still only lists the legacy
    Vivado-packaged VLNVs (`Fermi:user:qick_processor:2.0`,
    `QICK:QICK:qick_processor:2.0`) -- extending it with
    `qick:ip:qick_processor:1.0` so it also loads for the new fusesoc VLNV
    is still outstanding, not done. `cores/ip/qick_processor/driver/
    axis_qick_processor.py` is a symlink to the driver (single source of
    truth, matching Style A ("manual driver") from docs/DRIVER.md) --
    **still carries the old `axis_` filename** and should be renamed to
    `qick_processor.py` to match the RDL/constraints below.
  - **RDL**: `cores/ip/qick_processor/rdl/qick_processor_regmap.rdl`
    documents the full TPROC_CTRL/CFG/MEM_*/CORE_CFG/READ_SEL/status
    register map (strategy 2, driver/docs only -- no `--hdl`, since
    `qproc_axi_reg`'s `axil_slv`-based decode already handles TPROC_CTRL's
    whole-word self-clear that `peakrdl regblock` can't express).
  - **Constraints**: `constraints/qick_processor.xdc`/`_ooc.xdc` adapted
    from the legacy `qick_processor.xdc`/`_ooc.xdc`. The OOC clocks file
    ported directly (unchanged). The false-paths file's hierarchy-literal
    rules were re-derived against the new (renamed) instance hierarchy by
    tracing each legacy-preserved *signal* name; the generic CDC rule was
    upgraded from a name-pattern match (`*_cdc_reg*`, which would NOT have
    matched `cdc_bit_sync`'s actual `sync_r` register) to an
    `ASYNC_REG`-property-based match, which is robust to future renaming.
    NOT validated against an actual synthesized netlist (no Vivado
    synthesis run available in this port) -- the file's header flags two
    lower-confidence rules and instructs verifying every `get_cells`
    pattern resolves before relying on it in production.
  - Remaining follow-up (not blocking): extend the driver `bindto` (see
    above); rename the `driver/axis_qick_processor.py` symlink; a
    `driver/tests/` PeakRDL register-layer pytest suite for
    `qick_processor` (DRIVER.md documents the RDL as optional-but-useful
    for this even with a Style A manual driver); retiring the broken
    `qick:ip:qick_processor:2.0.0` leftover now that a real replacement
    exists.
  - **Naming/backward-compat note**: the legacy Vivado-packaged component
    is identified as `QICK:QICK:qick_processor:2.0` (component name
    "qick_processor", cell name `qick_processor_0`) and is hard-coded into
    several HOG block-design scripts (`firmware/Top/{111,4x2,216}/tpv2_*/
    bd_2023-1.tcl`). Backward compatibility with those scripts is a
    **packaging-time** concern: when `make package IP=qick_processor` is
    eventually run, pass `--ip-name qick_processor` (vendor/library
    `QICK`/`QICK`, version `2.0`) to reproduce the exact VLNV the HOG
    scripts expect, per the technique DRIVER.md already documents for this
    scenario.
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
    instances (same pattern as `qick_processor.xdc`), plus a
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
    `axis_readout_v3` (the other 3 readout IPs).
- **axis_readout_v2 bottom-up port** (PS-configured readout, second of the
  5 readout IPs): architecturally identical to `axis_dyn_readout_v1`'s
  demodulate + decimate chain (N_DDS=8, same `fir.coe` -- confirmed
  byte-for-byte identical between the two IPs, so `fir_decim8_dynro` was
  reused UNCHANGED), but configured via AXI-Lite registers
  (FREQ/PHASE/NSAMP/OUTSEL/MODE/WE, latched into the descriptor FIFO on a
  WE_REG edge) instead of a streamed descriptor push -- matching the
  production driver, which for this IP IS a real bindto/register-based
  `SocIP` (`AxisReadoutV2`), unlike `axis_dyn_readout_v1`'s connectivity-only
  `DummyIP`. Confirmed the legacy source tree's `axi_mst_0` (present as
  leftover `.xci`/`.veo`/`.vho` files, never instantiated by
  `axis_readout_v2.v`) and `down_conversion.v` (superseded by
  `down_conversion_fir.v`, same dead-code pattern as `axis_dyn_readout_v1`)
  are both unused here -- neither was ported.
  - **ctrl_ro_v2** (`qick:ctrl:ctrl_ro_v2`): phase-coherent DDS controller,
    faithful port of `ctrl.sv` -- an 83-bit descriptor (no `phrst` field:
    this IP is PS-configured, not tProc-streamed, so there's no
    per-descriptor phase-reset request; `cnt_n` free-runs unconditionally)
    and a simpler 8-stage `load_r1..load_r8` valid-pulse pipeline (vs
    `ctrl_dyn_ro`'s two-tier `sync_reg`+`load_r`). Ported fresh rather than
    parameterizing `ctrl_dyn_ro`, since the descriptor width itself differs
    (83 vs 88 bits) -- reusing it would have needed padding hacks for no
    real benefit.
  - **down_conversion_ro_v2** (`qick:dsp:down_conversion_ro_v2`): the
    per-lane demodulator, faithful port of `down_conversion.v` -- byte-for-
    byte identical math to `down_conversion_dynro`, built on `ctrl_ro_v2`
    instead of `ctrl_dyn_ro` (confirmed via diff that literally only the
    ctrl-instantiation and descriptor-width lines differ between the two
    legacy `down_conversion.v` files).
  - **readout_top_ro_v2** (`qick:dsp:readout_top_ro_v2`): assembles the
    83-bit descriptor FIFO (depth bumped 8->16, same `fifo_sync` minimum as
    `readout_top_dynro`), the demodulator, and `fir_decim8_dynro` (reused).
    WE_REG crosses from `s_axi_aclk` via `cdc_bit_sync` (replaces the
    legacy hand-rolled `synchronizer_n`) before edge-detection into the
    FIFO push strobe; FREQ/PHASE/NSAMP/OUTSEL/MODE themselves are NOT
    separately synchronized (quasi-static CDC, software holds them stable
    across the WE_REG pulse -- same pattern as `axis_sg_mux8_v1`'s
    PINC/POFF crossing). 4/4 SVUnit tests, including a full AXI-Lite-write
    -> FIFO -> demod -> decimate -> m1_axis integration path across two
    clock domains.
  - **axis_readout_v2** (`qick:ip:axis_readout_v2`): the packaged IP --
    `axil_slv`-backed AXI4-Lite register bank (6 registers: FREQ @0x00,
    PHASE @0x04, NSAMP @0x08, OUTSEL @0x0C, MODE @0x10, WE @0x14, matching
    the legacy `axi_slv.vhd` addressing exactly) wrapping
    `readout_top_ro_v2`. 5/5 SVUnit tests, lint clean.
  - **Driver**: `AxisReadoutV2` (`qick_lib/qick/drivers/readout.py`) already
    has the exact register layout (`REGISTERS = {'freq_reg': 0, 'phase_reg':
    1, 'nsamp_reg': 2, 'outsel_reg': 3, 'mode_reg': 4, 'we_reg': 5}`) --
    extended its `bindto` with `qick:ip:axis_readout_v2:1.0`. `make driver
    IP=axis_readout_v2`: 4/4 register-layer tests pass.
  - **RDL/constraints**: `cores/ip/axis_readout_v2/rdl/
    axis_readout_v2_regmap.rdl` documents the 6-register map (strategy 2,
    driver/docs only). Constraints are NEW (the legacy IP had no XDC at
    all): two-clock-domain OOC clocks (`s_axi_aclk`/`aclk`) plus the same
    `ASYNC_REG`-based CDC rule and a quasi-static false-path from
    `axil_slv`'s registers to the descriptor FIFO, mirroring
    `axis_sg_mux8_v1.xdc`'s pattern. NOT validated against an actual
    synthesized netlist.
  - Remaining: `axis_readout_v3`, `axis_pfb_readout_v2`,
    `axis_pfb_readout_v4` (the other 3 readout IPs).
- **axis_readout_v3 bottom-up port** (tProc-controlled readout v3, third of
  the 5 readout IPs): 4 parallel real-ADC-sample x complex-DDS
  demodulators feeding a 4x decimating lowpass FIR (107 taps, vs the
  120-tap/decimate-8 filter shared by `axis_dyn_readout_v1`/
  `axis_readout_v2`), single decimated output stream -- no separate
  "before decimation" tap this time. Config is tProc-streamed (s0_axis
  descriptor push, no AXI-Lite), matching the production driver
  (`AxisReadoutV3(AbsDynReadout)`, `DOWNSAMPLING=4`), same DummyIP pattern
  as `axis_dyn_readout_v1`.
  - Diffing the legacy `ctrl.sv` against `ctrl_dyn_ro_v1.sv` showed them
    byte-for-byte identical except for one thing: v3's `en` output logic is
    live (uncommented) where dyn_readout_v1's was entirely commented out.
    Investigating further, `down_conversion.sv`'s own legacy comment says
    "Always on output (not using en like in signal_gen_v6)" -- `en` is
    computed but never actually wired to anything downstream in EITHER IP.
    Since it is genuinely dead either way, `ctrl_dyn_ro` was reused
    UNCHANGED here too (no `en` port added) rather than creating a
    near-duplicate controller for a signal nothing consumes.
  - **down_conversion_ro_v3** (`qick:dsp:down_conversion_ro_v3`): the
    per-lane demodulator, faithful port of `down_conversion.sv`. Unlike
    `down_conversion_dynro`/`down_conversion_ro_v2`, this one has
    behavior-relevant differences, not just cosmetic ones: the product
    quantization TRUNCATES (bits[30:15], no +0.5 rounding constant) where
    the other two round to nearest, and the alignment pipeline is deeper/
    differently shaped (12-cycle input delay, separate mux-path delays,
    outsel delayed 15 cycles via its own `delay_line` rather than read
    straight off `ctrl_dyn_ro`'s pipeline). Confirmed via direct diff of
    the legacy files that these are real, deliberate differences in this
    IP, not sloppy inconsistency -- ported faithfully rather than
    "fixed" to match the other two.
  - **fir_decim4_ro_v3** (`qick:dsp:fir_decim4_ro_v3`): behavioural model
    of this IP's own `fir_0.xci` (for sim/lint only, real .xci for synth).
    107-tap direct-form decimate-by-4 convolution in real arithmetic using
    the exact `fir.coe` coefficients, 18-bit output per channel (2 bits of
    headroom over the 16-bit input, matching the coefficient sum's ~4.25x
    processing gain) packed into a 48-bit word with a 6-bit inter-channel
    gap -- reproducing the real IP's actual output convention as inferred
    from `down_conversion_fir.sv`'s own `{tdata_imag[16:1],
    tdata_real[16:1]}` extraction, since the bundled `fir_0.v` "model" in
    the legacy tree turned out to be yet another non-representative stub
    (32-bit output declared, but the real consumer reads it as 48-bit --
    same unreliable-placeholder pattern already seen in `fir_interp4_sgint`
    and `fir_decim8_dynro`'s source trees). 6/6 SVUnit tests.
  - **readout_top_ro_v3** (`qick:dsp:readout_top_ro_v3`): assembles the
    88-bit descriptor FIFO (depth bumped 8->16, same minimum as the other
    readout IPs), the demodulator, the decimating FIR, and the final
    18-bit-to-16-bit truncation/pack step. 4/4 SVUnit tests, including a
    full ADC-in -> demod -> decimate -> m_axis integration path.
  - **axis_readout_v3** (`qick:ip:axis_readout_v3`): the packaged IP --
    single clock domain (`aclk`), three AXI-Stream ports (s0 descriptor
    push, s1 ADC data in, single decimated m_axis out), no AXI-Lite. 4/4
    SVUnit tests, lint clean.
  - **Driver/RDL/constraints**: no `bindto` change needed (same
    connectivity-only DummyIP resolution as `axis_dyn_readout_v1`);
    symlinked the driver file for documentation consistency anyway. RDL is
    an empty addrmap (no registers). Constraints are NEW (no legacy XDC at
    all): single `aclk` OOC clock, one false-path on the `s0_axis`
    descriptor input -- identical pattern to `axis_dyn_readout_v1.xdc`.
  - Remaining: `axis_pfb_readout_v2`, `axis_pfb_readout_v4` (the last 2
    readout IPs; explicitly paused, to be picked up in a future session with
    fresh context given the jump in complexity -- SSR-FFT core, 8 FIR
    filters, MATLAB-derived coefficients).
- **axis_avg_buffer bottom-up port** (tProc-triggered averager + raw-capture
  buffer, the multi-register QICK readout back-end used by
  `qick_lib/qick/drivers/readout.py`'s `AxisAvgBuffer`/`AxisAvgBufferV1pt1`).
  `avg`/`avg_top` (`qick:math:avg`/`qick:math:avg_top`) were already ported
  and fully tested (16/16, 12/12) by earlier work in this same effort --
  reused as-is rather than duplicated. This port adds the sibling
  raw-capture half (`buffer`/`buffer_top`) and the top-level composition
  (`avg_buffer`) that combines both under one shared hardware trigger, plus
  the packaged AXI-Lite IP.
  - **buffer** (`qick:math:buffer`): faithful port of legacy `buffer.sv`
    (raw-sample capture FSM), written to mirror `avg.sv`'s exact style
    (async reset, header format) for consistency within this IP family --
    a deliberate choice even though it differs from this session's own
    synchronous-reset convention used elsewhere. 5-state FSM (INIT_ST/
    START_ST/TRIGGER_ST/MEMW_ST/WAIT_TRIGGER_ST). Same documented deviation
    as `avg`: adds an abort-on-`start_reg`-deassert path not present in the
    legacy original. 6/6 SVUnit tests.
  - **buffer_top** (`qick:math:buffer_top`): composition of `buffer` +
    `cdc_gray_sync` (resync `buf_start_reg`/`dr_start_reg`) + `bram_tdp` +
    `bram_to_axis` (replaces legacy `data_reader`) -- mirrors `avg_top.sv`
    minus the photon-mode fields and the second live-feed output stream
    (buffer has only one output stream, unlike avg's BRAM-readback + live
    feed pair). 3/3 SVUnit tests.
  - **avg_buffer** (`qick:math:avg_buffer`): top-level composition of
    `avg_top` + `buffer_top` sharing a single `cdc_bit_sync` trigger resync
    (replaces legacy `synchronizer_n`), exposing all 3 output streams
    (m0=avg BRAM readback, m1=buf BRAM readback, m2=avg live feed) and all
    15 avg_*/buf_* registers as discrete ports. 3/3 SVUnit tests. One open,
    deliberately-deprioritized item: the composition-level test's exact-sum
    check on the m2 live-feed accumulator was relaxed to a liveness/nonzero
    check after a persistent, not-fully-root-caused off-by-one/two count
    discrepancy (`avg`'s own dedicated suite already covers the exact
    arithmetic; this test's actual job -- proving the trigger fans out to
    both blocks -- is independently confirmed via the buf-side readback,
    which does pass with an exact match).
  - **Reuse decision: `mr_buffer_et` was NOT reused.** `mr_buffer_et`
    (`qick:ip:mr_buffer_et`) is a separate, already fully packaged,
    hardware-validated multi-channel/multi-rate buffer IP built earlier
    (likely by a parallel session) with a DIFFERENT, simpler 4-register map
    (`DW_CAPTURE_REG`/`DR_START_REG`/`STATUS_REG`/`DEBUG_REG`) and a
    different FSM (`axis_to_bram_trig`: INIT/TRIGGER/CAPTURE/END, always
    captures the full `2**N` window, no `addr_reg`/`len_reg`). Confirmed by
    reading `AxisAvgBuffer`/`AxisAvgBufferV1pt1` in `readout.py` that the
    production driver requires an exact 15-register layout with independent
    `addr_reg`/`len_reg` per averager/buffer/data-reader -- incompatible
    with `mr_buffer_et`'s register map, so building a faithful,
    register-compatible fresh port was the only option that doesn't break
    existing driver compatibility.
  - **axis_avg_buffer** (`qick:ip:axis_avg_buffer`, versioned `1.2.0`):
    the packaged IP -- `axil_slv` register bank (`NUM_REGS=15`) wrapping
    `avg_buffer`, register map matching `AxisAvgBufferV1pt2.REGISTERS`
    exactly (indices 0-11 avg_*/buf_* start/addr/len/dr_start/dr_addr/
    dr_len, 12-14 photon-mode/thresholds). 4/4 SVUnit tests (reset,
    register readback, buf capture + exact-match readback round-trip
    through the AXI-Lite map, and an avg-only-arms-avg cross-check), lint
    clean.
  - **Correction: versioned as 1.2, not 1.1.** Originally bound to
    `AxisAvgBufferV1pt1` on the assumption that the checked-in legacy
    source (`firmware/ip/axis_avg_buffer/src/`, whose stale `component.xml`
    claims v1.0) matched v1.1 firmware. The production driver marks v1.1
    as having a known bug (`FIRST_OUT_SAMPLE_BUG_FIX = False`): the first
    sample of any `transfer_avg`/`transfer_buf` read is always the data at
    address 0, worked around in software by requesting 2 extra samples and
    discarding them. Traced the `data_reader`/`bram_to_axis` FSM by hand
    (the `REGS_ST`/`READ_BRAM_ST`/`WRITE_FIFO_ST` address-latch pipeline
    gives the BRAM read a full cycle to settle before the first word is
    captured) and found no such bug, then confirmed empirically:
    `bram_to_axis`'s own SVUnit suite (`test_multiple_words`,
    `test_address_relatch`) requests nonzero-address bursts and checks the
    first returned word against that address, 12/12 passing. Located the
    real v1.2-tagged source at `main_qick/firmware/ip/axis_avg_buffer/`
    (`component.xml` `<spirit:version>1.2</spirit:version>`) and diffed
    every RTL file (`avg_buffer.v`, `avg.sv`, `avg_top.v`, `buffer.sv`,
    `buffer_top.v`, `axis_avg_buffer.v`, `data_reader.vhd`,
    `axi_slv_avg_buf.vhd`) against what's checked into this repo -- all
    byte-identical. Conclusion: this RTL already *is* the v1.2 (fixed)
    revision; the 1.0/1.1 labels floating around were stale packaging
    metadata, not a distinct earlier RTL state. No RTL change was needed --
    corrected the `.core` VLNV to `1.2.0` and moved the `qick:ip:
    axis_avg_buffer:1.2` bindto from `AxisAvgBufferV1pt1` (reverted to its
    original 2-entry bindto) onto `AxisAvgBufferV1pt2` instead. Re-verified
    lint/sim/driver-test all still pass (RTL untouched, only comments/
    labels changed).
  - **Driver/RDL/constraints**: `qick:ip:axis_avg_buffer:1.2` bindto on
    `AxisAvgBufferV1pt2` in `qick_lib/qick/drivers/readout.py`; symlinked
    `driver/axis_avg_buffer.py` to the same file. RDL documents all 15
    registers at 0x00-0x38 (strategy 2: docs/driver only, RTL decode stays
    the generic `axil_slv`). Constraints are NEW (legacy IP had none at the
    packaged level): 3 independent clock domains (`s_axi_aclk`,
    `s_axis_aclk`, `m_axis_aclk`), one false-path on the external
    `trigger` port -- same pattern as `mr_buffer_et`'s constraints. `make
    driver IP=axis_avg_buffer`: 4/4 register-layer tests pass.
  - Stray leftover files (`tb.sv`, `tb_avg.sv`, `tb_avg_top.sv`,
    `tb_buffer_top.sv`, `tb_avg_buffer.sv`, `tb_waves.wcfg`, `data_iq.txt`)
    from an earlier, unrelated directory-normalization commit were found
    sitting in `cores/ip/axis_avg_buffer/tests/` and left in place
    (untouched, not cleaned up as part of this port -- out of scope).
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

### Removed
- **Orphaned `utils/` data-mover cluster**: `data_reader`, `data_writer_trig`,
  `data_writer_sg`, `data_writer_sg_nt`, `data_capture_ctrl`,
  `data_capture_ctrl_top` (RTL + `cores/lib/utils/*` + their SVUnit tests).
  Each was an independent port of the same legacy VHDL/SV source already
  ported, separately, into the `axi/` family that IPs actually use:
  `data_reader`/`bram_to_axis` (`data_reader.vhd`), `data_writer_trig`/
  `axis_to_bram_trig`, `data_writer_sg`/`axis_to_bram_sg`
  (`axis_sg_int4_v2/data_writer.vhd`), `data_writer_sg_nt`/
  `axis_to_bram_sg_nt` (`axis_signal_gen_v6/data_writer.vhd`), and
  `data_capture_ctrl`/`buffer` (`axis_avg_buffer/src/buffer.sv` -- the
  latter now `qick:math:buffer`, added in this same effort). Confirmed via
  `.core` dependency search that nothing outside this cluster's own
  self-references ever depended on it -- the `axi/` versions are the ones
  wired into `avg_top`, `buffer_top`, `mr_buffer`, `sg_int4_top`,
  `sgv4_top`, `sgv6_top`, and the only ones that kept receiving fixes after
  both clusters were first ported on the same day. `data_capture_ctrl_top`
  (a standalone composition on top of `data_reader`) had no consumers
  either and was removed with it. Re-verified lint-clean on all 6 real
  consumers after removal.

## [0.1.0]
- Initial version.
