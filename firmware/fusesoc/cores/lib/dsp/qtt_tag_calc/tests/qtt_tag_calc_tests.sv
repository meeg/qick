// ============================================================================
// File: qtt_tag_calc_tests.sv
// Description: SVUnit test cases for qtt_tag_calc. Included by
//   qtt_tag_calc_tc00.sv.
// ============================================================================

`SVTEST(tc_no_trigger_below_threshold)
   bit timed_out;

   cb.tb_th_p <= 16'd150;
   cb.tb_arm_p <= 1'b1;
   repeat(3) @(cb);

   cb.tb_dt_p <= pack4(50, 50, 50, 50); // all below threshold
   @(cb);
   cb.tb_dt_p <= '0;

   wait_vld_p(timed_out);
   `FAIL_UNLESS_LOG(timed_out, "tag_vld_o should never assert when no sample crosses the threshold");
`SVTEST_END

`SVTEST(tc_lowest_index_wins)
   bit timed_out;
   logic [31:0] expected;

   cb.tb_th_p <= 16'd150;
   cb.tb_arm_p <= 1'b1;
   repeat(3) @(cb);

   // Index 0 and 2 both cross; the lowest index (0) must be reported.
   cb.tb_dt_p <= pack4(200, 50, 300, 50);
   @(cb);
   cb.tb_dt_p <= '0;

   wait_vld_p(timed_out);
   `FAIL_IF_LOG(timed_out, "tag_vld_o never asserted for a genuine crossing");
   @(cb); // tag_dt_o's registers latch on the same cycle tag_vld_o first pulses; visible one cycle later

   expected = {TIME_CK, 3'd0}; // enc_s = 0
   `FAIL_UNLESS_LOG(cb.tb_tagdt_p === expected,
      $sformatf("tag_dt_o=0x%08h expected 0x%08h (time_ck=%0d, adc_idx=0)", cb.tb_tagdt_p, expected, TIME_CK));
`SVTEST_END

`SVTEST(tc_trigger_basic)
   bit timed_out;
   logic [31:0] expected;

   cb.tb_th_p <= 16'd150;
   cb.tb_arm_p <= 1'b1;
   repeat(3) @(cb);

   // Monotonically increasing samples: index 1 (200) is the first to cross.
   cb.tb_dt_p <= pack4(50, 200, 300, 400);
   @(cb);
   cb.tb_dt_p <= '0;

   wait_vld_p(timed_out);
   `FAIL_IF_LOG(timed_out, "tag_vld_o never asserted for a genuine crossing");
   @(cb); // see note above

   expected = {TIME_CK, 3'd1}; // enc_s = 1
   `FAIL_UNLESS_LOG(cb.tb_tagdt_p === expected,
      $sformatf("tag_dt_o=0x%08h expected 0x%08h (time_ck=%0d, adc_idx=1)", cb.tb_tagdt_p, expected, TIME_CK));
`SVTEST_END

`SVTEST(tc_arm_gating)
   bit timed_out;
   int c;

   cb.tb_th_p  <= 16'd150;
   cb.tb_arm_p <= 1'b0; // never armed

   cb.tb_dt_p <= pack4(200, 50, 300, 50); // would cross if armed
   @(cb);
   cb.tb_dt_p <= '0;

   for (c = 0; c < 30; c++) begin
      @(cb);
      `FAIL_IF_LOG(cb.tb_trig_p === 1'b1, $sformatf("trig_o fired at cycle %0d while never armed", c));
      `FAIL_IF_LOG(cb.tb_vld_p === 1'b1, $sformatf("tag_vld_o fired at cycle %0d while never armed", c));
   end
`SVTEST_END

// End-to-end through the x_inter datapath (CMP_INTER=4, filter on - the
// realistic configuration, since with filter on ftr_smp/ftr_prev_smp are a
// sum of two samples in the same scale x_inter's curr_i/prev_i expect).
`SVTEST(tc_interpolation_end_to_end)
   bit timed_out;
   logic [31:0] expected;

   // dt = [0, 0, 500, 500]; with filter on and a quiet preceding cycle:
   //   ftr_smp    = [0, 0, 500, 1000]
   //   cmp_thr_s  = 2*100 = 200 -> cmp_flg = [F,F,T,T] -> enc_s = 2
   //   ftr_prev_smp[2] = 0, ftr_smp[2] = 500 -> x_inter(thr=100,prev=0,curr=500,cfg_inter=4)
   //     = floor((100<<4)/500) = floor(1600/500) = 3
   //   trig_time_adc_r = enc_m1 = enc_s-1 = 1 (cfg_inter_i != 0 selects enc_m1)
   cb.tb_th_i    <= 16'd100;
   cb.tb_inter_i <= 3'd4;
   cb.tb_arm_i   <= 1'b1;
   repeat(3) @(cb);

   // x_inter reads ftr_smp[enc_s]/ftr_prev_smp[enc_s] "live" (not a snapshot
   // taken when the crossing was first seen) at the time div_start actually
   // fires, several pipeline cycles after the crossing sample arrived
   // (1 filter + 1 compare-register + 2 encoder-output-register stages).
   // Real ADC pulses are slowly varying relative to that, so the samples
   // are still in place by then; hold this synthetic pulse the same way
   // instead of a single-cycle glitch. The outer FSM only lets trigger_cmp
   // (and so x_inter's div_start) pulse once per arm/inhibit cycle even
   // though the underlying crossing condition stays true the whole time,
   // so it's safe to leave dt_i asserted and just catch the first result.
   cb.tb_dt_i <= pack4(0, 0, 500, 500);

   wait_vld_i(timed_out);
   `FAIL_IF_LOG(timed_out, "tag_vld_o (interpolating DUT) never asserted for a genuine crossing");
   @(cb); // see note above
   cb.tb_dt_i <= '0;

   expected = {TIME_CK[24:0], 3'd1, 4'd3}; // time_ck=5, adc_idx=enc_m1=1, x_int=3 (only the low 25 bits of the ck counter survive when 4 interpolation bits are appended)
   `FAIL_UNLESS_LOG(cb.tb_tagdt_i === expected,
      $sformatf("tag_dt_o=0x%08h expected 0x%08h (time_ck=%0d, adc_idx=1, x_int=3)", cb.tb_tagdt_i, expected, TIME_CK));
`SVTEST_END
