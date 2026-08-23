// ============================================================================
// File: qproc_dispatcher_tests.sv
// Description: SVUnit test cases for qproc_dispatcher. Included by
//              qproc_dispatcher_tc00.sv.
// ============================================================================

`SVTEST(tc_reset_idle)
    `FAIL_IF(tb_all_fifo_full);
    `FAIL_IF(tb_some_fifo_full);
    `FAIL_IF(tb_port_trig_o[0]);
    `FAIL_IF(tb_port_tvalid_o[0]);
    `FAIL_IF(tb_m_axis_tvalid[0]);
`SVTEST_END

`SVTEST(tc_trigger_dispatch_fires_when_due)
    PORT_DT ev;
    ev = '{p_time: 32'd0, p_type: 1'b1, p_addr: 6'b10_0000, p_data: 168'd1}; // trigger ch0, value=1

    tb_core_en = 1'b1;
    tb_time_en = 1'b1;
    tb_time_abs_i = 48'd100; // already past any p_time=0 event

    push_event(ev);
    wait_until(tb_port_trig_o[0]);
    `FAIL_UNLESS(tb_port_trig_o[0]);
`SVTEST_END

`SVTEST(tc_data_dispatch_fires)
    PORT_DT ev;
    ev = '{p_time: 32'd0, p_type: 1'b1, p_addr: 6'b00_0000, p_data: 168'hA}; // data ch0, low nibble = 0xA

    tb_core_en = 1'b1;
    tb_time_en = 1'b1;
    tb_time_abs_i = 48'd100;

    push_event(ev);
    wait_until(tb_port_tvalid_o[0]);
    `FAIL_UNLESS(tb_port_tvalid_o[0]);
    `FAIL_UNLESS(tb_port_tdata_o[0] === 4'hA);
`SVTEST_END

`SVTEST(tc_wave_dispatch_waits_for_tready)
    PORT_DT ev;
    ev = '{p_time: 32'd0, p_type: 1'b0, p_addr: 6'd0, p_data: 168'h1122_3344_5566_7788_99AA_BBCC_DDEE_FF00_11};

    tb_core_en = 1'b1;
    tb_time_en = 1'b1;
    tb_time_abs_i = 48'd100;
    tb_m_axis_tready[0] = 1'b0;

    push_event(ev);
    // Give it plenty of time to (incorrectly) fire while tready is low.
    repeat(30) @(posedge tb_clk);
    `FAIL_IF(tb_m_axis_tvalid[0]);

    tb_m_axis_tready[0] = 1'b1;
    wait_until(tb_m_axis_tvalid[0]);
    `FAIL_UNLESS(tb_m_axis_tvalid[0]);
    `FAIL_UNLESS(tb_m_axis_tdata[0] === 168'h1122_3344_5566_7788_99AA_BBCC_DDEE_FF00_11);
`SVTEST_END

`SVTEST(tc_trigger_fifo_reports_full_when_filled)
    PORT_DT ev;
    // Never enable time_en, so nothing ever pops -- fill the 16-entry FIFO
    // (FIFO_DEPTH=4) with core_en held high.
    ev = '{p_time: 32'd0, p_type: 1'b1, p_addr: 6'b10_0000, p_data: 168'd1};

    tb_core_en = 1'b1;
    tb_time_en = 1'b0;

    for (int i = 0; i < 24; i++) begin
        push_event(ev);
    end
    wait_until(tb_some_fifo_full);
    `FAIL_UNLESS(tb_some_fifo_full);
`SVTEST_END

`SVTEST(tc_core_rst_flushes_trigger_fifo)
    PORT_DT ev;
    bit reached;
    ev = '{p_time: 32'd0, p_type: 1'b1, p_addr: 6'b10_0000, p_data: 168'd1};

    tb_core_en = 1'b1;
    tb_time_en = 1'b0; // don't drain, so the FIFO stays full after filling

    for (int i = 0; i < 24; i++) begin
        push_event(ev);
    end
    wait_until(tb_some_fifo_full);
    `FAIL_UNLESS(tb_some_fifo_full);

    // core_rst folds into the FIFO's wr_rstn (see the module header) and
    // should clear it back to not-full. XPM_FIFO_ASYNC's wr_rst_busy stays
    // high for a while after rst deasserts (see reset_dut()), so give the
    // same generous margin here.
    @(negedge tb_clk);
    tb_core_rst = 1'b1;
    repeat(4) @(posedge tb_clk);
    tb_core_rst = 1'b0;
    repeat(100) @(posedge tb_clk);
    `FAIL_IF(tb_some_fifo_full);
`SVTEST_END
