// ============================================================================
// File: axis_constant_iq_tc00.sv
// Description: SVUnit testbench top-level for axis_constant_iq.
// ============================================================================

`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module axis_constant_iq_unit_test;

    import svunit_pkg::svunit_testcase;

    string name = "axis_constant_iq_ut";
    svunit_testcase svunit_ut;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real AXI_FREQ  = 100e6;
    localparam real AXIS_FREQ = 200e6;
    localparam int  B         = 16;
    localparam int  BYTES     = B / 8;
    localparam int NUM_REGS   = 4;                 
    localparam int ADDR_W     = 6;
    localparam int AXI_DW     = 2*B;                 
    localparam int N_OUTS     = 4;                 


    // =========================================================================
    // Clock & Reset
    // =========================================================================
    logic tb_axi_clk  = 1'b0;
    logic tb_axis_clk = 1'b0;
    logic tb_axi_rstn = 1'b1;
    logic tb_axis_rstn = 1'b1;

    // =========================================================================
    // Interfaces
    // =========================================================================
    axi4_lite_if #(
        .DATA_WIDTH(AXI_DW), 
        .ADDR_WIDTH(ADDR_W) // Enough to address real, imag, we, reserved
        ) s_axi(
            .aclk   (tb_axi_clk ), 
            .aresetn(tb_axi_rstn)
        );

    axi4_stream_if #(
        .N_BYTES_TDATA (2* BYTES * N_OUTS), // Total bytes for N parallel I/Q outputs
        .N_BITS_TUSER  (1),
        .N_BITS_TID    (1),
        .N_BITS_TDEST  (1),
        .HAS_TSTRB     (1'b0),
        .HAS_TKEEP     (1'b0),
        .HAS_TID       (1'b0),
        .HAS_TDEST     (1'b0),
        .HAS_TUSER     (1'b0)
    ) axis_if (
        .i_clk  (tb_axis_clk),
        .i_rstn (tb_axis_rstn)
    );

    // =========================================================================
    // Clock generator
    // =========================================================================
    initial begin
        $dumpfile("axis_constant_iq.vcd");
        $dumpvars();
    end

    clk_gen #(.FREQ (AXI_FREQ)) axi_clk_gen (
        .i_enable (1'b1),
        .o_clk    (tb_axi_clk)
    );

    clk_gen #(.FREQ (AXIS_FREQ)) axis_clk_gen (
        .i_enable (1'b1),
        .o_clk    (tb_axis_clk)
    );

    // =========================================================================
    // Clocking block
    // =========================================================================
    default clocking tb_cb @(posedge s_axi.aclk);
        default input #1step output #2;
        output tb_axi_rstn;
        output tb_axis_rstn;
    endclocking

    // =========================================================================
    // DUT
    // =========================================================================
    axis_constant_iq #(
        .B (B),
        .N (N_OUTS)
    ) u_dut (
        .s_axi         (s_axi),
        .m_axis        (axis_if)
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
        tb_axi_rstn  <= 1'b0;
        tb_axis_rstn <= 1'b0;
        repeat(5) @(tb_cb);
        tb_axi_rstn  <= 1'b1;
        tb_axis_rstn <= 1'b1;
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    // =========================================================================
    // Test cases
    // =========================================================================
    `SVUNIT_TESTS_BEGIN
    `include "axis_constant_iq_tests.sv"
    `SVUNIT_TESTS_END

endmodule
