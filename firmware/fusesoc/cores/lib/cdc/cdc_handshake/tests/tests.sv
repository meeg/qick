//-------------------------------------------------------------------------------------------------//
`SVTEST(test00_reset)
  // Out of reset, nothing in flight: not busy, no spurious valid.
  repeat (10) @(src_cb);
  `FAIL_IF(tb_o_busy != 1'b0);
  `FAIL_IF(tb_o_valid != 1'b0);
`SVTEST_END

//-------------------------------------------------------------------------------------------------//
`SVTEST(test01_single_transfer)
  send_and_wait(8'hA5);
  `FAIL_IF(tb_o_data != 8'hA5);
`SVTEST_END

//-------------------------------------------------------------------------------------------------//
`SVTEST(test02_busy_asserts_while_in_flight)
  @(src_cb);
  src_cb.tb_i_data  <= 8'h3C;
  src_cb.tb_i_valid <= 1'b1;
  @(src_cb);
  src_cb.tb_i_valid <= 1'b0;

  // o_busy must be observable asserted immediately after the request
  `FAIL_IF(tb_o_busy != 1'b1);

  // ... and must clear again once the transfer completes.
  fork
    begin : wait_dst
      int timeout;
      timeout = 0;
      do begin
        @(dst_cb);
        timeout++;
        if (timeout > 200) `FAIL_IF_LOG(1, "timed out waiting for o_valid");
      end while (!dst_cb.tb_o_valid);
    end
  join

  repeat(20) @(src_cb);
  `FAIL_IF(tb_o_busy != 1'b0);
`SVTEST_END

//-------------------------------------------------------------------------------------------------//
`SVTEST(test03_sequential_transfers)
  logic [DW-1:0] words [4] = '{8'h11, 8'h22, 8'h33, 8'h44};

  for (int i = 0; i < 4; i++) begin
    send_and_wait(words[i]);
    `FAIL_IF(tb_o_data != words[i]);
  end
`SVTEST_END

//-------------------------------------------------------------------------------------------------//
