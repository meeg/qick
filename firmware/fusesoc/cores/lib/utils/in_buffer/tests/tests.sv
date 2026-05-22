`SVTEST(test00_reset)

`ASSERT_IMMEDIATE(tb_i_data  == '0);     
`ASSERT_IMMEDIATE(tb_i_valid == 1'b0);     
`ASSERT_IMMEDIATE(tb_o_ready == 1'b0);     
repeat(5) @(cb);
for (integer k = 0; k < 10; k = k + 1) begin
  cb.tb_rstn <= 1'b0;

  @(cb);

  cb.tb_rstn <= 1'b1;

  @(cb);

  `ASSERT_IMMEDIATE(tb_i_data  == '0);     
  `ASSERT_IMMEDIATE(tb_i_valid == 1'b0);     
  `ASSERT_IMMEDIATE(tb_o_ready == 1'b0);     
  @(cb);
end

`SVTEST_END
//-------------------------------------------------------------------------------------------------//
`SVTEST(test00_data)

cb.tb_i_data  <= 32'h0000000A;     
cb.tb_i_valid <= 1'b1;     
cb.tb_o_ready <= 1'b1;     
@(cb);
for (integer k = 0; k < 10; k = k + 1) begin
  cb.tb_i_data <= k;
  @(cb);

  `ASSERT_IMMEDIATE(tb_o_data  == k);     
  `ASSERT_IMMEDIATE(tb_o_valid == 1'b1);     
  `ASSERT_IMMEDIATE(tb_o_ready == 1'b1);     
end
cb.tb_i_valid <= 1'b0;     
cb.tb_o_ready <= 1'b0;     
repeat(10) @(cb);

`SVTEST_END
//-------------------------------------------------------------------------------------------------//
