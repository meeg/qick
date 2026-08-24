// ============================================================================
// File: ctrl_ro_v2_tc00.sv
// Description: SVUnit testbench top-level for ctrl_ro_v2.
// ============================================================================
`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module ctrl_ro_v2_unit_test;
    import svunit_pkg::svunit_testcase;

    string name = "ctrl_ro_v2_ut";
    svunit_testcase svunit_ut;

    localparam real CLOCK_FREQUENCY = 200e6;
    localparam int  N_DDS = 8;

    logic tb_clk     = 1'b0;
    logic tb_aresetn = 1'b1;

    clk_gen #(.FREQ (CLOCK_FREQUENCY)) u_clk (.i_enable(1'b1), .o_clk(tb_clk));

    logic            tb_fifo_rd_en_o;
    logic            tb_fifo_empty_i;
    logic [82:0]     tb_fifo_dout_i;
    logic [N_DDS*72-1:0] tb_dds_ctrl_o;
    logic [1:0]      tb_outsel_o;

    initial begin
        $dumpfile("ctrl_ro_v2.vcd");
        $dumpvars(0, dut);
    end

    ctrl_ro_v2 #(
        .N_DDS (N_DDS)
    ) dut (
        .aresetn      (tb_aresetn),
        .aclk         (tb_clk),
        .fifo_rd_en_o (tb_fifo_rd_en_o),
        .fifo_empty_i (tb_fifo_empty_i),
        .fifo_dout_i  (tb_fifo_dout_i),
        .dds_ctrl_o   (tb_dds_ctrl_o),
        .outsel_o     (tb_outsel_o)
    );

    function automatic logic [31:0] lane_phase(int lane);
        return tb_dds_ctrl_o[lane*72+32+:32];
    endfunction
    function automatic logic [31:0] lane_pinc_n(int lane);
        return tb_dds_ctrl_o[lane*72+:32];
    endfunction

    function automatic logic [82:0] build_descr(
        input logic [31:0] freq, input logic [31:0] phase,
        input logic [15:0] nsamp, input logic [1:0] outsel,
        input logic mode
    );
        logic [82:0] d = '0;
        d[31:0]  = freq;
        d[63:32] = phase;
        d[79:64] = nsamp;
        d[81:80] = outsel;
        d[82]    = mode;
        return d;
    endfunction

    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
        tb_fifo_empty_i = 1'b1;
        tb_fifo_dout_i  = '0;
        reset_dut();
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    task automatic reset_dut();
        tb_aresetn = 1'b0;
        repeat(4) @(posedge tb_clk);
        tb_aresetn = 1'b1;
        repeat(4) @(posedge tb_clk);
    endtask

    task automatic push_descriptor(input logic [82:0] descr);
        @(negedge tb_clk);
        tb_fifo_dout_i  = descr;
        tb_fifo_empty_i = 1'b0;
        wait (tb_fifo_rd_en_o === 1'b1);
        @(posedge tb_clk);
        @(negedge tb_clk);
        tb_fifo_empty_i = 1'b1;
        repeat(15) @(posedge tb_clk);
        @(negedge tb_clk);
    endtask

    `SVUNIT_TESTS_BEGIN
    `include "ctrl_ro_v2_tests.sv"
    `SVUNIT_TESTS_END

endmodule
