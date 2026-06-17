// ============================================================================
// File: mr_buffer_et_tests.sv
// Description: SVUnit test cases for mr_buffer_et.
// Included by mr_buffer_et_tc00.sv inside `SVUNIT_TESTS_BEGIN/END.
//
// All register accesses go through axi4_lite_if.axi_write / axi_read, which
// handle the full AXI4-Lite handshake (AW + W + B channels for writes,
// AR + R channels for reads) with timeout protection.
//
// Read-burst protocol — same as mr_buffer:
//   Every start_reader() call produces TOTAL_WORDS = NM * 2**N beats.
//   Always drain all TOTAL_WORDS beats before calling stop_reader().
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 00: Register readback — verify registers initialise to 0 and that a
// write-then-read round-trip works for dw_capture_reg and dr_start_reg.
// ----------------------------------------------------------------------------
`SVTEST(tc00_register_readback)
    logic [C_S_AXI_DW-1:0] rdata;

    // After reset all registers should be 0
    read_reg(REG_DW_CAPTURE, rdata);
    `FAIL_IF_LOG(rdata !== '0,
        $sformatf("tc00: REG_DW_CAPTURE after reset expected 0, got 0x%0h", rdata));

    read_reg(REG_DR_START, rdata);
    `FAIL_IF_LOG(rdata !== '0,
        $sformatf("tc00: REG_DR_START after reset expected 0, got 0x%0h", rdata));

    // Write 1 to dw_capture_reg, read back
    set_capture(1'b1);
    read_reg(REG_DW_CAPTURE, rdata);
    `FAIL_IF_LOG(rdata[0] !== 1'b1,
        $sformatf("tc00: REG_DW_CAPTURE[0] after write expected 1, got 0x%0h", rdata));

    // Clear it
    set_capture(1'b0);
    read_reg(REG_DW_CAPTURE, rdata);
    `FAIL_IF_LOG(rdata[0] !== 1'b0,
        $sformatf("tc00: REG_DW_CAPTURE[0] after clear expected 0, got 0x%0h", rdata));

    // Same for dr_start_reg
    set_start(1'b1);
    read_reg(REG_DR_START, rdata);
    `FAIL_IF_LOG(rdata[0] !== 1'b1,
        $sformatf("tc00: REG_DR_START[0] after write expected 1, got 0x%0h", rdata));
    set_start(1'b0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 01: Basic write/read — one beat captured via AXI-controlled registers,
// ch0 value verified through the full read burst.
// ----------------------------------------------------------------------------
`SVTEST(tc01_basic_write_read)
    logic [B-1:0] first_ch0;

    do_capture(16'hAAAA);

    start_reader();
    drain_burst(first_ch0);
    repeat(10) @(m_axis_if.s_cb);
    stop_reader();

    `FAIL_IF_LOG(first_ch0 !== 16'hAAAA,
        $sformatf("tc01: expected 0xAAAA, got 0x%0h", first_ch0));
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 02: Multiple beats — verify ch0 at consecutive BRAM addresses.
// Send 8 beats with distinct ch0 values, read back and verify in order.
//
// Read protocol with tready held high:
//   tready is asserted once before the loop and held for the full burst.
//   Each iteration waits for tvalid=1 (handshake), captures tdata, then
//   advances one cycle.  No per-beat tready toggling.
// ----------------------------------------------------------------------------
`SVTEST(tc02_multiple_beats)
    localparam int BEATS = 8;
    logic [B-1:0]        expected [BEATS];
    logic [M_DATA_W-1:0] word;
    logic                last;

    for (int i = 0; i < BEATS; i++)
        expected[i] = 16'hAAAA + B'(i);

    arm_and_trigger();

    for (int i = 0; i < BEATS; i++) begin
        $display("[TEST] Enviando beat %0d con ch0=0x%0h at %t", i, expected[i], $time);
        send_beat(expected[i], (i == BEATS-1) ? 1'b1 : 1'b0);
end

    // Wait for FIFO pipeline to drain into BRAM before disarming
    // (axis_to_bram_trig internal FIFO + BRAM write latency ~5 cycles)
    repeat(20) @(s_axis_if.m_cb);

    disarm();  // waits internally for FSM to reach INIT_ST

    // CDC margin from write domain (150 MHz) to read domain (200 MHz)
    repeat(50) @(m_axis_if.s_cb);
    start_reader();
while (!m_axis_if.tvalid) @(m_axis_if.s_cb);
    // Assert tready once and hold for the full burst
    m_axis_if.s_cb.tready <= 1'b1;
    @(m_axis_if.s_cb);  // synchronise to first read-domain edge

    // Verify ch0 at each of the first BEATS addresses
    // Word order: ch0@addr0, ch1@addr0, ..., ch(NM-1)@addr0,
    //             ch0@addr1, ..., ch(NM-1)@addr(BEATS-1), ...
    for (int addr = 0; addr < BEATS; addr++) begin
        for (int ch = 0; ch < NM; ch++) begin
            // Wait for DUT to assert tvalid (stall if needed)
            while (!m_axis_if.tvalid)
                @(m_axis_if.s_cb);

            // Handshake occurred — capture data at this posedge
            word = m_axis_if.tdata;
            last = m_axis_if.tlast;

            if (ch == 0) begin
                `FAIL_IF_LOG(word[B-1:0] !== expected[addr],
                    $sformatf("tc02: addr=%0d ch=0 expected 0x%0h got 0x%0h",
                              addr, expected[addr], word[B-1:0]));
            end

            // Advance to next beat
            @(m_axis_if.s_cb);
        end
    end

    // Drain remaining TOTAL_WORDS - BEATS*NM words to complete the burst
    for (int i = BEATS * NM; i < TOTAL_WORDS; i++) begin
        while (!m_axis_if.tvalid)
            @(m_axis_if.s_cb);
        last = m_axis_if.tlast;
        @(m_axis_if.s_cb);
    end

    // Release tready and verify tlast was on the final word
    m_axis_if.s_cb.tready <= 1'b0;
    `FAIL_IF_LOG(last !== 1'b1,
        "tc02: tlast not asserted on the last word of the burst");

    stop_reader();
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 03: Re-arm — second capture overwrites BRAM addr 0 from a new value.
// Verifies that disarm() via AXI causes the FSM to return to INIT_ST with
// addr_cnt reset, so the next capture starts from address 0.
// ----------------------------------------------------------------------------
`SVTEST(tc03_rearm_second_capture)
    logic [B-1:0] first_ch0;

    // First capture
    do_capture(16'hAAAA);
    start_reader();
    drain_burst(first_ch0);
    stop_reader();
    `FAIL_IF_LOG(first_ch0 !== 16'hAAAA,
        $sformatf("tc03 first: expected 0xAAAA, got 0x%0h", first_ch0));

    // Second capture must overwrite addr 0
    do_capture(16'hBBBB);
    start_reader();
    drain_burst(first_ch0);
    stop_reader();
    `FAIL_IF_LOG(first_ch0 !== 16'hBBBB,
        $sformatf("tc03 second: expected 0xBBBB, got 0x%0h", first_ch0));
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 04: Trigger before arm — stale trigger must not start capture.
// The hardware trigger is ignored when capture_reg=0 (INIT_ST).
// After arming, a fresh trigger is required.
// ----------------------------------------------------------------------------
`SVTEST(tc04_trigger_before_arm_ignored)
    // Stale trigger — capture_reg not yet asserted
    @(posedge s_axis_aclk);
    trigger <= 1'b1;
    @(posedge s_axis_aclk);
    trigger <= 1'b0;
    repeat(3) @(posedge s_axis_aclk);

    // Arm via AXI — FSM goes INIT_ST -> TRIGGER_ST
    set_capture(1'b1);
    repeat(8) @(posedge s_axis_aclk); // CDC settle

    // tready must still be low — FSM in TRIGGER_ST, no fresh trigger yet
    `FAIL_IF_LOG(s_axis_if.tready !== 1'b0,
        "tc04: tready should be low waiting for fresh trigger");

    // Clean up
    set_capture(1'b0);
    repeat(5) @(posedge s_axis_aclk);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 05: tready_force via debug_reg — write debug_reg[1]=1 via AXI and
// verify s_axis_tready is forced high without any capture being active.
// ----------------------------------------------------------------------------
`SVTEST(tc05_tready_force_via_axi)
    // Force tready high via debug_reg[1]
    set_debug(32'h0000_0002);
    repeat(5) @(posedge s_axis_aclk);
    `FAIL_IF_LOG(s_axis_if.tready !== 1'b1,
        "tc05: tready should be forced high by debug_reg[1]");

    // Clear
    set_debug(32'h0000_0000);
    repeat(5) @(posedge s_axis_aclk);
    `FAIL_IF_LOG(s_axis_if.tready !== 1'b0,
        "tc05: tready should return low after clearing debug_reg[1]");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 06: tlast position — verify tlast asserted exactly on word TOTAL_WORDS-1.
// ----------------------------------------------------------------------------
`SVTEST(tc06_tlast_on_last_word)
    logic [M_DATA_W-1:0] word;
    logic                last;
    int                  tlast_count = 0;
    int                  tlast_pos   = -1;

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
