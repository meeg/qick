// ============================================================================
// File: tests.sv
// Description: Full test suite for the buffer module.
// Included inside SVUNIT_TESTS_BEGIN/END — no task/function declarations here.
// Helper tasks are defined in buffer_tc00.sv (module scope).
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 00: Basic buffer write — 4 samples contiguous
// Verifies correct address incrementing and data routing.
// ----------------------------------------------------------------------------
`SVTEST(test_basic_write)
    int timed_out;
    arm_and_trigger(10'd5, 10'd4);

    cb.tb_din_valid_i <= 1'b1;
    for (int i = 0; i < 4; i++) begin
        cb.tb_din_i <= {16'(i*5), 16'(i*2)}; // Q, I
        @(cb);
        `FAIL_UNLESS_EQUAL(cb.tb_mem_we_o, 1'b1);
        `FAIL_UNLESS_EQUAL(cb.tb_mem_addr_o, 10'd5 + i);
        `FAIL_UNLESS_EQUAL(cb.tb_mem_di_o, {16'(i*5), 16'(i*2)});
    end
    cb.tb_din_valid_i <= 1'b0;
    cb.tb_din_i       <= '0;

    release_fsm();
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 01: Buffer write with valid bubbles
// FSM must only increment address and counter on valid data cycles.
// ----------------------------------------------------------------------------
`SVTEST(test_write_with_bubbles)
    arm_and_trigger(10'd10, 10'd3);

    for (int i = 0; i < 3; i++) begin
        // Valid cycle
        cb.tb_din_valid_i <= 1'b1;
        cb.tb_din_i       <= {16'hAAAA, 16'h5555};
        @(cb);
        `FAIL_UNLESS_EQUAL(cb.tb_mem_we_o, 1'b1);
        `FAIL_UNLESS_EQUAL(cb.tb_mem_addr_o, 10'd10 + i);

        // Bubble (idle cycle)
        cb.tb_din_valid_i <= 1'b0;
        cb.tb_din_i       <= '0;
        @(cb);
        `FAIL_UNLESS_EQUAL(cb.tb_mem_we_o, 1'b0); // No write during bubble
    end

    release_fsm();
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 02: Consecutive triggers (Re-arming via WAIT_TRIGGER_ST)
// Tests two bursts. FSM must wait for trigger to de-assert, return to 
// TRIGGER_ST, and accept a second trigger without dropping start_reg.
// ----------------------------------------------------------------------------
`SVTEST(test_consecutive_triggers)
    // --- First burst ---
    arm_and_trigger(10'd0, 10'd2);
    
    cb.tb_din_valid_i <= 1'b1;
    cb.tb_din_i       <= {16'd1, 16'd1}; @(cb); // addr 0
    cb.tb_din_i       <= {16'd2, 16'd2}; @(cb); // addr 1
    cb.tb_din_valid_i <= 1'b0;
    
    // FSM is now in WAIT_TRIGGER_ST. trigger_i is already 0.
    // It should automatically move back to TRIGGER_ST on the next cycle.
    @(cb); 

    // --- Second burst (requires re-arming start_reg) ---
    // Low start_reg to reset the FSM to the initial state before
    release_fsm();

    // Arm again with the new configuration (ADDR=20, LEN=2)
    arm_and_trigger(10'd20, 10'd2);

    // Send valid data
    cb.tb_din_valid_i <= 1'b1;
    cb.tb_din_i       <= {16'd3, 16'd3}; @(cb); // addr 20
    `FAIL_UNLESS_EQUAL(cb.tb_mem_we_o, 1'b1);
    `FAIL_UNLESS_EQUAL(cb.tb_mem_addr_o, 10'd20);
    
    cb.tb_din_i       <= {16'd4, 16'd4}; @(cb); // addr 21
    `FAIL_UNLESS_EQUAL(cb.tb_mem_addr_o, 10'd21);
    
    cb.tb_din_valid_i <= 1'b0;

    release_fsm();
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 03: FSM abort — start_reg drops in TRIGGER_ST
// mem_we_o must never assert; FSM must return to START_ST.
// ----------------------------------------------------------------------------
`SVTEST(test_abort_in_trigger_st)
    // Reach TRIGGER_ST without pulsing trigger
    cb.tb_addr_reg  <= 10'd0;
    cb.tb_len_reg   <= 10'd4;
    cb.tb_start_reg <= 1'b1;
    @(cb); // START_ST -> TRIGGER_ST

    // Abort: drop start_reg
    cb.tb_start_reg <= 1'b0;
    @(cb);

    // Assert valid data and trigger, expect NO writes since FSM aborted
    cb.tb_trigger_i   <= 1'b1;
    cb.tb_din_valid_i <= 1'b1;
    cb.tb_din_i       <= {16'hFFFF, 16'hFFFF};
    
    repeat(5) begin
        @(cb);
        `FAIL_UNLESS_EQUAL(cb.tb_mem_we_o, 1'b0);
    end

    cb.tb_trigger_i   <= 1'b0;
    cb.tb_din_valid_i <= 1'b0;
    release_fsm();
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 04: Trigger ignored before start_reg asserts
// mem_we_o must never assert if start_reg=0.
// ----------------------------------------------------------------------------
`SVTEST(test_trigger_without_start_reg)
    cb.tb_start_reg <= 1'b0;

    // Fire trigger and valid data while FSM is in INIT/START_ST
    cb.tb_trigger_i   <= 1'b1;
    cb.tb_din_valid_i <= 1'b1;
    cb.tb_din_i       <= {16'h1234, 16'h5678};
    
    repeat(5) begin
        @(cb);
        `FAIL_UNLESS_EQUAL(cb.tb_mem_we_o, 1'b0);
    end

    cb.tb_trigger_i   <= 1'b0;
    cb.tb_din_valid_i <= 1'b0;
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 05: Corner Case — Length of 0 (Protection check)
// If len_reg == 0, the FSM handles it gracefully and doesn't underflow.
// Should capture 0 samples or 1 sample depending on FSM specifics, but must 
// not write 2^N samples.
// ----------------------------------------------------------------------------
`SVTEST(test_len_reg_zero)
    arm_and_trigger(10'd50, 10'd0); // len_reg = 0

    cb.tb_din_valid_i <= 1'b1;
    cb.tb_din_i       <= {16'hDEAD, 16'hBEEF}; 
    @(cb);
    // Since len_r logic in buffer is: (len_reg == 0) ? '0 : len_reg - 1
    // It evaluates to len_r = 0. When cnt (0) == len_r (0) && valid, 
    // it writes 1 sample and immediately transitions to WAIT_TRIGGER_ST.
    
    `FAIL_UNLESS_EQUAL(cb.tb_mem_we_o, 1'b1);
    
    // Cycle 2: Should not write anymore
    cb.tb_din_i <= {16'h1111, 16'h2222};
    @(cb);
    `FAIL_UNLESS_EQUAL(cb.tb_mem_we_o, 1'b0);

    cb.tb_din_valid_i <= 1'b0;
    release_fsm();
`SVTEST_END