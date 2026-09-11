// ============================================================================
// File: fifo_dc_tests.sv
// Description: SVUnit test cases for fifo_dc. Included by fifo_dc_tc00.sv.
// ============================================================================

`SVTEST(tc_empty_on_reset)
   `FAIL_UNLESS_LOG(rd_cb.tb_empty === 1'b1, "async_empty_o should be high with nothing pushed");
   `FAIL_UNLESS_LOG(wr_cb.tb_full  === 1'b0, "async_full_o should be low with nothing pushed");
`SVTEST_END

`SVTEST(tc_push_pop_sequence)
   int trace[];
   int base;

   base = 16'h1000;
   push_seq(base, 5);

   // Let the write pointer's CDC settle before starting to pop.
   repeat(15) @(rd_cb);

   capture_trace(80, trace);
   `FAIL_UNLESS_LOG(trace_contains_seq(trace, base, 5),
      $sformatf("expected the run %0d..%0d somewhere in the captured data_o trace, not found", base, base+4));
`SVTEST_END

`SVTEST(tc_full_after_filling)
   bit timed_out;
   fill_until_full(64, timed_out);
   `FAIL_IF_LOG(timed_out, "async_full_o never asserted after filling past FIFO_AW=4 depth");
`SVTEST_END

`SVTEST(tc_flush_recovers)
   bit timed_out;

   push_seq(16'h2000, 3);
   repeat(10) @(wr_cb);

   wr_cb.tb_flush <= 1'b1;
   repeat(20) @(wr_cb);
   wr_cb.tb_flush <= 1'b0;

   wait_empty(timed_out);
   `FAIL_IF_LOG(timed_out, "FIFO never reported empty again after flush");

   // async_full_o has its own, independent CDC path (rd pointer synced back
   // into the wr domain) - give it the same kind of settle margin rather
   // than assuming it clears in lockstep with async_empty_o.
   repeat(15) @(wr_cb);
   `FAIL_UNLESS_LOG(wr_cb.tb_full === 1'b0, "async_full_o should be low after a flush");

   // Sanity: the FIFO must still work normally after a flush.
   begin
      int trace[];
      push_seq(16'h3000, 2);
      repeat(15) @(rd_cb);
      capture_trace(60, trace);
      `FAIL_UNLESS_LOG(trace_contains_seq(trace, 16'h3000, 2),
         "FIFO did not behave correctly for a push/pop after flush");
   end
`SVTEST_END
