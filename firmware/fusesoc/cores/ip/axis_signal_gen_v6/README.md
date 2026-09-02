# Arbitrary Signal Generator v6 (`axis_signal_gen_v6` / `sgv6`)

Waveform engine for the QICK RFSoC firmware. Reads 160-bit descriptors from a
FIFO, plays a per-lane envelope from block RAM, up-converts it with `N_DDS`
parallel DDS carriers, applies gain and saturation, and drives an
`N_DDS`-samples-per-cycle AXI4-Stream bus straight into a DAC. Supersedes SG-v5
with a fixed-rate output contract, a free-running phase reference, and per-lane
Q15 scaling with saturation.

- Project: QICK · VLNV `qick:ip:axis_signal_gen_v6:1.0.0`
- Author: @lharnaldi · Target: RFSoC (ZCU216 / ZCU111 class)
- Status: **IP-level SVUnit 11/11 with the `axi4_stream_if` protocol assertions
  active.** Datapath, phase accumulator, envelope memory mapping, gain,
  saturation, `phrst`, and the fixed-rate contract are all verified. Diagnostic
  probes (`tc_dump_*`) are kept in a separate file. Pending: lint sweep, XDC for
  the three clock domains, `.rdl` + driver, IP packaging. See §9.

---

## Table of Contents
1. [Overview](#1-overview)
2. [Descriptor format](#2-descriptor-format)
3. [Internal architecture](#3-internal-architecture)
4. [Output contract — fixed-rate, `tready` ignored — READ THIS](#4-output-contract--fixed-rate-tready-ignored--read-this)
5. [Phase generation and `phrst` — READ THIS](#5-phase-generation-and-phrst--read-this)
6. [Amplitude, scaling and saturation](#6-amplitude-scaling-and-saturation)
7. [Verification campaign — symptom → cause → fix](#7-verification-campaign--symptom--cause--fix)
8. [Testbench notes worth carrying to other blocks](#8-testbench-notes-worth-carrying-to-other-blocks)
9. [Files, build and open items](#9-files-build-and-open-items)

---

## 1. Overview

```
                       AXI4-Lite (s_axi_aclk)
   Python / tProc ───────────► START_ADDR_REG, WE_REG   (envelope writer regs)
                                     │
   envelope samples                  ▼
   ───────────────► s0_axis ──► axis_to_bram_sg_nt ──► BRAM_real[0..N_DDS-1]  ┐
   (s0_axis_aclk,                (one-hot bank demux)   BRAM_imag[0..N_DDS-1]  │
    32-bit I/Q)                                                                │
                                                          shared mem_addrb ◄───┤
   descriptors                                                                 │
   ───────────────► s1_axis ──► fifo_sync ──► ctrl_sgv6 ──► sgv6 datapath ◄────┘
   (aclk, 160-bit)              (16 deep)     (sequencer)   envelope × DDS,
                                                            gain, saturation
                                                                  │
                                                                  ▼
                                                     m_axis ──► axis_register_slice
                                                     (N_DDS×16)   (non-blocking) ──► DAC
```

**Three independent clock domains:**

| Domain | Signal | Role |
|--------|--------|------|
| Config | `s_axi_aclk` | envelope-writer registers (`START_ADDR`, `WE`) via AXI4-Lite |
| Write | `s0_axis_aclk` | envelope sample stream into BRAM port A |
| Datapath | `aclk` | descriptor FIFO, `ctrl_sgv6`, BRAM port B read, DDS, output |

The dual-clock BRAM (`bram_tdp`) resolves the write↔datapath crossing;
`cdc_gray_sync` carries `WE` into the write domain.

**Envelope memory layout.** `N_DDS` parallel banks, each 16 bits wide and `2**N`
deep. Sample `k` of a waveform lives in **bank `k mod N_DDS`, row `k / N_DDS`**.
One output beat reads **one shared row** across all `N_DDS` banks, emitting
samples `[r·N_DDS .. r·N_DDS+N_DDS-1]` in parallel. There is a single read
address `mem_addrb` for every bank — remember this, it constrains where a
mapping bug can and cannot live (§7.5).

Exposed to software as the `AxisSignalGen` driver (shared V4/V5/V6 interface;
`MAXV = 2^15-2`, `SAMPS_PER_CLK = 16 = N_DDS`, `B_DDS = B_PHASE = 32`, no mixer).
The legacy `rndq_reg` is a no-op in this IP and slated for removal.

Two synthesis modes (`GEN_DDS`): `"TRUE"` up-converts with the DDS, `"FALSE"` is
baseband envelope only. Two envelope types (`ENVELOPE_TYPE`): `"COMPLEX"`
(separate real/imag banks) or `"REAL"` (imag forced to zero).

---

## 2. Descriptor format

The 160-bit word queued on `s1_axis` and read from the FIFO by `ctrl_sgv6`:

| bits | field | width | meaning |
|------|-------|-------|---------|
| 159..149 | — | 11 | unused |
| 148 | `phrst` | 1 | phase reset (see §5) |
| 147 | `stdysel` | 1 | steady-value select at end of waveform |
| 146 | `mode` | 1 | 1 = periodic / non-stop |
| 145..144 | `outsel` | 2 | output source: **0 = product, 1 = DDS, 2 = envelope** |
| 143..128 | `nsamp` | 16 | burst length (see ⚠️ below) |
| 127..112 | — | 16 | unused |
| 111..96 | `gain` | 16 | output gain (signed) |
| 95..80 | — | 16 | unused |
| 79..64 | `addr` | 16 | envelope start row in memory |
| 63..32 | `phase` | 32 | initial phase (`2^32 = 360°`) |
| 31..0 | `freq` | 32 | phase increment `pinc` (`0 = DC`, `2^31 = Nyquist`) |

> ⚠️ **`nsamp` drives a per-cycle countdown, not a sample total.** `ctrl_sgv6`
> loads `cnt_nsamp_r` from this field and decrements it **once per `aclk`**,
> returning to `READ_ST` when it reaches 2. The burst therefore lasts ~`nsamp`
> **output beats**, and each beat emits `N_DDS` samples. The QICK Python packer
> is responsible for whatever `length_in_samples ↔ nsamp` conversion the user
> API implies (`w_length` in the user docs); confirm that mapping in the Python
> class before trusting a raw `nsamp` as "samples". The `-2` early return is the
> pipeline flush margin.

This 160-bit descriptor arrives on **`s1_axis` from the tProcessor**, not from
PYNQ. The user never writes these bits by hand: `AveragerProgramV2.add_pulse(...)`
(`freq`, `phase`, `gain`, `envelope`, `style`, `length`, …) is compiled by the
`asm_v2` layer / generator manager into the tProc waveform that drives `s1_axis`.
The only PYNQ-side path into this block is the **envelope loader** (§3.1), a DMA
into BRAM gated by `START_ADDR_REG` / `WE_REG` — see the `AxisSignalGen` /
`AbsArbSignalGen.load()` driver, which packs I into `[15:0]` and Q into `[31:16]`
of each 32-bit word. There is **no** `pack_waveform()` in the driver; earlier docs
that referenced one were wrong.

---

## 3. Internal architecture

Two RTL layers: `sgv6_top` assembles the memory subsystem around the `sgv6`
datapath, which in turn wraps `ctrl_sgv6` (the sequencer) and the per-lane
arithmetic.

### 3.1 `sgv6_top` — memory subsystem

| Block | Instance | Role |
|-------|----------|------|
| `fifo_sync` | `fifo_i` | 160-bit descriptor FIFO, depth 16 |
| `axis_to_bram_sg_nt` | `writer_i` | envelope stream → shared BRAM write port + one-hot bank select |
| `bram_tdp` ×`N_DDS` | `gen_mem[i].mem_real_i` (+ `mem_imag_i`) | dual-port dual-clock envelope banks |
| `sgv6` | `sgv6_i` | datapath |

- `fifo_wr_en = s1_axis_tvalid_i & s1_axis_tready_o` — a **qualified** write
  enable (both sides of the handshake). An earlier version tied it to `tvalid`
  alone and could push the same descriptor twice.
- The `N_DDS` banks share the read address `mem_addrb` (from `sgv6_i.o_mem_addr`)
  and each `bram_tdp` sets **`OUT_REG_B = 1`** — a 2-cycle read latency chosen to
  match the 2-cycle `delay_line` in `sgv6` (the comment in the RTL states this
  explicitly). Real and imag banks of a lane share `mem_addrb` and `mem_en[i]`
  so I and Q stay coherent.

### 3.2 `ctrl_sgv6` — sequencer

Two-state one-hot FSM:

```
READ_ST : assert o_fifo_rd_en; when (mode || !fifo_empty) latch the descriptor,
          load cnt_nsamp_r from nsamp, go to CNT_ST.
CNT_ST  : decrement cnt_nsamp_r each cycle; when it reaches 2, go to READ_ST.
```

It produces, aligned to the datapath latency through fixed register pipelines:
the per-lane DDS control word `o_dds_ctrl`, the envelope read address
`o_mem_addr`, `o_gain`, `o_src` (= `outsel`), `o_stdy`, and `o_en`.

**Read address.** `addr_cnt` loads the descriptor `addr` when `rd_en_r2`, else
increments by 1 each cycle; `o_mem_addr = addr_cnt_r6` (6 alignment stages).
One increment per beat = one row per beat = a clean `N_DDS`-sample frame.

**Phase generation** (the heart of the block):

```
phase_v0[i] = pinc · i                     per-lane offset (0 .. (N_DDS-1)·pinc)
phase_0     = pinc · cnt_n + phase         beat-advancing absolute phase
phase_v1[i] = phase_v0[i] + phase_0        per-lane absolute phase → DDS i
pinc_n      = pinc · N_DDS                  per-cycle advance (shared, packed in ctrl word)
```

- `cnt_n` is a **non-stop time counter**: `cnt_n <= cnt_n + N_DDS` every cycle,
  reset to 0 **only** when `sync_reg && phrst_int`. This is what makes the phase
  time-referenced rather than pulse-referenced (§5).
- `cnt_n_reg <= cnt_n` is a **pipeline stage** feeding the phase multiplier. It
  must update every cycle (see the §7.1 bug — it used to be gated).
- `pinc · cnt_n_reg` is a **split multiplier** (`WL = 17` low/high partials,
  shifted and summed mod `2^32`) so it maps to DSP slices and meets timing; the
  original single 48-bit multiply is kept commented for reference.

The packed 72-bit per-lane DDS control word is
`{7'h00, sync_reg_r7, phase_v1_r1[i], pinc_n_r5}` — 7 pad + 1 sync + 32-bit
absolute phase + 32-bit `pinc_n`. The DDS consumes the phase from the high half;
`pinc` in the low half is unused on the pre-accumulated (`signal_gen`) path.

### 3.3 `sgv6` — per-lane datapath

For each of `N_DDS` lanes: read envelope from BRAM, (optionally) multiply by the
DDS carrier, apply gain, round with saturation, drive 16 bits of the output bus.
`outsel` selects product / DDS-only / envelope-only. Fixed `delay_line`s align
the DDS, memory, gain, `src`, `stdy` and `en` pipelines so a given output beat
combines matching envelope, carrier and control. `o_axis_tvalid = en_la_r`;
`o_sat = |sat_lane`.

### 3.4 Latency (orientation, not exhaustive)

| Path | Notes |
|------|-------|
| BRAM read | 2 cycles (`OUT_REG_B = 1`), matched to `sgv6`'s 2-cycle mux delay |
| DDS core | latency 10 (`dds_compiler_signal_gen`; the sim model matches) |
| Envelope (product path) | `delay_line N=9` then further mux/product stages |
| Control (`o_mem_addr` / `gain` / `src` / `stdy` / `en`) | `addr_cnt_r6`, `gain_r7`, `outsel_r7`, `stdysel_r7`, `en_reg_r8` |

The absolute numbers matter less than the invariant: every path is padded so the
frame that appears at `m_axis` is internally consistent. Do not add or remove a
register on one path without re-balancing the others.

---

## 4. Output contract — fixed-rate, `tready` ignored — READ THIS

**`sgv6` is a fixed-rate source.** Once a descriptor starts, it emits one output
beat per `aclk` for the whole burst. `i_axis_tready` is **not honored** — it
exists only for interface conformance. In `sgv6_top` the output feeds an
`axis_register_slice` in non-blocking mode (tready always high) and then the DAC,
which is always ready. That is the intended and only supported deployment.

> ⚠️ **Do not place a blocking element downstream** (a FIFO that can fill, a DMA,
> a resampler that can stall) without first adding a `tready`-gated global enable
> across the *entire* pipeline. A single output FIFO is not enough: the generator
> keeps producing and would overrun it silently.

Consequence for verification: because the real sink (a DAC) always accepts, the
`axi4_stream_if` master-stability assertions (`AXIS_TVALID_STABLE`,
`AXI4STREAM_ERRM_TDATA_STABLE`) never fire in normal operation. They fire **only**
if a test deliberately lowers `tready`. The suite models the DAC with
`assign m_if.tready = 1'b1` at module level plus `m_if.s_cb.tready <= 1'b1` in the
tests; the one test that must lower `tready` to prove the contract brackets that
window with `$assertoff`/`$asserton` (§7.4).

---

## 5. Phase generation and `phrst` — READ THIS

The phase presented to lane `i` at output beat `r` is

```
phase(r, i) = phase_descriptor + pinc · (cnt_n(r) + i)
```

where `cnt_n` is the **free-running** time counter. This has one consequence that
looks like a bug the first time you see it but is by design:

**With `phrst = 0`, the pulse phase is referenced to absolute time, not to the
start of the pulse.** `cnt_n` is never reset, so where a pulse "lands" in phase
depends on when in the free-running count it starts. This is exactly what makes
multiple pulses mutually phase-coherent.

**With `phrst = 1`, `cnt_n` is reset (`sync_reg && phrst`) at descriptor load,**
so the first output beat starts at exactly `phase_descriptor`.

Measured, `pinc = 2^24` (⅟₁₆ turn per beat), lane 0 across beats — the value is
the DDS cosine, `+32766` is phase 0:

```
phrst=0:  23167  30270  32765  30270  23167  12538  0  ...   peak (phase 0) at beat 2
phrst=1:  32765  30270  23167  12538  0  ...                 peak (phase 0) at beat 0
```

So with `phrst=1` the phase-0 crossing sits on beat 0 with **no fractional or
half-beat latency** — the counter reset and the first emitted beat are aligned.
The beat-2 offset seen with `phrst=0` is not a pipeline defect; it is the
free-running reference.

> ⚠️ **When you need to verify absolute phase, or take a phase-0 reference,
> set `phrst = 1`.** With `phrst = 0` the starting phase is deterministic in
> simulation but arbitrary with respect to the pulse — do not assert `cos(0)` on
> beat 0.

> ⚠️ **Testbench corollary (§7.2):** to check DDS output values against a cosine
> model you must also make the frequency **beat-aligned** — `pinc` a multiple of
> `2^28`, so `N_DDS·pinc ≡ 0 (mod 2^32)` — otherwise the fixed startup offset
> above rotates every frame and the tone appears sign-flipped.

### 5.1 Who computes which term — READ THIS BEFORE TOUCHING `ctrl_sgv6`

The formula above is produced by **two** pieces of hardware, and the split is
not visible in the RTL alone. Each lane's 72-bit word on the DDS interface is

```
{7'h00, sync, phase_v1[i], pinc_n}
         bit64  bits[63:32]  bits[31:0]
```

* **bits[31:0] — `pinc_n = pinc · N_DDS`.** The *increment*. The DDS Compiler
  accumulates this itself: `dds_compiler_signal_gen.xci` sets
  `Phase_Increment = Streaming`. One accumulate per clock is one per output
  beat, so this is the `pinc · cnt_n(r)` term — **the RTL never adds it.**
* **bits[63:32] — `phase_v1[i] = i·pinc + phase_0`.** The *offset*, added by
  the IP every cycle and never accumulated (`Phase_offset = Streaming`). Here
  `phase_0 = pinc · cnt_n_reg + phase_descriptor`, and `cnt_n_reg` is a
  **snapshot** of the free-running counter latched once per pulse:

  ```systemverilog
  if (sync_reg_r1 == 1'b1)
     cnt_n_reg <= cnt_n;        // NOT an unconditional copy
  ```

**`phase_0` must be constant for the whole pulse.** If `cnt_n_reg` is allowed
to follow `cnt_n` every cycle, the RTL accumulates as well as the IP, the phase
advances twice, and the output frequency is exactly `2·f`. See §7.6 — that is
not hypothetical, it shipped.

---

## 6. Amplitude, scaling and saturation

Documented as-is; the testbench compares the RTL against both a faithful model
(what the RTL does) and the intended Q15-with-saturation behaviour.

- **Envelope × DDS product** quantizes with `prod_y_full_real[30:15]` — full Q15
  scale. A previous `[31:16]` dropped a factor of 2, so shaped pulses came out at
  half the amplitude of constant pulses at the same gain. **Fixed.**
- **Baseband / envelope-only path** no longer applies `>>1`; both paths now share
  the same Q15 scale. (The old `>>1` was there to match the halved product path.)
- **Gain stage saturates to ±MAXV (32766)** via a 17-bit rounded intermediate,
  clamping instead of wrapping. Without this, `gain·envelope·DDS` near full scale
  wrapped from large positive to large negative. `o_sat = |sat_lane` flags any
  lane clamping this cycle (sticky status is surfaced at the wrapper).

> ⚠️ Full-scale envelope in the RTL is **MAXV = 2^15 − 2 = 32766**, not 32767.
> Cosine reference models that use 32767 will differ by 1 LSB at the peaks — real,
> expected, and within any sane tolerance.

---

## 7. Verification campaign — symptom → cause → fix

Five threads. Each is written the way it was actually found, because the wrong
turns are as instructive as the fixes: **on this block, output values alone
repeatedly failed to distinguish an RTL bug from a testbench artifact. What
worked every time was dumping raw internal signals and reading them, not fitting
them to an assumed model.**

### 7.1 Phase pipeline frozen (RTL bug)

- **Symptom.** Every DDS-carrier test failed. Values looked like an exact sign
  inversion (`got = -expected`) — e.g. lane 0 at phase 0 read `-32766` instead of
  `+32767`.
- **Cause.** `cnt_n_reg`, the pipeline stage feeding the phase multiplier, was
  gated: `if (sync_reg_r1 == 1'b1) cnt_n_reg <= cnt_n;`. `sync_reg_r1` is a
  one-cycle pulse at descriptor load (it mirrors `load_r`, driven by
  `rd_en_int & ~i_fifo_empty`). So `cnt_n_reg` latched **once** and froze for the
  rest of the burst → `pinc·cnt_n_reg` constant → `phase_0` constant → every lane
  a fixed phase for the whole pulse. The accumulator `cnt_n` was fine; the *pipe
  feeding the multiply* closed after one cycle.
- **Fix.** Remove the gate; `cnt_n_reg <= cnt_n` runs unconditionally (the `if`
  is now commented in `ctrl_sgv6`).
- **Evidence.** Post-fix raw dump, `pinc = 2^24`, lane 0 sweeps a full cosine over
  16 beats (`23167 30270 32765 30270 23167 12538 0 -12539 …`), advancing exactly
  `N_DDS·pinc` per beat. A frozen pipe would show 16 identical values.

> ⛔ **This entry is wrong and its fix was reverted — see §7.6.** The
> observation is accurate: with the gate in place `phase_0` is constant for the
> whole pulse. That is *by design*. The per-beat advance is supposed to come
> from the DDS Compiler's own accumulator (§5.1), which
> `dds_compiler_model.sv` does not emulate as configured, so the correct RTL
> looks frozen in simulation. Removing the gate made simulation sweep and made
> hardware run at double frequency. The "evidence" above is the RTL doing the
> accumulation that the IP was already doing.

### 7.2 Sign-flip in the tests (methodology, not RTL)

- **Symptom.** After 7.1, some DDS value tests still failed as `got = -expected`.
- **Cause.** The tests drove `pinc = 2^27`. Combined with the free-running
  startup offset (§5), an unaligned frequency rotates the sampled frame — at
  `pinc = 2^27`, `N_DDS·pinc = 2^31` = a half turn, so the first captured beat's
  base phase is `2^31` and `cos` inverts.
- **Fix.** Use **beat-aligned** carrier frequencies in value tests: `pinc` a
  multiple of `2^28` so `N_DDS·pinc ≡ 0 (mod 2^32)` and the frame is invariant to
  which beat is sampled. The datapath was never wrong here.

### 7.3 Carrier startup offset (by design — see §5)

- **Symptom.** Phase-0 crossing landed on beat 2, not beat 0.
- **Cause / resolution.** Free-running `cnt_n` with `phrst = 0`. Confirmed by the
  `phrst=0` vs `phrst=1` dump (§5): with `phrst=1` the crossing moves to beat 0.
  **Nothing to fix.**

### 7.4 Fixed-rate contract vs AXIS assertions

- **Symptom.** The test that lowers `m_axis_tready` to prove the source ignores
  backpressure tripped `AXIS_TVALID_STABLE` / `AXI4STREAM_ERRM_TDATA_STABLE`.
- **Cause.** Correct — while `tready` is low the fixed-rate source keeps changing
  `tvalid`/`tdata`, which is a *deliberate* non-compliant-master behaviour this
  output is documented to have (§4). The interface assertions encode a compliant
  master.
- **Fix.** The test runs the same descriptor twice over an equal window (tready
  high vs forced low) and requires equal valid-beat counts, bracketing the
  forced-low window with `$assertoff(0, m_if)` / `$asserton(0, m_if)` and a
  generous drain before re-arming (so no clocked assertion window straddles the
  release edge). Everything outside that window keeps full assertion coverage.

### 7.5 Envelope "+1 sample skew" (testbench driver artifact)

- **Symptom.** In envelope mode, lane `i` returned sample `i+1`: the output frame
  straddled two rows (beat 0 = samples `[1..16]`, not `[0..15]`).
- **Localization (structural).** The read uses **one shared `mem_addrb`** for all
  banks with identical per-lane latency, so a read can only ever emit a clean row
  `[r·N_DDS .. r·N_DDS+N_DDS-1]`. A frame that straddles rows must be **baked into
  memory by the write**, not created on read — so `ctrl_sgv6` and the read
  datapath are exonerated by construction.
- **Cause (measured).** A cycle-by-cycle dump of the BRAM write port showed the
  **first write was already sample 1** at bank 0 — sample 0 was never written. The
  writer's first handshake carried `d1 = sample 1`. Root cause was **upstream in
  the testbench**: `axis_to_bram_sg_nt` pre-asserts a *registered* `tready`
  (`tready_r`) while idle in `WAIT_TVALID`; the old `load_envelope` did
  `present; @(m_cb); while(!tready) @(m_cb);`, so with `tready` already high it
  advanced after a single clocking edge, and the `m_cb` output skew meant the DUT
  sampled the *second* beat first — sample 0 was dropped by the driver, never by
  the RTL. **Real hardware is unaffected**: a compliant DMA master holds the beat
  until the handshake.
- **Fix (testbench).** `load_envelope` now presents the first beat, takes a
  **lead edge** so the DUT can sample it before any `tready`-based advance, holds
  `tvalid` continuously, and advances `tdata` only on an edge where `tready` was
  sampled high. After the fix the write map is natural (`sample s → bank s%16`)
  and the `re[i+1]` / `(k+1)%N_DDS` compensations were removed from
  `tc_envelope_only` / `tc_gaussian` — they had been papering over the dropped
  sample.

---

### 7.6 Double phase accumulation — §7.1 undone

**Symptom.** On a VRK160 (first hardware run of the SystemVerilog port) every
requested frequency came out at exactly twice the request, with images spaced
by the AXI-Stream beat rate. Sixteen requests fit

```
measured == -2·f_requested   (mod 491.52 MHz)
```

to within 0.04 MHz — better than the FFT bin. `outsel=2`, which takes the
envelope and leaves the DDS out of the path, gave a single clean tone at the
right frequency with no images, placing the fault in the DDS path alone. The
generator's own simulation passed throughout, including a new test written
specifically to check the phase across beat boundaries.

**Cause.** The `cnt_n_reg` gate removed in §7.1. `phase_0` must be constant for
the pulse; the per-beat advance belongs to the DDS Compiler (§5.1). Ungated,
the RTL accumulates as well and the phase advances twice. The beat-rate images
follow from the two accumulations sitting at different pipeline depths.

**Fix.** Restore the gate. Verified on hardware: 100/300/500/700 MHz land
within 0.04 MHz of prediction at 84–90 dB over the noise floor, no images.

**Why this happened, and why it will happen again if only the gate is
restored.** §7.1 was not careless — it was misled by an unfaithful model, and
the same trap is still set:

1. `dds_compiler_signal_gen.sv` instantiates `dds_compiler_model` **without
   passing `STREAMING`**, so it defaults to 0 — "phase pre-accumulated
   upstream" — reading the high bits and never accumulating the low ones. That
   is the opposite of `dds_compiler_signal_gen.xci`
   (`Phase_Increment = Streaming`). Against that model the correct RTL looks
   frozen, which is exactly the symptom §7.1 set out to fix.
2. Every `pinc` in the suite is beat-aligned (§8.0), so nothing looks past one
   frame.

Neither of the model's two branches matches the real configuration, which needs
*accumulate the low bits **and** add the high bits as an offset*. Making it
faithful breaks the whole suite today, because the tests assert absolute phase
that a free-running accumulator does not guarantee — `tc_pure_tone_all_lanes`
then reports `lane 1 got 32765 expected 30272`. **The tests have to become
phase-agnostic first, then the model can be fixed.**
`tc_frequency_unaligned_across_beats` is written that way and is the pattern.

---

## 8. Testbench notes worth carrying to other blocks

- **Sample the output through the clocking block, never on a raw `@(posedge
  aclk)`.** Raw sampling catches the wrong beat and manufactures phantom
  per-lane errors; read `m_if.s_cb.tdata`.
- **Value-check DDS tones only at beat-aligned frequencies** (`pinc` a multiple
  of `2^28`). Otherwise the free-running phase offset rotates the frame (§7.2).
  Use `phrst = 1` when you need phase 0 on beat 0 (§5).
- **The sink is a DAC — always ready.** Model it with `tready` tied high; the
  protocol assertions then stay quiet in normal runs and only a deliberate
  `tready`-drop test needs a bracketed `$assertoff` (§7.4).
- **A guarded capture must gate on `tvalid`.** Reading a fixed number of `s_cb`
  ticks without checking `tvalid` re-reads held/post-burst data as if it were
  fresh — that is what produced a "single-beat burst" mirage mid-campaign.
- **Dump raw, don't fit.** Three different phase models were proposed from output
  values and all three were wrong; a `$display` of the raw captured beats (and of
  the raw write port) settled each question immediately.
- **`-d SVUNIT` must be in `xelab_options`**, or the `axi4_stream_if` protocol
  assertions never compile. When they do fire they can corrupt the SVUnit pass
  counter, so fix assertion failures before trusting anything else.
- **`nsamp` is consumed as a per-cycle countdown**, so a burst is ~`nsamp` beats;
  size stimulus accordingly and confirm the Python `length ↔ nsamp` mapping.

### 8.0 Beat-aligned frequencies are a blind spot

The `phrst` corollary in §5 pushes you towards beat-aligned `pinc` — multiples
of `2^28` — whenever you want to compare against a cosine model, and every
frequency test in this suite does exactly that. The cost is that such a tone
repeats identically every frame, so **no beat-aligned test can see whether the
phase advances correctly from one beat to the next.** §7.6 lived in that gap.

The way out is not to assert absolute phase at all. A sampled cosine obeys

```
x[n-1] + x[n+1] = 2·cos(2π·pinc/2^32) · x[n]
```

for **any** starting phase and **any** amplitude, so it survives pipeline
latency and gain scaling, and it can be evaluated straight across frame
boundaries — which is where a missing beat-to-beat carry breaks it while every
within-frame check still passes. That is what
`tc_frequency_unaligned_across_beats` does, with `pinc = 2^32/24`.

### 8.1 IP-level suite (11/11)

| Test | What |
|------|------|
| `tc_reg_readback` | envelope-writer registers via AXI4-Lite |
| `tc_pure_tone_all_lanes` | DDS-only, all 16 lanes match `cos(i·pinc)` (beat-aligned) |
| `tc_phase_offset` | non-zero descriptor phase shifts every lane |
| `tc_frequency_sweep_exact` | several beat-aligned `pinc`, exact per-lane cosine |
| `tc_modulated_pulse_all_lanes` | product of constant envelope × carrier |
| `tc_envelope_only_all_lanes` | envelope mode, natural `sample s → bank s%16` |
| `tc_gain_scaling` | half gain → half output (ratio, sign cancels) |
| `tc_sat_status_reg` | clamping pulse sets sticky flag; CTRL clears it |
| `tc_gaussian_envelope` | shaped envelope, symmetric, peak centred |
| `tc_fixed_rate_ignores_tready` | production independent of `tready` (bracketed asserts) |
| `tc_carrier_beat_parity` *(diag)* | documents the unaligned-frequency rotation |

Diagnostic dumps (`tc_dump_mem_mapping`, `tc_dump_write_mapping`,
`tc_dump_write_startup`, `tc_dump_phrst_compare`, …) live in a separate probe
file and are informational — keep them out of the pass/fail suite.

---

## 9. Files, build and open items

```
cores/ip/axis_signal_gen_v6/
  README.md                          # this file
  axis_signal_gen_v6.core            # VLNV qick:ip:axis_signal_gen_v6:1.0.0
  hdl/sgv6_top.sv                    # memory subsystem + datapath assembly
  hdl/sgv6.sv                        # per-lane datapath (envelope × DDS, gain, sat)
  hdl/ctrl_sgv6.sv                   # sequencer: FSM, phase gen, alignment pipelines
  hdl/axis_to_bram_sg_nt.sv          # envelope stream → one-hot bank BRAM writer
  tests/axis_signal_gen_v6_tc00.sv   # SVUnit module, clocks, helpers (load_envelope, build_descr)
  tests/axis_signal_gen_v6_tests.sv  # SVTEST suite (11/11)
  tests/axis_signal_gen_v6_probes.sv # diagnostic dumps (informational)
  rdl/                               # TODO
  driver/                            # TODO
  constraints/                       # TODO — 3 async domains + config MCP
depends:
  bram_tdp, fifo_sync, delay_line, cdc_gray_sync
  dds_compiler_signal_gen (Xilinx IP) / dds_compiler_model (sim/lint model)
```

⚠️ Shared building blocks (`bram_tdp`, `fifo_sync`, `delay_line`,
`cdc_gray_sync`) are verified in their own suites; do not re-diagnose them here.

**Open items**

- [ ] ~~Phase pipeline fix (`cnt_n_reg` ungated)~~ — **reverted, see §7.6.** The
      gate is correct; ungating it doubled the output frequency on hardware
- [ ] Make `dds_compiler_model` faithful to the XCI (accumulate low bits AND add
      high bits as offset), after making the tests phase-agnostic — §7.6
- [x] Beat-aligned frequency methodology for value tests
- [x] `phrst` characterised as free-running reference (phrst=0 vs phrst=1 dump)
- [x] Fixed-rate contract test with bracketed AXIS assertions
- [x] Envelope write mapping corrected (`load_envelope` driver; RTL exonerated)
- [x] Amplitude Q15 `[30:15]`, no baseband `>>1`, gain saturation to ±MAXV
- [ ] `make lint IP=axis_signal_gen_v6` (Verible / verilator sweep)
- [ ] XDC: `set_clock_groups -asynchronous` across `s_axi` / `s0_axis` / `aclk`;
      constrain the `WE`/`START_ADDR` config path and the envelope-writer CDC
- [ ] `.rdl` for the envelope-writer registers + driver + pytest
- [ ] IP packaging (`component.xml` + `xgui`); verify AXI4-Stream inference from
      the `s0_axis_*` / `s1_axis_*` / `m_axis_*` port names
- [ ] Confirm the `length ↔ nsamp` (samples vs beats) mapping in the `asm_v2`
      generator manager (the tProc-side descriptor packer — **not** a driver
      `pack_waveform`, which does not exist) and reflect it in the user doc
- [ ] Live-hardware end-to-end (descriptor → envelope → DAC)
```
