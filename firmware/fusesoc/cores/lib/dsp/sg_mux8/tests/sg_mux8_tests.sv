// ============================================================================
// File: sg_mux8_tests.sv
// Description: SVUnit test cases for sg_mux8. Included by sg_mux8_tc00.sv.
// ============================================================================

`SVTEST(tc_reset_idle)
    `FAIL_UNLESS(tb_m_axis_tvalid_o === 1'b0);
    `FAIL_UNLESS(tb_s_axis_tready_o === 1'b1);
    `FAIL_UNLESS(tb_m_axis_tdata_o === '0);
`SVTEST_END

`SVTEST(tc_descriptor_produces_valid_output)
    bit reached;
    write_channel_regs(0, 32'h1000_0000, 32'h0000_0000, 16'h7FFF);
    push_descriptor(8'h01, 32'd20);
    wait_for_mvalid(1'b1, 40, reached);
    `FAIL_UNLESS(reached);
`SVTEST_END

`SVTEST(tc_all_channels_masked_off_gives_zero_output)
    bit reached;
    write_channel_regs(0, 32'h1000_0000, 32'h0000_0000, 16'h7FFF);
    // mask=0: every channel is muted regardless of PINC/GAIN, so the
    // adder-tree sum (and therefore m_axis_tdata_o) must stay zero even
    // while tvalid is asserted for the descriptor's duration.
    push_descriptor(8'h00, 32'd20);
    wait_for_mvalid(1'b1, 40, reached);
    `FAIL_UNLESS(reached);
    `FAIL_UNLESS(tb_m_axis_tdata_o === '0);
`SVTEST_END

`SVTEST(tc_mvalid_deasserts_after_playback)
    bit reached;
    write_channel_regs(0, 32'h1000_0000, 32'h0000_0000, 16'h7FFF);
    push_descriptor(8'h01, 32'd4);
    wait_for_mvalid(1'b1, 40, reached);
    `FAIL_UNLESS(reached);
    wait_for_mvalid(1'b0, 30, reached);
    `FAIL_UNLESS(reached);
`SVTEST_END

`SVTEST(tc_ready_stays_high_when_fifo_not_full)
    // A single descriptor push never comes close to filling the 16-deep
    // fifo_sync, so tready should never drop during normal operation.
    write_channel_regs(0, 32'h1000_0000, 32'h0000_0000, 16'h7FFF);
    push_descriptor(8'h01, 32'd4);
    `FAIL_UNLESS(tb_s_axis_tready_o === 1'b1);
`SVTEST_END
