// ============================================================================
// File: axis_kidsim_v3_tests.sv
// Description: SVUnit tests for axis_kidsim_v3. Included by *_tc00.sv.
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 01: Per-lane data routing (all lanes bypass). Each lane's input
//   sub-word must appear on its own output sub-word after TOP_LAT.
// ----------------------------------------------------------------------------
`SVTEST(tc_lane_routing)
    logic [32*L-1:0] word_in;
    logic [32*L-1:0] word_out;
    logic            last;
    // configure every lane to bypass (OUTSEL=2)
    for (int ln = 0; ln < L; ln++)
        config_lane(ln, 2, 4000, 0, 0, 32767, 0);
    // build a distinct marker per lane, packed into one AXIS word
    word_in = '0;
    for (int ln = 0; ln < L; ln++)
        word_in[ln*32 +: 32] = pack_qi(1000 + ln, 2000 + ln);
    // send one beat, then let the pipeline drain and capture the output beat
    fork
        s_axis.tx(word_in, 1'b0);            // one input beat
        begin
            m_axis.rx(word_out, last);       // first output beat
        end
    join
    for (int ln = 0; ln < L; ln++) begin
        logic [31:0] exp;
        exp = word_in[ln*32 +: 32];
        if (word_out[ln*32 +: 32] !== exp) begin
            $display("ROUTING lane %0d: exp 0x%08h got 0x%08h",
                     ln, exp, word_out[ln*32 +: 32]);
            `FAIL_IF(1);
        end
    end
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 02: WE addressing — a write with ADDR=k only configures lane k. Set
//   lane 1 to OUTSEL=3 (output 0) while the others stay bypass; check only
//   lane 1 is zeroed on the output.
// ----------------------------------------------------------------------------
`SVTEST(tc_we_addressing)
    logic [32*L-1:0] word_in;
    logic [32*L-1:0] word_out;
    logic            last;
    for (int ln = 0; ln < L; ln++)
        config_lane(ln, 2, 4000, 0, 0, 32767, 0);   // all bypass
    config_lane(1, 3, 4000, 0, 0, 32767, 0);         // lane 1 -> OUTSEL=3 (zero)

    word_in = '0;
    for (int ln = 0; ln < L; ln++)
        word_in[ln*32 +: 32] = pack_qi(1000 + ln, 2000 + ln);
    fork
        s_axis.tx(word_in, 1'b0);
        m_axis.rx(word_out, last);
    join
    for (int ln = 0; ln < L; ln++) begin
        logic [31:0] exp;
        exp = (ln == 1) ? 32'h0 : word_in[ln*32 +: 32];
        if (word_out[ln*32 +: 32] !== exp) begin
            $display("WE-ADDR lane %0d: exp 0x%08h got 0x%08h",
                     ln, exp, word_out[ln*32 +: 32]);
            `FAIL_IF(1);
        end
    end
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 03: m_axis valid/last follow lane 0. Send a beat with tlast=1; the
//   output beat must carry tlast=1 (from lane 0), captured by rx().
// ----------------------------------------------------------------------------
`SVTEST(tc_mvalid_lane0)
    logic [32*L-1:0] word_out;
    logic            last;
    for (int ln = 0; ln < L; ln++)
        config_lane(ln, 2, 4000, 0, 0, 32767, 0);
    fork
        s_axis.tx('0, 1'b1);                  // beat with tlast=1
        m_axis.rx(word_out, last);
    join
    // rx() only returns on a valid beat, so reaching here means m_axis.tvalid
    // asserted. Check tlast propagated from lane 0.
    `FAIL_IF(last !== 1'b1);
`SVTEST_END