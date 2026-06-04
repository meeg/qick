// ============================================================================
// File: data_writer_sg_tests.sv
// Description: SVUnit test cases for data_writer_sg.
// Included by data_writer_sg_tc00.sv.
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 01: Reset — FSM stays in INIT_ST, no memory writes
// ----------------------------------------------------------------------------
`SVTEST(test_reset_no_write)
    repeat(5) @(cb);
    `FAIL_IF(tb_mem_we);
    `FAIL_IF(tb_s_axis_tready);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 02: we_reg=0 keeps FSM in INIT_ST — no tready, no mem_we
// ----------------------------------------------------------------------------
`SVTEST(test_idle_no_tready)
    cb.tb_we_reg <= 1'b0;
    repeat(10) @(cb);
    `FAIL_IF(tb_s_axis_tready);
    `FAIL_IF(tb_mem_we);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 03: Enable writer — tready asserted when FSM reaches WAIT_TVALID_ST
// ----------------------------------------------------------------------------
`SVTEST(test_enable_asserts_tready)
    enable_writer(32'd0);
    // After enable_writer FSM is in WAIT_TVALID_ST — tready_r should be 1
    // (tready_r is one cycle behind tready_i due to register)
    repeat(2) @(cb);
    `FAIL_IF(!tb_s_axis_tready);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 04: Single write — correct address and data appear on memory bus
