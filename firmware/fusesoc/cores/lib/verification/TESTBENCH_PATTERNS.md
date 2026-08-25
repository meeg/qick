**# SVUnit Testbench Patterns — QICK Firmware Verification**

Lessons learned from the verification campaign on `alu_arithmetic_unit`, `alu_bitwise_unit`, `alu`, `timed_ictrl`, `tpv1_ctrl`, `bram_simple_sp`, and `regfile_8p`. These patterns apply to any SVUnit testbench in this repo.

---

**## 1. Clocking Block Timing: outputs drive before the edge, inputs sample after**

All testbenches use:

```systemverilog
default clocking cb @(posedge tb_clk);
default input #1step output #2;
    ...
endclocking
```

Rule: after `@(cb)`, you are **in** the new state — its outputs are already visible. Do not check outputs before the first `@(cb)` of a state.

drive signal        → FSM still in current state
@(cb)               → FSM transitions; new state outputs visible NOW
check outputs       ✓

This is the most common source of off-by-one errors in Moore FSM testbenches.

---

**## 2. Moore FSM: present the opcode/input one cycle before it is needed**

For processors or decoders where an input (e.g. opcode) is latched in state N and used in state N+1, present it **during state N**, not after reaching N+1.

Example from `tpv1_ctrl`: the opcode must be stable during `FETCH_ST` (where `ir_en=1`) so the FSM can dispatch correctly in `DECODE_ST`.

```systemverilog
// WRONG: opcode presented after DECODE_ST is reached
@(cb);              // → DECODE_ST
cb.tb_opcode <= op; // FSM already sampled opcode=0

// CORRECT: opcode presented during FETCH_ST
cb.tb_opcode <= op; // IR load: mirrors hardware ir_en behavior
@(cb);              // → DECODE_ST: FSM sees correct opcode
@(cb);              // → first instruction state: ready to check
```

---

**## 3. Pipeline latency: count register stages, not clock edges**

Every pipeline register between input and output adds one cycle of latency. Count them explicitly before writing helper tasks.

| Module | Latency | Reason |
|--------|---------|--------|
| `alu_arithmetic_unit` | 2 cycles | `din_a_r` → `dout_r` → `dout_rr` |
| `alu_bitwise_unit`    | 2 cycles | same structure |
| `alu` (top)           | 3 cycles | sub-module (2) + `op_rrr` selector alignment (3) |
| `regfile`             | 1 cycle  | synchronous read in `always_ff` |
| `regfile_8p`          | 2 cycles | `regfile` read (1) + `pnum_r` mux (1) |

Read tasks must wait the full latency before sampling:

```systemverilog
// regfile_8p: 2-cycle read latency
task read_reg0(...);
    cb.tb_pnum  <= page;
    cb.tb_addr0 <= addr;
@(cb);   // Cycle 1: regfile clocks addr
@(cb);   // Cycle 2: pnum_r mux resolves
    data = tb_dout0;
endtask
```

---

**## 4. Diagnosing read failures: X vs 0x0000 mean different things**

When a read check fails, the value returned tells you the root cause:

| Got | Meaning | Fix |
|-----|---------|--------|
| Value shifted by one position | A handshake was miscounted: the testbench either sampled a beat it never consumed, or consumed one it never counted | Section 8 — check the ready/valid ordering in the driver tasks, not the DUT |
| Correct data, wrong beat count | `tlast` position or a stranded tail | Section 10 — check `beats.size()`; if the count is short by exactly `NT`, suspect section 16 |
| `0xxxxx` (X/Z) | Memory never initialized; no hardware reset on `mem[]` | Write a known value before reading |
| `0x0000` (all zeros) | Written correctly but sampled too early | Add missing latency cycles in read task |
| Stale value from previous test | Test state leaking between SVUnit tests | Initialize all relevant registers at test start |

`$isunknown()` in the first assertion of each test catches the X case early.

---

