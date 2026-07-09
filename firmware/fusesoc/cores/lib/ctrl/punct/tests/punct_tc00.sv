// ============================================================================
// File: punct_tc00.sv
// Description: SVUnit testbench top-level for punct (QICK / axis_kidsim_v3).
//   Puncturing / per-frame sample selector: asserts o_dout_en on the sample
//   whose in-frame index equals i_id_reg. Latency 2 on valid/last.
// ============================================================================
`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module punct_unit_test;
    import svunit_pkg::svunit_testcase;

    string name = "punct_ut";
    svunit_testcase svunit_ut;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real CLOCK_FREQUENCY = 250e6;

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    logic tb_clk  = 1'b0;
    logic tb_rstn = 1'b1;
    clk_gen #(.FREQ (CLOCK_FREQUENCY)) u_clk (.i_enable(1'b1), .o_clk(tb_clk));

    // =========================================================================
    // DUT signals
    // =========================================================================
    logic        tb_din_valid = 1'b0;
    logic        tb_din_last  = 1'b0;
    logic [15:0] tb_id_reg    = '0;
    logic        tb_dout_valid;
    logic        tb_dout_last;
    logic        tb_dout_en;

    // =========================================================================
    // Clocking block
    // =========================================================================
    default clocking tb_cb @(posedge tb_clk);
        default input #1step output #2;
        output tb_rstn;
        output tb_din_valid;
        output tb_din_last;
        output tb_id_reg;
        input  tb_dout_valid;
        input  tb_dout_last;
        input  tb_dout_en;
    endclocking

    // =========================================================================
    // Dump
    // =========================================================================
    initial begin
        $dumpfile("punct.vcd");
        $dumpvars(0, dut);
    end

    // =========================================================================
    // DUT
    // =========================================================================
    punct dut (
        .i_clk        (tb_clk),
        .i_rstn       (tb_rstn),
        .i_din_valid  (tb_din_valid),
        .i_din_last   (tb_din_last),
        .o_dout_valid (tb_dout_valid),
        .o_dout_last  (tb_dout_last),
        .o_dout_en    (tb_dout_en),
        .i_id_reg     (tb_id_reg)
    );

    // =========================================================================
    // Helpers
    // =========================================================================
    task automatic reset_dut();
        tb_cb.tb_rstn      <= 1'b0;
        tb_cb.tb_din_valid <= 1'b0;
        tb_cb.tb_din_last  <= 1'b0;
        tb_cb.tb_id_reg    <= '0;
        repeat(5) @(tb_cb);
        tb_cb.tb_rstn <= 1'b1;
        repeat(2) @(tb_cb);
    endtask

    // Drive one frame of `len` valid samples (last on the final one).
    task automatic send_frame(input int len);
        for (int k = 0; k < len; k++) begin
            tb_cb.tb_din_valid <= 1'b1;
            tb_cb.tb_din_last  <= (k == len-1);
            @(tb_cb);
        end
        tb_cb.tb_din_valid <= 1'b0;
        tb_cb.tb_din_last  <= 1'b0;
    endtask

    // =========================================================================
    // SVUnit
    // =========================================================================
    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
        reset_dut();
    endtask

    task teardown();
        svunit_ut.teardown();
        tb_cb.tb_din_valid <= 1'b0;
        tb_cb.tb_din_last  <= 1'b0;
        repeat(2) @(tb_cb);
    endtask

    `SVUNIT_TESTS_BEGIN
    `include "punct_tests.sv"
    `SVUNIT_TESTS_END

endmodule