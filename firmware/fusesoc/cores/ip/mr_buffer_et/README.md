# Multi-Rate Buffer with External Trigger (mr_buffer_et)

Multi-channel, multi-rate capture buffer with an AXI4-Lite configuration port,
an armed/externally-triggered write side, and a streamed read-out on a second,
independent clock domain. Captures `NM` parallel channels of `B` bits each into
`NM` independent true-dual-port BRAMs, then serializes the whole window out as
a single AXI4-Stream burst.

- Project: **TBD** (please confirm — CONTROLLERS? DAQ/ACQ?)
- VLNV: core `qick:mem:mr_buffer:1.0.0` · wrapper `qick:ip:mr_buffer_et:1.2.0`
  (both confirmed from `fusesoc run` output)
- Author: `@lharnaldi` (assumed, matching `axis_iq_offset` — please confirm)
- Target: **zcu216** (confirmed — deployed bitfile path
  `.../firmware/Top/216/phase_ctrl_sys_dma/...`)
- Status: **core 7/7 SVUnit · wrapper 7/7 SVUnit · driver pytest 4/4 · XDC
  (3 async domains) · both lint-clean (Verilator) · live-hardware capture
  confirmed working end-to-end (see §4).** IP packaging (`component.xml`)
  not yet confirmed (see §6 Open items).

---

## 1. Overview

```
                 trigger ──CDC(cdc_gray_sync)──► trigger_resync (s_axis_aclk domain)
                    │
  s_axis (NM*B, s_axis_aclk) ──► [ NM × axis_to_bram_trig ] ──► [ NM × bram_tdp (true dual-port) ]
                                        armed by dw_capture_reg_resync                │ port B
                                                                                       ▼
                                                          [ bram_to_axis_nt ] ──► m_axis (B, m_axis_aclk)
                                                          armed by dr_start_reg_resync

  AXI4-Lite (s_axi_aclk) ──► dw_capture_reg / dr_start_reg / debug_reg
                         ◄── capture_done (STATUS, CDC'd back via cdc_bit_sync)
```

Typical use (loop-settling / snapshot capture over DMA):
1. SW writes `dw_capture=1` → arms the writer (all `NM` channel writers armed
   together).
2. `trigger` (external, asynchronous) fires → each BRAM fills with `2**N`
   samples/channel at full write-side rate.
3. SW writes `dr_start=1` → drains the whole captured window out `m_axis` as
   one burst.
4. Downstream (e.g. AXI-DMA S2MM) consumes `NM*2**N` beats, ending in `tlast`.

**Three clock domains**, all independent:
- `s_axi_aclk` — AXI4-Lite config
- `s_axis_aclk` — write/capture datapath (full-rate, e.g. 307.2 MHz)
- `m_axis_aclk` — read/drain datapath (e.g. 99 MHz, matched to DMA/HP port)

### 1.1 Output word order (read burst)
`TOTAL_WORDS = NM * 2**N` words per burst, `tlast` on the final beat:
```
word 0            : ch0 @ addr 0
word 1            : ch1 @ addr 0
...
word NM-1         : ch(NM-1) @ addr 0
word NM           : ch0 @ addr 1
...
word NM*2**N - 1  : ch(NM-1) @ addr (2**N - 1)   ← tlast here
```
⚠️ Every `start_reader()` (i.e. every `dr_start` pulse) starts a burst of
exactly `TOTAL_WORDS` beats. The whole burst must be consumed before the next
`dr_start`, otherwise the following read sees stale data left in the output
path from the previous incomplete burst.

⚠️ The read side always drains the **entire** window (all `NM` channels, all
`2**N` addresses) — there is no partial-channel or partial-address readout.

---

## 2. Core: `mr_buffer`

### 2.1 Parameters
| Param | Default | Meaning                                    |
|-------|---------|---------------------------------------------|
| `NM`  | 8       | Number of memories / parallel channels       |
| `N`   | 8       | Address width per BRAM → depth = `2**N` = 256|
| `B`   | 16      | Data width per BRAM (bits)                    |

