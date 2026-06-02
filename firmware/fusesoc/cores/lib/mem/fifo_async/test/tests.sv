// ============================================================================
// File: tests.sv
// Description: Test suite for fifo_async module.
//
// FIFO timing (READ_MODE="std", FIFO_READ_LATENCY=1):
//   Cycle N  : rd_en=1 presented (XPM internal gate: rd_en & ~rd_rst_busy & ~empty)
//   Cycle N+1: dout valid, data_valid=1
//
// data_valid is the authoritative signal for when dout holds valid data.
// All read scoreboards use data_valid rather than a manual pipeline counter.
//
// CDC note: empty/full are synchronized across clock domains (2-stage).
// Allow ~5 read-clock cycles after a write burst before expecting empty=0.
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 00: Reset state — empty=1, full=0 after reset
// ----------------------------------------------------------------------------
`SVTEST(test00_reset)
    repeat(10) @(posedge rd_clk);
    `ASSERT_IMMEDIATE(empty == 1'b1);
    `ASSERT_IMMEDIATE(full  == 1'b0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 01: Basic flow — write burst then read burst
// Writes 50 random words, waits for CDC propagation of empty flag,
// then reads them back one at a time using data_valid as the capture strobe.
// ----------------------------------------------------------------------------
`SVTEST(test01_basic_flow)
    logic [B-1:0] rand_data;
    logic [B-1:0] exp;
    int           words_written;
    int           timeout_cnt;

    words_written = 0;
    model_q       = {};
    wr_en         = 1'b0;
    rd_en         = 1'b0;

    repeat(10) @(posedge wr_clk);

    // --- Write burst ---
    while (words_written < 50) begin
        @(posedge wr_clk);
        if (!full && !dut.wr_rst_busy) begin
            rand_data = $urandom;
            wr_en    <= 1'b1;
            din      <= rand_data;
            model_q.push_back(rand_data);
            words_written++;
        end else begin
            wr_en <= 1'b0;
        end
    end
    @(posedge wr_clk);
    wr_en <= 1'b0;

    $display("[TEST01] Wrote %0d words.", words_written);

    // --- Wait for empty flag to de-assert (CDC sync, up to 10 rd_clk cycles) ---
    timeout_cnt = 0;
    while (empty === 1'b1) begin
        @(posedge rd_clk);
        timeout_cnt++;
        if (timeout_cnt > 20) begin
            $display("[FAIL] test01: empty still 1 after %0d rd_clk cycles", timeout_cnt);
            `FAIL_IF(1);
        end
    end

    // --- Read burst: use data_valid as capture strobe ---
    for (int i = 0; i < words_written; i++) begin

        // Wait until FIFO has data
        timeout_cnt = 0;
        while (empty === 1'b1) begin
            @(posedge rd_clk);
            timeout_cnt++;
            if (timeout_cnt > 20) begin
                $display("[FAIL] test01: empty=1 waiting for word %0d", i);
                `FAIL_IF(1);
            end
        end

        // Issue read pulse
        @(posedge rd_clk);
        rd_en <= 1'b1;
        @(posedge rd_clk);
        rd_en <= 1'b0;

        // Wait for data_valid (latency=1: arrives this cycle)
        timeout_cnt = 0;
        while (data_valid !== 1'b1) begin
            @(posedge rd_clk);
            timeout_cnt++;
            if (timeout_cnt > 5) begin
                $display("[FAIL] test01: data_valid never asserted for word %0d", i);
                `FAIL_IF(1);
            end
        end

        exp = model_q.pop_front();
        `FAIL_UNLESS_EQUAL(dout, exp);
    end

    repeat(10) @(posedge rd_clk);
    `ASSERT_IMMEDIATE(empty == 1'b1);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 02: Random stress — concurrent producer/consumer threads
// Producer writes random data at ~50% duty cycle on wr_clk.
// Consumer reads when data is available at ~50% duty cycle on rd_clk.
// Scoreboard uses data_valid to capture dout at the correct cycle.
// ----------------------------------------------------------------------------
`SVTEST(test02_random_stress)
    model_q = {};
    wr_en   = 1'b0;
    rd_en   = 1'b0;
    din     = '0;

    fork

        // --- PRODUCER (write domain) ---
        begin : producer
            logic [B-1:0] wdata;
            int           words_written;
            words_written = 0;
            repeat(400) begin
                @(posedge wr_clk);
                if (!full && !dut.wr_rst_busy && $urandom_range(0, 1)) begin
                    wdata = $urandom;
                    wr_en <= 1'b1;
                    din   <= wdata;
                    model_q.push_back(wdata);
                end else begin
                    wr_en <= 1'b0;
                end
            end
            // Evaluate the last write pending after going out of the cycle
            @(posedge wr_clk);
            if (wr_en && !full && !dut.wr_rst_busy) begin
              model_q.push_back(din);
              words_written++;
            end
            wr_en <= 1'b0;
//            @(posedge wr_clk);
//            wr_en <= 1'b0;
        end

        // --- CONSUMER (read domain) ---
        // Uses data_valid as the authoritative capture strobe.
        // rd_en is issued when FIFO is not empty and we choose to read.
        // dout is captured on the cycle data_valid=1 (one cycle after rd_en).
        begin : consumer
            logic [B-1:0] exp_data;

            repeat(600) begin
                @(posedge rd_clk);

                // 1. If FIFO let us know the data is valid, we capture it.
                if (data_valid) begin
                    if (model_q.size() > 0) begin
                        exp_data = model_q.pop_front();
                        if (dout !== exp_data) begin
                            $display("[FAIL] stress mismatch: expected 0x%0h got 0x%0h",
                                     exp_data, dout);
                            `FAIL_IF(1);
                        end
                    end else begin
                        $display("[FAIL] scoreboard underflow — data_valid with empty model_q");
                        `FAIL_IF(1);
                    end
                end

                // 2. Decide independently if we must emit a read order
                if (!empty && !dut.rd_rst_busy && $urandom_range(0, 1)) begin
                    rd_en <= 1'b1;
                end else begin
                    rd_en <= 1'b0;
                end
            end
            @(posedge rd_clk);
            rd_en <= 1'b0;
        end

    join

    // Cool-down: let any in-flight reads complete
    repeat(10) @(posedge rd_clk);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 03: Full condition — write until full, verify full flag, then drain
// ----------------------------------------------------------------------------
`SVTEST(test03_full_condition)
    logic [B-1:0] wdata;
    logic [B-1:0] exp;
    int           words_written;
    int           timeout_cnt;

    words_written = 0;
    model_q       = {};
    wr_en         = 1'b0;
    rd_en         = 1'b0;

    // Write until full
    repeat(N + 10) begin
        @(posedge wr_clk);
        
        // 1. Verify if the last programmed write in previous cycle WAS OK
        if (wr_en && !full && !dut.wr_rst_busy) begin
            model_q.push_back(din);
            words_written++;
        end

        // 2. Prepare the next write attempt
        if (!full && !dut.wr_rst_busy) begin
            wdata = $urandom;
            wr_en <= 1'b1;
            din   <= wdata;
        end else begin
            wr_en <= 1'b0;
        end
    end
    
    // Evaluate the last write pending after going out of the cycle
    @(posedge wr_clk);
    if (wr_en && !full && !dut.wr_rst_busy) begin
        model_q.push_back(din);
        words_written++;
    end
    wr_en <= 1'b0;

    $display("[TEST03] Wrote %0d words, full=%b", words_written, full);
    `ASSERT_IMMEDIATE(full == 1'b1);

    // CDC: wait for empty to de-assert on read side
    timeout_cnt = 0;
    while (empty === 1'b1) begin
        @(posedge rd_clk);
        if (timeout_cnt++ > 20) begin
            $display("[FAIL] test03: empty stuck after full write");
            `FAIL_IF(1);
        end
    end

    // Drain all words
    for (int i = 0; i < words_written; i++) begin
        timeout_cnt = 0;
        while (empty === 1'b1) begin
            @(posedge rd_clk);
            if (timeout_cnt++ > 20) begin
                $display("[FAIL] test03: empty=1 waiting for word %0d", i);
                `FAIL_IF(1);
            end
        end

        @(posedge rd_clk);
        rd_en <= 1'b1;
        @(posedge rd_clk);
        rd_en <= 1'b0;

        timeout_cnt = 0;
        while (data_valid !== 1'b1) begin
            @(posedge rd_clk);
            if (timeout_cnt++ > 5) begin
                $display("[FAIL] test03: data_valid timeout at word %0d", i);
                `FAIL_IF(1);
            end
        end

        exp = model_q.pop_front();
        `FAIL_UNLESS_EQUAL(dout, exp);
    end

    repeat(10) @(posedge rd_clk);
    `ASSERT_IMMEDIATE(empty == 1'b1);
    `ASSERT_IMMEDIATE(full  == 1'b0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 04: Write after read — interleaved single-word transactions
// Alternates: write 1, read 1, verify. Exercises the empty→not-empty
// CDC path on every transaction.
// ----------------------------------------------------------------------------
`SVTEST(test04_interleaved)
    logic [B-1:0] wdata;
    logic [B-1:0] exp;
    int           timeout_cnt;

    model_q = {};
    wr_en   = 1'b0;
    rd_en   = 1'b0;

    repeat(20) begin

        // Write one word
        wdata = $urandom;
        @(posedge wr_clk);
        while (full || dut.wr_rst_busy) @(posedge wr_clk);
        wr_en <= 1'b1;
        din   <= wdata;
        model_q.push_back(wdata);
        @(posedge wr_clk);
        wr_en <= 1'b0;

        // Wait for CDC empty flag to de-assert
        timeout_cnt = 0;
        while (empty === 1'b1) begin
            @(posedge rd_clk);
            if (timeout_cnt++ > 20) begin
                $display("[FAIL] test04: empty stuck after single write");
                `FAIL_IF(1);
            end
        end

        // Read the word
        @(posedge rd_clk);
        rd_en <= 1'b1;
        @(posedge rd_clk);
        rd_en <= 1'b0;

        timeout_cnt = 0;
        while (data_valid !== 1'b1) begin
            @(posedge rd_clk);
            if (timeout_cnt++ > 5) begin
                $display("[FAIL] test04: data_valid timeout");
                `FAIL_IF(1);
            end
        end

        exp = model_q.pop_front();
        `FAIL_UNLESS_EQUAL(dout, exp);
    end

    repeat(5) @(posedge rd_clk);
    `ASSERT_IMMEDIATE(empty == 1'b1);
`SVTEST_END
