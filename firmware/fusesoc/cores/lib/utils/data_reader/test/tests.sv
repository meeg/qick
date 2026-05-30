// ============================================================================
// File: tests.sv
// Description: Test suite for data_reader module.
// Included inside SVUNIT_TESTS_BEGIN/END — no task/function declarations here.
// All helper tasks are defined in data_reader_tc00.sv (module scope).
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 00: Single word read
// ----------------------------------------------------------------------------
`SVTEST(test_single_word)
    logic [B-1:0] expected[1];
    logic [B-1:0] actual[];

    expected[0] = B'(5);
    start_reader(N'(5), N'(1));
    read_all_data(1, actual);
    verify_data(expected, actual, "test_single_word");
    `FAIL_UNLESS_EQUAL(actual.size(), 1);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 01: Multiple words — sequential addresses
// ----------------------------------------------------------------------------
`SVTEST(test_multiple_words)
    logic [B-1:0] expected[5];
    logic [B-1:0] actual[];

    for (int i = 0; i < 5; i++) expected[i] = B'(10 + i);
    start_reader(N'(10), N'(5));
    read_all_data(5, actual);
    verify_data(expected, actual, "test_multiple_words");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 02: dlast asserted on last word only
// ----------------------------------------------------------------------------
`SVTEST(test_dlast_assertion)
    int   count;
    int   timeout;
    int   errors;
    logic last_seen;

    count     = 0;
    timeout   = 0;
    errors    = 0;
    last_seen = 1'b0;

    start_reader(N'(20), N'(3));
    cb.tb_dready <= 1'b1;

    while (count < 3) begin
        @(cb);
        timeout++;
        if (tb_dvalid && tb_dready) begin
            count++;
            if (count < 3 && tb_dlast) begin
                $display("FAIL: dlast asserted early at word %0d", count);
                errors++;
            end
            if (count == 3 && !tb_dlast) begin
                $display("FAIL: dlast not asserted on last word");
                errors++;
            end
            if (count == 3 && tb_dlast) last_seen = 1'b1;
        end
        if (timeout > 50) begin
            $display("[TIMEOUT] test_dlast_assertion");
            `FAIL_IF(1);
        end
    end

    timeout = 0;
    while (tb_dvalid) begin
        @(cb);
        if (timeout++ > 20) break;
    end
    cb.tb_dready <= 1'b0;
    @(cb);

    if (errors > 0) `FAIL_IF(1);
    `FAIL_UNLESS(last_seen);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 03: Consecutive reads without reset
// ----------------------------------------------------------------------------
`SVTEST(test_consecutive_reads)
    logic [B-1:0] expected1[3];
    logic [B-1:0] expected2[4];
    logic [B-1:0] actual[];

    for (int i = 0; i < 3; i++) expected1[i] = B'(40 + i);
    for (int i = 0; i < 4; i++) expected2[i] = B'(50 + i);

    start_reader(N'(40), N'(3));
    read_all_data(3, actual);
    verify_data(expected1, actual, "consecutive first");

    start_reader(N'(50), N'(4));
    read_all_data(4, actual);
    verify_data(expected2, actual, "consecutive second");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 04: Backpressure — 3-cycle stall between each word
// ----------------------------------------------------------------------------
`SVTEST(test_backpressure)
    logic [B-1:0] expected[6];
    logic [B-1:0] actual[];
    int  count;
    int  timeout;

    for (int i = 0; i < 6; i++) expected[i] = B'(30 + i);
    actual  = new[6];
    count   = 0;
    timeout = 0;

    start_reader(N'(30), N'(6));
    cb.tb_dready <= 1'b1;

    while (count < 6) begin
        @(cb);
        timeout++;

        if (tb_dvalid && tb_dready) begin
            actual[count] = tb_dout;
            $display("[BKPR] data[%0d] = 0x%0h", count, tb_dout);
            count++;
            if (count < 6) begin
                cb.tb_dready <= 1'b0;
                repeat(3) @(cb);
                cb.tb_dready <= 1'b1;
            end
        end

        if (timeout > 200) begin
            $display("[TIMEOUT] test_backpressure after %0d words", count);
            `FAIL_IF(1);
        end
    end

    cb.tb_dready <= 1'b1;
    timeout = 0;
    while (tb_dvalid) begin
        @(cb);
        if (timeout++ > 20) break;
    end
    cb.tb_dready <= 1'b0;
    @(cb);

    verify_data(expected, actual, "test_backpressure");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 05: Reset during operation — FSM must recover
