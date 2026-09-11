// ============================================================================
// File: axis_avg_buffer_tests.sv
// Description: SVUnit test cases for the axis_avg_buffer packaged IP.
// ============================================================================

`SVTEST(test_reset_idle)
    logic [31:0] rdata;
    reg_read(ADDR_AVG_START, rdata);
    `FAIL_UNLESS_EQUAL(rdata[0], 1'b0)
    reg_read(ADDR_BUF_START, rdata);
    `FAIL_UNLESS_EQUAL(rdata[0], 1'b0)
    `FAIL_UNLESS_EQUAL(m0_if.tvalid, 1'b0)
    `FAIL_UNLESS_EQUAL(m1_if.tvalid, 1'b0)
    `FAIL_UNLESS_EQUAL(m2_if.tvalid, 1'b0)
`SVTEST_END

`SVTEST(test_register_readback)
    logic [31:0] rdata;

    reg_write(ADDR_AVG_ADDR, 32'd3);
    reg_read(ADDR_AVG_ADDR, rdata);
    `FAIL_UNLESS_EQUAL(rdata, 32'd3)

    reg_write(ADDR_AVG_LEN, 32'd5);
    reg_read(ADDR_AVG_LEN, rdata);
    `FAIL_UNLESS_EQUAL(rdata, 32'd5)

    reg_write(ADDR_BUF_ADDR, 32'd7);
    reg_read(ADDR_BUF_ADDR, rdata);
    `FAIL_UNLESS_EQUAL(rdata, 32'd7)

    reg_write(ADDR_BUF_LEN, 32'd4);
    reg_read(ADDR_BUF_LEN, rdata);
    `FAIL_UNLESS_EQUAL(rdata, 32'd4)

    reg_write(ADDR_AVG_PHOTON_MODE, 32'd1);
    reg_read(ADDR_AVG_PHOTON_MODE, rdata);
    `FAIL_UNLESS_EQUAL(rdata[0], 1'b1)

    reg_write(ADDR_AVG_H_THRSH, 32'h0000_1234);
    reg_read(ADDR_AVG_H_THRSH, rdata);
    `FAIL_UNLESS_EQUAL(rdata, 32'h0000_1234)

    reg_write(ADDR_AVG_L_THRSH, 32'h0000_0056);
    reg_read(ADDR_AVG_L_THRSH, rdata);
    `FAIL_UNLESS_EQUAL(rdata, 32'h0000_0056)
`SVTEST_END

// Arm buf via the AXI-Lite register map, pulse the shared hardware trigger,
// feed a few constant samples, then drain the raw-capture BRAM back out
// m1_axis and confirm it round-trips exactly. This is the one thing that's
// genuinely new at THIS layer (the AXI-Lite decode driving the datapath) --
// buffer/buffer_top's own testbenches already exhaustively cover the FSM.
`SVTEST(test_buf_capture_and_readback)
    logic [2*B-1:0] expected;
    int i, timeout;
    int timed_out = 0;

    expected = {16'h0000, 16'h002A}; // 42

    arm_buf(32'd0, 32'd3);
    pulse_trigger();
    drive_const_samples(3, expected);

    reg_write(ADDR_BUF_DR_ADDR, 32'd0);
    reg_write(ADDR_BUF_DR_LEN, 32'd3);
    reg_write(ADDR_BUF_DR_START, 32'h1);

    m1_if.tready = 1'b1;
    for (i = 0; i < 3 && !timed_out; i++) begin
        timeout = 0;
        while (!m1_if.tvalid && !timed_out) begin
            @(posedge axis_clk);
            timeout++;
            if (timeout > 500) timed_out = 1;
        end
        if (!timed_out) begin
            `FAIL_UNLESS_EQUAL(m1_if.tdata, expected)
            @(posedge axis_clk);
        end
    end
    `FAIL_IF_LOG(timed_out, "test_buf_capture_and_readback: timed out waiting for m1_axis data")

    reg_write(ADDR_BUF_DR_START, 32'h0);
    repeat(5) @(posedge axis_clk);
`SVTEST_END

// Confirm the shared trigger port reaches the avg datapath too (arming avg
// only, not buf) -- proves the register map correctly gates AVG_START
// independently of BUF_START. Exact accumulator arithmetic is already
// covered by avg's own 16/16 SVUnit suite; here we only need liveness.
`SVTEST(test_avg_only_arms_avg_not_buf)
    int timeout = 0;
    int timed_out = 0;

    arm_avg(32'd0, 32'd3);
    pulse_trigger();
    drive_const_samples(3, {16'h0000, 16'h000A});

    reg_write(ADDR_AVG_DR_ADDR, 32'd0);
    reg_write(ADDR_AVG_DR_LEN, 32'd1);
    reg_write(ADDR_AVG_DR_START, 32'h1);

    m0_if.tready = 1'b1;
    while (!m0_if.tvalid && !timed_out) begin
        @(posedge axis_clk);
        timeout++;
        if (timeout > 500) timed_out = 1;
    end
    `FAIL_IF_LOG(timed_out, "test_avg_only_arms_avg_not_buf: timed out waiting for m0_axis data")
    if (!timed_out) `FAIL_IF(m0_if.tdata === '0)

    reg_write(ADDR_AVG_DR_START, 32'h0);
    repeat(5) @(posedge axis_clk);

    // buf was never armed, so its m1 stream must stay idle.
    `FAIL_UNLESS_EQUAL(m1_if.tvalid, 1'b0)
`SVTEST_END
