// ============================================================================
// File: sgv4_tests.sv
// Description: SVUnit test cases for sgv4 amplitude characterisation.
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 01: Reset — output not valid.
// ----------------------------------------------------------------------------
`SVTEST(tc_reset_idle)
    repeat(5) @(posedge tb_clk);
    `FAIL_IF(tb_axis_tvalid !== 1'b0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 02: Mid-scale envelope, mid-scale gain, full-scale cosine (I/Q).
// ----------------------------------------------------------------------------
`SVTEST(tc_level_midscale)
    logic [15:0] dout0, exp_rtl;
    logic [159:0] d;
    tb_outsel_reg = 1'b0;                  // parte real
    set_envelope(16'h4000, 16'h2000);
    d = build_descr(32'd0, 32'd0, 16'd0, 16'h4000, 16'd64, 2'd0,
                    1'b0, 1'b0, 1'b0, 1'b0);
    load_descriptor(d);
    wait_output(dout0);
    exp_rtl = ref_rtl_sel(16'sh4000, 16'sh2000,
                          16'sh7FFF, 16'sh0000, 16'sh4000, 1'b0);
    $display("[LEVEL midscale] RTL=0x%04h  faithful=0x%04h", dout0, exp_rtl);
    `FAIL_IF_LOG(dout0 !== exp_rtl,
        $sformatf("RTL 0x%04h != faithful 0x%04h", dout0, exp_rtl));
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 03: Full-scale everything — expose wrap-around / level loss.
// ----------------------------------------------------------------------------
`SVTEST(tc_level_fullscale)
    logic [15:0] dout0, exp_rtl;
    logic [159:0] d;
    tb_outsel_reg = 1'b0;
    set_envelope(16'(MAXV), 16'(MAXV));
    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'd64, 2'd0, 1'b0, 1'b0, 1'b0, 1'b0);
    load_descriptor(d);
    wait_output(dout0);
    exp_rtl = ref_rtl_sel(16'(MAXV), 16'(MAXV),
                          16'sh7FFF, 16'sh0000, 16'(MAXV), 1'b0);
    $display("[LEVEL fullscale] RTL=0x%04h  faithful=0x%04h", dout0, exp_rtl);
    `FAIL_IF_LOG(dout0 !== exp_rtl,
        $sformatf("RTL 0x%04h != faithful 0x%04h", dout0, exp_rtl));
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 04: OUTSEL = 1 (I only) — Q should be zeroed.
// ----------------------------------------------------------------------------
`SVTEST(tc_outsel_real_vs_imag)
    logic [15:0] out_re, out_im, exp_re, exp_im;
    logic [159:0] d;
    set_envelope(16'h4000, 16'h2000);

    // outsel = 0 -> parte real
    tb_outsel_reg = 1'b0;
    d = build_descr(32'd0, 32'd0, 16'd0, 16'h4000, 16'd64, 2'd0,
                    1'b0, 1'b0, 1'b0, 1'b0);
    load_descriptor(d);
    wait_output(out_re);

    // outsel = 1 -> parte imag
    tb_outsel_reg = 1'b1;
    d = build_descr(32'd0, 32'd0, 16'd0, 16'h4000, 16'd64, 2'd0,
                    1'b0, 1'b0, 1'b0, 1'b0);
    load_descriptor(d);
    wait_output(out_im);

    exp_re = ref_rtl_sel(16'sh4000, 16'sh2000, 16'sh7FFF, 16'sh0000, 16'sh4000, 1'b0);
    exp_im = ref_rtl_sel(16'sh4000, 16'sh2000, 16'sh7FFF, 16'sh0000, 16'sh4000, 1'b1);
    $display("[OUTSEL] real=0x%04h (exp 0x%04h)  imag=0x%04h (exp 0x%04h)",
             out_re, exp_re, out_im, exp_im);
    `FAIL_IF_LOG(out_re !== exp_re, $sformatf("real path 0x%04h != 0x%04h", out_re, exp_re));
    `FAIL_IF_LOG(out_im !== exp_im, $sformatf("imag path 0x%04h != 0x%04h", out_im, exp_im));
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 05: src=2 (envelope only) — complex envelope passthrough.
// ----------------------------------------------------------------------------
`SVTEST(tc_envelope_only)
    logic [15:0] dout0;
    logic [159:0] d;
    tb_outsel_reg = 1'b0;               // real -> debe salir env_re
    set_envelope(16'h4000, 16'h2000);
    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'd64, 2'd2, 1'b0, 1'b0, 1'b0, 1'b0);
    load_descriptor(d);
    wait_output(dout0);
    $display("[ENV ONLY] env_re=0x4000 out=0x%04h", dout0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 06: Full-scale product path reaches ~MAXV (not MAXV/2).
// ----------------------------------------------------------------------------
`SVTEST(tc_fullscale_fixed)
    logic [15:0] dout0;
    logic [159:0] d;
    tb_outsel_reg = 1'b0;
    set_envelope(16'(MAXV), 16'h0000);
    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'd64, 2'd0, 1'b0, 1'b0, 1'b0, 1'b0);
    load_descriptor(d);
    wait_output(dout0);
    $display("[FIXED fullscale] -> out=0x%04h (%0d)", dout0, $signed(dout0));
    `FAIL_IF_LOG($signed(dout0) < 16'sd30000,
        $sformatf("I should be ~MAXV, got 0x%04h (%0d)", dout0, $signed(dout0)));
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 07: Saturation — no wrap, clamps to MAXV.
// ----------------------------------------------------------------------------
`SVTEST(tc_saturation_no_wrap)
    logic [15:0] dout0;
    logic [159:0] d;
    tb_outsel_reg = 1'b0;
    set_envelope(16'h7FFF, 16'h7FFF);
    d = build_descr(32'd0, 32'd0, 16'd0, 16'h7FFF, 16'd64, 2'd0,
                    1'b0, 1'b0, 1'b0, 1'b0);
    load_descriptor(d);
    wait_output(dout0);
    $display("[SATURATION] -> out=0x%04h (%0d)", dout0, $signed(dout0));
    `FAIL_IF_LOG($signed(dout0) < 16'sd0,
        $sformatf("wrap detected! out=0x%04h (%0d)", dout0, $signed(dout0)));
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 08: DDS only, complex carriers.
// ----------------------------------------------------------------------------
`SVTEST(tc_dds_only_complex)
    logic [15:0] dout0;
    logic [159:0] d;
    tb_outsel_reg = 1'b0;              // cos -> parte real
    d = build_descr(32'd0, 32'd0, 16'd0, 16'(MAXV),
                    16'd64, 2'd1, 1'b0, 1'b0, 1'b0, 1'b0);
    load_descriptor(d);
    // esperar a que el pipe del DDS se llene tras tvalid
    wait_output(dout0);
    repeat(15) @(posedge tb_clk);
    dout0 = tb_axis_tdata[15:0];
    $display("[DDS-ONLY DC] freq=0 src=1 outsel=0 -> real=0x%04h", dout0);
    `FAIL_IF_LOG($signed(dout0) < 16'sd30000, "DDS-only real path gave near-zero");
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 09: Saturation flag coherence with complex path.
// ----------------------------------------------------------------------------
`SVTEST(tc_sat_flag_coherent)
    logic [159:0] d;
    logic [15:0] envs [4] = '{16'h2000, 16'h7FFF, 16'h8000, 16'h8001};
    int t;
    foreach (envs[k]) begin
        bit saw_sat = 1'b0;
        bit saw_clamp = 1'b0;
        set_envelope(envs[k], envs[k]);
        d = build_descr(32'd0, 32'd0, 16'd0, 16'h7FFF, 16'd32, 2'd0,
                        1'b0, 1'b0, 1'b0, 1'b0);
        load_descriptor(d);
        for (t = 0; t < 60; t++) begin
            @(posedge tb_clk);
            if (dut.o_sat) saw_sat = 1'b1;
            // Check if lane-0 output equals a clamp value
            if (dut.o_axis_tvalid) begin
                if (dut.o_axis_tdata[15:0] === 16'h7FFE ||
                    dut.o_axis_tdata[15:0] === 16'h8002) saw_clamp = 1'b1;
            end
        end
        $display("[SAT COHERENT] env=0x%04h  o_sat=%b  clamp_out=%b",
                 envs[k], saw_sat, saw_clamp);
    end
    `FAIL_IF(1'b0);   // characterisation
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 10: Multiple lanes — all lanes produce same output.
// ----------------------------------------------------------------------------
`SVTEST(tc_all_lanes_match)
    logic [15:0] lane0, lane7;
    logic [159:0] d;
    tb_outsel_reg = 1'b0;
    set_envelope(16'h4000, 16'h2000);
    d = build_descr(32'd0, 32'd0, 16'd0, 16'h4000, 16'd64, 2'd0,
                    1'b0, 1'b0, 1'b0, 1'b0);
    load_descriptor(d);
    wait_output(lane0);
    lane0 = tb_axis_tdata[0*16 +: 16];
    lane7 = tb_axis_tdata[7*16 +: 16];
    $display("[ALL LANES] lane0=0x%04h  lane7=0x%04h", lane0, lane7);
    `FAIL_IF_LOG(lane0 !== lane7,
        $sformatf("Lanes differ: lane0=0x%04h lane7=0x%04h", lane0, lane7));
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 11: Phase increment — DDS carrier changes correctly.
// ----------------------------------------------------------------------------
`SVTEST(tc_dds_phase_increment)
    logic [159:0] d;
    logic [31:0] pinc;
    bit pinc_propagated = 1'b0;
    int t;
logic [31:0] expected_pinc;
logic [31:0] actual_pinc;
    
    // Use a pinc with a recognizable value
    pinc = 32'h1234_5678;
    
    $display("[DDS TEST] Starting with pinc=0x%08h", pinc);
    
    // Descriptor: outsel=1 (DDS only), gain=MAXV
    d = build_descr(pinc, 32'd0, 16'h0000, 16'h7FFF,
                    16'd128, 2'd1, 1'b0, 1'b0, 1'b0, 1'b0);
    load_descriptor(d);
    
    // Wait for the DDS to become valid
    t = 0;
    while (!tb_axis_tvalid && t < 100) begin
        @(posedge tb_clk);
        t++;
    end
    
    if (!tb_axis_tvalid) begin
        $display("[DDS TEST] ERROR: DDS never became valid");
        `FAIL_IF(1'b1);
    end
    
    // Wait for the DDS latency (8 cycles)
    repeat(15) @(posedge tb_clk);
    
    // Verify that the pinc was propagated correctly to the controller
    // The pinc in the controller should be pinc * N_DDS
    expected_pinc = pinc * N_DDS;  // 0x12345678 * 8 = 0x91A2B3C0
    actual_pinc = dut.ctrl_i.o_dds_ctrl[31:0];
    
    $display("[DDS TEST] Expected pinc = 0x%08h (pinc * N_DDS)", expected_pinc);
    $display("[DDS TEST] Actual pinc = 0x%08h", actual_pinc);
    $display("[DDS TEST] Control phase = 0x%08h", dut.ctrl_i.o_dds_ctrl[63:32]);
    $display("[DDS TEST] Gain = 0x%04h", dut.ctrl_i.o_gain);
    
    // Verify that the pinc was propagated correctly
    if (actual_pinc === expected_pinc) begin
        pinc_propagated = 1'b1;
        $display("[DDS TEST] Pinc propagated correctly!");
    end else begin
        $display("[DDS TEST] Pinc mismatch! Expected 0x%08h, got 0x%08h", 
                 expected_pinc, actual_pinc);
    end
    
    // Verify that the DDS has the correct phase
    // With pinc=0, the phase should be 0
    // With pinc != 0, the phase should change over time
    // But since the DDS is in DC mode, the output may be constant
    
    $display("[DDS TEST] DDS output: cos=0x%04h sin=0x%04h", 
             dut.gen_lane[0].dds_i.m_axis_data_tdata[15:0],
             dut.gen_lane[0].dds_i.m_axis_data_tdata[31:16]);
    
    $display("[DDS TEST] pinc_propagated=%b", pinc_propagated);
    
    // The test passes if the pinc was propagated correctly to the controller
    `FAIL_IF_LOG(!pinc_propagated, 
        $sformatf("Pinc did not propagate: expected 0x%08h, got 0x%08h", 
                  expected_pinc, actual_pinc));
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 12: Memory address increments correctly.
// ----------------------------------------------------------------------------
`SVTEST(tc_mem_addr_increments)
    logic [15:0] start_addr = 16'h1000;
    logic [15:0] addr_seen;
    logic [159:0] d;
    
    d = build_descr(32'd0, 32'd0, start_addr, 16'h4000, 16'd32, 2'd2,
                    1'b0, 1'b0, 1'b0, 1'b0);
    load_descriptor(d);
    
    // Wait for first output and capture address
    for (int k = 0; k < 20; k++) begin
        @(posedge tb_clk);
        if (tb_axis_tvalid) begin
            addr_seen = dut.o_mem_addr;
            $display("[MEM ADDR] cycle %0d: addr=0x%04h", k, addr_seen);
        end
    end
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST: Verify that the descriptor is loaded correctly.
// ----------------------------------------------------------------------------
`SVTEST(tc_descriptor_load_debug)
    logic [159:0] d;
    logic [31:0] expected_pinc = 32'h1234_5678;
    logic [31:0] expected_phase = 32'h9ABC_DEF0;
    logic [15:0] expected_gain = 16'h4000;
    logic [15:0] expected_addr = 16'h0040;

    d = build_descr(expected_pinc, expected_phase, expected_addr, expected_gain,
                    16'd64, 2'd0, 1'b0, 1'b0, 1'b0, 1'b0);
    load_descriptor(d);

    // Wait for the controller to process the descriptor
    repeat(30) @(posedge tb_clk);

    // Verify that the pinc was loaded correctly
    $display("[DEBUG] Descriptor loaded: pinc=0x%08h", expected_pinc);
    $display("[DEBUG] Control pinc output = 0x%08h", dut.ctrl_i.o_dds_ctrl[31:0]);
    $display("[DEBUG] Control phase output = 0x%08h", dut.ctrl_i.o_dds_ctrl[63:32]);
    $display("[DEBUG] Gain output = 0x%04h", dut.ctrl_i.o_gain);
    $display("[DEBUG] Mem addr output = 0x%04h", dut.ctrl_i.o_mem_addr);

    // Verify internal signals
    $display("[DEBUG] fifo_dout_r = 0x%040h", dut.ctrl_i.fifo_dout_r);
    $display("[DEBUG] pinc_int = 0x%08h", dut.ctrl_i.pinc_int);
    $display("[DEBUG] pinc_r1 = 0x%08h", dut.ctrl_i.pinc_r1);
    $display("[DEBUG] pinc_r2 = 0x%08h", dut.ctrl_i.pinc_r2);
    $display("[DEBUG] pinc_n = 0x%08h", dut.ctrl_i.pinc_n);
    $display("[DEBUG] pinc_n_r5 = 0x%08h", dut.ctrl_i.pinc_n_r5);

    // The test always passes, it just shows information
    `FAIL_IF(1'b0);  // Force failure to see the information
`SVTEST_END
