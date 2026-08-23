// ============================================================================
// File: axis_qick_processor_tests.sv
// Description: SVUnit test cases for axis_qick_processor. Included by
//              axis_qick_processor_tc00.sv.
// ============================================================================

`SVTEST(tc_reset_idle)
    logic [31:0] data;
    s_axi.axi_read(ADDR_TPROC_CTRL, data);
    `FAIL_UNLESS(data === 32'd0);
    s_axi.axi_read(ADDR_FIXED_ID, data);
    `FAIL_UNLESS(data === 32'd9);
    `FAIL_UNLESS(tb_s0_axis_tready); // unused-input tready is always driven high
`SVTEST_END

`SVTEST(tc_unused_input_ports_tie_ready_high)
    // Only s0 is wired into qick_processor (IN_PORT_QTY=1); every s*_axis
    // tready is still hard-tied to 1, including the unused ones.
    `FAIL_UNLESS(tb_s1_axis_tready);
`SVTEST_END

`SVTEST(tc_unused_wave_port_tied_off)
    // OUT_WPORT_QTY=1: channel 1's AXIS master output must be tied to
    // not-valid (gen_wave_port_not_present).
    `FAIL_IF(tb_m1_axis_tvalid);
`SVTEST_END

`SVTEST(tc_unused_trigger_pins_tied_off)
    // OUT_TRIG_QTY=2: only trig_0/trig_1 are wired; trig_2 and above must
    // be tied to 0 (gen_trigger_port_not_present).
    `FAIL_IF(tb_trig_2_o);
    `FAIL_IF(tb_trig_5_o);
    `FAIL_IF(tb_trig_31_o);
`SVTEST_END

`SVTEST(tc_axi_register_round_trip)
    logic [31:0] data;
    s_axi.axi_write(ADDR_TPROC_CFG, 32'h0000_0ABC);
    s_axi.axi_read(ADDR_TPROC_CFG, data);
    `FAIL_UNLESS(data === 32'h0000_0ABC);

    s_axi.axi_write(ADDR_CORE_CFG, 32'h0000_0055);
    s_axi.axi_read(ADDR_CORE_CFG, data);
    `FAIL_UNLESS(data === 32'h0000_0055);
`SVTEST_END

`SVTEST(tc_axi_start_reaches_run)
    bit reached;
    // TPROC_CTRL bit 2 = START; same integration path as qick_processor's
    // own testbench, exercised here through axis_qick_processor's flat
    // AXI-Lite pins.
    s_axi.axi_write(ADDR_TPROC_CTRL, 32'h0000_0004);
    wait_for_core_st(C_RUN, reached);
    `FAIL_UNLESS(reached);
`SVTEST_END

`SVTEST(tc_external_proc_start_pin_reaches_run)
    bit reached;
    // Exercises axis_qick_processor's OWN addition: the external
    // proc_start_i level pin, synchronized (cdc_reg_sync) and edge-detected
    // into a one-shot pulse before reaching qick_processor. The pin only
    // takes effect once TPROC_CFG[10] selects the external start source
    // (qproc_ctrl.sv's proc_start_io gate) -- mirrors the real driver's
    // start_src('external') (qick_lib/qick/drivers/tproc.py).
    s_axi.axi_write(ADDR_TPROC_CFG, 32'h0000_0400);

    @(negedge tb_clk);
    tb_proc_start_i = 1'b1;
    repeat(5) @(posedge tb_clk);
    tb_proc_start_i = 1'b0;

    wait_for_core_st(C_RUN, reached);
    `FAIL_UNLESS(reached);
`SVTEST_END