**## 5. Memories without reset must be explicitly initialized in tests**

Modules using `logic [B-1:0] mem [N]` (e.g. `regfile`, `bram_simple_sp`) do not reset their array contents — only control registers reset. In simulation, `mem[]` starts as X.

```systemverilog
// WRONG: assumes mem[10] is 0 after reset
read_reg0(0, 10, read_data);
`FAIL_UNLESS_LOG(read_data == 0, "...");  // will see X

// CORRECT: write a known value first
write_reg(0, 10, 16'h0000);
read_reg0(0, 10, read_data);
`FAIL_UNLESS_LOG(read_data == 0, "...");  // reliable
```

When a test needs to verify that a location was _not_ written (e.g. write enable
gating), initialize that location to a known value before the operation under
test, then verify it is unchanged after.

---

**## 6. Concurrent assertions: always use** `disable iff (!rstn)`

Assertions that fire at time zero — before the clocking block has run — will
fail spuriously because signals are X. Guard all concurrent assertions:

```systemverilog
// WRONG: fires at time 0 when signals are X
property zero_a_detect;
@(posedge tb_clk)
    (tb_din_a == '0) |-> (tb_zero_a == 1'b1);
endproperty

// CORRECT
property zero_a_detect;
@(posedge tb_clk) disable iff (!tb_rstn)
    (tb_din_a == '0) |-> (tb_zero_a == 1'b1);
endproperty
```

Exception: properties using `|=>` (non-overlapping implication) are naturally
safe because the consequent evaluates one cycle later, by which time signals are
valid.

---

**## 7. Inter-test state isolation**

SVUnit runs `setup()` / `teardown()` between tests, but hardware state (memory contents, pipeline registers) carries over. Each test should initialize only the state it depends on. Do not assume a fresh device.

The `setup()` task should:
- Assert and deassert reset
- Drive all inputs to safe idle values
- **Not** attempt to initialize memories (too slow for large arrays)

Individual tests are responsible for initializing any memory locations they need to read with predictable values.

---

**## 8. Clocking-block drives land at the** _next_ **clocking event**

A synchronous drive through a clocking block is not visible on the bus at the edge you are standing on. `cb.sig <= v` schedules the drive for the next clocking event plus the output skew. This single fact caused four separate bugs in one campaign.

**The ready-before-valid trap.** A master that samples `ready` before its `valid` has reached the bus can cancel its own beat:

```systemverilog
// WRONG — tx() that drops the beat whenever the slave already holds tready high
m_cb.tdata  <= data;
m_cb.tvalid <= 1'b1;      // scheduled for T1 + skew
do begin
@(m_cb);                // returns at T1; tvalid is NOT on the bus yet
end while (!m_cb.tready); // tready already high -> loop exits immediately
m_cb.tvalid <= 1'b0;      // scheduled for T1 + skew TOO — last write wins
```

Both drives land in the same time slot, `tvalid` never rises, and the beat vanishes silently. Align to the clocking event _before_ driving:

```systemverilog
// CORRECT
@(m_cb);                  // align first
m_cb.tdata  <= data;      // drive lands at T0 + skew
m_cb.tvalid <= 1'b1;
do begin
@(m_cb);                // at T1 the DUT sees tvalid: the sampled ready is real
if (++cnt > timeout) $fatal(1, "[AXIS_FATAL] TX timeout");
end while (!m_cb.tready);
m_cb.tvalid <= 1'b0;      // different slot — no cancellation
```

The same defect appears on the slave side and in AXI4-Lite:

| Task | Symptom | Fix |
|------|---------|-----|
| `tx` / `burst_tx` | beat silently dropped when the DUT holds tready high | align with `@(m_cb)` before driving |
| `rx` | returns a beat that was never consumed; the next call returns it again | one `@(s_cb)` after raising tready |
| `burst_rx` | first beat counted twice — packet length off by exactly one | one `@(s_cb)` after raising tready |
| `axi_write` / `axi_read` | write lost when the slave holds awready/arready high in idle | `do...while` instead of `while` |

The tell for all of these is an off-by-one that is _constant_ and _data-independent_: 2049 beats instead of 2048, every time, in every test. A constant offset is a scheduling bug. A varying one is a logic bug.

---

**## 9. Never mix raw-signal sampling with clocking-block drives**

If you drive a signal through a clocking block, sample everything on that interface through the same clocking block. Reading the raw signal right after `@(cb)` returns puts you in the same delta region in which the DUT is updating it — you get the old value or the new one depending on scheduling order.

```systemverilog
// WRONG — drives tready through s_cb, samples the raw bus
m_axis_if.s_cb.tready <= 1'b1;
while (!m_axis_if.tvalid) @(m_axis_if.s_cb);
word = m_axis_if.tdata;      // races with fifo_dout updating

// CORRECT
m_axis_if.s_cb.tready <= 1'b1;
@(m_axis_if.s_cb);
do @(m_axis_if.s_cb); while (!m_axis_if.s_cb.tvalid);
word = m_axis_if.s_cb.tdata; // sampled #1step before the edge
```

The symptom is a test that passes and an almost identical one that fails, with a value that is neither right nor obviously wrong — often the bus's idle value `0x0000`) rather than the expected payload.

**The one legitimate exception.** Clocking-block _outputs_ cannot be read at all — xsim rejects it with `VRFC 10-3226` — so a task that needs to know whether it is currently asserting `tready` must read the raw signal. This is safe _because_ of the output skew: a signal driven with `output #2` only changes 2 ns after a clocking event, so it is stable at the sampling edge. Write the reason in a comment, or someone will "fix" it later.

**Corollary:** helper functions that expose raw asynchronous reads `sample_tdata`, `sample_tlast`) belong in waveform debugging only. Say so in their docstring. They are a loaded gun pointed at every checker in the repo.

