// ============================================================================
// File: qcore_ctrl_hazard_tests.sv
// Description: SVUnit test cases for qcore_ctrl_hazard. Included by
//              qcore_ctrl_hazard_tc00.sv.
// ============================================================================

`SVTEST(tc_reset_idle)
    #1;
    `FAIL_IF(tb_bubble_id_o);
    `FAIL_IF(tb_bubble_rd_o);
    `FAIL_UNLESS(tb_reg_d_dt_o[0] === 32'd0);
    `FAIL_UNLESS(tb_reg_a_dt_o[0] === 32'd0);
`SVTEST_END

`SVTEST(tc_dport_forward_from_x1_alu)
    tb_rs_d_addr_i[0] = 7'd5;
    tb_x1_reg_i = '{we: 1'b1, r_wave_we: 1'b0, addr: 7'd5, src: 2'b00, port_re: 1'b0};
    tb_x1_alu_dt_i = 32'hA1A1_A1A1;
    #1;
    `FAIL_IF(tb_bubble_rd_o); // ALU result is available combinationally, no stall
    @(posedge tb_clk);
    @(negedge tb_clk);
    `FAIL_UNLESS(tb_reg_d_dt_o[0] === 32'hA1A1_A1A1);
`SVTEST_END

`SVTEST(tc_dport_forward_from_x1_dmem_stalls)
    tb_rs_d_addr_i[0] = 7'd5;
    tb_x1_reg_i = '{we: 1'b1, r_wave_we: 1'b0, addr: 7'd5, src: 2'b01, port_re: 1'b0};
    #1;
    `FAIL_UNLESS(tb_bubble_rd_o); // DMEM data not back yet -> bubble
`SVTEST_END

`SVTEST(tc_dport_forward_from_x2_dmem_no_stall)
    tb_rs_d_addr_i[0] = 7'd6;
    tb_x2_reg_i = '{we: 1'b1, r_wave_we: 1'b0, addr: 7'd6, src: 2'b01, port_re: 1'b0};
    tb_x2_dmem_dt_i = 32'hB2B2_B2B2;
    #1;
    `FAIL_IF(tb_bubble_rd_o); // X2-stage DMEM data is already valid
    @(posedge tb_clk);
    @(negedge tb_clk);
    `FAIL_UNLESS(tb_reg_d_dt_o[0] === 32'hB2B2_B2B2);
`SVTEST_END

`SVTEST(tc_dport_no_forward_passthrough)
    tb_rs_d_addr_i[0] = 7'd9;
    tb_rs_d_dt_i[0]   = 32'hC3C3_C3C3;
    @(posedge tb_clk);
    @(negedge tb_clk);
    `FAIL_UNLESS(tb_reg_d_dt_o[0] === 32'hC3C3_C3C3);
`SVTEST_END

`SVTEST(tc_aport_forward_from_x1_alu)
    tb_rs_a_addr_i[0] = 6'd5;
    tb_x1_reg_i = '{we: 1'b1, r_wave_we: 1'b0, addr: 7'd5, src: 2'b00, port_re: 1'b0};
    tb_x1_alu_dt_i = 32'hD4D4_D4D4;
    #1;
    `FAIL_IF(tb_bubble_rd_o);
    @(posedge tb_clk);
    @(negedge tb_clk);
    `FAIL_UNLESS(tb_reg_a_dt_o[0] === 32'hD4D4_D4D4);
`SVTEST_END

`SVTEST(tc_aport_forward_from_x1_dmem_stalls)
    tb_rs_a_addr_i[0] = 6'd5;
    tb_x1_reg_i = '{we: 1'b1, r_wave_we: 1'b0, addr: 7'd5, src: 2'b01, port_re: 1'b0};
    #1;
    `FAIL_UNLESS(tb_bubble_rd_o);
`SVTEST_END

`SVTEST(tc_wmem_after_wave_write_stalls_id)
    tb_id_wmem_we = 1'b1;
    tb_x1_reg_i   = '{we: 1'b0, r_wave_we: 1'b1, addr: 7'd0, src: 2'b00, port_re: 1'b0};
    #1;
    `FAIL_UNLESS(tb_bubble_id_o);
`SVTEST_END

`SVTEST(tc_port_write_after_pending_write_stalls_id)
    tb_id_type_wp = 1'b1;
    tb_port_we    = 1'b1;
    #1;
    `FAIL_UNLESS(tb_bubble_id_o);
`SVTEST_END

`SVTEST(tc_flag_used_after_flag_we_stalls_id)
    tb_id_flag_used = 1'b1;
    tb_flag_we      = 1'b1;
    #1;
    `FAIL_UNLESS(tb_bubble_id_o);
`SVTEST_END

`SVTEST(tc_flag_used_after_cfg_write_stalls_id)
    tb_id_flag_used = 1'b1;
    tb_x1_reg_i = '{we: 1'b0, r_wave_we: 1'b0, addr: 7'b000_0010, src: 2'b00, port_re: 1'b0}; // s_cfg addr
    #1;
    `FAIL_UNLESS(tb_bubble_id_o);
`SVTEST_END

`SVTEST(tc_jump_after_saddr_write_stalls_id)
    tb_x1_reg_i = '{we: 1'b0, r_wave_we: 1'b0, addr: 7'b000_1111, src: 2'b00, port_re: 1'b0}; // s_addr
    tb_id_jmp_i = 1'b1;
    #1;
    `FAIL_UNLESS(tb_bubble_id_o);
`SVTEST_END

`SVTEST(tc_rand_access_always_stalls_id)
    tb_rd_reg_i = '{we: 1'b0, r_wave_we: 1'b0, addr: 7'b000_0001, src: 2'b00, port_re: 1'b0}; // s_rand write
    #1;
    `FAIL_UNLESS(tb_bubble_id_o);

    tb_rd_reg_i = NO_REG;
    tb_rs_d_addr_i[0] = 7'b000_0001; // s_rand read
    #1;
    `FAIL_UNLESS(tb_bubble_id_o);
`SVTEST_END

`SVTEST(tc_core_rdt_read_after_peripheral_stalls_rd)
    tb_rs_d_addr_i[0] = 7'b000_0110; // core_r_dt (address 6 or 7)
    tb_x1_periph_use  = 1'b1;
    #1;
    `FAIL_UNLESS(tb_bubble_rd_o);
`SVTEST_END

`SVTEST(tc_port_read_after_dport_rd_stalls_rd)
    tb_rs_d_addr_i[0] = 7'b000_1000; // in_port (address 8 or 9)
    tb_rd_reg_i = '{we: 1'b0, r_wave_we: 1'b0, addr: 7'd0, src: 2'b00, port_re: 1'b1};
    #1;
    `FAIL_UNLESS(tb_bubble_rd_o);
`SVTEST_END

`SVTEST(tc_status_read_after_cfg_write_stalls_rd)
    tb_rs_d_addr_i[0] = 7'b000_1010; // status
    tb_x1_reg_i = '{we: 1'b0, r_wave_we: 1'b0, addr: 7'b000_0010, src: 2'b00, port_re: 1'b0}; // s_cfg addr
    #1;
    `FAIL_UNLESS(tb_bubble_rd_o);
`SVTEST_END

`SVTEST(tc_stime_read_after_peripheral_stalls_rd)
    tb_rs_d_addr_i[0] = 7'b000_1011; // time_usr
    tb_x2_periph_use  = 1'b1;
    #1;
    `FAIL_UNLESS(tb_bubble_rd_o);
`SVTEST_END
