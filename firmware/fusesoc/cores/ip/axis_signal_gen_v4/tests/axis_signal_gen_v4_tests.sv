// ============================================================================
// File: axis_signal_gen_v4_tests.sv
// Description: SVUnit integration tests for axis_signal_gen_v4.
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 01: Register readback via AXI-Lite (incl. OUTSEL + RNDQ dummy).
// ----------------------------------------------------------------------------
`SVTEST(tc_reg_readback)
    logic [31:0] rd;
    reg_write(REG_START_ADDR, 32'h0000_00AB);
    reg_read (REG_START_ADDR, rd);
    `FAIL_IF_LOG(rd !== 32'h0000_00AB, $sformatf("START_ADDR readback 0x%08h", rd));

    reg_write(REG_WE, 32'h1);
    reg_read (REG_WE, rd);
    `FAIL_IF_LOG(rd[0] !== 1'b1, $sformatf("WE readback 0x%08h", rd));
    reg_write(REG_WE, 32'h0);

    reg_write(REG_OUTSEL, 32'h1);
    reg_read (REG_OUTSEL, rd);
    `FAIL_IF_LOG(rd[0] !== 1'b1, $sformatf("OUTSEL readback 0x%08h", rd));
    reg_write(REG_OUTSEL, 32'h0);

    // RNDQ is a deprecated dummy: must still read/write back (bindto compat).
    reg_write(REG_RNDQ, 32'hDEAD_BEEF);
    reg_read (REG_RNDQ, rd);
    `FAIL_IF_LOG(rd !== 32'hDEAD_BEEF, $sformatf("RNDQ dummy readback 0x%08h", rd));
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 02: Envelope load via AXI-Lite + S0, read back via src=mem.
// ----------------------------------------------------------------------------
`SVTEST(tc_envelope_load)
    logic [15:0] re [], im [];
    logic [15:0] peak;
    logic [159:0] d;
    reg_write(REG_OUTSEL, 32'd0);   // real
    const_envelope(N_DDS*4, 16'h4000, re, im);
    load_envelope(N_DDS*4, re, im);
    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'd16, 2'd2 /*mem*/, 1'b0, 1'b0, 1'b0);
    queue_descriptor(d);
    capture_burst(peak);
    $display("[ENV LOAD] env=0x4000 src=mem peak=0x%04h (%0d)", peak, $signed(peak));
    `FAIL_IF_LOG($signed(peak) < 16'sd10000, "envelope loadback near-zero");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 03: Full-scale amplitude end-to-end (product path).
// ----------------------------------------------------------------------------
`SVTEST(tc_amplitude_fullscale)
    logic [15:0] re [], im [];
    logic [15:0] peak;
    logic [159:0] d;
    reg_write(REG_OUTSEL, 32'd0);
    const_envelope(N_DDS*4, 16'(MAXV), re, im);
    load_envelope(N_DDS*4, re, im);
    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'd16, 2'd0 /*product*/, 1'b0, 1'b0, 1'b0);
    queue_descriptor(d);
    capture_burst(peak);
    $display("[AMP fullscale] peak=0x%04h (%0d)", peak, $signed(peak));
    `FAIL_IF_LOG($signed(peak) < 16'sd30000,
        $sformatf("fullscale should be ~MAXV, got %0d", $signed(peak)));
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 04: DDS-only tone (src=1) reaches full scale.
// ----------------------------------------------------------------------------
`SVTEST(tc_dds_only)
    logic [15:0] re [], im [];
    logic [15:0] peak;
    logic [159:0] d;
    reg_write(REG_OUTSEL, 32'd0);
    const_envelope(N_DDS, 16'h0000, re, im);
    load_envelope(N_DDS, re, im);
    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'd16, 2'd1 /*DDS*/, 1'b0, 1'b0, 1'b0);
    queue_descriptor(d);
    capture_burst(peak);
    $display("[DDS ONLY] peak=0x%04h (%0d)", peak, $signed(peak));
    `FAIL_IF_LOG($signed(peak) < 16'sd10000, "DDS-only near-zero");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 05 (NUEVO v4): OUTSEL_REG static real/imag select, end-to-end.
//   Load env with re != im, play src=mem. OUTSEL=0 -> real, OUTSEL=1 -> imag.
// ----------------------------------------------------------------------------
`SVTEST(tc_outsel_toggle)
    logic [15:0] re [], im [];
    logic [15:0] peak_real, peak_imag;
    logic [159:0] d;
    localparam logic [15:0] RVAL = 16'h4000;   // real ~ 0x4000
    localparam logic [15:0] IVAL = 16'h2000;   // imag ~ 0x2000 (distinct)

    const_envelope_ri(N_DDS*4, RVAL, IVAL, re, im);
    load_envelope(N_DDS*4, re, im);

    // OUTSEL = 0 -> real path.
    reg_write(REG_OUTSEL, 32'd0);
    repeat(20) @(posedge aclk);          // CDC margin for outsel -> aclk
    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'd16, 2'd2 /*mem*/, 1'b0, 1'b0, 1'b0);
    queue_descriptor(d);
    capture_burst(peak_real);
    $display("[OUTSEL] OUTSEL=0 (real) peak=0x%04h (%0d)", peak_real, $signed(peak_real));

    // OUTSEL = 1 -> imag path.
    reg_write(REG_OUTSEL, 32'd1);
    repeat(20) @(posedge aclk);
    queue_descriptor(d);
    capture_burst(peak_imag);
    $display("[OUTSEL] OUTSEL=1 (imag) peak=0x%04h (%0d)", peak_imag, $signed(peak_imag));

    // real amplitude (0x4000) should be clearly larger than imag (0x2000).
    `FAIL_IF_LOG($signed(peak_real) <= $signed(peak_imag),
        $sformatf("OUTSEL: real(%0d) should exceed imag(%0d)",
                  $signed(peak_real), $signed(peak_imag)));
    `FAIL_IF_LOG($signed(peak_imag) < 16'sd4000,
        "OUTSEL=1 imag path near-zero (select likely stuck on real)");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 06: saturation status register via AXI-Lite (sticky set/hold/clear).
// ----------------------------------------------------------------------------
`SVTEST(tc_sat_status_reg)
    logic [15:0] re [], im [];
    logic [31:0] status;
    logic [159:0] d;
    bit saw_o_sat = 1'b0, saw_sticky = 1'b0;
    int t;

    reg_write(REG_OUTSEL, 32'd0);
    // Clear any prior sticky.
    reg_write(REG_CTRL, 32'h1);
    reg_write(REG_CTRL, 32'h0);
    repeat(20) @(posedge aclk);

    // Saturating pulse: env = 0x8000, gain full.
    const_envelope(N_DDS*4, 16'h8000, re, im);
    load_envelope(N_DDS*4, re, im);
    d = build_descr(32'd0, 32'd0, 16'd0, 16'h7FFF, 16'd16, 2'd0, 1'b0, 1'b0, 1'b0);
    queue_descriptor(d);

    m_if.tready <= 1'b1;
    for (t = 0; t < 150; t++) begin
        @(posedge aclk);
        if (dut.saturating) saw_o_sat  = 1'b1;   // instantaneous port
        if (dut.sat_sticky) saw_sticky = 1'b1;   // sticky (internal)
    end
    $display("[SAT DBG] saw_o_sat(port)=%b saw_sticky(internal)=%b", saw_o_sat, saw_sticky);

    repeat(20) @(posedge s_axi_aclk);   // CDC sticky -> axi
    reg_read(REG_STATUS, status);
    $display("[SAT STATUS] STATUS=0x%08h sat_sticky_axi=%b", status, dut.sat_sticky_axi);
    `FAIL_IF_LOG(status[0] !== 1'b1, "sticky saturation not set in STATUS_REG");

    reg_write(REG_CTRL, 32'h1);
    reg_write(REG_CTRL, 32'h0);
    repeat(20) @(posedge s_axi_aclk);
    reg_read(REG_STATUS, status);
    $display("[SAT STATUS] after clear: STATUS=0x%08h", status);
    `FAIL_IF_LOG(status[0] !== 1'b0, "sticky not cleared");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 07: pure tone (src=1) — one zero crossing over 16 lanes for pinc=2^32/32.
// ----------------------------------------------------------------------------
`SVTEST(tc_pure_tone_verify)
    logic [15:0] re [], im [];
    logic signed [15:0] carrier [N_DDS];
    logic [159:0] d;
    logic [31:0] pinc;
    reg_write(REG_OUTSEL, 32'd0);
    const_envelope(N_DDS, 16'h0000, re, im);
    load_envelope(N_DDS, re, im);
    pinc = 32'h0800_0000;   // 2^32/32
    d = build_descr(pinc, 32'd0, 16'd0, 16'(MAXV),
                    16'd16, 2'd1, 1'b0, 1'b0, 1'b0);
    queue_descriptor(d);
    m_if.tready <= 1'b1;
    while (!m_if.tvalid) @(posedge aclk);
    for (int i = 0; i < N_DDS; i++)
        carrier[i] = m_if.tdata[i*16 +: 16];
    begin
        int zc = 0;
        for (int i = 1; i < N_DDS; i++)
            if (($signed(carrier[i-1]) >= 0) != ($signed(carrier[i]) >= 0)) zc++;
        $display("[TONE VERIFY] zero_crossings=%0d (expect 1)", zc);
        `FAIL_IF_LOG(zc != 1, "carrier should cross zero exactly once");
        `FAIL_IF_LOG($signed(carrier[15]) < 16'sd30000, "carrier peak too low");
    end
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 08: modulated pulse (src=0) — constant envelope * carrier.
// ----------------------------------------------------------------------------
`SVTEST(tc_modulated_pulse)
    logic [15:0] re [], im [];
    logic signed [15:0] out [N_DDS];
    logic [159:0] d;
    logic [31:0] pinc;
    int zc = 0;
    reg_write(REG_OUTSEL, 32'd0);
    const_envelope(N_DDS, 16'h4000, re, im);
    load_envelope(N_DDS, re, im);
    pinc = 32'h0800_0000;
    d = build_descr(pinc, 32'd0, 16'd0, 16'(MAXV),
                    16'd16, 2'd0 /*product*/, 1'b0, 1'b0, 1'b0);
    queue_descriptor(d);
    m_if.tready <= 1'b1;
    while (!m_if.tvalid) @(posedge aclk);
    for (int i = 0; i < N_DDS; i++)
        out[i] = m_if.tdata[i*16 +: 16];
    for (int i = 1; i < N_DDS; i++)
        if (($signed(out[i-1]) >= 0) != ($signed(out[i]) >= 0)) zc++;
    $display("[MODULATED] zero_crossings=%0d", zc);
    `FAIL_IF_LOG(zc != 1, "modulated carrier should cross zero once");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 09: frequency sweep — crossing count scales with pinc.
// ----------------------------------------------------------------------------
`SVTEST(tc_frequency_sweep)
    logic [15:0] re [], im [];
    logic signed [15:0] carrier [N_DDS];
    logic [159:0] d;
    logic [31:0] pincs [3] = '{32'h0800_0000, 32'h1000_0000, 32'h2000_0000};
    int exp_zc [3] = '{1, 2, 4};
    reg_write(REG_OUTSEL, 32'd0);
    const_envelope(N_DDS, 16'h0000, re, im);
    load_envelope(N_DDS, re, im);
    foreach (pincs[j]) begin
        int zc = 0;
        d = build_descr(pincs[j], 32'd0, 16'd0, 16'(MAXV),
                        16'd16, 2'd1 /*DDS*/, 1'b0, 1'b0, 1'b0);
        queue_descriptor(d);
        m_if.tready <= 1'b1;
        while (!m_if.tvalid) @(posedge aclk);
        for (int i = 0; i < N_DDS; i++)
            carrier[i] = m_if.tdata[i*16 +: 16];
        for (int i = 1; i < N_DDS; i++)
            if (($signed(carrier[i-1]) >= 0) != ($signed(carrier[i]) >= 0)) zc++;
        $display("[FREQ SWEEP] pinc=0x%08h zc=%0d (expect ~%0d)", pincs[j], zc, exp_zc[j]);
        `FAIL_IF_LOG(zc < exp_zc[j]-1 || zc > exp_zc[j]+1,
            $sformatf("pinc 0x%08h: zc=%0d not near %0d", pincs[j], zc, exp_zc[j]));
        repeat(30) @(posedge aclk);
    end
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 10: gaussian envelope shape (src=mem, no carrier).
//   NOTE: gaussian formula fixed from the corrupted v6 source ('_' -> '*').
// ----------------------------------------------------------------------------
`SVTEST(tc_gaussian_envelope)
    localparam int NROWS = 4;
    localparam int NSAMP = N_DDS * NROWS;
    logic [15:0] re [], im [];
    logic signed [15:0] frame [N_DDS];
    logic [159:0] d;
    real center, sigma, g;
    reg_write(REG_OUTSEL, 32'd0);
    re = new[NSAMP]; im = new[NSAMP];
    center = real'(N_DDS) / 2.0;
    sigma  = real'(N_DDS) / 6.0;
    for (int row = 0; row < NROWS; row++)
        for (int k = 0; k < N_DDS; k++) begin
            g = $exp(-0.5 * ((real'(k) - center) / sigma) ** 2);  // FIXED
            re[row*N_DDS + k] = $rtoi(g * real'(MAXV));
            im[row*N_DDS + k] = 16'h0000;
        end
    load_envelope(NSAMP, re, im);
    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'(NSAMP), 2'd2 /*mem*/, 1'b0, 1'b0, 1'b0);
    queue_descriptor(d);
    m_if.tready <= 1'b1;
    while (!m_if.tvalid) @(posedge aclk);
    repeat(1) @(posedge aclk);   // skip transient cycle
    for (int i = 0; i < N_DDS; i++)
        frame[i] = m_if.tdata[i*16 +: 16];
    begin
        int peak_idx = 0, peak_val = -40000;
        for (int i = 0; i < N_DDS; i++)
            if ($signed(frame[i]) > peak_val) begin
                peak_val = $signed(frame[i]); peak_idx = i;
            end
        $display("[GAUSSIAN] peak at lane %0d, value %0d", peak_idx, peak_val);
        `FAIL_IF_LOG(peak_idx < 6 || peak_idx > 9, "peak not near center");
        `FAIL_IF_LOG($signed(frame[0]) > peak_val/4, "edge lane0 too big");
    end
`SVTEST_END
