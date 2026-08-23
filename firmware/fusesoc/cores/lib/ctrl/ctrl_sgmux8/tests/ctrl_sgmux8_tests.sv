// ============================================================================
// File: ctrl_sgmux8_tests.sv
// Description: SVUnit test cases for ctrl_sgmux8. Included by
//              ctrl_sgmux8_tc00.sv.
// ============================================================================

`SVTEST(tc_reset_idle_asserts_fifo_rd_en)
    // In READ_ST (the reset state), rd_en_int (and therefore fifo_rd_en_o)
    // is asserted unconditionally -- a real fifo simply won't produce valid
    // data while empty, the state machine only advances once it isn't.
    `FAIL_UNLESS(tb_fifo_rd_en_o === 1'b1);
    `FAIL_UNLESS(tb_en_o === 1'b0);
`SVTEST_END

`SVTEST(tc_mask_reaches_output_after_descriptor)
    bit reached;
    push_descriptor(8'hAB, 32'd3);
    wait_for_en(1'b1, 20, reached);
    `FAIL_UNLESS(reached);
    `FAIL_UNLESS(tb_mask_o === 8'hAB);
`SVTEST_END

`SVTEST(tc_en_deasserts_after_nsamp_plus_one_cycles)
    bit reached;
    push_descriptor(8'hFF, 32'd2);
    wait_for_en(1'b1, 20, reached);
    `FAIL_UNLESS(reached);
    // Playback runs nsamp+1 cycles in CNT_ST; en_o must eventually drop
    // back to 0 once the FSM returns to READ_ST and no new descriptor
    // follows.
    wait_for_en(1'b0, 30, reached);
    `FAIL_UNLESS(reached);
`SVTEST_END

`SVTEST(tc_ready_for_next_descriptor_after_playback)
    bit reached;
    push_descriptor(8'h01, 32'd1);
    wait_for_en(1'b0, 30, reached);
    `FAIL_UNLESS(reached);
    // Back in READ_ST: fifo_rd_en_o must be reasserted, ready to pop the
    // next descriptor. en_o (delay_line-pipelined) lags the FSM's own
    // return to READ_ST, so poll rather than assume they land on the
    // same cycle.
    wait_for_rd_en(1'b1, 10, reached);
    `FAIL_UNLESS(reached);
`SVTEST_END

`SVTEST(tc_back_to_back_descriptors_update_mask)
    bit reached;
    push_descriptor(8'h0F, 32'd1);
    wait_for_en(1'b1, 20, reached);
    `FAIL_UNLESS(reached);
    `FAIL_UNLESS(tb_mask_o === 8'h0F);

    wait_for_en(1'b0, 30, reached);
    `FAIL_UNLESS(reached);

    push_descriptor(8'hF0, 32'd1);
    wait_for_en(1'b1, 20, reached);
    `FAIL_UNLESS(reached);
    `FAIL_UNLESS(tb_mask_o === 8'hF0);
`SVTEST_END
