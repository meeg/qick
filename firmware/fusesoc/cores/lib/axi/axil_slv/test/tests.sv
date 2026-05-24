`SVTEST(test00_reset)

//`ASSERT_IMMEDIATE(tb_cb.tb_o_data  == '0);     
//repeat(5) @(tb_cb);
for (integer k = 0; k < 10; k = k + 1) begin
    tb_rstn <= 1'b0;
    @(s_axi.m_cb);
    tb_rstn <= 1'b1;
    @(s_axi.m_cb);
    //`ASSERT_IMMEDIATE(tb_cb.tb_o_data  == '0);     
end

`SVTEST_END
//-------------------------------------------------------------------------------------------------//
`SVTEST(test01_write_all)

 for (int i = 0; i < NUM_REGS; i++) begin
  s_axi.axi_write(4*i,  32'h1 + i);
    //`FAIL_UNLESS_EQUAL(rx_data, (a[NB-1:0] + b[NB-1:0]));
  end
`SVTEST_END

