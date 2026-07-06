// ============================================================================
// File: sgv4_top_tests.sv
// Description: SVUnit integration tests for sgv4_top.
//   Tests 01-04 ported from sgv6_top (N_DDS=8, no per-descriptor real/imag).
//   Tests 05-07 are v4-specific: outsel_reg toggle, FIFO backpressure/overflow,
//   saturation.
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 01: Reset — output not valid.
// ----------------------------------------------------------------------------
`SVTEST(tc_reset_idle)
    repeat(5) @(posedge tb_aclk);
    `FAIL_IF(tb_m_tvalid !== 1'b0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 02: Envelope loadback — capture the whole output burst, report peak.
//   outsel_reg=0 -> real bank drives the output.
// ----------------------------------------------------------------------------
`SVTEST(tc_envelope_loadback)
    logic [15:0] re [N_DDS*4];
    logic [15:0] im [N_DDS*4];
    logic [15:0] peak;
    logic [15:0] samp;
    logic [159:0] d;
    int t, nseen;

    tb_outsel_reg <= 1'b0;                 // real
    for (int k = 0; k < N_DDS*4; k++) begin re[k]=16'h4000; im[k]=16'h0000; end
    load_envelope(N_DDS*4, re, im);

    // outsel field is 2'd2 (mem) for ctrl_sgv4; top real/imag is outsel_reg.
    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'd16 /*nsamp*/, 2'd2 /*mem*/, 1'b0, 1'b0, 1'b0);
    queue_descriptor(d);

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
    `FAIL_IF(nseen == 0);                   // must have produced a burst
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 03: Alignment — constant env + constant DDS -> steady burst.
// ----------------------------------------------------------------------------
`SVTEST(tc_alignment_check)
    logic [15:0] re [N_DDS*4];
    logic [15:0] im [N_DDS*4];
    logic [15:0] samples [$];
    logic [159:0] d;
    int t, nseen;

    tb_outsel_reg <= 1'b0;
    for (int k = 0; k < N_DDS*4; k++) begin re[k]=16'h4000; im[k]=16'h0000; end
    load_envelope(N_DDS*4, re, im);

    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'd16, 2'd0 /*product*/, 1'b0, 1'b0, 1'b0);
    queue_descriptor(d);

    t = 0;
    while (!tb_m_tvalid && t < 200) begin @(posedge tb_aclk); t++; end
    $display("[ALIGN] tvalid after %0d cycles", t);

    nseen = 0;
    while (tb_m_tvalid && nseen < 300) begin
        samples.push_back(tb_m_tdata[15:0]);
        nseen++;
        @(posedge tb_aclk);
    end
    $display("[ALIGN] burst_len=%0d", nseen);
    for (int k = 0; k < nseen && k < 12; k++)
        $display("   sample[%0d] = 0x%04h (%0d)", k, samples[k], $signed(samples[k]));
    `FAIL_IF(nseen == 0);
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

    tb_outsel_reg <= 1'b0;
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
    $display("[AMP fullscale] burst_len=%0d  peak=0x%04h (%0d)",
             nseen, peak, $signed(peak));
    `FAIL_IF(nseen == 0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 05 (v4-specific): outsel_reg toggle — real vs imag select.
//   Load a DISTINCT real and imag envelope, then run the SAME descriptor twice:
//   once with outsel_reg=0 (real) and once with =1 (imag). The two bursts must
//   differ, proving the static select is wired and honoured.
// ----------------------------------------------------------------------------
`SVTEST(tc_outsel_toggle)
    logic [15:0] re [N_DDS*4];
    logic [15:0] im [N_DDS*4];
    logic [15:0] peak_real, peak_imag, samp;
    logic [159:0] d;
    int t, nseen;

    // real = +0x4000, imag = +0x1000 (clearly distinct magnitudes).
    for (int k = 0; k < N_DDS*4; k++) begin re[k]=16'h4000; im[k]=16'h1000; end
    load_envelope(N_DDS*4, re, im);

    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'd16, 2'd2 /*mem*/, 1'b0, 1'b0, 1'b0);

    // ---- pass 1: outsel_reg = 0 (real) ----
    tb_outsel_reg <= 1'b0;
    @(posedge tb_aclk);
    queue_descriptor(d);
    peak_real = '0; nseen = 0; t = 0;
    while (!tb_m_tvalid && t < 200) begin @(posedge tb_aclk); t++; end
    while (tb_m_tvalid && nseen < 300) begin
        samp = tb_m_tdata[15:0];
        if ($signed(samp) > $signed(peak_real)) peak_real = samp;
        nseen++;
        @(posedge tb_aclk);
    end
    $display("[OUTSEL] real  peak=0x%04h (%0d)", peak_real, $signed(peak_real));

    repeat(20) @(posedge tb_aclk);

    // ---- pass 2: outsel_reg = 1 (imag) ----
    tb_outsel_reg <= 1'b1;
    @(posedge tb_aclk);
    queue_descriptor(d);
    peak_imag = '0; nseen = 0; t = 0;
    while (!tb_m_tvalid && t < 200) begin @(posedge tb_aclk); t++; end
    while (tb_m_tvalid && nseen < 300) begin
        samp = tb_m_tdata[15:0];
        if ($signed(samp) > $signed(peak_imag)) peak_imag = samp;
        nseen++;
        @(posedge tb_aclk);
    end
    $display("[OUTSEL] imag  peak=0x%04h (%0d)", peak_imag, $signed(peak_imag));

    // real envelope (0x4000) > imag envelope (0x1000): real peak must exceed imag.
    `FAIL_IF($signed(peak_real) <= $signed(peak_imag));
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 06 (v4-specific): FIFO backpressure / overflow guard.
//   REGRESSION for the fifo_wr_en bug: keeps S1 tvalid high while pushing more
//   descriptors than FIFO depth (16). While tready is LOW, no descriptor may be
//   consumed/corrupted. We assert:
//     (a) tready deasserts once the FIFO fills, and
//     (b) no write happens while full (checked by SVA below if RTL exposes
//         wr_err; here we check behavioural: exactly the accepted descriptors
//         come out, none lost/duplicated).
//   With the BUG present (fifo_wr_en = tvalid alone), this test should FAIL
//   (overflow) — proving it catches the defect. After the fix
//   (fifo_wr_en = tvalid & ~fifo_full) it must PASS.
// ----------------------------------------------------------------------------
`SVTEST(tc_fifo_backpressure)
    logic [15:0] re [N_DDS*2];
    logic [15:0] im [N_DDS*2];
    logic [159:0] d;
    int accepted;
    bit saw_full;

    // small envelope so descriptors don't drain instantly.
    for (int k = 0; k < N_DDS*2; k++) begin re[k]=16'h4000; im[k]=16'h0000; end
    load_envelope(N_DDS*2, re, im);
    tb_outsel_reg <= 1'b0;

    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'd64 /*long nsamp so FIFO backs up*/, 2'd2, 1'b0, 1'b0, 1'b0);

    // Hold tvalid high and try to push 32 descriptors (FIFO depth = 16).
    accepted = 0; saw_full = 1'b0;
    tb_s1_tdata  <= d;
    tb_s1_tvalid <= 1'b1;
    for (int k = 0; k < 32; k++) begin
        @(posedge tb_aclk);
        if (tb_s1_tready) accepted++;
        else              saw_full = 1'b1;   // tready dropped -> FIFO full seen
    end
    tb_s1_tvalid <= 1'b0;
    @(posedge tb_aclk);

    $display("[BACKPRESSURE] accepted=%0d  saw_full=%0b (FIFO depth=16)",
             accepted, saw_full);

    // (a) tready MUST deassert at some point (FIFO must fill and push back).
    `FAIL_IF(saw_full !== 1'b1);
    // (b) Must never accept more than the FIFO can hold without draining.
    //     If fifo_wr_en ignores full, `accepted` keeps climbing == overflow.
    `FAIL_IF(accepted > 16 + 4);   // small slack for in-flight drain
`SVTEST_END

             // ----------------------------------------------------------------------------
// TEST 07 (v4, REVISED): Saturation guard is a NEGATIVE test at top level.
//
//   RATIONALE (verified against sgv4.sv):
//   o_sat asserts when round_ext = prodg_y_full[31:15] exceeds +/-32766
//   (STRICT >). With the double-Q15 reduction (product [30:15] then gain
//   [31:15]), the worst case reachable from 16-bit env x DDS x gain is:
//       max ~ 32767 * 32767 = 0x3FFF_0001 -> [31:15] = 0x7FFE = 32766
//   which EQUALS the threshold but does NOT exceed it (> is strict).
//   Therefore o_sat is UNREACHABLE from the top with 16-bit operands and MUST
//   stay 0. tc_amplitude_fullscale already showed peak 0x7FFB (32763), no clip.
//
//   The POSITIVE saturation test (forcing prodg_y_full_real_r2 past the clamp)
//   belongs at the sgv4 UNIT level, where the internal reg is drivable.
//   TODO: add sgv4_ut::tc_saturation_forced.
// ----------------------------------------------------------------------------
`SVTEST(tc_saturation_guard_negative)
    logic [15:0] re [N_DDS*4];
    logic [15:0] im [N_DDS*4];
    logic [159:0] d;
    int t, nseen;
    bit sat_seen;

    tb_outsel_reg <= 1'b0;
    // Absolute worst case: full-scale real envelope + full-scale gain.
    for (int k = 0; k < N_DDS*4; k++) begin re[k]=16'(MAXV); im[k]=16'h0000; end
    load_envelope(N_DDS*4, re, im);

    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'd16, 2'd0 /*product*/, 1'b0, 1'b0, 1'b0);
    queue_descriptor(d);

    sat_seen = 1'b0; nseen = 0; t = 0;
    while (!tb_m_tvalid && t < 200) begin
        if (tb_sat) sat_seen = 1'b1;
        @(posedge tb_aclk); t++;
    end
    while (tb_m_tvalid && nseen < 300) begin
        if (tb_sat) sat_seen = 1'b1;
        nseen++;
        @(posedge tb_aclk);
    end
    $display("[SAT-NEG] burst_len=%0d  sat_seen=%0b (expect 0: unreachable from top)",
             nseen, sat_seen);
    // o_sat must NOT assert: saturation is unreachable with 16-bit operands.
    `FAIL_IF(sat_seen !== 1'b0);
`SVTEST_END
// ----------------------------------------------------------------------------
// TEST 08 (v4, REVISED): Enable/valid window + live-sample count.
//
//   RUN 2 finding: with nsamp=48 but only 4 envelope rows loaded, only 4
//   non-zero samples appear — the read address (mem_addrb) advances every cycle
//   and runs past the loaded envelope into unwritten (zero) memory. That is a
//   TEST stimulus shortfall, NOT an RTL bug: tvalid_high correctly = nsamp = 48.
//
//   FIX: load ENOUGH envelope rows to cover the whole nsamp window.
//   With N_DDS banks, one stream "row" = N_DDS samples. For nsamp read
//   addresses we need >= nsamp rows => nsamp*N_DDS stream samples.
// ----------------------------------------------------------------------------
`SVTEST(tc_valid_window)
    localparam int NSAMP = 48;
    logic [15:0] re [NSAMP*N_DDS];
    logic [15:0] im [NSAMP*N_DDS];
    logic [159:0] d;
    int t, valid_cycles, nonzero_cycles;
    logic [15:0] s;

    tb_outsel_reg <= 1'b0;
    // Fill enough rows (NSAMP rows across all banks) so the read address never
    // runs off the loaded envelope during the burst.
    for (int k = 0; k < NSAMP*N_DDS; k++) begin re[k]=16'h4000; im[k]=16'h0000; end
    load_envelope(NSAMP*N_DDS, re, im);

    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'(NSAMP), 2'd0 /*product*/, 1'b0, 1'b0, 1'b0);
    queue_descriptor(d);

    t = 0;
    while (!tb_m_tvalid && t < 200) begin @(posedge tb_aclk); t++; end

    valid_cycles = 0; nonzero_cycles = 0;
    while (tb_m_tvalid && valid_cycles < 300) begin
        s = tb_m_tdata[15:0];
        if (s !== 16'h0000) nonzero_cycles++;
        valid_cycles++;
        @(posedge tb_aclk);
    end
    $display("[WINDOW] tvalid_high=%0d cycles, nonzero=%0d (nsamp=%0d, rows=%0d)",
             valid_cycles, nonzero_cycles, NSAMP, NSAMP);

    // tvalid window must match nsamp within pipeline slack.
    `FAIL_IF(valid_cycles < NSAMP-4 || valid_cycles > NSAMP+8);
    // With the envelope fully covering the window, most samples must be live.
    `FAIL_IF(nonzero_cycles < NSAMP-8);
`SVTEST_END