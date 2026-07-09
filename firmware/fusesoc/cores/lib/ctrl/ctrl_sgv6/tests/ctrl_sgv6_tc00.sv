// ============================================================================
// File: ctrl_sgv6_tc00.sv
// Description: SVUnit testbench top-level for ctrl_sgv6 (signal gen v6 control).
//
//   Verifies the FIFO-descriptor decode, the READ/CNT FSM, the FIFO read
//   handshake, and the pipeline timing of the control outputs (gain, src,
//   stdy, addr, en). Pipeline latencies are NOT assumed: they are measured at
//   runtime by driving a known descriptor and counting cycles until each field
//   appears on the output.
//
//   Waveform descriptor (160 bits):
//     [148] phrst | [147] stdysel | [146] mode | [145:144] outsel |
//     [143:128] nsamp | [111:96] gain | [79:64] addr | [63:32] phase | [31:0] freq
// ============================================================================
`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module ctrl_sgv6_unit_test;
    import svunit_pkg::svunit_testcase;

    string name = "ctrl_sgv6_ut";
    svunit_testcase svunit_ut;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real CLOCK_FREQUENCY = 200e6;
    localparam int  N     = 16;
    localparam int  N_DDS = 16;
    localparam int  MAXV  = 2**15 - 2;   // 32766, from the driver

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    logic tb_clk  = 1'b0;
    logic tb_rstn = 1'b1;

    clk_gen #(.FREQ (CLOCK_FREQUENCY)) u_clk (.i_enable(1'b1), .o_clk(tb_clk));

    // =========================================================================
    // DUT signals
    // =========================================================================
    logic                 tb_fifo_rd_en;
    logic                 tb_fifo_empty = 1'b1;
    logic [159:0]         tb_fifo_dout  = '0;
    logic [N_DDS*72-1:0]  tb_dds_ctrl;
    logic [N-1:0]         tb_mem_addr;
    logic [15:0]          tb_gain;
    logic [1:0]           tb_src;
    logic                 tb_stdy;
    logic                 tb_en;

    // =========================================================================
    // Clocking block
    // =========================================================================
    default clocking tb_cb @(posedge tb_clk);
        default input #1step output #2;
        output tb_rstn;
        output tb_fifo_empty;
        output tb_fifo_dout;
        input  tb_fifo_rd_en;
        input  tb_mem_addr;
        input  tb_gain;
        input  tb_src;
        input  tb_stdy;
        input  tb_en;
    endclocking

    // =========================================================================
    // Dump
    // =========================================================================
    initial begin
        $dumpfile("ctrl_sgv6.vcd");
        $dumpvars(0, dut);
    end

    // =========================================================================
    // DUT
    // =========================================================================
    ctrl_sgv6 #(
        .N     (N),
        .N_DDS (N_DDS)
    ) dut (
        .i_rstn       (tb_rstn),
        .i_clk        (tb_clk),
        .o_fifo_rd_en (tb_fifo_rd_en),
        .i_fifo_empty (tb_fifo_empty),
        .i_fifo_dout  (tb_fifo_dout),
        .o_dds_ctrl   (tb_dds_ctrl),
        .o_mem_addr   (tb_mem_addr),
        .o_gain       (tb_gain),
        .o_src        (tb_src),
        .o_stdy       (tb_stdy),
        .o_en         (tb_en)
    );

    // =========================================================================
    // Helper: build a 160-bit waveform descriptor.
    // =========================================================================
    function automatic logic [159:0] build_descr(
        input logic [31:0] freq,
        input logic [31:0] phase,
        input logic [15:0] addr,
        input logic [15:0] gain,
        input logic [15:0] nsamp,
        input logic [1:0]  outsel,
        input logic        mode,
        input logic        stdysel,
        input logic        phrst
    );
        logic [159:0] d;
        d = '0;
        d[31:0]    = freq;
        d[63:32]   = phase;
        d[79:64]   = addr;
        d[111:96]  = gain;
        d[143:128] = nsamp;
        d[145:144] = outsel;
        d[146]     = mode;
        d[147]     = stdysel;
        d[148]     = phrst;
        return d;
    endfunction

    // =========================================================================
    // FIFO model: present one descriptor, drop empty, honor rd_en.
    //   Presents 'descr' with empty=0; on the cycle the DUT reads (rd_en=1),
    //   marks the FIFO empty again (single-shot).
    // =========================================================================
    task automatic push_descriptor(input logic [159:0] descr);
        tb_cb.tb_fifo_dout  <= descr;
        tb_cb.tb_fifo_empty <= 1'b0;
        // wait until the DUT asserts read enable, then drop empty
        @(tb_cb);
        while (!tb_fifo_rd_en) @(tb_cb);
        // descriptor consumed
        tb_cb.tb_fifo_empty <= 1'b1;
        @(tb_cb);
    endtask

    // Keep the FIFO continuously non-empty with a given descriptor (for
    // measuring steady-state output timing).
    task automatic hold_descriptor(input logic [159:0] descr);
        tb_cb.tb_fifo_dout  <= descr;
        tb_cb.tb_fifo_empty <= 1'b0;
    endtask

    // =========================================================================
    // Measure how many cycles after a descriptor is loaded until 'o_gain'
    // equals the expected gain (used to discover the pipeline latency).
    // =========================================================================
    task automatic measure_gain_latency(
        input  logic [159:0] descr,
        input  logic [15:0]  exp_gain,
        output int           latency,
        input  int           timeout = 64
    );
        int t = 0;
        latency = -1;
        hold_descriptor(descr);
        // wait for the read handshake to latch the descriptor
        @(tb_cb);
        while (!tb_fifo_rd_en && t < timeout) begin @(tb_cb); t++; end
        // now count cycles until gain appears
        t = 0;
        while (tb_gain !== exp_gain && t < timeout) begin
            @(tb_cb);
            t++;
        end
        if (tb_gain === exp_gain) latency = t;
    endtask

    // =========================================================================
    // SVUnit
    // =========================================================================
    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
        tb_cb.tb_rstn       <= 1'b0;
        tb_cb.tb_fifo_empty <= 1'b1;
        tb_cb.tb_fifo_dout  <= '0;
        repeat(10) @(tb_cb);
        tb_cb.tb_rstn <= 1'b1;
        repeat(5) @(tb_cb);
    endtask

    task teardown();
        svunit_ut.teardown();
        tb_cb.tb_fifo_empty <= 1'b1;
        repeat(5) @(tb_cb);
    endtask

    // Global timeout
    initial begin
        #50_000_000;
        $display("INFO: Global timeout reached");
        $finish;
    end

    `SVUNIT_TESTS_BEGIN
    `include "ctrl_sgv6_tests.sv"
    `SVUNIT_TESTS_END

endmodule
