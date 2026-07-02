// ============================================================================
// File: axis_to_bram_trig_tests.sv
// Description: SVUnit test cases for axis_to_bram_trig.
// Included by axis_to_bram_trig_tc00.sv.
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 01: Reset — no writes, tready low
// ----------------------------------------------------------------------------
`SVTEST(test_reset_no_write)
    axis_if.s_cb.tready <= 1'b1;
    repeat(5) @(tb_cb);
    `FAIL_IF(axis_if.s_cb.tvalid);
    repeat(5) @(tb_cb);
`SVTEST_END
