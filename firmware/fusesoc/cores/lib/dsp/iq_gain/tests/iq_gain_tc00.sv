// ============================================================================
// File: iq_gain_unit_test.sv
// Description: SVUnit testbench top-level for iq_gain.
//   Verifies the I/Q amplification and saturation logic.
//   Includes a bit-true software reference model for multiplication and clamping.
// ============================================================================
`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module iq_gain_unit_test;
    import svunit_pkg::svunit_testcase;
    string name = "iq_gain_ut";
    svunit_testcase svunit_ut;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real CLOCK_FREQUENCY = 250e6;
    localparam int  DW = 16;
    localparam int  GW = 4;
    localparam int  LATENCY = 3; // 3 stages of registers

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    logic tb_aclk    = 1'b0;
    logic tb_aresetn = 1'b0;
    
    // Assuming that you have the clk_gen component in your library
    clk_gen #(.FREQ (CLOCK_FREQUENCY)) u_clk (.i_enable(1'b1), .o_clk(tb_aclk));

    // =========================================================================
    // DUT signals
    // =========================================================================
    logic signed [DW-1:0] tb_i_in = '0;
    logic signed [DW-1:0] tb_q_in = '0;
    logic        [GW-1:0] tb_gain  = '0;
    logic signed [DW-1:0] tb_i_out;
    logic signed [DW-1:0] tb_q_out;

    // =========================================================================
    // Clocking block
    // =========================================================================
    default clocking tb_cb @(posedge tb_aclk);
        default input #1step output #2;
        output tb_aresetn;
        output tb_i_in;
        output tb_q_in;
        output tb_gain;
        input  tb_i_out;
        input  tb_q_out;
    endclocking

    // =========================================================================
    // DUT
    // =========================================================================
    iq_gain #(
        .DW (DW),
        .GW (GW)
    ) dut (
        .aclk    (tb_aclk),
        .aresetn (tb_aresetn),
        .i_in    (tb_i_in),
        .q_in    (tb_q_in),
        .gain    (tb_gain),
        .i_out   (tb_i_out),
        .q_out   (tb_q_out)
    );

    // =========================================================================
    // Dump
    // =========================================================================
    initial begin
        $dumpfile("iq_gain.vcd");
        $dumpvars(0, dut);
    end

    // =========================================================================
    // Golden Model
    // =========================================================================
    typedef struct {
        logic signed [DW-1:0] i;
        logic signed [DW-1:0] q;
    } iq_t;

    function automatic iq_t golden_model(
        input logic signed [DW-1:0] i_in,
        input logic signed [DW-1:0] q_in,
        input logic        [GW-1:0] gain
    );
        // Model the internal multiplication width
        logic signed [DW+GW-1:0] i_mult;
        logic signed [DW+GW-1:0] q_mult;
        iq_t out;

        // Multiply by treating gain as positive signed
        i_mult = i_in * $signed({1'b0, gain});
        q_mult = q_in * $signed({1'b0, gain});

        // Saturation logic
        out.i = (i_mult > 32767) ? 32767 : ((i_mult < -32768) ? -32768 : i_mult[DW-1:0]);
        out.q = (q_mult > 32767) ? 32767 : ((q_mult < -32768) ? -32768 : q_mult[DW-1:0]);

        return out;
    endfunction

    // =========================================================================
    // Helpers
    // =========================================================================
    task automatic reset_dut();
        tb_cb.tb_aresetn <= 1'b0;
        tb_cb.tb_i_in    <= '0;
        tb_cb.tb_q_in    <= '0;
        tb_cb.tb_gain    <= '0;
        repeat(5) @(tb_cb);
        tb_cb.tb_aresetn <= 1'b1;
        repeat(2) @(tb_cb);
    endtask

    task automatic test_stream(input int count);
        iq_t expected_q[$];

        fork
            // Driver thread
            begin
                for (int n = 0; n < count; n++) begin
                    logic signed [DW-1:0] rnd_i = $urandom;
                    logic signed [DW-1:0] rnd_q = $urandom;
                    logic        [GW-1:0] rnd_g = $urandom;

                    tb_cb.tb_i_in  <= rnd_i;
                    tb_cb.tb_q_in  <= rnd_q;
                    tb_cb.tb_gain  <= rnd_g;

                    expected_q.push_back(golden_model(rnd_i, rnd_q, rnd_g));
                    @(tb_cb);
                end
                tb_cb.tb_i_in  <= '0;
                tb_cb.tb_q_in  <= '0;
                tb_cb.tb_gain  <= '0;
            end

            // Monitor thread
            begin
                // Wait LATENCY cycles (DUT) + 1 extra cycle (Clocking Block)
                repeat(LATENCY + 1) @(tb_cb); 
                
                for (int n = 0; n < count; n++) begin
                    iq_t exp = expected_q.pop_front();
                    // Add a small delay to ensure the sample is stable
                    if (tb_cb.tb_i_out !== exp.i || tb_cb.tb_q_out !== exp.q) begin
                        $display("STREAM MISMATCH n=%0d: exp(%0d,%0d) got(%0d,%0d)",
                                n, exp.i, exp.q, signed'(tb_cb.tb_i_out), signed'(tb_cb.tb_q_out));
                        `FAIL_IF(1);
                    end
                    @(tb_cb);
                end
            end
        join
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
    endtask

    `SVUNIT_TESTS_BEGIN
    `include "iq_gain_tests.sv"
    `SVUNIT_TESTS_END

endmodule