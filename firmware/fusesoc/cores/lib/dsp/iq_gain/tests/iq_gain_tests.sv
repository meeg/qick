// ============================================================================
// File: iq_gain_tests.sv
// Description: SVUnit test cases for iq_gain.
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 01: Reset / Idle
// ----------------------------------------------------------------------------
`SVTEST(tc_idle_zero)
    repeat(10) @(tb_cb);
    `FAIL_IF(tb_i_out !== '0);
    `FAIL_IF(tb_q_out !== '0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 02: Latency check
// ----------------------------------------------------------------------------
`SVTEST(tc_latency_check)
    iq_t exp;
    tb_cb.tb_i_in  <= 16'sd1000;
    tb_cb.tb_q_in  <= 16'sd2000;
    tb_cb.tb_gain  <= 4'd2;
    exp = golden_model(16'sd1000, 16'sd2000, 4'd2);

    @(tb_cb);
    tb_cb.tb_i_in  <= '0;
    tb_cb.tb_q_in  <= '0;

    // Verify it hasn't arrived yet (sumamos +1 por el delay del CB)
    for (int i = 1; i < LATENCY + 1; i++) begin
        `FAIL_IF(tb_cb.tb_i_out === exp.i); 
        @(tb_cb);
    end
    // Exact latency sampled safely via CB
    `FAIL_IF(tb_cb.tb_i_out !== exp.i);
    `FAIL_IF(tb_cb.tb_q_out !== exp.q);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 03: Unity Gain (Passthrough)
// ----------------------------------------------------------------------------
`SVTEST(tc_unity_gain)
    tb_cb.tb_i_in  <= 16'sd12345; 
    tb_cb.tb_q_in  <= -16'sd15000; // Literal signed de 16 bits
    tb_cb.tb_gain  <= 4'd1;

    repeat(LATENCY + 1) @(tb_cb);

    `FAIL_IF(tb_cb.tb_i_out !== 16'sd12345);
    `FAIL_IF(tb_cb.tb_q_out !== -16'sd15000);
`SVTEST_END
// ----------------------------------------------------------------------------
// TEST 04: Mute (Gain = 0)
// ----------------------------------------------------------------------------
`SVTEST(tc_mute)
    tb_cb.tb_i_in  <= 16'sd32000;
    tb_cb.tb_q_in  <= -16'sd32000;
    tb_cb.tb_gain  <= 4'd0;

    repeat(LATENCY + 1) @(tb_cb);

    `FAIL_IF(tb_cb.tb_i_out !== '0);
    `FAIL_IF(tb_cb.tb_q_out !== '0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 05: Positive Saturation
// ----------------------------------------------------------------------------
`SVTEST(tc_sat_pos)
    // Valid Input (16 bits) * Gain -> Result > 32767
    tb_cb.tb_i_in  <= 16'sd20000; 
    tb_cb.tb_q_in  <= 16'sd20000;
    tb_cb.tb_gain  <= 4'd2;

    repeat(LATENCY + 1) @(tb_cb);

    `FAIL_IF(tb_cb.tb_i_out !== 16'sd32767);
    `FAIL_IF(tb_cb.tb_q_out !== 16'sd32767);
`SVTEST_END
// ----------------------------------------------------------------------------
// TEST 06: Negative Saturation
// ----------------------------------------------------------------------------
`SVTEST(tc_sat_neg)
    // -20000 * 2 = -40000 -> should clamp to -32768
    tb_cb.tb_i_in  <= -16'sd20000;
    tb_cb.tb_q_in  <= -16'sd20000;
    tb_cb.tb_gain  <= 4'd2;

    repeat(LATENCY + 1) @(tb_cb);

    `FAIL_IF(tb_cb.tb_i_out !== -16'sd32768);
    `FAIL_IF(tb_cb.tb_q_out !== -16'sd32768);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 07: Random Streaming
// ----------------------------------------------------------------------------
`SVTEST(tc_streaming_random)
    test_stream(1000);
`SVTEST_END