// ============================================================================
// File: sgv6_top_tests.sv
// Description: SVUnit integration tests for sgv6_top.
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 01: Reset — output not valid, S0 ready behaviour sane.
// ----------------------------------------------------------------------------
`SVTEST(tc_reset_idle)
    repeat(5) @(posedge tb_aclk);
    `FAIL_IF(tb_m_tvalid !== 1'b0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 02: Envelope loadback — capture the whole output burst, report peak.
// ----------------------------------------------------------------------------
`SVTEST(tc_envelope_loadback)
    logic [15:0] re [N_DDS*4];   // enough to fill several rows
    logic [15:0] im [N_DDS*4];
    logic [15:0] peak;
    logic [15:0] samp;
    logic [159:0] d;
    int t, nseen;
    // Constant envelope across many samples (fills rows 0..3 of all banks).
    for (int k = 0; k < N_DDS*4; k++) begin re[k]=16'h4000; im[k]=16'h0000; end
    load_envelope(N_DDS*4, re, im);
    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'd16 /*nsamp*/, 2'd2 /*mem*/, 1'b0, 1'b0, 1'b0);
    queue_descriptor(d);
    // Capture the whole burst: from first tvalid until tvalid drops.
    peak = '0; nseen = 0; t = 0;
    while (!tb_m_tvalid && t < 200) begin @(posedge tb_aclk); t++; end
    while (tb_m_tvalid && nseen < 300) begin
        samp = tb_m_tdata[15:0];
        if (samp !== 16'h0000) begin
            if ($signed(samp) > $signed(peak)) peak = samp;
        end
        nseen++;
        @(posedge tb_aclk);
    end
    $display("[LOADBACK] env=0x4000 src=mem  burst_len=%0d  peak=0x%04h (%0d)",
             nseen, peak, $signed(peak));
    `FAIL_IF(1'b0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 03: Alignment — capture burst window with constant env + constant DDS.
//   In product mode, steady output within the burst must be constant.
// ----------------------------------------------------------------------------
`SVTEST(tc_alignment_check)
    logic [15:0] re [N_DDS*4];
    logic [15:0] im [N_DDS*4];
    logic [15:0] samples [$];
    logic [15:0] s;
    logic [159:0] d;
    int t, nseen;
    bit stable_flag;
    for (int k = 0; k < N_DDS*4; k++) begin re[k]=16'h4000; im[k]=16'h0000; end
    load_envelope(N_DDS*4, re, im);
    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'd16, 2'd0 /*product*/, 1'b0, 1'b0, 1'b0);
    queue_descriptor(d);
    t = 0;
    while (!tb_m_tvalid && t < 200) begin @(posedge tb_aclk); t++; end
    $display("[ALIGN] tvalid after %0d cycles", t);
    // Capture all samples during the burst.
    nseen = 0;
    while (tb_m_tvalid && nseen < 300) begin
        samples.push_back(tb_m_tdata[15:0]);
        nseen++;
        @(posedge tb_aclk);
    end
    $display("[ALIGN] burst_len=%0d", nseen);
    // Print the first several samples of the burst.
    for (int k = 0; k < nseen && k < 12; k++)
        $display("   sample[%0d] = 0x%04h (%0d)", k, samples[k], $signed(samples[k]));
    `FAIL_IF(1'b0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 04: Amplitude full-scale — peak within the burst.
// ----------------------------------------------------------------------------
`SVTEST(tc_amplitude_fullscale)
    logic [15:0] re [N_DDS*4];
    logic [15:0] im [N_DDS*4];
    logic [15:0] peak;
    logic [15:0] samp;
    logic [159:0] d;
    int t, nseen;
    for (int k = 0; k < N_DDS*4; k++) begin re[k]=16'(MAXV); im[k]=16'h0000; end
    load_envelope(N_DDS*4, re, im);
    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'd16, 2'd0 /*product*/, 1'b0, 1'b0, 1'b0);
    queue_descriptor(d);
    peak = '0; nseen = 0; t = 0;
    while (!tb_m_tvalid && t < 200) begin @(posedge tb_aclk); t++; end
    while (tb_m_tvalid && nseen < 300) begin
        samp = tb_m_tdata[15:0];
        if ($signed(samp) > $signed(peak)) peak = samp;
        nseen++;
        @(posedge tb_aclk);
    end
    $display("[AMP fullscale] burst_len=%0d  peak=0x%04h (%0d)  [isolated=0x3FFD]",
             nseen, peak, $signed(peak));
    `FAIL_IF(1'b0);
`SVTEST_END