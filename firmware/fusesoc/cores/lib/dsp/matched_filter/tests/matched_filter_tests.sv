// ============================================================================
// File: matched_filter_tests.sv
// Description: SVUnit test cases for matched_filter.
// ============================================================================

`SVTEST(test_reset)
    `FAIL_IF(cb.tb_dout_valid_o)
    `FAIL_IF(cb.tb_trigger_o)
`SVTEST_END

// Loads the SAME weight value across the whole envelope table (sidesteps
// the WGT/DSP-latency address skew documented in matched_filter.sv's
// header -- whichever table index the read pointer has reached, the
// weight value is identical), then streams a constant sample and checks
// the complex-multiply result against a hand-computed expectation.
`SVTEST(test_weighted_multiply)
    logic [2*B-1:0] expected;
    logic [2*B-1:0] actual;
    int i;

    // I = 0x4000 (16384), Q = 0x0000.
    cb.tb_dw_addr_reg <= '0;
    cb.tb_we_reg      <= 1'b1;
    repeat(2) @(cb);
    for (i = 0; i < 8; i++) begin
        wgt_if.tx({16'h4000, 16'h0000});
    end
    cb.tb_we_reg <= 1'b0;
    repeat(5) @(cb);

    pulse_trigger();

    cb.tb_din_valid_i <= 1'b1;
    cb.tb_din_i        <= {16'h4000, 16'h0000};
    repeat(6) @(cb);
    cb.tb_din_valid_i <= 1'b0;

    // ac = 0x4000*0x4000 = 0x10000000 -> top 16 bits = 0x1000 (I).
    // bd = 0, ad = 0, bc = 0 -> Q = 0x0000.
    expected = {16'h1000, 16'h0000};

    wait_for_output(actual);
    `FAIL_UNLESS_EQUAL(actual, expected)
`SVTEST_END

// trigger_o must lag trigger_i by exactly WGT_LATENCY+DSP_LATENCY (7)
// register stages -- 8 clocking-block cycles counted from (and including)
// the cycle trigger_i first appears on the bus.
`SVTEST(test_trigger_latency)
    int cycles;
    int timed_out;

    cb.tb_trigger_i <= 1'b1;
    @(cb);
    cb.tb_trigger_i <= 1'b0;

    cycles = 1;
    timed_out = 0;
    while (!cb.tb_trigger_o && !timed_out) begin
        @(cb);
        cycles++;
        if (cycles > 20) timed_out = 1;
    end
    `FAIL_IF_LOG(timed_out, "test_trigger_latency: trigger_o never asserted");
    if (!timed_out) `FAIL_UNLESS_EQUAL(cycles, 8)
`SVTEST_END
