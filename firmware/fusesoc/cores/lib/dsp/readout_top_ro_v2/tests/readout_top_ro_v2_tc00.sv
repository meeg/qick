// ============================================================================
// File: readout_top_ro_v2_tc00.sv
// Description: SVUnit testbench top-level for readout_top_ro_v2.
// ============================================================================
`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module readout_top_ro_v2_unit_test;
    import svunit_pkg::svunit_testcase;

    string name = "readout_top_ro_v2_ut";
    svunit_testcase svunit_ut;

    localparam real CLOCK_FREQUENCY = 200e6;

    logic tb_clk  = 1'b0;
    logic tb_rstn = 1'b1;

    clk_gen #(.FREQ (CLOCK_FREQUENCY)) u_clk (.i_enable(1'b1), .o_clk(tb_clk));

    // TODO: declare DUT signals

    initial begin
        $dumpfile("readout_top_ro_v2.vcd");
        $dumpvars(0, dut);
    end

    // TODO: instantiate the DUT
    // readout_top_ro_v2 dut ( ... );

    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    `SVUNIT_TESTS_BEGIN
    `include "readout_top_ro_v2_tests.sv"
    `SVUNIT_TESTS_END

endmodule
