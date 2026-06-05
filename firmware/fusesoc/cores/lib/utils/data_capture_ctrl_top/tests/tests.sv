// ============================================================================
// File: tests.sv
// Description: Test suite for buffer_top module.
// Included inside SVUNIT_TESTS_BEGIN/END of buffer_top_tc00.sv.
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 00: Reset State
// Verify that AXIS master signals are de-asserted following a system reset.
// ----------------------------------------------------------------------------
`SVTEST(test_reset)
    `FAIL_IF(m_axis_tvalid !== 1'b0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 01: Basic Capture and Readback
// Configure the buffer, inject 4 consecutive data samples, and read them back
// via the AXI Stream master interface. Verify data integrity.
// ----------------------------------------------------------------------------
`SVTEST(test_write_read_basic)
    int num_samples = 4;
    logic [2*B-1:0] read_data[];
    int timed_out;
    int tlast_err;
    int errors = 0;
    logic [2*B-1:0] base_val = 32'hA000_0001;

    // 1. Arm buffer and inject data
    arm_and_trigger(N'(0), N'(num_samples));
    inject_data(num_samples, base_val);
    
    // Release buffer start register to finish capture (if required by FSM)
    repeat(5) @(sys_cb);
    sys_cb.buf_start_reg <= 1'b0;

    // Margin for Clock Domain Crossing (CDC) into BRAM/AXI domains
    repeat(15) @(axi_cb);

    // 2. Start reader and fetch data
    start_reader(N'(0), N'(num_samples));
    read_m_data(num_samples, read_data, timed_out, tlast_err);

    axi_cb.dr_start_reg <= 1'b0;

    `FAIL_IF(timed_out);
    if (tlast_err > 0) $display("[FAIL] tlast asserted at the wrong word index.");
    `FAIL_IF(tlast_err > 0);

    // 3. Verify data payload
    for (int i = 0; i < num_samples; i++) begin
        if (read_data[i] !== (base_val + i)) begin
            $display("[FAIL] Data mismatch at idx %0d: Expected %0h, Got %0h", i, (base_val + i), read_data[i]);
            errors++;
        end
    end
    `FAIL_IF(errors > 0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 02: Read with Backpressure
// Simulate a slow AXI Stream slave by toggling m_axis_tready. Ensure the
// reader FSM halts appropriately and no data words are lost or duplicated.
// ----------------------------------------------------------------------------
`SVTEST(test_read_backpressure)
    int num_samples = 9;
    logic [2*B-1:0] read_data[];
    int count = 0;
    int timeout_cnt = 0;
    int errors = 0;
    logic [2*B-1:0] base_val = 32'hBEEF_0000;
    
    // Arm, trigger, and write data
    arm_and_trigger(N'(10), N'(num_samples));
    inject_data(num_samples, base_val);
    
    repeat(5) @(sys_cb);
    sys_cb.buf_start_reg <= 1'b0;
    repeat(15) @(axi_cb);

    // Start reader
    start_reader(N'(10), N'(num_samples));
    read_data = new[num_samples];

    // Interleave tready to stall the reader pipeline
    while (count < num_samples) begin
        axi_cb.m_axis_tready <= 1'b1;
        @(axi_cb);
        if (m_axis_tvalid && m_axis_tready) begin
            read_data[count] = m_axis_tdata;
            count++;
            
            // Stash tready for 4 cycles to simulate backpressure
            if (count < num_samples) begin
                axi_cb.m_axis_tready <= 1'b0; 
                repeat(4) @(axi_cb);
            end
        end
        
        timeout_cnt++;
        if (timeout_cnt > 200) begin
            $display("[FAIL] Timeout waiting for data during backpressure test.");
            `FAIL_IF(1);
        end
    end
    axi_cb.m_axis_tready <= 1'b0;
    repeat(5) @(axi_cb);

    // Verify all data words arrived intact
    for (int i = 0; i < num_samples; i++) begin
        if (read_data[i] !== (base_val + i)) errors++;
    end
    `FAIL_IF(errors > 0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 03: Reset Recovery During Operation
// Issue an asynchronous reset midway through an active capture. Verify that 
// the module recovers safely and can execute a subsequent capture flawlessly.
// ----------------------------------------------------------------------------
`SVTEST(test_reset_recovery)
    int num_samples = 3;
    logic [2*B-1:0] read_data[];
    int timed_out;
    int tlast_err;

    // Phase 1: Initiate capture, then interrupt with reset
    arm_and_trigger(N'(20), N'(10));
    sys_cb.din_valid_i <= 1'b1;
     repeat(5) begin
        sys_cb.din_i <= 32'hDEAD_BEEF;
        @(sys_cb);
    end
    sys_cb.din_valid_i <= 1'b0;
    sys_cb.din_i       <= '0;

    // Reset mid-capture — reset_dut manages the full cycle and stabilization
    sys_cb.buf_start_reg  <= 1'b0;
    sys_cb.buf_len_reg    <= '0;
    sys_cb.buf_addr_reg   <= '0;

    // Trigger abrupt hardware reset
    reset_dut();
    
    // Clear stimuli from Phase 1
    sys_cb.din_valid_i   <= 1'b0;
    sys_cb.buf_start_reg <= 1'b0;

    // Phase 2: Attempt clean operation post-reset
    arm_and_trigger(N'(30), N'(num_samples));
    inject_data(num_samples, 32'hCAFE_0000);
    
    repeat(5) @(sys_cb);
    sys_cb.buf_start_reg <= 1'b0;
    repeat(15) @(axi_cb);

    start_reader(N'(30), N'(num_samples));
    read_m_data(num_samples, read_data, timed_out, tlast_err);
    
    `FAIL_IF(timed_out);
    `FAIL_IF(tlast_err > 0);
    `FAIL_IF(read_data[0] !== 32'hCAFE_0000); // Verify integrity of the first word
`SVTEST_END