With defaults: `TOTAL_WORDS = 8 * 256 = 2048` words/burst, `s_axis_tdata` is
`NM*B = 128` bits wide, `m_axis_tdata` is `B = 16` bits wide.

### 2.2 Ports
```
trigger                                    // async, will be CDC'd to s_axis_aclk

s_axis_aclk, s_axis_aresetn
s_axis_tready
s_axis_tdata   [NM*B-1:0]
s_axis_tstrb   [(NM*B/8)-1:0]
s_axis_tlast
s_axis_tvalid

m_axis_aclk, m_axis_aresetn
m_axis_tvalid
m_axis_tdata   [B-1:0]
m_axis_tstrb   [(B/8)-1:0]
m_axis_tlast
m_axis_tready

dw_capture_reg   // already sync'd to s_axis_aclk by caller/CDC upstream? (see note)
dr_start_reg     // already sync'd to m_axis_aclk by caller/CDC upstream? (see note)
debug_reg  [31:0]  // [0]=force trigger, [1]=force s_axis_tready

s_dbg_probe [31:0]
m_dbg_probe [31:0]
o_capture_done
```

> Note on `dw_capture_reg` / `dr_start_reg`: despite the port comment implying
> these arrive pre-synchronized, the **core itself** re-synchronizes them
> internally with its own `cdc_gray_sync` instances (`sync_dw_capture`,
> `sync_dr_start`), i.e. these inputs are treated as arriving from an
> unrelated (AXI-Lite) clock domain and are re-timed to `s_axis_aclk` /
> `m_axis_aclk` respectively before use. Same treatment for `trigger`
> (`sync_trigger`, `N=2, M=1`), combined first with the debug force bit:
> `trigger_or_dbg = trigger | debug_reg[0]`.

### 2.3 Internal architecture
- **Per-channel write path** (`generate` over `NM`): each channel gets its own
  `axis_to_bram_trig` (arms on `dw_capture_reg_resync`, starts capturing on
  `trigger_resync`, writes BRAM port A) driving a `bram_tdp` (true dual-port
  BRAM, depth `2**N`, width `B`).
- `s_axis_tready = (&s_axis_tready_i) | s_axis_tready_force` — the input is
  only accepted once **every** channel's writer is ready, OR'd with the debug
  force bit (`debug_reg[1]`).
- `o_capture_done = &cap_done_ch` — AND-reduction of every channel's
  `axis_to_bram_trig.o_capture_done`; the whole capture is "done" only once
  every channel has finished.
- **Read path**: all `NM` BRAM port-B outputs are concatenated (`dob_c`,
  `NM*B` bits) and fed to a single `bram_to_axis_nt` instance, which serializes
  the full window (all channels, all addresses) onto `m_axis` per §1.1's word
  order, armed by `dr_start_reg_resync`.
- **Debug probes**: `s_dbg_probe`/`m_dbg_probe` pack a handful of write-/
  read-side status bits plus the low byte of data/address/write-data for ILA
  use (see RTL comments for exact bit layout — unchanged from the legacy VHDL
  probe format).

### 2.4 Sub-cores referenced (not covered by this doc — document separately if needed)
- `cdc_gray_sync #(.N, .M)` — CDC synchronizer, gray-coded, `N`=stages,
  `M`=width. VLNV `qick:cdc:cdc_gray_sync:1.0.0`.
- `axis_to_bram_trig #(.N, .B)` — per-channel triggered AXI4-Stream → BRAM
  writer. VLNV `qick:axi:axis_to_bram_trig:1.0.0`. **Contains an internal
  `fifo_sync` (XPM sync FIFO)** between the AXI4-Stream input and the BRAM
  write port (confirmed by sim hierarchy:
  `gen_channel[i].u_axis_to_bram_trig.fifo_i.xpm_fifo_sync_inst...`) — not a
  direct combinational/registered write path as assumed earlier.
- `bram_tdp #(.NB_ADDR, .NB_DATA)` — true dual-port BRAM wrapper. VLNV
  `qick:mem:bram_tdp:1.0.0`.
