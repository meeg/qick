`SVTEST(test00_reset)

//`ASSERT_IMMEDIATE(cb.tb_o_up  == 1'b0);     
//`ASSERT_IMMEDIATE(cb.tb_o_dn  == 1'b0);     
for (integer k = 0; k < 10; k = k + 1) begin
  cb.tb_rstn <= 1'b0;
  //`ASSERT_IMMEDIATE(cb.tb_o_up  == 1'b0);     
  //`ASSERT_IMMEDIATE(cb.tb_o_dn  == 1'b0);     
  @(cb);
  cb.tb_rstn <= 1'b1;
  @(cb);
end
  repeat(100) @(cb);

`SVTEST_END
//-------------------------------------------------------------------------------------------------//
`SVTEST(test01_normal)

    @(cb);
    for (integer k = 0; k < 10; k = k + 1) begin
        repeat($urandom_range(1,100))@(cb);
        //`ASSERT_IMMEDIATE(tb_o_data  == k);     
    end
    repeat(1000) @(cb);
     
`SVTEST_END
//-------------------------------------------------------------------------------------------------//
//`SVTEST(test02_8bit_data)
//
//    cb.tb_i_data  <= 8'hAB;     
//    @(cb);
//        for (integer k = 0; k < 10; k = k + 1) begin
//          cb.tb_i_data <= k;
//          repeat(5)@(cb);
//          //`ASSERT_IMMEDIATE(tb_o_data  == k);     
//    end
//    repeat(10) @(cb);
//     
//`SVTEST_END
////-------------------------------------------------------------------------------------------------//
