// ============================================================================
// File: axis_kidsim_v3_tc00.sv
// Description: SVUnit TB for axis_kidsim_v3 (L-lane KID simulator IP).
//   Light integration test using axi4_lite_if (register writes) and
//   axi4_stream_if (input/output streams). Verifies per-lane data routing,
//   WE-by-ADDR register addressing, and m_axis valid/last following lane 0.
// ============================================================================
`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module axis_kidsim_v3_unit_test;
    import svunit_pkg::svunit_testcase;

    string name = "axis_kidsim_v3_ut";
    svunit_testcase svunit_ut;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real CLK_FREQ = 250e6;
    localparam int  L        = 4;
    localparam int  TOP_LAT  = 24;

    localparam int  AXI_DW   = 32;
    localparam int  AXI_AW   = 8;

    // Register byte addresses.
    localparam logic [AXI_AW-1:0] A_DDS_BVAL  = 8'h00;
    localparam logic [AXI_AW-1:0] A_DDS_SLOPE = 8'h04;
    localparam logic [AXI_AW-1:0] A_DDS_STEPS = 8'h08;
    localparam logic [AXI_AW-1:0] A_DDS_WAIT  = 8'h0C;
    localparam logic [AXI_AW-1:0] A_DDS_FREQ  = 8'h10;
    localparam logic [AXI_AW-1:0] A_IIR_C0    = 8'h14;
    localparam logic [AXI_AW-1:0] A_IIR_C1    = 8'h18;
    localparam logic [AXI_AW-1:0] A_IIR_G     = 8'h1C;
    localparam logic [AXI_AW-1:0] A_OUTSEL    = 8'h20;
    localparam logic [AXI_AW-1:0] A_PUNCT_ID  = 8'h24;
    localparam logic [AXI_AW-1:0] A_ADDR      = 8'h28;
    localparam logic [AXI_AW-1:0] A_WE        = 8'h2C;

    // =========================================================================
    // Clock & Reset (single clock domain for this light TB)
    // =========================================================================
    logic clk  = 1'b0;
    logic rstn = 1'b1;
    clk_gen #(.FREQ (CLK_FREQ)) u_clk (.i_enable(1'b1), .o_clk(clk));

    // =========================================================================
    // Interfaces
    // =========================================================================
    axi4_lite_if #(
        .DATA_WIDTH (AXI_DW),
        .ADDR_WIDTH (AXI_AW)
    ) s_axi (.aclk(clk), .aresetn(rstn));

    axi4_stream_if #(
        .TDATA_WIDTH (32*L)
    ) s_axis (.aclk(clk), .aresetn(rstn));

    axi4_stream_if #(
        .TDATA_WIDTH (32*L)
    ) m_axis (.aclk(clk), .aresetn(rstn));

    // Per-lane trigger.
    logic [L-1:0] tb_trigger = '0;

    // =========================================================================
    // Dump
    // =========================================================================
    initial begin
        $dumpfile("axis_kidsim_v3.vcd");
        $dumpvars();
    end

    // =========================================================================
    // DUT (interfaces wired to flat ports)
    // =========================================================================
    axis_kidsim_v3 #(
        .L (L)
    ) dut (
        .trigger       (tb_trigger),
        .s_axi_aclk    (clk),
        .s_axi_aresetn (rstn),
        .s_axi_awaddr  (s_axi.awaddr),
        .s_axi_awprot  (s_axi.awprot),
        .s_axi_awvalid (s_axi.awvalid),
        .s_axi_awready (s_axi.awready),
        .s_axi_wdata   (s_axi.wdata),
        .s_axi_wstrb   (s_axi.wstrb),
        .s_axi_wvalid  (s_axi.wvalid),
        .s_axi_wready  (s_axi.wready),
        .s_axi_bresp   (s_axi.bresp),
        .s_axi_bvalid  (s_axi.bvalid),
        .s_axi_bready  (s_axi.bready),
        .s_axi_araddr  (s_axi.araddr),
        .s_axi_arprot  (s_axi.arprot),
        .s_axi_arvalid (s_axi.arvalid),
        .s_axi_arready (s_axi.arready),
        .s_axi_rdata   (s_axi.rdata),
        .s_axi_rresp   (s_axi.rresp),
        .s_axi_rvalid  (s_axi.rvalid),
        .s_axi_rready  (s_axi.rready),
        .aresetn       (rstn),
        .aclk          (clk),
        .s_axis_tvalid (s_axis.tvalid),
        .s_axis_tdata  (s_axis.tdata),
        .s_axis_tlast  (s_axis.tlast),
        .m_axis_tvalid (m_axis.tvalid),
        .m_axis_tdata  (m_axis.tdata),
        .m_axis_tlast  (m_axis.tlast)
    );

    // The DUT has no s_axis_tready (continuous pipeline). Force the interface's
    // tready high so s_axis.tx() handshakes complete. The DUT ignores it.
    assign s_axis.tready = 1'b1;
    // m_axis has no external consumer backpressure in the DUT; drive tready=1
    // so the m_axis interface monitor sees the stream (we sample tdata directly).
    // (m_axis.tready is an interface signal, not a DUT input, so drive it here.)
    assign m_axis.tready = 1'b1;

    // =========================================================================
    // Helpers
    // =========================================================================
    // Configure lane `lane`: write regs then pulse WE with ADDR=lane.
    task automatic config_lane(input int lane, input int outsel,
                               input int freq, input int c0,
                               input int c1,   input int g,
                               input int punct_id);
        s_axi.axi_write(A_DDS_FREQ,  freq);
        s_axi.axi_write(A_IIR_C0,    c0);
        s_axi.axi_write(A_IIR_C1,    c1);
        s_axi.axi_write(A_IIR_G,     g);
        s_axi.axi_write(A_OUTSEL,    outsel);
        s_axi.axi_write(A_PUNCT_ID,  punct_id);
        s_axi.axi_write(A_ADDR,      lane);
        s_axi.axi_write(A_WE,        32'h1);   // latch into lane `lane`
        s_axi.axi_write(A_WE,        32'h0);
    endtask

    function automatic logic [31:0] pack_qi(input int q, input int i);
        return {q[15:0], i[15:0]};
    endfunction

    // =========================================================================
    // SVUnit
    // =========================================================================
    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();

        // idle explicit BEFORE the reset, blocking, without m_reset() dependency
        s_axis.tvalid = 1'b0;  s_axis.tlast = 1'b0;  s_axis.tdata = '0;
        s_axis.tstrb  = '1;    s_axis.tkeep = '0;    s_axis.tuser = '0;
        s_axis.tid    = '0;    s_axis.tdest = '0;
        tb_trigger = '0;

        rstn = 1'b0;
        repeat(20) @(posedge clk);
        rstn = 1'b1;

        s_axis.m_reset();      // master side of input stream
        s_axi.reset();
        repeat(5) @(posedge clk);
    endtask

    task teardown();
        svunit_ut.teardown();
        s_axis.idle();
        repeat(2) @(posedge clk);
    endtask

    `SVUNIT_TESTS_BEGIN
    `include "axis_kidsim_v3_tests.sv"
    `SVUNIT_TESTS_END

endmodule