- `bram_to_axis_nt #(.NT, .N, .B)` — multi-BRAM → single AXI4-Stream reader
  (`NT` = number of tiled memories). VLNV `qick:axi:bram_to_axis_nt:1.0.0`.
  **Also contains an internal `fifo_sync`** (`u_bram_to_axis_nt.fifo_i...`)
  on the read/output side.
- Both FIFOs depend on `qick:mem:fifo_sync:1.0.0` and `qick:interfaces:bram_if:0.1.0`.

### 2.5 Verification (core — 7/7 SVUnit, lint-clean)
Run: `make lint IP=mr_buffer` · `make sim IP=mr_buffer`. Two sim clocks:
150 MHz and 200 MHz (write-side / read-side datapath testbench clocks).

| Test | What (name-inferred) | Result |
|------|------------------------|--------|
| tc00 basic_write_read        | single arm→trigger→capture→drain round trip     | PASS |
| tc01 multiple_beats          | multi-beat write burst captured correctly        | PASS |
| tc02 rearm_second_capture    | arm/trigger/drain, then re-arm for a 2nd capture | PASS |
| tc03 trigger_before_arm_ignored | a trigger arriving before `dw_capture` is armed has no effect | PASS |
| tc04 no_capture_no_tready    | writer not armed → `s_axis_tready` stays deasserted (no false accept) | PASS |
| tc05 tready_force_override   | `debug_reg[1]` forces `s_axis_tready=1` regardless of arm state | PASS |
| tc06 tlast_on_last_word      | `m_axis_tlast` asserted exactly on the final beat of the `TOTAL_WORDS` burst | PASS |

> Test names are inferred from the SVUnit log identifiers; exact per-test
> assertions not independently reviewed (test source not provided).

---

## 3. Wrapper: `mr_buffer_et`

AXI4-Lite configuration wrapper around `mr_buffer`, adding the third
(`s_axi_aclk`) clock domain and register-mapped control/status.

### 3.1 CDC (config `s_axi_aclk` → datapath domains)
- `dw_capture_reg` (from `slv_regs_o[0][0]`) is passed straight into the core,
  where it is re-synchronized to `s_axis_aclk` by the core's own
  `cdc_gray_sync` (see §2.2 note) — **no separate CDC in the wrapper**.
- `dr_start_reg` (from `slv_regs_o[1][0]`) — same: passed through, core
  re-syncs to `m_axis_aclk` internally.
- `debug_reg` (`slv_regs_o[15]`) — passed through combinationally, consumed by
  the core in whichever domain it's used (`debug_reg[0]` in `s_axis_aclk` via
  `trigger_or_dbg`, `debug_reg[1]` in `s_axis_aclk` for `tready` force). Not
  independently CDC'd — relies on `debug_reg` being quasi-static (a debug-only
  register, not toggled during normal operation).
- **STATUS read-back**: `capture_done` (core, `s_axis_aclk` domain, named
  `capture_done_s`) is brought back to `s_axi_aclk` via a dedicated
  `cdc_bit_sync #(.NB(1))` (`u_sync_cap_done`) before being exposed as
  `STATUS[0]`.

⚠️ Unlike `axis_iq_offset`'s toggle+load scheme for multi-bit buses, there is
no multi-bit config value here needing MCP handling — every AXI-Lite-writable
field is single-bit (`dw_capture`, `dr_start`, and the two debug bits), so
per-bit `cdc_gray_sync`/passthrough is sufficient.

### 3.2 Register map (confirmed from `mr_buffer_et_regmap.rdl`; `NUM_REGS = 16`,
`C_S_AXI_DW = 32`, `C_S_AXI_AW = 6` → addressable range `0x00`–`0x3C`, `compact`
addressing)

