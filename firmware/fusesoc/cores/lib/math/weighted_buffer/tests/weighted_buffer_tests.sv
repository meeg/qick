// ============================================================================
// File: weighted_buffer_tests.sv
// Description: SVUnit test cases for weighted_buffer.
// ============================================================================

`SVTEST(test_reset_idle)
    `FAIL_UNLESS_EQUAL(m0_if.tvalid, 1'b0)
    `FAIL_UNLESS_EQUAL(m1_if.tvalid, 1'b0)
    `FAIL_UNLESS_EQUAL(m2_if.tvalid, 1'b0)
`SVTEST_END

// Loads a constant weight across the whole envelope table and streams a
// constant sample -- with everything constant, the 2-sample WGT/DSP
// address skew documented in matched_filter.sv becomes invisible, letting
// this test focus on "is weighting actually applied end to end" (buf
// readback must show the FILTERED product, not the raw input).
//
// CONFIRMED IN SIMULATION: the first sample buffer_top captures after
// each trigger is stale (reads 0, not the filtered product). This is a
// direct, faithfully-reproduced consequence of matched_filter's
// dout_valid_o/dout_o skew (see matched_filter.sv's header): avg_buffer.v
// (legacy) wires matched_filter's dout_valid_o/dout_o straight into
// avg_top_i/buffer_top_i's din_valid_i/din_i with no compensating
// register, exactly as ported here in weighted_buffer.sv -- so
// buffer_top's TRIGGER_ST->MEMW_ST transition (gated by trigger_filtered,
// which shares matched_filter's TOTAL_LATENCY chain with dout_valid_o)
// lines up with the *first* dout_valid_o pulse, whose dout_o has not
// settled yet. Every capture window is effectively one sample short of
// what was requested, with a stale leading sample. Reproduced and
// verified here rather than silently corrected; flag to hardware owners
// if unintended.
`SVTEST(test_weighted_buf_readback)
    logic [2*B-1:0] expected;
    logic [2*B-1:0] actual[];
    int timed_out;
    int timeout;
    int i;

    // I = 0x4000 (16384), Q = 0x0000.
    load_constant_weight({16'h4000, 16'h0000});

    arm_buf(8'd0, 8'd3);
    pulse_trigger();
    inject_data(3, {16'h4000, 16'h0000});

    // ac = 0x4000*0x4000 -> top 16 bits = 0x1000 (I); Q stays 0.
    expected = {16'h1000, 16'h0000};

    tb_buf_dr_addr_reg  = '0;
    tb_buf_dr_len_reg   = 9'd3;
    tb_buf_dr_start_reg = 1'b1;

    actual = new[3];
    m1_if.tready = 1'b1;
    timed_out = 0;
    for (i = 0; i < 3 && !timed_out; i++) begin
        timeout = 0;
        while (!m1_if.tvalid && !timed_out) begin
            @(posedge tb_clk);
            timeout++;
            if (timeout > 500) timed_out = 1;
        end
        if (!timed_out) begin
            actual[i] = m1_if.tdata;
            @(posedge tb_clk);
        end
    end
    `FAIL_IF_LOG(timed_out, "test_weighted_buf_readback: timed out waiting for m1_axis data")

    // actual[0] is the stale leading sample (see header comment above);
    // actual[1]/actual[2] are the true filtered products.
    if (!timed_out) begin
        `FAIL_UNLESS_EQUAL(actual[1], expected)
        `FAIL_UNLESS_EQUAL(actual[2], expected)
    end

    tb_buf_dr_start_reg = 1'b0;
    repeat(5) @(posedge tb_clk);
`SVTEST_END

// Confirm the shared trigger fans out to avg too (arm avg only, not buf) --
// proves matched_filter's trigger_o (DSP-latency compensated) reaches both
// sub-blocks through the same composition path as avg_buffer's own test.
`SVTEST(test_weighted_avg_arms_on_shared_trigger)
    int timed_out;
    int timeout;

    load_constant_weight({16'h4000, 16'h0000});

    arm_avg(8'd0, 32'd3);
    pulse_trigger();
    inject_data(3, {16'h4000, 16'h0000});

    tb_avg_dr_addr_reg  = '0;
    tb_avg_dr_len_reg   = 9'd1;
    tb_avg_dr_start_reg = 1'b1;

    m0_if.tready = 1'b1;
    timed_out = 0;
    timeout = 0;
    while (!m0_if.tvalid && !timed_out) begin
        @(posedge tb_clk);
        timeout++;
        if (timeout > 500) timed_out = 1;
    end
    `FAIL_IF_LOG(timed_out, "test_weighted_avg_arms_on_shared_trigger: timed out waiting for m0_axis data")
    if (!timed_out) `FAIL_IF(m0_if.tdata === '0)

    tb_avg_dr_start_reg = 1'b0;
    repeat(5) @(posedge tb_clk);
`SVTEST_END
