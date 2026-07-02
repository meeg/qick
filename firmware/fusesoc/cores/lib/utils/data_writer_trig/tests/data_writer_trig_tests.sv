// ============================================================================
// File: data_writer_trig_tests.sv
// Description: SVUnit test cases for data_writer_trig.
// Included by data_writer_trig_tc00.sv.
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 01: Reset — no writes, no tready
// ----------------------------------------------------------------------------
`SVTEST(test_reset_no_write)
    repeat(5) @(cb);
    `FAIL_IF(tb_mem_we);
    `FAIL_IF(tb_s_axis_tready);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 02: capture_reg=0 — FSM stays in INIT_ST, trigger ignored
// ----------------------------------------------------------------------------
`SVTEST(test_no_capture_reg_ignores_trigger)
    pulse_trigger();
    repeat(10) @(cb);
    `FAIL_IF(tb_mem_we);
    `FAIL_IF(tb_s_axis_tready);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 03: Armed but no trigger — tready stays low (TRIGGER_ST)
// ----------------------------------------------------------------------------
`SVTEST(test_armed_no_trigger_no_tready)
    arm();
    repeat(10) @(cb);
    `FAIL_IF(tb_s_axis_tready); // FIFO not being filled → tready=0
    `FAIL_IF(tb_mem_we);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 04: Full capture — exactly DEPTH writes with correct addresses
// After trigger: stream DEPTH samples, verify all DEPTH addresses 0..DEPTH-1
// are written exactly once.
// ----------------------------------------------------------------------------
`SVTEST(test_full_capture_addresses)
    logic [N-1:0] addr_out[];
    logic [B-1:0] data_out[];
    int got;

    arm();
    pulse_trigger();

    fork
        stream_data(DEPTH, 16'h0001);
        capture_writes(DEPTH, addr_out, data_out, got, 300);
    join

    if (got !== DEPTH) begin
        $display("[FAIL] test_full_capture_addresses: got %0d writes, expected %0d", got, DEPTH);
        `FAIL_IF(1);
    end

    for (int i = 0; i < DEPTH; i++) begin
        if (addr_out[i] !== N'(i)) begin
            $display("[FAIL] test_full_capture_addresses: addr[%0d]=0x%0h expected 0x%0h",
                     i, addr_out[i], N'(i));
            `FAIL_IF(1);
        end
    end
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 05: Full capture — data integrity
// Verify mem_di matches injected data in order.
// ----------------------------------------------------------------------------
`SVTEST(test_full_capture_data)
    logic [N-1:0] addr_out[];
    logic [B-1:0] data_out[];
    int got;

    arm();
    pulse_trigger();

    fork
        stream_data(DEPTH, 16'h0010);
        capture_writes(DEPTH, addr_out, data_out, got, 300);
    join

    for (int i = 0; i < DEPTH; i++) begin
        logic [B-1:0] expected = B'(16'h0010 + i);
        if (data_out[i] !== expected) begin
            $display("[FAIL] test_full_capture_data: data[%0d]=0x%0h expected 0x%0h",
                     i, data_out[i], expected);
            `FAIL_IF(1);
        end
    end
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 06: FSM stops after DEPTH writes — extra stream data ignored
// Send 2*DEPTH samples, verify only DEPTH writes occur.
// ----------------------------------------------------------------------------
`SVTEST(test_stops_at_depth)
    logic [N-1:0] addr_out[];
    logic [B-1:0] data_out[];
    int got;
    int extra_writes = 0;

    arm();
    pulse_trigger();

    fork
        stream_data(DEPTH * 2, 16'h0001);
        capture_writes(DEPTH, addr_out, data_out, got, 300);
    join_any

    disable fork; // stop capture_writes if it hasn't already

    // After DEPTH writes FSM is in END_ST — monitor for extra writes
    repeat(20) @(cb) begin
        if (tb_mem_we) extra_writes++;
    end

    `FAIL_IF(extra_writes > 0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 07: Re-arm after capture — FSM can perform a second capture
// ----------------------------------------------------------------------------
`SVTEST(test_rearm_second_capture)
    logic [N-1:0] addr_out[];
    logic [B-1:0] data_out[];
    int got;

    // First capture
    arm();
    pulse_trigger();
    fork
        stream_data(DEPTH, 16'hAAAA);
        capture_writes(DEPTH, addr_out, data_out, got, 300);
    join

    // Disarm and re-arm
    disarm();
    arm();
    pulse_trigger();

    // Second capture
    fork
        stream_data(DEPTH, 16'hBBBB);
        capture_writes(DEPTH, addr_out, data_out, got, 300);
    join

    if (got !== DEPTH) begin
        $display("[FAIL] test_rearm_second_capture: got %0d writes on second capture", got);
        `FAIL_IF(1);
    end

    // Verify second capture data
    for (int i = 0; i < DEPTH; i++) begin
        logic [B-1:0] expected = B'(16'hBBBB + i);
        if (data_out[i] !== expected) begin
            $display("[FAIL] test_rearm_second_capture: data[%0d]=0x%0h expected 0x%0h",
                     i, data_out[i], expected);
            `FAIL_IF(1);
        end
    end
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 08: Trigger before capture_reg — trigger must be ignored
// Assert trigger first, then arm — capture must not start from stale trigger.
// ----------------------------------------------------------------------------
`SVTEST(test_trigger_before_arm_ignored)
    int early_writes = 0;

    // Trigger before arming
    pulse_trigger();
    repeat(5) @(cb);

    // Now arm — FSM goes to TRIGGER_ST, needs a fresh trigger
    arm();

    // Monitor: no writes should occur without a new trigger
    repeat(15) @(cb) begin
        if (tb_mem_we) early_writes++;
    end

    `FAIL_IF(early_writes > 0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 09: Reset during capture — stops all writes
// ----------------------------------------------------------------------------
`SVTEST(test_reset_during_capture)
    int writes_after_reset = 0;

    arm();
    pulse_trigger();

    // Send a few samples then reset
    cb.tb_s_axis_tvalid <= 1'b1;
    cb.tb_s_axis_tdata  <= 16'h1234;
    repeat(4) @(cb);

    cb.tb_rstn          <= 1'b0;
    cb.tb_s_axis_tvalid <= 1'b0;
    repeat(5) @(cb);
    cb.tb_rstn <= 1'b1;
    repeat(5) @(cb);

    repeat(10) @(cb) begin
        if (tb_mem_we) writes_after_reset++;
    end

    `FAIL_IF(writes_after_reset > 0);
    `FAIL_IF(tb_s_axis_tready);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 10: mem_en always asserted during capture
// ----------------------------------------------------------------------------
`SVTEST(test_mem_en_during_capture)
    logic [N-1:0] addr_out[];
    logic [B-1:0] data_out[];
    int got;
    int en_deasserted = 0;

    arm();
    pulse_trigger();

    fork
        stream_data(DEPTH, 16'h0001);
        begin
            // Monitor mem_en during capture window
            repeat(DEPTH + 10) @(cb) begin
                if (tb_mem_we && !tb_mem_en)
                    en_deasserted++;
            end
        end
        capture_writes(DEPTH, addr_out, data_out, got, 300);
    join

    `FAIL_IF(en_deasserted > 0);
`SVTEST_END
