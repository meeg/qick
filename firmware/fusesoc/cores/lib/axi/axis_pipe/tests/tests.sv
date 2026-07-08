//-------------------------------------------------------------------------------------------------//
// tests.sv
// Se incluye entre `SVUNIT_TESTS_BEGIN y `SVUNIT_TESTS_END dentro de axis_pipe_unit_test
//-------------------------------------------------------------------------------------------------//

`SVTEST(test00_reset)
  m_axis_if.s_cb.tready <= 1'b1; // evitar X propagation
  repeat(2) @(cb);

  // Estado después de reset
  `FAIL_UNLESS(m_axis_if.s_cb.tvalid == 1'b0);
  `FAIL_UNLESS(s_axis_if.m_cb.tready == 1'b1);

  for (int k = 0; k < 10; k++) begin
    tb_rstn <= 1'b0;
    @(cb);
    tb_rstn <= 1'b1;
    @(cb);
    `FAIL_UNLESS(m_axis_if.s_cb.tvalid == 1'b0);
    `FAIL_UNLESS(s_axis_if.m_cb.tready == 1'b1);
  end
`SVTEST_END

//-------------------------------------------------------------------------------------------------//

`SVTEST(test00_data)
  m_axis_if.s_cb.tready <= 1'b1;
  s_axis_if.m_cb.tvalid <= 1'b0;
  @(cb);

  for (int k = 0; k < 10; k++) begin
    // Inyecta el dato k, con tlast en la última palabra
    s_axis_if.tx(k, (k == 9) ? 1'b1 : 1'b0);
    @(m_axis_if.s_cb);
    `FAIL_UNLESS(m_axis_if.s_cb.tvalid == 1'b1);
    `FAIL_UNLESS(m_axis_if.s_cb.tdata  == k);
  end

  s_axis_if.m_cb.tvalid <= 1'b0;
  m_axis_if.s_cb.tready <= 1'b0;
  repeat(10) @(cb);
`SVTEST_END

//-------------------------------------------------------------------------------------------------//