// After pipeline (3 stages): mem_addr = start_addr, mem_di = sent data.
// ----------------------------------------------------------------------------
`SVTEST(test_single_write)
    logic [N-1:0] addr_out[];
    logic [B-1:0] data_out[];

    enable_writer(32'd10); // start at address 10
    send_stream(1, 16'hABCD, addr_out, data_out);

    `FAIL_UNLESS_EQUAL(addr_out[0], N'(10));
    `FAIL_UNLESS_EQUAL(data_out[0], 16'hABCD);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 05: Sequential writes — addresses auto-increment from start_addr
// ----------------------------------------------------------------------------
`SVTEST(test_address_increment)
    logic [N-1:0] addr_out[];
    logic [B-1:0] data_out[];
    localparam int COUNT = 8;
    localparam int START = 5;

    enable_writer(32'(START));
    send_stream(COUNT, 16'h0001, addr_out, data_out);

    for (int i = 0; i < COUNT; i++) begin
        if (addr_out[i] !== N'(START + i)) begin
            $display("[FAIL] test_address_increment: addr[%0d]=0x%0h expected 0x%0h",
                     i, addr_out[i], N'(START + i));
            `FAIL_IF(1);
        end
    end
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 06: Data pipeline — mem_di matches sent data in order
// ----------------------------------------------------------------------------
`SVTEST(test_data_pipeline)
    logic [N-1:0] addr_out[];
    logic [B-1:0] data_out[];
    localparam int COUNT = 4;

    enable_writer(32'd0);
    send_stream(COUNT, 16'h0010, addr_out, data_out);

    for (int i = 0; i < COUNT; i++) begin
        if (data_out[i] !== B'(16'h0010 + i)) begin
            $display("[FAIL] test_data_pipeline: data[%0d]=0x%0h expected 0x%0h",
                     i, data_out[i], B'(16'h0010 + i));
            `FAIL_IF(1);
        end
    end
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 07: Disable mid-stream — FSM returns to INIT_ST, writes stop
// ----------------------------------------------------------------------------
`SVTEST(test_disable_stops_writes)
    int write_count_after_disable = 0;

    enable_writer(32'd0);

    // Send 3 samples
    for (int i = 0; i < 3; i++) begin
        cb.tb_s_axis_tdata  <= B'(i + 1);
        cb.tb_s_axis_tvalid <= 1'b1;
        @(cb iff tb_s_axis_tready);
    end
    @(cb);
    cb.tb_s_axis_tvalid <= 1'b0;

    // Disable
    disable_writer();

    // Count any writes that occur after disable settled
    repeat(10) @(cb) begin
        if (tb_mem_we) write_count_after_disable++;
    end

    `FAIL_IF(write_count_after_disable > 0);
    `FAIL_IF(tb_s_axis_tready);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 08: Start address register — writer respects different start addresses
// ----------------------------------------------------------------------------
`SVTEST(test_start_addr_register)
    logic [N-1:0] addr_out[];
    logic [B-1:0] data_out[];
    localparam int START_A = 20;
    localparam int START_B = 50;

    // First burst at START_A
    enable_writer(32'(START_A));
    send_stream(2, 16'hAAAA, addr_out, data_out);
    `FAIL_UNLESS_EQUAL(addr_out[0], N'(START_A));
    disable_writer();

    // Second burst at START_B
    enable_writer(32'(START_B));
    send_stream(2, 16'hBBBB, addr_out, data_out);
    `FAIL_UNLESS_EQUAL(addr_out[0], N'(START_B));
    disable_writer();
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 09: tvalid gap — FSM returns to WAIT_TVALID_ST when tvalid drops,
// then resumes when tvalid returns. Data and Addresses must be contiguous.
// ----------------------------------------------------------------------------
`SVTEST(test_tvalid_gap_with_data_check)
    
    // 1. Struct to save writing transactions
    typedef struct {
        logic [N-1:0] addr;
        logic [B-1:0] data;
    } mem_txn_t;
    
    mem_txn_t actual_writes[$];
    mem_txn_t expected_writes[$];

    enable_writer(32'd0);

    // 2. We define the "Golden Model": what we expect to be written to memory
    expected_writes.push_back('{addr: 16'd0, data: 16'd1});
    expected_writes.push_back('{addr: 16'd1, data: 16'd2});
    expected_writes.push_back('{addr: 16'd2, data: 16'hDEAD});

    // 3. Launch a concurrent monitor to observe the pipeline output
    //fork
    //    forever @(cb) begin
    //        if (cb.tb_mem_we) begin
    //            actual_writes.push_back('{addr: cb.tb_mem_addr, data: cb.tb_mem_di});
    //        end
    //    end
    //join_none
    // 3. Launch a concurrent monitor (Workaround para XSIM)
    fork
        forever @(negedge tb_clk) begin 
            // Use signals without the 'cb.' prefix since we're outside the testbench class context
            if (tb_mem_we) begin
                actual_writes.push_back('{addr: tb_mem_addr, data: tb_mem_di});
            end
        end
    join_none

    // --- STIMULUS ---
    
    // Send the first 2 samples
    for (int i = 0; i < 2; i++) begin
        cb.tb_s_axis_tdata  <= B'(i + 1);
        cb.tb_s_axis_tvalid <= 1'b1;
        @(cb iff tb_s_axis_tready);
    end
    
    // Low tvalid immediately after the last accepted transfer
    cb.tb_s_axis_tvalid <= 1'b0;
    cb.tb_s_axis_tdata  <= '0;

    // Generate the inactivity gap (5 cycles)
    repeat(5) @(cb);

    // Resume and send 1 more sample
    cb.tb_s_axis_tvalid <= 1'b1;
    cb.tb_s_axis_tdata  <= 16'hDEAD;
    @(cb iff tb_s_axis_tready);
    cb.tb_s_axis_tvalid <= 1'b0;

    // Give time for the pipeline to drain completely (3 stages + margin)
    repeat(5) @(cb);

    // Stop the monitor in background for that it doesn't continue running in other tests
    disable fork;

    // --- VERIFICATION ---
    
    // A. Check if there were any spurious writes (the size must be exact)
    `FAIL_UNLESS_EQUAL(actual_writes.size(), expected_writes.size());
    
    // B. Check the content of each write
    foreach(actual_writes[i]) begin
        `FAIL_IF_LOG(
            actual_writes[i].addr !== expected_writes[i].addr, 
            $sformatf("Addr mismatch at %0d: exp %0h, got %0h", i, expected_writes[i].addr, actual_writes[i].addr)
        );
        `FAIL_IF_LOG(
            actual_writes[i].data !== expected_writes[i].data, 
            $sformatf("Data mismatch at %0d: exp %0h, got %0h", i, expected_writes[i].data, actual_writes[i].data)
        );
    end

`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 10: Reset during operation — mem_we deasserts, FSM returns to INIT_ST
// ----------------------------------------------------------------------------
`SVTEST(test_reset_during_operation)
    int writes_after_reset = 0;

    enable_writer(32'd0);

    // Send 2 samples
    cb.tb_s_axis_tvalid <= 1'b1;
    cb.tb_s_axis_tdata  <= 16'h1234;
    repeat(2) @(cb);

    // Assert reset
    cb.tb_rstn          <= 1'b0;
    // In a real scenario, the AXI master would stop driving tvalid immediately when reset is asserted.
    // We model this by de-asserting tvalid in the same cycle as reset.
    cb.tb_we_reg        <= 1'b0;
    cb.tb_s_axis_tvalid <= 1'b0;
    repeat(5) @(cb);
    cb.tb_rstn <= 1'b1;
    repeat(5) @(cb);

    // After reset: no writes, no tready
    repeat(5) @(cb) begin
        if (tb_mem_we) writes_after_reset++;
    end

    `FAIL_IF(writes_after_reset > 0);
    `FAIL_IF(tb_s_axis_tready);
`SVTEST_END
