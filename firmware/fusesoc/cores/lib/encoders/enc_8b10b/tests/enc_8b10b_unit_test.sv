`include "svunit_defines.svh"

//////////////////////////////////////////////////////////////////////////////
// SVUnit testbench for enc_8b10b (IBM 8b/10b encoder).
//
// Self-checking against a golden ROM (enc_8b10b_golden.hex): 1024 entries
// indexed by {k, rd, byte} -> {code_err, rd_next, sym10}. The ROM was produced
// from libsv's LUT AFTER it was cross-validated, entry for entry, against an
// independent from-scratch 8b/10b golden over all 256 data + 12 control codes
// in both disparities (0 mismatches). Here we replay streams through the
// synthesizable core and confirm it reproduces that table cycle by cycle.
//
// Timing contract: output is registered, one cycle after the word is presented
// while en_i is high. Drive scheme below is "present for one cycle, sample the
// cycle after" so there is no off-by-one to reason about.
//////////////////////////////////////////////////////////////////////////////

module enc_8b10b_unit_test;
  import svunit_pkg::svunit_testcase;

  string name = "enc_8b10b_ut";
  svunit_testcase svunit_ut;

  //--------------------------------------------------------------------------
  // DUT signals
  //--------------------------------------------------------------------------
  logic       clk_i;
  logic       rst_ni;
  logic       en_i;
  logic [7:0] din_i;
  logic       k_i;
  logic [9:0] dout_o;
  logic       disp_o;
  logic       code_err_o;
  logic       dout_valid_o;

  enc_8b10b dut (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .en_i         (en_i),
    .din_i        (din_i),
    .k_i          (k_i),
    .dout_o       (dout_o),
    .disp_o       (disp_o),
    .code_err_o   (code_err_o),
    .dout_valid_o (dout_valid_o)
  );

  // free-running clock
  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  // golden ROM: {code_err[11], rd_next[10], sym10[9:0]}
  logic [11:0] gold [0:1023];

  // running-disparity model (0 => -1, 1 => +1); tracks the DUT's internal rd
  logic rd_model;

  // the 12 legal control bytes (K.28.0..7, K.23/27/29/30.7)
  localparam int NUM_K = 12;
  logic [7:0] k_legal [0:NUM_K-1];

  //--------------------------------------------------------------------------
  function void build();
    svunit_ut = new(name);
    $readmemh("enc_8b10b_golden.hex", gold);
    k_legal[0]=8'h1C; k_legal[1]=8'h3C; k_legal[2]=8'h5C; k_legal[3]=8'h7C;
    k_legal[4]=8'h9C; k_legal[5]=8'hBC; k_legal[6]=8'hDC; k_legal[7]=8'hFC;
    k_legal[8]=8'hF7; k_legal[9]=8'hFB; k_legal[10]=8'hFD; k_legal[11]=8'hFE;
  endfunction

  //--------------------------------------------------------------------------
  task setup();
    svunit_ut.setup();
    en_i  = 1'b0;
    din_i = 8'h00;
    k_i   = 1'b0;
    // reset: rd resets to 0 (=-1)
    rst_ni = 1'b0;
    repeat (3) @(posedge clk_i);
    rst_ni = 1'b1;
    @(posedge clk_i);
    rd_model = 1'b0;
  endtask

  //--------------------------------------------------------------------------
  task teardown();
    svunit_ut.teardown();
  endtask

  //--------------------------------------------------------------------------
  // Drive one word, then sample+check the registered output the next cycle.
  // Uses the current rd_model to index the golden, then advances rd_model.
  //--------------------------------------------------------------------------
  task automatic drive_check(input logic k, input logic [7:0] b);
    logic [9:0]  idx;
    logic [11:0] exp;
    idx = {k, rd_model, b};
    exp = gold[idx];

    @(posedge clk_i);
    din_i <= b; k_i <= k; en_i <= 1'b1;   // present for this cycle
    @(posedge clk_i);
    en_i <= 1'b0;                          // sampled at this edge; outputs update now
    #1;                                    // let NBAs settle before sampling
    `FAIL_UNLESS_EQUAL(dout_o,     exp[9:0])
    `FAIL_UNLESS_EQUAL(disp_o,     exp[10])
    `FAIL_UNLESS_EQUAL(code_err_o, exp[11])
    `FAIL_UNLESS(dout_valid_o == 1'b1)
    // symbol weight must always be 4, 5 or 6 ones (bounded disparity)
    `FAIL_UNLESS($countones(dout_o) inside {4,5,6})
    rd_model = exp[10];
  endtask

  //==========================================================================
  `SVUNIT_TESTS_BEGIN

  //------------------------------------------------------------------
  // Reset drives outputs to their defined idle values.
  `SVTEST(reset_values)
    `FAIL_UNLESS_EQUAL(dout_o,     10'b0)
    `FAIL_UNLESS_EQUAL(code_err_o, 1'b0)
    `FAIL_UNLESS_EQUAL(disp_o,     1'b0)   // rd = 0 => -1
    `FAIL_UNLESS_EQUAL(dout_valid_o, 1'b0)
  `SVTEST_END

  //------------------------------------------------------------------
  // All 256 data bytes, in order, from the reset disparity.
  `SVTEST(data_sweep_pass1)
    for (int b = 0; b < 256; b++) drive_check(1'b0, b[7:0]);
  `SVTEST_END

  //------------------------------------------------------------------
  // Second pass back-to-back: the running disparity entering each byte
  // now differs from pass 1, so many codes get exercised at both RD.
  // (Exhaustive both-RD equivalence is proven offline; this is the
  //  in-sim regression that the synthesizable core matches the table.)
  `SVTEST(data_sweep_two_passes)
    for (int b = 0; b < 256; b++) drive_check(1'b0, b[7:0]);
    for (int b = 0; b < 256; b++) drive_check(1'b0, b[7:0]);
  `SVTEST_END

  //------------------------------------------------------------------
  // The 12 legal control symbols encode with code_err_o = 0.
  `SVTEST(control_codes_legal)
    foreach (k_legal[j]) begin
      drive_check(1'b1, k_legal[j]);
      `FAIL_UNLESS(code_err_o == 1'b0)
    end
  `SVTEST_END

  //------------------------------------------------------------------
  // An illegal control code (e.g. K.00.0 = 8'h00) must raise code_err_o.
  // We check the flag against the golden (which carries libsv's behaviour).
  `SVTEST(control_code_illegal_flags_error)
    logic [9:0]  idx;
    logic [11:0] exp;
    idx = {1'b1, rd_model, 8'h00};
    exp = gold[idx];
    `FAIL_UNLESS(exp[11] == 1'b1)          // sanity: golden marks it illegal
    drive_check(1'b1, 8'h00);
    `FAIL_UNLESS(code_err_o == 1'b1)
  `SVTEST_END

  //------------------------------------------------------------------
  // en_i low holds the symbol and drops valid (no spurious advance).
  `SVTEST(enable_gating_holds_output)
    logic [9:0] held;
    drive_check(1'b0, 8'h55);
    held = dout_o;
    // idle a few cycles with en_i low
    din_i <= 8'hAA; k_i <= 1'b0; en_i <= 1'b0;
    repeat (4) @(posedge clk_i);
    #1;
    `FAIL_UNLESS_EQUAL(dout_o, held)       // unchanged
    `FAIL_UNLESS(dout_valid_o == 1'b0)     // valid dropped
  `SVTEST_END

  `SVUNIT_TESTS_END
  //==========================================================================

endmodule
