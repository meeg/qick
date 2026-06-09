// ============================================================================
// File: axis_constant_tc00.sv
// Description: SVUnit testbench top-level for axis_constant.
// ============================================================================

`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module axis_constant_unit_test;

    import svunit_pkg::svunit_testcase;

    string name = "axis_constant_ut";
    svunit_testcase svunit_ut;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real CLOCK_FREQUENCY = 200e6;
    localparam int  B     = 16;
    localparam int  BYTES = B / 8;

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    logic tb_clk  = 1'b0;
    logic tb_rstn = 1'b1;

    // =========================================================================
    // Interfaces
    // =========================================================================
    axi4_stream_if #(
        .N_BYTES_TDATA (BYTES),
        .N_BITS_TUSER  (1),
        .N_BITS_TID    (1),
        .N_BITS_TDEST  (1),
        .HAS_TSTRB     (1'b0),
        .HAS_TKEEP     (1'b0),
        .HAS_TID       (1'b0),
        .HAS_TDEST     (1'b0),
        .HAS_TUSER     (1'b0)
    ) axis_if (
        .i_clk  (tb_clk),
        .i_rstn (tb_rstn)
    );

    // =========================================================================
    // Clock generator
    // =========================================================================
    initial begin
        $dumpfile("axis_constant.vcd");
        $dumpvars();
    end

    clk_gen #(.FREQ (CLOCK_FREQUENCY)) u_clk_gen (
        .i_enable (1'b1),
        .o_clk    (tb_clk)
    );

    // =========================================================================
    // Clocking block
    // =========================================================================
    default clocking tb_cb @(posedge tb_clk);
        default input #1step output #2;
        output tb_rstn;
    endclocking

    // =========================================================================
    // DUT
    // =========================================================================
    axis_constant #(
        .DATA_WIDTH (B)
    ) u_dut (
        .m_axis_aresetn (tb_rstn),
        .m_axis_aclk    (tb_clk),
        .m_axis         (axis_if.master)
    );

    // =========================================================================
    // SVUnit build / setup / teardown
    // =========================================================================
    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
        repeat(5) @(tb_cb);
        tb_rstn <= 1'b0;
        repeat(5) @(tb_cb);
        tb_rstn <= 1'b1;
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    // =========================================================================
    // Test cases
    // =========================================================================
    `SVUNIT_TESTS_BEGIN
    `include "axis_constant_tests.sv"
    `SVUNIT_TESTS_END

endmodule
