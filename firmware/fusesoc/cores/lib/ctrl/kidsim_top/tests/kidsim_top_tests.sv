// ============================================================================
// File: kidsim_top_tests.sv
// Description: SVUnit tests for kidsim_top. Included by kidsim_top_tc00.sv.
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 01: WE latch — before a WE, config stays at defaults (OUTSEL=2). After
//   a WE with OUTSEL=2, a marker bypasses to the output at TOP_LAT.
// ----------------------------------------------------------------------------
`SVTEST(tc_bypass_latency)
    logic [31:0] marker;
    marker = pack_qi(16'sd1234, 16'sd5678);
    write_config(2, 0, 4000, 0, 0, 32767);
    tb_cb.tb_din_valid <= 1'b1;
    tb_cb.tb_din <= marker;
    @(tb_cb);
    tb_cb.tb_din <= '0;
    repeat(TOP_LAT) @(tb_cb);
    if (tb_dout !== marker) begin
        $display("BYPASS: exp 0x%08h got 0x%08h at lat %0d", marker, tb_dout, TOP_LAT);
        `FAIL_IF(1);
    end
    tb_cb.tb_din_valid <= 1'b0;
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 02: Default before WE — after reset, OUTSEL defaults to 2 (bypass), so
//   a marker still bypasses even without any configuration write.
// ----------------------------------------------------------------------------
`SVTEST(tc_default_bypass)
    logic [31:0] marker;
    marker = pack_qi(16'sd0777, 16'sd0333);
    // NO write_config -> defaults (outsel=2)
    tb_cb.tb_din_valid <= 1'b1;
    tb_cb.tb_din <= marker;
    @(tb_cb);
    tb_cb.tb_din <= '0;
    repeat(TOP_LAT) @(tb_cb);
    `FAIL_IF(tb_dout !== marker);
    tb_cb.tb_din_valid <= 1'b0;
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST: Frame streaming — a full frame streams through and comes out at the
//   output, valid/last aligned to the data (skew=0). With OUTSEL=0, punct
//   selecting one sample, IIR pass-through and CW carrier, every output sample
//   (processed or bypassed) matches its input within tolerance, and last
//   asserts on the final sample.
// ----------------------------------------------------------------------------
`SVTEST(tc_frame_streaming)
    localparam int FLEN = 6;
    localparam int BASE = 3000;
    logic [31:0] exp_frame [0:FLEN-1];
    int  k;
    // config: OUTSEL=0 (main), punct selects idx 2, CW carrier, IIR passthrough
    write_config(0, 2, 4000, 0, 0, 32767);
    for (int j = 0; j < FLEN; j++)
        exp_frame[j] = pack_qi(BASE + j, BASE + j + 100);

    k = 0;
    fork
        // driver
        send_frame(FLEN, BASE);
        // checker: sample the output only when dout_valid is high (skew=0 now).
        begin
            int exp_i, exp_q, err_i, err_q;
            for (int c = 0; c < TOP_LAT + FLEN + 12 && k < FLEN; c++) begin
                @(tb_cb);
                if (tb_dout_valid === 1'b1) begin
                    exp_i = signed'(exp_frame[k][15:0]);
                    exp_q = signed'(exp_frame[k][31:16]);
                    err_i = tb_dout_i - exp_i; if (err_i < 0) err_i = -err_i;
                    err_q = tb_dout_q - exp_q; if (err_q < 0) err_q = -err_q;
                    if (!(err_i < 50 && err_q < 50)) begin
                        $display("FRAME MISMATCH k=%0d: exp=(%0d,%0d) got=(%0d,%0d)",
                                 k, exp_i, exp_q, tb_dout_i, tb_dout_q);
                        `FAIL_IF(1);
                    end
                    // last must assert on the final sample of the frame
                    if (k == FLEN-1) begin
                        if (tb_dout_last !== 1'b1) begin
                            $display("FRAME last not asserted on final sample");
                            `FAIL_IF(1);
                        end
                    end else begin
                        if (tb_dout_last !== 1'b0) begin
                            $display("FRAME last asserted early at k=%0d", k);
                            `FAIL_IF(1);
                        end
                    end
                    k++;
                end
            end
        end
    join
    if (k !== FLEN) begin
        $display("FRAME: got %0d valid beats, expected %0d", k, FLEN);
        `FAIL_IF(1);
    end
    tb_cb.tb_din_valid <= 1'b0;
`SVTEST_END

// Diagnóstico: latencia de valid, dato-bypass (OUTSEL=2) y dato-processed (OUTSEL=0)
`SVTEST(tc_measure_both_paths)
    int v_lat, dbyp_lat, dproc_lat;
    logic [31:0] marker;
    marker = pack_qi(16'sd1000, 16'sd2000);

    // --- bypass path ---
    write_config(2, 0, 4000, 0, 0, 32767);   // OUTSEL=2
    v_lat = -1; dbyp_lat = -1;
    tb_cb.tb_din_valid <= 1'b1; tb_cb.tb_din <= marker;
    @(tb_cb);
    tb_cb.tb_din_valid <= 1'b0; tb_cb.tb_din <= '0;
    for (int c = 1; c < 32; c++) begin
        @(tb_cb);
        if (v_lat==-1 && tb_dout_valid===1'b1) v_lat = c;
        if (dbyp_lat==-1 && tb_dout===marker)  dbyp_lat = c;
    end

    // --- processed path (OUTSEL=0, CW, passthrough): dout ~= din ---
    write_config(0, 0, 4000, 0, 0, 32767);   // OUTSEL=0, punct_id=0 (first sample)
    dproc_lat = -1;
    repeat(40) @(tb_cb);   // let carrier spin up
    tb_cb.tb_din_valid <= 1'b1; tb_cb.tb_din <= marker;
    @(tb_cb);
    tb_cb.tb_din_valid <= 1'b0; tb_cb.tb_din <= '0;
    for (int c = 1; c < 40; c++) begin
        @(tb_cb);
        // processed sample ~= marker (within tolerance)
        if (dproc_lat==-1 &&
            (tb_dout_i > 1900 && tb_dout_i < 2100) &&
            (tb_dout_q > 900  && tb_dout_q < 1100)) dproc_lat = c;
    end

    $display("PATHS: valid_lat=%0d  bypass_data_lat=%0d  processed_data_lat=%0d",
             v_lat, dbyp_lat, dproc_lat);
    $display("SKEW valid-vs-bypass=%0d  valid-vs-processed=%0d",
             dbyp_lat - v_lat, dproc_lat - v_lat);
`SVTEST_END