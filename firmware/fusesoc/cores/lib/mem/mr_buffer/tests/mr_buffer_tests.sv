// ============================================================================
// File: mr_buffer_tests.sv
// Description: SVUnit test cases for mr_buffer.
// Included by mr_buffer_tc00.sv inside `SVUNIT_TESTS_BEGIN/END.
//
// Read-burst protocol (IMPORTANT):
//   Every call to start_reader() triggers bram_to_axis_nt to emit exactly
//   TOTAL_WORDS = NM * 2**N beats with tlast=1 on the last beat.
//   The output word order is:
//     word 0         : ch0 @ addr 0
//     word 1         : ch1 @ addr 0
//     ...
//     word NM-1      : ch(NM-1) @ addr 0
//     word NM        : ch0 @ addr 1
//     ...
//     word NM*2**N-1 : ch(NM-1) @ addr (2**N - 1)  <- tlast
//
//   Always consume ALL TOTAL_WORDS beats before calling stop_reader().
//   Interrupting a burst mid-way leaves stale data in the output FIFO which
//   will contaminate the next read burst.
//   Use drain_burst() (defined in mr_buffer_tc00.sv) to do this safely.
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 00: Basic write/read — single beat captured, ch0 value verified
// ----------------------------------------------------------------------------
`SVTEST(tc00_basic_write_read)
    logic [B-1:0] first_word;

    do_capture(16'hAAAA);

    start_reader();
    drain_burst(first_word);
    stop_reader();

    `FAIL_IF_LOG(first_word !== 16'hAAAA,
        $sformatf("tc00: expected 0xAAAA, got 0x%0h", first_word));
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 01: Multiple beats — verify ch0 data at consecutive BRAM addresses
// Send 8 beats with distinct ch0 values, read back and verify the first 8
// words of each read burst (ch0 @ addr 0..7).
// ----------------------------------------------------------------------------
`SVTEST(tc01_multiple_beats)
    localparam int BEATS = 8;
    logic [B-1:0] expected [BEATS];
    logic [B-1:0] word;
    logic         last;

    for (int i = 0; i < BEATS; i++)
        expected[i] = 16'hAAAA + B'(i);

    arm_and_trigger();
    for (int i = 0; i < BEATS; i++)
        send_beat(expected[i], (i == BEATS-1) ? 1'b1 : 1'b0);
    repeat(5) @(s_axis_if.s_cb);
    disarm();
    repeat(20) @(m_axis_if.m_cb);

    start_reader();

    // Read first BEATS*NM words: for each address, ch0 is the first of NM words
    for (int addr = 0; addr < BEATS; addr++) begin
        for (int ch = 0; ch < NM; ch++) begin
            m_axis_if.rx(word, last);
            if (ch == 0) begin
                `FAIL_IF_LOG(word !== expected[addr],
                    $sformatf("tc01: addr=%0d expected 0x%0h got 0x%0h",
                              addr, expected[addr], word));
            end
        end
    end

    // Drain remaining words to complete the burst cleanly
    for (int i = BEATS * NM; i < TOTAL_WORDS; i++)
        m_axis_if.rx(word, last);

    `FAIL_IF(last !== 1'b1);
    stop_reader();
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 02: Re-arm after capture — second capture overwrites BRAM at addr 0
// Verifies that after disarm() the FSM returns to INIT_ST and addr_cnt
// resets to 0, so the next capture overwrites from address 0.
// ----------------------------------------------------------------------------
`SVTEST(tc02_rearm_second_capture)
    logic [B-1:0] first_word;

    // First capture
    do_capture(16'hAAAA);
    start_reader();
    drain_burst(first_word);
    stop_reader();
    `FAIL_IF_LOG(first_word !== 16'hAAAA,
        $sformatf("tc02 first: expected 0xAAAA, got 0x%0h", first_word));

    // Second capture — must overwrite addr 0 with the new value
    do_capture(16'hBBBB);
    start_reader();
    drain_burst(first_word);
    stop_reader();
    `FAIL_IF_LOG(first_word !== 16'hBBBB,
        $sformatf("tc02 second: expected 0xBBBB, got 0x%0h", first_word));
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 03: Trigger ignored before arm — FSM must not capture stale trigger
// A trigger pulse before capture_reg is asserted must be ignored.
// After arming, a fresh trigger is needed to start capture.
// ----------------------------------------------------------------------------
`SVTEST(tc03_trigger_before_arm_ignored)
    // Stale trigger — capture_reg not yet asserted
    @(s_axis_if.s_cb);
    trigger <= 1'b1;
    @(s_axis_if.s_cb);
    trigger <= 1'b0;
    repeat(3) @(s_axis_if.s_cb);

    // Arm — FSM goes INIT_ST -> TRIGGER_ST but the stale pulse has passed
    @(s_axis_if.s_cb);
    dw_capture_reg <= 1'b1;
    repeat(5) @(s_axis_if.s_cb);

    // tready must still be low — FSM is in TRIGGER_ST waiting for a fresh pulse
    `FAIL_IF_LOG(s_axis_if.tready !== 1'b0,
        "tc03: tready should be low while waiting for trigger");

    // Clean up
    @(s_axis_if.s_cb);
    dw_capture_reg <= 1'b0;
    repeat(5) @(s_axis_if.s_cb);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 04: capture_reg=0, no trigger — tready stays low (no force)
// ----------------------------------------------------------------------------
`SVTEST(tc04_no_capture_no_tready)
    // Ensure tready_force is off
    `FAIL_IF(debug_reg[1] !== 1'b0);

    repeat(10) @(s_axis_if.s_cb);
    `FAIL_IF_LOG(s_axis_if.tready !== 1'b0,
        "tc04: tready should be low when capture is disabled");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 05: tready_force override (debug_reg[1])
// With capture disabled, debug_reg[1]=1 must force s_axis_tready high.
// ----------------------------------------------------------------------------
`SVTEST(tc05_tready_force_override)
    @(s_axis_if.s_cb);
    debug_reg[1] <= 1'b1;
    repeat(3) @(s_axis_if.s_cb);
    `FAIL_IF_LOG(s_axis_if.tready !== 1'b1,
        "tc05: tready should be forced high by debug_reg[1]");

    @(s_axis_if.s_cb);
    debug_reg[1] <= 1'b0;
    repeat(3) @(s_axis_if.s_cb);
    `FAIL_IF_LOG(s_axis_if.tready !== 1'b0,
        "tc05: tready should return low after clearing debug_reg[1]");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 06: tlast on the last word of the read burst
// Verify that tlast is asserted exactly on word TOTAL_WORDS-1 and not before.
// ----------------------------------------------------------------------------
`SVTEST(tc06_tlast_on_last_word)
    logic [B-1:0] word;
    logic         last;
    int           tlast_count = 0;
    int           tlast_pos   = -1;

    do_capture(16'hCCCC);

    start_reader();
    for (int i = 0; i < TOTAL_WORDS; i++) begin
        m_axis_if.rx(word, last);
        if (last) begin
            tlast_count++;
            tlast_pos = i;
        end
    end
    stop_reader();

    `FAIL_IF_LOG(tlast_count !== 1,
        $sformatf("tc06: expected 1 tlast, got %0d", tlast_count));
    `FAIL_IF_LOG(tlast_pos !== TOTAL_WORDS - 1,
        $sformatf("tc06: tlast at word %0d, expected %0d",
                  tlast_pos, TOTAL_WORDS - 1));
`SVTEST_END