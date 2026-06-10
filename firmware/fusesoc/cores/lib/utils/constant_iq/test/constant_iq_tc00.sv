// ============================================================================
// File: constant_iq_tc00.sv
// Description: SVUnit testbench top-level for constant_iq.
// ============================================================================

`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module constant_iq_unit_test;

    import svunit_pkg::svunit_testcase;

    string name = "constant_iq_ut";
    svunit_testcase svunit_ut;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real AXI_FREQ  = 100e6;
    localparam real AXIS_FREQ = 200e6;
    localparam int  IQ_WIDTH  = 16;
    localparam int  BYTES     = IQ_WIDTH / 8;
    localparam int  NUM_REGS   = 4;                 
    localparam int  ADDR_W     = 6;
    localparam int  AXI_DW     = 2*IQ_WIDTH;                 
    localparam int  NUM_CHANNELS     = 4;                 


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
        .TDATA_WIDTH (2* IQ_WIDTH * NUM_CHANNELS), // Total bytes for N parallel I/Q outputs
        .HAS_TSTRB     (1'b0),
        .HAS_TKEEP     (1'b0),
        .HAS_TID       (1'b0),
        .HAS_TDEST     (1'b0),
        .HAS_TUSER     (1'b0)
    ) axis_if (
        .aclk  (tb_axis_clk),
        .aresetn (tb_axis_rstn)
    );

    // =========================================================================
    // Clock generator
    // =========================================================================
    initial begin
        $dumpfile("constant_iq.vcd");
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
    constant_iq #(
        .IQ_WIDTH (IQ_WIDTH),
        .NUM_CHANNELS (NUM_CHANNELS)
    ) u_dut (
        .s_axi_aclk(tb_axi_clk),
        .s_axi_aresetn(tb_axi_rstn),
        .s_axi         (s_axi),
        .m_axis_aclk(tb_axis_clk),
        .m_axis_aresetn(tb_axis_rstn),
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
    `include "constant_iq_tests.sv"
    `SVUNIT_TESTS_END

endmodule
