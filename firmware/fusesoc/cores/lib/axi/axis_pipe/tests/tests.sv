`SVTEST(test00_reset)

m_axis_if.s_cb.tready <= 1'b1; // evitar X propagation

repeat(2) @(cb);

// Estado después de reset
`ASSERT_IMMEDIATE(m_axis_if.s_cb.tvalid == 1'b0);
`ASSERT_IMMEDIATE(s_axis_if.m_cb.tready == 1'b1);

for (int k = 0; k < 10; k++) begin
  tb_rstn <= 1'b0;
  @(cb);

  tb_rstn <= 1'b1;
  @(cb);

  `ASSERT_IMMEDIATE(m_axis_if.s_cb.tvalid == 1'b0);
  `ASSERT_IMMEDIATE(s_axis_if.m_cb.tready == 1'b1);
end

`SVTEST_END

//-------------------------------------------------------------------------------------------------//
`SVTEST(test00_data)

s_axis_if.m_cb.tdata  <= 32'h0000000A;     
@(m_axis_if.s_cb);
s_axis_if.m_cb.tvalid <= 1'b1;     
m_axis_if.s_cb.tready <= 1'b1;     
for (integer k = 0; k < 10; k = k + 1) begin
  s_axis_if.tx(k,(k == 9) ? 1'b1 : 1'b0);
  @(m_axis_if.s_cb);

  `ASSERT_IMMEDIATE(m_axis_if.s_cb.tdata  == k);     
  `ASSERT_IMMEDIATE(m_axis_if.s_cb.tvalid == 1'b1);     
end
s_axis_if.m_cb.tvalid <= 1'b0;     
m_axis_if.s_cb.tready <= 1'b0;     
repeat(10) @(cb);

`SVTEST_END
//-------------------------------------------------------------------------------------------------//