| Addr | Reg name        | Field(s)                          | R/W | Notes                              |
|------|------------------|------------------------------------|-----|-------------------------------------|
| 0x00 | `DW_CAPTURE_REG` | `DW_CAPTURE`[0:0]                   | RW  | write 1 to **ARM** the writer; next trigger fills all `NM` BRAMs starting at addr 0. Write 0 to **re-arm** — this also clears `STATUS.CAPTURE_DONE`. |
| 0x04 | `DR_START_REG`   | `DR_START`[0:0]                      | RW  | write 1 to drain the captured window as one `NM*2**N`-beat burst (`tlast` on final beat). Consume **all** beats before writing 0. |
| 0x08 | `STATUS_REG`     | `CAPTURE_DONE`[0:0]                  | RO  | high once every channel has finished capturing; CDC'd from `s_axis_aclk`→`s_axi_aclk` via `cdc_bit_sync`; clears on `DW_CAPTURE` deassert (re-arm). |
| 0x0C–0x38 | (unmapped in `.rdl`, reg[3..14] in HW) | —              | RO  | reads 0                            |
| 0x3C | `DEBUG_REG`      | `FORCE_TRIGGER`[0:0], `FORCE_TREADY`[1:1] | RW | `FORCE_TRIGGER` OR-ed with the external `trigger`; `FORCE_TREADY` forces `s_axis_tready` high. Debug/bring-up only. |

`axil_slv` instantiated with `RO_MASK = 16'b0000_0000_0000_0100` (only
reg[2]/STATUS is read-only) — same `axil_slv` component used across the repo
(see `axis_iq_offset` README §3.4 for the general signature convention).

### 3.3 Debug output gating
`s_dbg_probe`/`m_dbg_probe` top-level outputs are only driven from the core's
internal probes when the `DEBUG` parameter is `1`; otherwise tied to `0`
(`generate`/`gen_debug` vs `gen_ndebug`).

### 3.4 Verification (wrapper — 7/7 SVUnit, lint-clean)
Run: `make lint IP=mr_buffer_et` · `make sim IP=mr_buffer_et`. Three sim
clocks: 100 MHz (`s_axi_aclk`), 150 MHz and 200 MHz (write-side/read-side
datapath), confirming the wrapper TB exercises all three clock domains.

| Test | What (name-inferred) | Result |
|------|------------------------|--------|
| tc00 register_readback        | AXI-Lite write + read-back across the register map | PASS |
| tc01 basic_write_read         | end-to-end arm→trigger→capture→drain through AXI-Lite control | PASS |
| tc02 multiple_beats           | multi-beat capture through the wrapper (log shows per-beat data driven, e.g. ch0 = 0xaaaa…0xaab1) | PASS |
| tc03 rearm_second_capture     | re-arm and capture a second window via AXI-Lite | PASS |
| tc04 trigger_before_arm_ignored | trigger before `CAPTURE.dw_capture` is written has no effect | PASS |
| tc05 tready_force_via_axi     | `DEBUG` register forces `s_axis_tready` via AXI-Lite | PASS |
| tc06 tlast_on_last_word       | `m_axis_tlast` on the correct final beat, driven through the wrapper | PASS |

> Test names are inferred from the SVUnit log identifiers; exact per-test
> assertions not independently reviewed (test source not provided). STATUS
> (`capture_done`) CDC correctness is presumably covered by tc00/tc01 but not
> confirmed as a dedicated CDC-latency test.

### 3.5 Driver (pytest 4/4)
`make driver-test IP=mr_buffer_et` → PeakRDL-generated Python register model
(`mr_buffer_et_regmap_pkg/`) + `qick.ip.SocIP`-based driver class:

- Class `MrBufferEt(SocIP)`, `bindto = ['qick:ip:mr_buffer_et:1.2']` (matches
  major.minor only — patch version `1.2.0` not part of the bind string, same
  convention presumably used by other QICK drivers).
- Register access via `.regs` (a `RegModel` built in `_init_firmware()`, wired
  to `self.mmio` — works for both a raw PYNQ `Overlay` and `QickSoc`), e.g.
  `ip.regs.DW_CAPTURE_REG.DW_CAPTURE.write(1)`,
  `ip.regs.STATUS_REG.CAPTURE_DONE.read()`.
