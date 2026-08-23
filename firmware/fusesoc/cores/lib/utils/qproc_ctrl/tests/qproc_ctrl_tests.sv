// ============================================================================
// File: qproc_ctrl_tests.sv
// Description: SVUnit test cases for qproc_ctrl. Included by
//              qproc_ctrl_tc00.sv.
// ============================================================================

`SVTEST(tc_reset_holds_core_and_time_in_reset)
    // The core FSM parks in C_RST_STOP (asserting core_rst_o) until
    // all_fifo_full_i pulses -- it does not self-advance.
    `FAIL_UNLESS(tb_core_st_do === C_RST_STOP);
    `FAIL_UNLESS(tb_core_rst_o);

    // The time FSM's RST_STOP has no such external gate: it pulses
    // time_rst_o for exactly one cycle and then self-advances to T_STOP, so
    // by the time setup() settles it has already parked in T_STOP.
    `FAIL_UNLESS(tb_time_st_do === T_STOP);
    `FAIL_IF(tb_time_rst_o);
`SVTEST_END

`SVTEST(tc_core_start_reaches_run_via_fifo_handshake)
    bit reached;

    // START (ps_tproc_ctrl_i[2]) drives core_rst_run_p; the FSM parks in
    // C_RST_RUN asserting core_rst_o until all_fifo_full_i is seen high,
    // then waits for it to drop before declaring C_RUN.
    tb_all_fifo_full_i = 1'b1;
    tb_ps_tproc_ctrl_i[2] = 1'b1;
    wait_for_core_st(C_RST_RUN_WAIT, reached);
    `FAIL_UNLESS(reached);

    tb_all_fifo_full_i = 1'b0;
    wait_for_core_st(C_RUN, reached);
    `FAIL_UNLESS(reached);
    `FAIL_UNLESS(tb_core_en_o);
`SVTEST_END

`SVTEST(tc_core_stop_returns_to_stop)
    bit reached;

    tb_all_fifo_full_i = 1'b1;
    tb_ps_tproc_ctrl_i[2] = 1'b1; // START
    wait_for_core_st(C_RST_RUN_WAIT, reached);
    `FAIL_UNLESS(reached);
    tb_all_fifo_full_i = 1'b0;
    wait_for_core_st(C_RUN, reached);
    `FAIL_UNLESS(reached);

    tb_ps_tproc_ctrl_i[3] = 1'b1; // STOP (bit-wise edge-detected, bit2 stays steady)
    wait_for_core_st(C_STOP, reached);
    `FAIL_UNLESS(reached);
    `FAIL_IF(tb_core_en_o);
`SVTEST_END

`SVTEST(tc_time_free_runs_after_start)
    bit reached;
    logic [47:0] prev;

    tb_ps_tproc_ctrl_i[2] = 1'b1; // START -> time_rst_run_p (T_RST_RUN auto-advances to T_RUN)
    wait_for_time_st(T_RUN, reached);
    `FAIL_UNLESS(reached);

    repeat(2) @(posedge tb_clk);
    prev = tb_time_abs_o;
    repeat(5) begin
        @(posedge tb_clk);
        `FAIL_UNLESS(tb_time_abs_o === prev + 48'd1);
        prev = tb_time_abs_o;
    end
`SVTEST_END