---

**## 10. Single-beat and packet APIs are not interchangeable**

`rx()` consumes one beat and lowers `tready` immediately. Calling it in a loop to drain a packet does **not** work: the deassert at the end of one call and the assert at the start of the next land in the same clocking slot and cancel, so `tready` stays continuously high. The DUT then free-runs at one beat per cycle while the testbench counts one per two, the packet ends mid-loop, and the task dies on a timeout with no explanation.

Use the packet API `burst_rx`) for anything delimited by `tlast`. It holds `tready` for the whole packet and stops on `tlast`, which also makes the returned length a free correctness check:

```systemverilog
m_axis_if.burst_rx(beats);
`FAIL_IF_LOG(beats.size() !== TOTAL_WORDS,
$sformatf("burst had %0d beats, expected %0d (tlast position)",
              beats.size(), TOTAL_WORDS));
```

That one assertion covers early `tlast`, late `tlast`, and dropped beats. It is the single highest-value check in a streaming testbench.

---

**## 11. Park buses in idle** _before_ **reset, not after**

`m_reset()` blocks until `aresetn` is high, so it cannot be what clears `tvalid` during the reset window itself. Anything not explicitly driven sits at X, and X fails `tvalid == 1'b0`.

```systemverilog
task setup();
    svunit_ut.setup();

// Blocking assignments on the raw signals, on purpose: this has to happen
// before reset is asserted, and m_reset() cannot run that early.
    s_axis_if.tvalid = 1'b0;
    s_axis_if.tlast  = 1'b0;
    s_axis_if.tdata  = '0;
    s_axis_if.tstrb  = '1;
    s_axis_if.tkeep  = '0;
    s_axis_if.tuser  = '0;
    m_axis_if.tready = 1'b0;

// ... assert reset, hold, release ...

    s_axis_if.m_reset();   // hand over to the clocking-block driver
endtask
```