- `_hw_read`/`_hw_write` map straight to `self.mmio.read`/`.write`;
  `_hw_read_block`/`_hw_write_block` loop over 4-byte-strided addresses (used
  by PeakRDL for any multi-register block access, not needed for this regmap
  since every register here is independent).
- No hand-written high-level convenience methods yet (file ends at the
  `regs` property in what was shared — confirm if there's more below that).

Pytest (`cores/ip/mr_buffer_et/driver/tests/test_mr_buffer_et_regs.py`):

| Test | Result |
|------|--------|
| `test_reset_values`          | PASS |
| `test_register_offsets`      | PASS |
| `test_field_roundtrip`       | PASS |
| `test_register_independence` | PASS |

### 3.6 XDC (3 async domains)
- `constraints/mr_buffer_et.xdc` (scoped): a single
  `set_clock_groups -asynchronous` across all three clocks (`s_axi_aclk`,
  `s_axis_aclk`, `m_axis_aclk`) covers every cross-domain path — including the
  true-dual-port BRAM write↔read port pair inside `bram_tdp` — on the strength
  of the `ASYNC_REG`-tagged synchronizer cells (`cdc_gray_sync` inside
  `mr_buffer` for `dw_capture`/`dr_start`/`trigger`/BRAM gray pointers,
  `cdc_bit_sync` in the wrapper for `capture_done`). Also `set_false_path -from
  [get_ports trigger*]` — the external HW trigger is asynchronous by
  construction and handled entirely by `sync_trigger`.
  ⚠️ Note this is a coarser approach than `axis_iq_offset`'s XDC (which adds
  scoped `set_max_delay -datapath_only` to each individual synchronizer cell on
  top of the clock-group declaration) — here the design relies on the
  `-asynchronous` clock-group declaration alone plus `ASYNC_REG` properties on
  the sync cells. Worth confirming this is the intended/sufficient constraint
  strategy for this core (vs. an omission).
- `constraints/mr_buffer_et_ooc.xdc`: OOC placeholder clocks for standalone
  synthesis — `s_axi_aclk` period 10.000 ns, `s_axis_aclk` period 3.255 ns
  (307.2 MHz), `m_axis_aclk` period 10.000 ns. Note: a 10.000 ns period is
  **100.000 MHz** exactly; the file's own comment labels these clocks
  "~99 MHz placeholder" — minor label/value mismatch, doesn't affect the
  constraint itself (100 MHz vs 99 MHz is conservative either way for OOC
  timing closure) but worth a one-line fix if it matters for documentation
  accuracy elsewhere.

---

## 4. PYNQ / QICK usage (confirmed on hardware — zcu216)

Real driver import path: `qick.drivers.mr_buffer_et.MrBufferEt` (and, for
comparison, `qick.drivers.axis_iq_offset.AxisIqOffset` — instantiated as
`soc.axis_iq_offset_I` / `soc.axis_iq_offset_Q`, one per I/Q lane).

```python
from qick import QickSoc
from qick.drivers.mr_buffer_et import MrBufferEt
import numpy as np, time
from pynq import allocate

soc = QickSoc(bitfile=BIT, no_tproc=True)
mr, dma = soc.mr_buffer_et_0, soc.axi_dma_mon

N_SAMP, NCH = 1 << 16, 2                      # this deployed instance: NM=2, N=16
buf = allocate(shape=(NCH*N_SAMP,), dtype=np.int16)

# defensive reset before arming
mr.regs.DR_START_REG.DR_START.write(0)
mr.regs.DW_CAPTURE_REG.DW_CAPTURE.write(0)
time.sleep(0.01)

mr.regs.DW_CAPTURE_REG.DW_CAPTURE.write(1)     # arm
mr.regs.DEBUG_REG.FORCE_TRIGGER.write(1)       # software trigger (pulse)
mr.regs.DEBUG_REG.FORCE_TRIGGER.write(0)

t0 = time.time()
while mr.regs.STATUS_REG.CAPTURE_DONE.read() == 0:
    if time.time() - t0 > 2.0: raise TimeoutError("no CAPTURE_DONE")

# IMPORTANT ordering: arm the DMA receive *before* pulsing DR_START
dma.recvchannel.transfer(buf)
mr.regs.DR_START_REG.DR_START.write(1)
dma.recvchannel.wait()
mr.regs.DR_START_REG.DR_START.write(0)
mr.regs.DW_CAPTURE_REG.DW_CAPTURE.write(0)     # re-arm/reset for next capture

data = np.array(buf)
I, Q = data[0::2], data[1::2]                  # interleaved I/Q, per §1.1 word order
```

