// ============================================================================
// File: axis_weighted_buffer_tests.sv
// Description: SVUnit test cases for the axis_weighted_buffer packaged IP.
// ============================================================================

`SVTEST(test_reset_idle)
    logic [31:0] rdata;
    reg_read(ADDR_START, rdata);
    `FAIL_UNLESS_EQUAL(rdata[1:0], 2'b00)
    `FAIL_UNLESS_EQUAL(m0_if.tvalid, 1'b0)
    `FAIL_UNLESS_EQUAL(m1_if.tvalid, 1'b0)
    `FAIL_UNLESS_EQUAL(m2_if.tvalid, 1'b0)
`SVTEST_END

`SVTEST(test_register_readback)
    logic [31:0] rdata;

    reg_write(ADDR_AVG_ADDR, 32'd3);
    reg_read(ADDR_AVG_ADDR, rdata);
    `FAIL_UNLESS_EQUAL(rdata, 32'd3)

    reg_write(ADDR_BUF_LEN, 32'd4);
    reg_read(ADDR_BUF_LEN, rdata);
    `FAIL_UNLESS_EQUAL(rdata, 32'd4)

    reg_write(ADDR_AVG_H_THRSH, 32'h0000_1234);
    reg_read(ADDR_AVG_H_THRSH, rdata);
    `FAIL_UNLESS_EQUAL(rdata, 32'h0000_1234)

    reg_write(ADDR_WGT_DW_ADDR, 32'h0000_0007);
    reg_read(ADDR_WGT_DW_ADDR, rdata);
    `FAIL_UNLESS_EQUAL(rdata, 32'h0000_0007)

    // start_reg: bit0=avg, bit1=buf are independent bits of the SAME register.
    reg_write(ADDR_START, 32'h3);
    reg_read(ADDR_START, rdata);
    `FAIL_UNLESS_EQUAL(rdata[1:0], 2'b11)
`SVTEST_END

// Loads a constant weight across the whole envelope table and streams a
// constant sample -- buf readback must show the FILTERED product, not the
// raw input, proving the register map correctly reaches matched_filter's
// weight-load path and the datapath through to buffer_top.
//
// The first captured sample is stale (see weighted_buffer's own test for
// the full explanation: matched_filter's dout_valid_o/dout_o skew,
// faithfully reproduced from the legacy avg_buffer.v wiring) -- only
// samples[1:] are checked here.
`SVTEST(test_weighted_buf_readback)
    logic [2*B-1:0] expected;
    int i, timeout;
    int timed_out = 0;

    // I = 0x4000 (16384), Q = 0x0000.
    load_constant_weight({16'h4000, 16'h0000});

    arm_buf(32'd0, 32'd3);
    pulse_trigger();
    drive_const_samples(3, {16'h4000, 16'h0000});

    // ac = 0x4000*0x4000 -> top 16 bits = 0x1000 (I); Q stays 0.
    expected = {16'h1000, 16'h0000};

    reg_write(ADDR_BUF_DR_ADDR, 32'd0);
    reg_write(ADDR_BUF_DR_LEN, 32'd3);
    reg_write(ADDR_DR_START, 32'h2); // bit1 = BUF_DR_START

    m1_if.tready = 1'b1;
    for (i = 0; i < 3 && !timed_out; i++) begin
        timeout = 0;
        while (!m1_if.tvalid && !timed_out) begin
            @(posedge axis_clk);
            timeout++;
            if (timeout > 500) timed_out = 1;
        end
        if (!timed_out) begin
            // Skip the stale leading sample (i==0); verify the rest.
            if (i != 0) `FAIL_UNLESS_EQUAL(m1_if.tdata, expected)
            @(posedge axis_clk);
        end
    end
    `FAIL_IF_LOG(timed_out, "test_weighted_buf_readback: timed out waiting for m1_axis data")

    reg_write(ADDR_DR_START, 32'h0);
    repeat(5) @(posedge axis_clk);
`SVTEST_END