Also check what the reset helpers leave behind. A `s_reset()` that ends with `s_cb.tready <= 1'b1` puts the sink in an accepting state the moment reset releases — which, on a DUT that streams on a register write, means a packet can drain into nowhere while the test is busy elsewhere. Prefer explicit idle.

---

**## 12. Run with the protocol assertions on**

The `axi4_stream_if` compliance checkers only compile under `-d SVUNIT`. A suite that has never been run with them is measuring far less than it looks. Turning them on for the first time typically surfaces uninitialised buses (section 11) before it surfaces anything about the DUT.

Two things to know when they fire:

- A concurrent assertion failure **aborts the test** a few cycles later, so everything after it in that test is not executed. A run where every test fails early is usually one root cause, not many.
- The SVUnit pass counter **underflows**. `FAILED (4294966773 of 7 tests passing `is` 2**32 - 523`, i.e. 523 assertion failures. Read the count as a failure tally, not as a test result.

While reviewing the interface's own assertions, check for copy-paste inversions — `(!aresetn && tvalid) |-> ...` instead of `(aresetn && tvalid) |-> ...` disables the check entirely while looking perfectly plausible.

---

**## 13. Escape paths in helper tasks must fail the test**

Every early `return`, `break` and timeout inside a drain or send helper is a path where the test finishes without checking anything. If it only prints, the test goes green.

```systemverilog
// WRONG — a short drain passes silently and leaves beats in the DUT's FIFO
if (++timeout_cnt > 500) begin
$display("[ERROR] drain_burst: tvalid timeout at beat %0d", i);
return;
end
```

This is worse than a plain false pass: for a DUT whose read burst must be consumed in full, a silent short drain contaminates the _next_ test with stale data, and the failure then appears somewhere unrelated. Prefer `$fatal` in interface tasks and `FAIL_IF_LOG` in test code.

---

**## 14. Verify the parametrisation you actually deploy**

A parametrised core verified at one set of parameters tells you nothing about another. `bram_to_axis_nt` was green for months at `NM=8, N=8` and shipped in a bitstream at `NM=2, N=16`, where it lost the last `NT` beats of every burst. The bug needed the producer to barely outrun the consumer; at `NT=8` the margin hid it completely.

Make the deployed configuration a first-class simulation target. With FuseSoC, expose the parameters as `vlogdefine` and add a second target:

```yaml
parameters:
MRBUF_NM: {datatype: int, paramtype: vlogdefine, default: 8}
MRBUF_N:  {datatype: int, paramtype: vlogdefine, default: 8}

targets:
sim: &sim
parameters: [MRBUF_NM, MRBUF_N]
# ...
sim_deployed:
<<: *sim
parameters: [MRBUF_NM=2, MRBUF_N=16]
```

and in the testbench:

```systemverilog
`ifndef MRBUF_NM
`define MRBUF_NM 8
`endif
localparam **int** NM = `MRBUF_NM;
```

The deployed target is slower — a full-depth burst is minutes of wall clock rather than seconds — so run the small configuration per push and the deployed one at merge. When the project's parameters change in Vivado, move `sim_deployed` with them, or it silently stops testing what you think.

---

**## 15. A new test must fail against the old RTL**

After writing a test for a bug you just fixed, revert the fix and confirm the test fails. Two tests written for specific `axis_to_bram_trig` fixes passed against both versions — the failure mode simply was not reachable from the testbench, so the tests were documentation, not verification.

This costs two minutes and is the only thing that distinguishes a regression test from one that just happens to be green.

---

**## 16. Do not retire on a status flag — count the events**

An RTL pattern rather than a testbench one, but it is what the whole campaign came down to, and it is worth recognising in review.

XPM FIFO's `empty` deasserts one to two cycles _after_ a write. An FSM that decides a burst is finished by reading `empty` can retire while its final words are still in flight:

```systemverilog
// WRONG
FIFO_ST: if (!fifo_empty) next_state = FIFO_ST;
else             next_state = END_ST;   // and stream_en drops here
```