⚠️ This deployed instance is parameterized `NM=2` (I/Q pair, not the RTL's
default `NM=8`), `N=16` (depth `2**16 = 65536`, not the default `N=8`) — the
`TOTAL_WORDS = NM*2**N` formula and word-order from §1.1 still hold, just with
these instance-specific parameters. Confirms `mr_buffer`/`mr_buffer_et` are
used as a general-purpose parameterized buffer, not fixed at the RTL defaults.

---

## 5. Files (paths assumed by FuseSoC convention — confirm exact layout)
```
cores/.../mr_buffer/
  README.md                  # this file
  hdl/mr_buffer.sv            # ✅ RTL present
  mr_buffer.core              # ✅ VLNV qick:mem:mr_buffer:1.0.0 (fusesoc-confirmed)
  tests/                      # ✅ SVUnit, 7/7 PASS (tc00..tc06, see §2.5)
  model/                      # ⬜ TBD (Python golden model?)
cores/ip/mr_buffer_et/
  hdl/mr_buffer_et.sv          # ✅ RTL present, VLNV qick:ip:mr_buffer_et:1.2.0
  mr_buffer_et.core            # ✅ fusesoc-confirmed
  tests/                       # ✅ SVUnit, 7/7 PASS (tc00..tc06, see §3.4)
  rdl/mr_buffer_et_regmap.rdl        # ✅ 4 regs (DW_CAPTURE/DR_START/STATUS/DEBUG)
  rdl/mr_buffer_et_regmap_pkg/       # ✅ generated (PeakRDL-python)
  driver/mr_buffer_et.py             # ✅ MrBufferEt(SocIP), bindto qick:ip:mr_buffer_et:1.2
  driver/tests/test_mr_buffer_et_regs.py  # ✅ pytest 4/4
  constraints/mr_buffer_et.xdc       # ✅ scoped, 3 async domains + false path on trigger
  constraints/mr_buffer_et_ooc.xdc   # ✅ OOC placeholder clocks (100 / 307.2 / 100 MHz)
```

## 6. Open items
- [x] core RTL (`mr_buffer.sv`) — VLNV `qick:mem:mr_buffer:1.0.0`
- [x] wrapper RTL (`mr_buffer_et.sv`, AXI4-Lite + CDC) — VLNV `qick:ip:mr_buffer_et:1.2.0`
- [x] core lint (Verilator, clean) + SVUnit sim (7/7 PASS)
- [x] wrapper lint (Verilator, clean) + SVUnit sim (7/7 PASS)
- [x] `.rdl` (4 regs) + PeakRDL driver + pytest (4/4 PASS)
- [x] XDC (scoped, 3 async domains + OOC placeholder clocks)
- [x] target confirmed: zcu216
- [x] live-hardware end-to-end capture confirmed (arm → force-trigger →
      capture-done → DMA drain), see §4
- [ ] confirm Project grouping / Author
- [ ] confirm whether `mr_buffer_et.xdc`'s clock-group-only CDC strategy
      (no per-cell `set_max_delay -datapath_only`) is intentional vs.
      `axis_iq_offset`'s more granular approach (see §3.6 note)
- [ ] get/review actual SVUnit test source (`tests/*.sv`) to confirm the
      per-test assertions behind the inferred names above
- [ ] IP packaging (`component.xml` + `xgui`)
- [ ] document `axis_to_bram_trig` (incl. its internal `fifo_sync`),
      `bram_tdp`, `bram_to_axis_nt` (incl. its internal `fifo_sync`),
      `cdc_gray_sync`, `cdc_bit_sync` sub-cores if not already documented
      elsewhere