// ----------------------------------------------------------------------------
`SVTEST(test_reset_during_operation)
    logic [B-1:0] expected[5];
    logic [B-1:0] actual[];

    for (int i = 0; i < 5; i++) expected[i] = B'(60 + i);

    start_reader(N'(60), N'(5));
    repeat(3) @(cb);
    reset_dut();

    start_reader(N'(60), N'(5));
    read_all_data(5, actual);
    verify_data(expected, actual, "after_reset");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 06: Address re-latched between captures
// ----------------------------------------------------------------------------
`SVTEST(test_address_relatch)
    logic [B-1:0] expected_a[2];
    logic [B-1:0] expected_b[2];
    logic [B-1:0] actual[];

    expected_a[0] = B'(100); expected_a[1] = B'(101);
    expected_b[0] = B'(200); expected_b[1] = B'(201);

    start_reader(N'(100), N'(2));
    read_all_data(2, actual);
    verify_data(expected_a, actual, "addr_relatch A");

    start_reader(N'(200), N'(2));
    read_all_data(2, actual);
    verify_data(expected_b, actual, "addr_relatch B");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 07: Zero length read — FSM must not hang, dvalid must stay 0
// ----------------------------------------------------------------------------
`SVTEST(test_zero_length)
    start_reader(N'(10), N'(0));
    repeat(10) @(cb);
    `FAIL_UNLESS(tb_dvalid == 1'b0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 08: FIFO full stall
// Collect all 20 words; apply a 50-cycle stall after the 5th word to force
// the FIFO to fill. The FSM must pause and resume without losing data.
// dready is managed via cb.tb_dready throughout to avoid race conditions.
// ----------------------------------------------------------------------------
`SVTEST(test_fifo_full_stall)
    logic [B-1:0] expected[20];
    logic [B-1:0] actual[];
    int  count;
    int  timeout;

    for (int i = 0; i < 20; i++) expected[i] = B'(80 + i);
    actual  = new[20];
    count   = 0;
    timeout = 0;

    start_reader(N'(80), N'(20));
    cb.tb_dready <= 1'b1;

    while (count < 20) begin
        @(cb);
        timeout++;

        if (tb_dvalid && tb_dready) begin
            actual[count] = tb_dout;
            $display("[READ] data[%0d] = 0x%0h", count, tb_dout);
            count++;

            if (count == 5) begin
                // Long stall: forces FIFO to fill, FSM must pause BRAM reads
                cb.tb_dready <= 1'b0;
                repeat(50) @(cb);
                cb.tb_dready <= 1'b1;
            end
        end

        if (timeout > 500) begin
            $display("[TIMEOUT] test_fifo_full_stall: got %0d of 20 words", count);
            `FAIL_IF(1);
        end
    end

    cb.tb_dready <= 1'b1;
    timeout = 0;
    while (tb_dvalid) begin
        @(cb);
        if (timeout++ > 50) break;
    end
    cb.tb_dready <= 1'b0;
    @(cb);

    verify_data(expected, actual, "test_fifo_full_stall");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 09: Concurrent start ignored — pulsing start_reg while busy must not
// corrupt the current transfer
// ----------------------------------------------------------------------------
`SVTEST(test_concurrent_start_ignored)
    logic [B-1:0] expected[5];
    logic [B-1:0] actual[];

    for (int i = 0; i < 5; i++) expected[i] = B'(120 + i);

    start_reader(N'(120), N'(5));
    repeat(2) @(cb);

    // Attempt a second start while FSM is active
    cb.tb_start_reg <= 1'b1;
    @(cb);
    cb.tb_start_reg <= 1'b0;

    read_all_data(5, actual);
    verify_data(expected, actual, "test_concurrent_start_ignored");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 10: Memory wrap-around (addr 255 → 0 with N=8)
// ----------------------------------------------------------------------------
`SVTEST(test_memory_wrap)
    logic [B-1:0] expected[2];
    logic [B-1:0] actual[];

    expected[0] = B'(255);
    expected[1] = B'(0);

    start_reader(N'(255), N'(2));
    read_all_data(2, actual);
    verify_data(expected, actual, "test_memory_wrap");
`SVTEST_END