The stranded words never come out, and if one of them carries `tlast` the consumer hangs forever. Count the actual strobes instead:

```systemverilog
// CORRECT
always_ff @(posedge clk) begin
if (!rstn)   fifo_level <= '0;
else unique case ({fifo_wr_en, fifo_rd_en})
2'b10:   fifo_level <= fifo_level + 1'b1;
2'b01:   fifo_level <= fifo_level - 1'b1;
default: fifo_level <= fifo_level;
endcase
end

FIFO_ST: if (fifo_level == '0) next_state = END_ST;
```

The generalisation: **status flags are advisory, strobes are authoritative.** Anything that gates a completion decision, a `tlast`, or a handshake should be derived from the event itself. The same reasoning covers `fifo_wr_en` — write on `tvalid && tready`, never on `tvalid` alone, or a stalled cycle duplicates the beat.

---

**## 17. Structure and Scope**

To ensure maintainability and avoid compilation errors in large test suites:

1. **Variable Declarations in `SVTEST`**: Any variable used within a `` `SVTEST(name) ... `SVTEST_END `` block must be declared at the beginning of the block. Do not declare variables in the middle of the test logic.
2. **Helper Function Location**: The `_tests.sv` file must contain only the test cases. Any helper functions (e.g., reference models like `exp_mem` or complex checkers) must be placed in the `_tc00.sv` (or corresponding top-level test) file to avoid multiple-definition errors and keep the test list clean.

---

**## 18. `axil_slv`: always connect `i_reg_is_readonly` explicitly**

`axil_slv.sv` declares `input logic [NUM_REGS-1:0] i_reg_is_readonly = '0`, so it looks safe to leave unconnected when every register is plain `sw=rw`. In xsim it is not: for a parameter-sized vector port, an omitted connection resolves bit 0 to the declared default but leaves the remaining bits floating (`z`), rather than replicating the default across the whole width.

`axil_slv`'s write-enable guard is `!i_reg_is_readonly[reg_idx]`. `!1'bz` evaluates to `1'bx`, and `if (x)` is treated as false — so a write to any register index whose readonly bit floated is silently dropped. Register 0 writes fine (its bit happens to resolve to `0`), which is exactly the trap: a `tc_axi_register_round_trip` test that only checks register 0 passes while every other register is dead.

This was found via four IPs whose round-trip tests failed at the *second* register in the test (`tc_axi_register_round_trip::FAILED` on the second `reg_write`/`reg_read` pair, first one always green): `axis_sg_int4_v2`, `axis_readout_v2`, `axis_sg_mux8_v1`, `axis_sg_mixmux8_v1`. In `axis_sg_int4_v2` this was worse than a failed assertion: the dead register was `WE_REG` (envelope capture enable), so `axis_to_bram_sg`'s FSM never left `INIT_ST`, `s0_axis_tready` never asserted, and the testbench's unbounded `while (!tready)` wait in `load_envelope` spun forever — multi-GB VCD, simulator killed by hand.

```systemverilog
// WRONG — relies on the port default for every bit; only bit 0 gets it in xsim
axil_slv #(.NUM_REGS(NUM_REGS)) axil_slv_i (
    ...
    .o_slv_regs (slv_regs_o),
    .i_slv_regs (slv_regs_o)
);

// CORRECT — tie off explicitly, even when nothing is read-only
axil_slv #(.NUM_REGS(NUM_REGS)) axil_slv_i (
    ...
    .o_slv_regs        (slv_regs_o),
    .i_slv_regs        (slv_regs_o),
    .i_reg_is_readonly ('0)
);
```

The tell: `tc_axi_register_round_trip` (or equivalent) fails on a specific register, not on all of them, and the value read back is the register's *previous* contents (reset value or whatever the last successful write left), not X. If a downstream test hangs instead of failing, check whether the dead register gates a blocking wait in the testbench (a capture/write-enable bit) rather than just a datapath value.
