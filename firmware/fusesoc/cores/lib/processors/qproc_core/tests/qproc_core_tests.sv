// ============================================================================
// File: qproc_core_tests.sv
// Description: SVUnit test cases for qproc_core. Included by
//              qproc_core_tc00.sv.
// ============================================================================

`SVTEST(tc_reset_idle)
    ps_read(SEL_DMEM, 16'h0000);
    `FAIL_UNLESS(tb_ps_mem_r_dt_o === 168'd0);
`SVTEST_END

`SVTEST(tc_load_pmem_execute_store_to_dmem)
    bit matched;

    // Load a single store-immediate instruction (ai=0 -> dmem addr 0,
    // data = imm11) at PMEM address 0 via the PS port.
    ps_write(SEL_PMEM, 16'h0000, {96'd0, mk_store_imm(1'b0, 11'h055)});

    tb_en_i = 1'b1;

    matched = 1'b0;
    for (int n = 0; n < 40 && !matched; n++) begin
        ps_read(SEL_DMEM, 16'h0000);
        if (tb_ps_mem_r_dt_o === {136'd0, 32'h0000_0055})
            matched = 1'b1;
    end
    `FAIL_UNLESS(matched);
`SVTEST_END

`SVTEST(tc_halted_core_never_executes)
    // Same program as above, but en_i stays low: the CPU must never fetch,
    // so DMEM addr 0 stays whatever it already was (BRAM contents are not
    // cleared by reset, so don't assume it starts at 0 -- capture a
    // baseline first).
    logic [167:0] baseline;
    ps_read(SEL_DMEM, 16'h0000);
    baseline = tb_ps_mem_r_dt_o;

    ps_write(SEL_PMEM, 16'h0000, {96'd0, mk_store_imm(1'b0, 11'h055)});

    tb_en_i = 1'b0;
    repeat(40) @(posedge tb_clk);

    ps_read(SEL_DMEM, 16'h0000);
    `FAIL_UNLESS(tb_ps_mem_r_dt_o === baseline);
`SVTEST_END
