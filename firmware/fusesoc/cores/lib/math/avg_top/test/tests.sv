// ============================================================================
// File: tests.sv
// Description: Test suite for avg_top module.
// Included inside SVUNIT_TESTS_BEGIN/END.
// All helper tasks are defined in avg_top_tc00.sv (module scope).
//
// avg block protocol reminder:
//   - start_reg must stay HIGH through TRIGGER_ST and AVG_ST.
//   - trigger_i must be pulsed while start_reg is high.
//   - After WRITE_MEM_ST drop start_reg to release WAIT_TRIGGER_ST.
//
// Data format on m0/m1 output (4*B = 64 bits):
//   [63:32] = acc_q (sum of Q samples, sign-extended to 2*B)
//   [31:0]  = acc_i (sum of I samples, sign-extended to 2*B)
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 00: Reset state — AXI outputs must be de-asserted after reset
// ----------------------------------------------------------------------------
`SVTEST(test_reset)
    `FAIL_IF(tb_m0_axis_tvalid !== 1'b0);
    `FAIL_IF(tb_m1_axis_tvalid !== 1'b0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 01: Accumulation — m1_axis immediate stream (async FIFO path)
// Inject 4 samples of I=100 (0x0064), Q=0.
// Expected acc_i = 400 (0x0000_0190), acc_q = 0.
// mem_di_o = {acc_q[31:0], acc_i[31:0]} = 64'h0000_0000_0000_0190
// m1_axis carries this value as soon as WRITE_MEM_ST fires.
// ----------------------------------------------------------------------------
`SVTEST(test_accumulation_m1_stream)
    logic [4*B-1:0] expected[1];
    logic [4*B-1:0] actual[];
    int timed_out;

    // I=100, Q=0 → din_i = {16'h0000, 16'h0064}
    // 4 samples → acc_i = 400 = 0x0000_0190, acc_q = 0
    expected[0] = 64'h0000_0000_0000_0190;

    avg_arm_and_trigger(N'(0), 32'd4, 1'b0, 16'd0, 16'd0);

    // Inject 4 samples
    sys_cb.tb_din_valid_i <= 1'b1;
    repeat(4) begin
        sys_cb.tb_din_i <= {16'h0000, 16'h0064}; // Q=0, I=100
        @(sys_cb);
    end
    sys_cb.tb_din_valid_i <= 1'b0;
    sys_cb.tb_din_i       <= '0;

    // Allow AVG FSM to reach WRITE_MEM_ST (a few extra sys clocks)
    repeat(10) @(sys_cb);

    // Release FSM
    sys_cb.tb_avg_start_reg <= 1'b0;

    // Read from m1_axis (async FIFO, AXI clock domain)
    read_m1_data(1, actual, timed_out);

    if (timed_out) begin
        $display("[FAIL] test_accumulation_m1_stream: timeout waiting for m1 data");
        `FAIL_IF(1);
    end

    verify_data(expected, actual, "test_accumulation_m1_stream");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 02: Accumulation — m0_axis BRAM readout path
// Same stimulus as TEST 01 but data is read back from BRAM via data_reader.
// Expected: same 64-bit result at the address written by avg.
// ----------------------------------------------------------------------------
`SVTEST(test_accumulation_m0_bram)
    logic [4*B-1:0] expected[1];
    logic [4*B-1:0] actual[];
    int timed_out;
    int tlast_errors;

    // 3 samples: I=10 (0x000A), Q=-5 (0xFFFB)
    // acc_i = 30 = 0x0000_001E
    // acc_q = -15 sign-extended to 32b = 0xFFFF_FFF1
    expected[0] = {32'hFFFF_FFF1, 32'h0000_001E};

    avg_arm_and_trigger(N'(5), 32'd3, 1'b0, 16'd0, 16'd0);

    sys_cb.tb_din_valid_i <= 1'b1;
    repeat(3) begin
        sys_cb.tb_din_i <= {16'hFFFB, 16'h000A}; // Q=-5, I=10
        @(sys_cb);
    end
    sys_cb.tb_din_valid_i <= 1'b0;
    sys_cb.tb_din_i       <= '0;

    // Wait for WRITE_MEM_ST to complete — BRAM write is registered
    repeat(10) @(sys_cb);
    sys_cb.tb_avg_start_reg <= 1'b0;

    // Allow CDC settling before starting data_reader in AXI domain
    repeat(10) @(axi_cb);

    // Trigger data_reader to read back address 5
    start_reader(N'(5), N'(1));
    read_m0_data(1, actual, timed_out, tlast_errors);

    if (timed_out) begin
        $display("[FAIL] test_accumulation_m0_bram: timeout waiting for m0 data");
        `FAIL_IF(1);
    end

    verify_data(expected, actual, "test_accumulation_m0_bram");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 03: Multiple captures to consecutive addresses
// Two captures: addr=0 gets 2×I=50, addr=1 gets 2×I=75.
// Then data_reader reads back both. addr_r auto-increments after each write.
// ----------------------------------------------------------------------------
`SVTEST(test_consecutive_captures_bram)
    logic [4*B-1:0] expected[2];
    logic [4*B-1:0] actual[];
    int timed_out;
    int tlast_errors;

    // --- Capture 1: addr=0, 2 samples I=50 → acc_i=100=0x64 ---
    expected[0] = {32'h0000_0000, 32'h0000_0064};

    avg_arm_and_trigger(N'(0), 32'd2, 1'b0, 16'd0, 16'd0);

    sys_cb.tb_din_valid_i <= 1'b1;
    repeat(2) begin
        sys_cb.tb_din_i <= {16'h0000, 16'h0032}; // Q=0, I=50
        @(sys_cb);
    end
    sys_cb.tb_din_valid_i <= 1'b0;
    sys_cb.tb_din_i       <= '0;

    // CRITICAL FIX: Allow the capture to fully complete and the address to auto-increment.
    // Drop start_reg to release the FSM, which allows addr_r to increment.
    repeat(10) @(sys_cb);
    sys_cb.tb_avg_start_reg <= 1'b0; // <-- THIS LINE IS KEY
    repeat(10) @(axi_cb);

    // --- Capture 2: addr is now 1, 2 samples I=75 → acc_i=150=0x96 ---
    expected[1] = {32'h0000_0000, 32'h0000_0096};

    // Now, re-arm for the new address.
    avg_arm_and_trigger(N'(1), 32'd2, 1'b0, 16'd0, 16'd0); // <-- Use avg_arm_and_trigger again!

    sys_cb.tb_din_valid_i <= 1'b1;
    repeat(2) begin
        sys_cb.tb_din_i <= {16'h0000, 16'h004B}; // Q=0, I=75
        @(sys_cb);
    end
    sys_cb.tb_din_valid_i <= 1'b0;
    sys_cb.tb_din_i       <= '0;
    repeat(10) @(sys_cb);
    sys_cb.tb_avg_start_reg <= 1'b0;

    // Allow BRAM write to settle before reading back
    repeat(15) @(axi_cb);

    // Read back both words starting at addr=0
    start_reader(N'(0), N'(2));
    read_m0_data(2, actual, timed_out, tlast_errors);

    if (timed_out) begin
        $display("[FAIL] test_consecutive_captures_bram: timeout");
        `FAIL_IF(1);
    end
    verify_data(expected, actual, "test_consecutive_captures_bram");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 04: m0_axis dlast asserted on last word
// Capture 3 samples across 3 trigger cycles; verify:
//   - dlast only asserted on the last word
//   - accumulated data correct at each address
// ----------------------------------------------------------------------------
`SVTEST(test_m0_dlast)
    logic [4*B-1:0] actual[];
    logic [4*B-1:0] expected[];
    int timed_out;
    int tlast_errors;
    int data_errors;

    expected = new[3];
    expected[0] = {{(2*B){1'b0}}, 32'h0000_0006};
    expected[1] = {{(2*B){1'b0}}, 32'h0000_0006};
    expected[2] = {{(2*B){1'b0}}, 32'h0000_0006};

    // Arm FSM and fire first trigger
    avg_arm_and_trigger(N'(10), 32'd3, 1'b0, 16'd0, 16'd0);

    // --- Trigger 1 ---
    inject_data(3, {16'h0000, 16'h0001});
    wait_for_wait_trigger_st();  // FSM finish WRITE_MEM_ST before the next trigger

    // --- Trigger 2 ---
    pulse_trigger();
    inject_data(3, {16'h0000, 16'h0001});
    wait_for_wait_trigger_st();

    // --- Trigger 3 ---
    pulse_trigger();
    inject_data(3, {16'h0000, 16'h0001});
    wait_for_wait_trigger_st();

    repeat(15) @(axi_cb);
    start_reader(N'(10), N'(3));
    read_m0_data(3, actual, timed_out, tlast_errors);

    if (timed_out) begin
        $display("[FAIL] test_m0_dlast: Reader timeout");
        `FAIL_IF(1);
    end
    if (tlast_errors > 0)
        $display("[FAIL] test_m0_dlast: tlast mismatch (%0d errors)", tlast_errors);
    `FAIL_IF(tlast_errors > 0);

    data_errors = 0;
    for (int i = 0; i < 3; i++) begin
        if (actual[i] !== expected[i]) begin
            $display("[FAIL] test_m0_dlast: data[%0d] = 0x%0h, expected 0x%0h",
                     i, actual[i], expected[i]);
            data_errors++;
        end
    end
    if (data_errors > 0)
        $display("[FAIL] test_m0_dlast: data mismatch (%0d errors)", data_errors);
    `FAIL_IF(data_errors > 0);

`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 05: Abort — drop start_reg in TRIGGER_ST, verify no spurious write
// Then confirm system recovers and completes a clean capture.
// ----------------------------------------------------------------------------
`SVTEST(test_start_reg_abort)
    logic [4*B-1:0] expected[1];
    logic [4*B-1:0] actual[];
    int timed_out;
    int i;

    // Get FSM to TRIGGER_ST then abort
    sys_cb.tb_avg_addr_reg  <= N'(20);
    sys_cb.tb_avg_len_reg   <= 32'd2;
    sys_cb.tb_avg_start_reg <= 1'b1;
    repeat (5) @(sys_cb); // TRIGGER_ST
    sys_cb.tb_avg_start_reg <= 1'b0; // abort
    repeat(5) @(sys_cb);

    // m1 must be empty (no write occurred)
    // Check m1_axis_tvalid is 0 over next 5 AXI cycles
    for (i = 0; i < 5; i++) begin
        @(axi_cb);
        if (tb_m1_axis_tvalid) begin
            $display("[FAIL] test_start_reg_abort: spurious m1 write after abort");
            `FAIL_IF(1);
        end
    end

    // Recover: clean capture of 2 samples I=7 at addr=20
    expected[0] = {32'h0000_0000, 32'h0000_000E}; // acc_i = 14 = 2*7

    sys_cb.tb_avg_start_reg <= 1'b1;
    repeat(5) @(sys_cb);
    sys_cb.tb_trigger_i <= 1'b1;
    @(sys_cb);
    sys_cb.tb_trigger_i <= 1'b0;
    sys_cb.tb_din_valid_i <= 1'b1;
    repeat(2) begin
        sys_cb.tb_din_i <= {16'h0000, 16'h0007};
        @(sys_cb);
    end
    sys_cb.tb_din_valid_i <= 1'b0;
    sys_cb.tb_din_i       <= '0;
    repeat(10) @(sys_cb);
    sys_cb.tb_avg_start_reg <= 1'b0;

    read_m1_data(1, actual, timed_out);
    if (timed_out) begin
        $display("[FAIL] test_start_reg_abort: timeout after recovery");
        `FAIL_IF(1);
    end
    verify_data(expected, actual, "test_start_reg_abort_recovery");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 06: Photon mode — count rising edges, verify via m1_axis
// Signal: 0, 60, 55, 5, 70, 70 with H=50, L=10 → 2 edges
// Expected: acc_photon = 2 = 64'h0000_0000_0000_0002
// ----------------------------------------------------------------------------
`SVTEST(test_photon_mode_m1)
    logic [4*B-1:0] expected[1];
    logic [4*B-1:0] actual[];
    int timed_out;

    expected[0] = 64'h0000_0000_0000_0002;

    sys_cb.tb_avg_addr_reg        <= N'(30);
    sys_cb.tb_avg_len_reg         <= 32'd6;
    sys_cb.tb_avg_photon_mode_reg <= 1'b1;
    sys_cb.tb_avg_h_thrsh_reg     <= 16'd50;
    sys_cb.tb_avg_l_thrsh_reg     <= 16'd10;
    sys_cb.tb_avg_start_reg       <= 1'b1;
    repeat(5) @(sys_cb);

    sys_cb.tb_trigger_i <= 1'b1;
    @(sys_cb);
    sys_cb.tb_trigger_i <= 1'b0;

    sys_cb.tb_din_valid_i <= 1'b1;
    sys_cb.tb_din_i <= {16'd0, 16'd0};  @(sys_cb);
    sys_cb.tb_din_i <= {16'd0, 16'd60}; @(sys_cb);
    sys_cb.tb_din_i <= {16'd0, 16'd55}; @(sys_cb);
    sys_cb.tb_din_i <= {16'd0, 16'd5};  @(sys_cb);
    sys_cb.tb_din_i <= {16'd0, 16'd70}; @(sys_cb);
    sys_cb.tb_din_i <= {16'd0, 16'd70}; @(sys_cb);
    sys_cb.tb_din_valid_i <= 1'b0;
    sys_cb.tb_din_i       <= '0;

    repeat(10) @(sys_cb);
    sys_cb.tb_avg_start_reg       <= 1'b0;
    sys_cb.tb_avg_photon_mode_reg <= 1'b0;

    read_m1_data(1, actual, timed_out);
    if (timed_out) begin
        $display("[FAIL] test_photon_mode_m1: timeout");
        `FAIL_IF(1);
    end
    verify_data(expected, actual, "test_photon_mode_m1");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 07: m0_axis backpressure — stall m0_axis_tready mid-transfer
// Capture 4 samples, read back with backpressure every other word.
// ----------------------------------------------------------------------------
`SVTEST(test_m0_backpressure)
    logic [4*B-1:0] expected[4];
    logic [4*B-1:0] actual[];
    int  count;
    int  timeout;

    // 4 captures at consecutive addresses: addr=50,51,52,53
    // Each with 1 sample of I=N*10 (10,20,30,40)
    for (int i = 0; i < 4; i++)
        expected[i] = {32'h0000_0000, 32'(10 * (i + 1))};

    // Run 4 single-sample captures
    for (int cap = 0; cap < 4; cap++) begin
        sys_cb.tb_avg_addr_reg  <= N'(50 + cap);
        sys_cb.tb_avg_len_reg   <= 32'd1;
        sys_cb.tb_avg_start_reg <= 1'b1;
        if (cap == 0) repeat(3) @(sys_cb); // wait only before first trigger
        else          @(sys_cb);           // subsequent captures, start_reg already high

        sys_cb.tb_trigger_i <= 1'b1;
        @(sys_cb);
        sys_cb.tb_trigger_i <= 1'b0;
        sys_cb.tb_din_valid_i <= 1'b1;
        sys_cb.tb_din_i <= {16'h0000, 16'(10 * (cap + 1))};
        @(sys_cb);
        sys_cb.tb_din_valid_i <= 1'b0;
        sys_cb.tb_din_i       <= '0;
        repeat(6) @(sys_cb);
        // hold start_reg for next capture or drop at end
        if (cap == 3) sys_cb.tb_avg_start_reg <= 1'b0;
    end

    repeat(15) @(axi_cb);

    // Read back 4 words from addr=50 with backpressure
    start_reader(N'(50), N'(4));
    count   = 0;
    timeout = 0;
    actual  = new[4];
    axi_cb.tb_m0_axis_tready <= 1'b1;

    while (count < 4) begin
        @(axi_cb);
        timeout++;
        if (tb_m0_axis_tvalid && tb_m0_axis_tready) begin
            actual[count] = tb_m0_axis_tdata;
            $display("[M0 BKPR] data[%0d] = 0x%0h", count, tb_m0_axis_tdata);
            count++;
            if (count < 4) begin
                axi_cb.tb_m0_axis_tready <= 1'b0;
                repeat(5) @(axi_cb);
                axi_cb.tb_m0_axis_tready <= 1'b1;
            end
        end
        if (timeout > 300) begin
            $display("[TIMEOUT] test_m0_backpressure after %0d words", count);
            `FAIL_IF(1);
        end
    end

    timeout = 0;
    while (tb_m0_axis_tvalid) begin
        @(axi_cb);
        if (timeout++ > 20) break;
    end
    axi_cb.tb_m0_axis_tready <= 1'b0;
    @(axi_cb);

    verify_data(expected, actual, "test_m0_backpressure");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 08: Full range – capture and read maximum depth (2^N samples)
// Verify that address counter rolls over correctly and BRAM handles full depth.
// N=10 → 1024 samples. Write one sample per address (I = address, Q = 0).
// Then read back all 1024 words and check each.
// ----------------------------------------------------------------------------
`SVTEST(test_full_range)
    logic [4*B-1:0] expected[];
    logic [4*B-1:0] actual[];
    int timed_out;
    int max_depth = 2**N;
    int tlast_errors;

    expected = new[max_depth];
    for (int i = 0; i < max_depth; i++) begin
        expected[i] = {32'h0000_0000, 32'(i)};
    end

    // Make a capture for each address (len=1)
    for (int i = 0; i < max_depth; i++) begin
        avg_arm_and_trigger(N'(i), 32'd1, 1'b0, 16'd0, 16'd0);
        sys_cb.tb_din_valid_i <= 1'b1;
        sys_cb.tb_din_i <= {16'h0000, i[15:0]};
        @(sys_cb);
        sys_cb.tb_din_valid_i <= 1'b0;
        sys_cb.tb_din_i       <= '0;
        repeat(5) @(sys_cb);
        if (i == max_depth-1) sys_cb.tb_avg_start_reg <= 1'b0;
    end

    repeat(20) @(axi_cb);
    start_reader(N'(0), (N+1)'(1024));
    read_m0_data(max_depth, actual, timed_out, tlast_errors, 10000);
    if (timed_out) `FAIL_IF(1);
    verify_data(expected, actual, "test_full_range");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 09: Abort during AVG_ST (cancel while accumulating samples)
// Start capture, inject part of the samples, then drop avg_start_reg.
// Verify that no write occurs (BRAM and m0 stream stay unchanged).
// Then recover with a clean capture at the same address.
// ----------------------------------------------------------------------------
`SVTEST(test_abort_during_avg_st)
    logic [4*B-1:0] expected[1];
    logic [4*B-1:0] actual[];
    int timed_out;
    int tlast_errors;

    // --- Phase 1: Aborted capture (5 samples at addr=42, only 2 injected) ---
    avg_arm_and_trigger(N'(42), 32'd5, 1'b0, 16'd0, 16'd0);
    inject_data(2, {16'h0000, 16'h0010}); // I=16, Q=0 (partial, 2 of 5)

    // Abort mid-capture
    sys_cb.tb_avg_start_reg <= 1'b0;
    repeat(6) @(sys_cb); // margin for CDC resync to take effect in avg FSM

    // Inject 3 more samples — must be ignored since start_reg=0
    inject_data(3, {16'h0000, 16'h0010});

    // Verify no spurious output on m0
    repeat(20) @(axi_cb);
    if (tb_m0_axis_tvalid) begin
        $display("[FAIL] test_abort_during_avg_st: spurious m0 data after abort");
        `FAIL_IF(1);
    end

    // --- Phase 2: Recovery capture (3 samples I=20 + i at addr=42) ---
    // Expected: acc_i = 20 + 21 + 22 = 63 = 0x0000_003F, acc_q = 0
    expected[0] = {32'h0000_0000, 32'(20+21+22)}; // = 63 = 0x3f 

    avg_arm_and_trigger(N'(42), 32'd3, 1'b0, 16'd0, 16'd0);
    inject_data(3, {16'h0000, 16'h0014}); // I=20, Q=0

    wait_for_wait_trigger_st(); // ensure WRITE_MEM_ST completed
    sys_cb.tb_avg_start_reg <= 1'b0;

    repeat(15) @(axi_cb);
    start_reader(N'(42), N'(1));
    read_m0_data(1, actual, timed_out, tlast_errors, 500);

    if (timed_out) begin
        $display("[FAIL] test_abort_during_avg_st: timeout reading recovery data");
        `FAIL_IF(1);
    end
    `FAIL_IF(tlast_errors > 0);
    verify_data(expected, actual, "test_abort_during_avg_st");

`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 10: Read before write - start data_reader before any capture occurs
// Verify that m0_axis_tvalid behavior is handled correctly (dummy read),
// then perform a capture and read to confirm the reader retrieves new data.
// ----------------------------------------------------------------------------
`SVTEST(test_read_before_write)
    logic [4*B-1:0] expected[1];
    logic [4*B-1:0] actual[];
    logic [4*B-1:0] dummy_actual[]; // Used to flush the initial garbage data
    int timed_out;
    int dummy_timed_out;
    int tlast_errors;
    int dummy_tlast_err;

    // --- Phase 1: Reader before any capture occurs ---
    // Start the reader. The BRAM contains uninitialized data (X) at this point.
    start_reader(N'(100), N'(1));
    
    // CRITICAL FIX: We must consume the AXI stream data to prevent the
    // data_reader FSM from stalling indefinitely waiting for tready=1.
    read_m0_data(1, dummy_actual, dummy_timed_out, dummy_tlast_err, 500);
    
    // Allow the reader FSM to complete the handshake and return to IDLE/INIT
    repeat(10) @(axi_cb); 

    // --- Phase 2: Capture at addr=100, 2 samples of I=25 -> acc_i=50 ---
    expected[0] = {32'h0000_0000, 32'(50)};

    avg_arm_and_trigger(N'(100), 32'd2, 1'b0, 16'd0, 16'd0);

    // Inject 2 constant samples (I=25)
    sys_cb.tb_din_valid_i <= 1'b1;
    repeat(2) begin
        sys_cb.tb_din_i <= {16'h0000, 16'h0019};
        @(sys_cb);
    end
    sys_cb.tb_din_valid_i <= 1'b0;
    sys_cb.tb_din_i       <= '0;

    // Wait for the pipeline to finish WRITE_MEM_ST
    wait_for_wait_trigger_st(); 
    sys_cb.tb_avg_start_reg <= 1'b0;

    // --- Phase 3: Reader after the capture ---
    // Allow time for the data_reader to transition END_ST -> INIT_ST
    repeat(15) @(axi_cb); // CDC margin

    // Read the newly written averaged data
    start_reader(N'(100), N'(1));
    read_m0_data(1, actual, timed_out, tlast_errors, 500);

    if (timed_out) begin
        $display("[FAIL] test_read_before_write: timeout reading after write");
        `FAIL_IF(1);
    end
    `FAIL_IF(tlast_errors > 0);
    
    // Verify that the actual data matches the expected 50
    verify_data(expected, actual, "test_read_before_write");

`SVTEST_END
    
// ----------------------------------------------------------------------------
// TEST 11: Reset during operation – assert rstn while capturing and reading
// Then release reset and verify system can perform a new capture correctly.
// ----------------------------------------------------------------------------
   `SVTEST(test_reset_during_operation)
    logic [4*B-1:0] expected[1];
    logic [4*B-1:0] actual[];
    int timed_out;
    int tlast_err;

    // --- Phase 1: Reset during active capture ---
    avg_arm_and_trigger(N'(200), 32'd10, 1'b0, 16'd0, 16'd0);
    sys_cb.tb_din_valid_i <= 1'b1;
    repeat(5) begin
        sys_cb.tb_din_i <= {16'h0000, 16'h0005};
        @(sys_cb);
    end
    sys_cb.tb_din_valid_i <= 1'b0;
    sys_cb.tb_din_i       <= '0;

    // Reset mid-capture — reset_dut manages the full cycle and stabilization
    sys_cb.tb_avg_start_reg  <= 1'b0;
    sys_cb.tb_avg_len_reg    <= '0;
    sys_cb.tb_avg_addr_reg   <= '0;
    reset_dut();

    // --- Phase 2: Clean capture after reset ---
    expected[0] = {32'h0000_0000, 32'(42)};

    avg_arm_and_trigger(N'(200), 32'd1, 1'b0, 16'd0, 16'd0);

    sys_cb.tb_din_valid_i <= 1'b1;
    sys_cb.tb_din_i       <= {16'h0000, 16'h002A}; // I=42
    @(sys_cb);
    sys_cb.tb_din_valid_i <= 1'b0;
    sys_cb.tb_din_i       <= '0;

    wait_for_wait_trigger_st();
    sys_cb.tb_avg_start_reg <= 1'b0;

    repeat(15) @(axi_cb);
    start_reader(N'(200), N'(1));
    read_m0_data(1, actual, timed_out, tlast_err, 500);

    if (timed_out) begin
        $display("[FAIL] test_reset_during_operation: timeout after reset recovery");
        `FAIL_IF(1);
    end
    `FAIL_IF(tlast_err > 0);
    verify_data(expected, actual, "test_reset_during_operation");

`SVTEST_END
     