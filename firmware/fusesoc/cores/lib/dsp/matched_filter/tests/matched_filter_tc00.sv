// ============================================================================
// File: matched_filter_tc00.sv
// Description: SVUnit testbench for matched_filter (single clock domain:
//              write_clk == clk, to keep the CDC aspect out of scope --
//              axis_to_bram_sg's own CDC is already covered elsewhere).
// ============================================================================

`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module matched_filter_unit_test;

    import svunit_pkg::svunit_testcase;

    string name = "matched_filter_ut";
    svunit_testcase svunit_ut;

    localparam real CLOCK_FREQ = 200e6;
    localparam int  N = 6;
    localparam int  B = 16;

    logic tb_clk  = 1'b0;
    logic tb_rstn = 1'b1;

    clk_gen #(.FREQ (CLOCK_FREQ)) u_clk_gen (.i_enable(1'b1), .o_clk(tb_clk));

    axi4_stream_if #(.TDATA_WIDTH(2*B)) wgt_if (.aclk(tb_clk), .aresetn(tb_rstn));

    logic            tb_trigger_i;
    logic            tb_trigger_o;
    logic            tb_din_valid_i;
    logic [2*B-1:0]  tb_din_i;
    logic [2*B-1:0]  tb_dout_o;
    logic            tb_dout_valid_o;
    logic [31:0]     tb_len_reg;
    logic [31:0]     tb_dw_addr_reg;
    logic            tb_we_reg;

    default clocking cb @(posedge tb_clk);
        default input #1step output #2;
        output tb_rstn;
        output tb_trigger_i;
        output tb_din_valid_i;
        output tb_din_i;
        output tb_len_reg;
        output tb_dw_addr_reg;
        output tb_we_reg;
        input  tb_trigger_o;
        input  tb_dout_o;
        input  tb_dout_valid_o;
    endclocking

    matched_filter #(
        .N (N),
        .B (B)
    ) dut (
        .clk            (tb_clk),
        .rstn           (tb_rstn),
        .write_rstn     (tb_rstn),
        .write_clk      (tb_clk),
        .trigger_i      (tb_trigger_i),
        .trigger_o      (tb_trigger_o),
        .s_axis_tready  (wgt_if.tready),
        .s_axis_tdata   (wgt_if.tdata),
        .s_axis_tvalid  (wgt_if.tvalid),
        .din_valid_i    (tb_din_valid_i),
        .din_i          (tb_din_i),
        .dout_o         (tb_dout_o),
        .dout_valid_o   (tb_dout_valid_o),
        .len_reg        (tb_len_reg),
        .dw_addr_reg    (tb_dw_addr_reg),
        .we_reg         (tb_we_reg)
    );

    // =========================================================================
    // Helper tasks
    // =========================================================================

    task automatic pulse_trigger();
        cb.tb_trigger_i <= 1'b1;
        @(cb);
        cb.tb_trigger_i <= 1'b0;
    endtask

    // Wait for dout_valid_o and return dout_o.
    //
    // NOTE: dout_valid_o (from the dout_valid_reg/TOTAL_LATENCY chain,
    // tracking raw din_valid_i) asserts ONE CYCLE BEFORE dout_o settles to
    // its final value (dout_o comes from filt_ii_quant_r/filt_qq_quant_r,
    // an extra register on top of the DSP's registered output that the
    // legacy VHDL's TOTAL_LATENCY constant does not account for).
    // Confirmed empirically in simulation (dut.ac/bd/ad/bc were already
    // correct the cycle dout_valid_o first pulsed, but dout_o itself
    // caught up only one cycle later) -- this is a property of the ported
    // legacy design, reproduced faithfully rather than "fixed"; see
    // matched_filter.sv's header comment.
    task automatic wait_for_output(output logic [2*B-1:0] data, input int timeout_cycles = 50);
        int timeout = 0;
        while (!cb.tb_dout_valid_o) begin
            @(cb);
            timeout++;
            if (timeout > timeout_cycles) begin
                `FAIL_IF_LOG(1, "wait_for_output: timed out waiting for dout_valid_o");
                return;
            end
        end
        @(cb);
        data = cb.tb_dout_o;
    endtask

    // =========================================================================
    // SVUnit build / setup / teardown
    // =========================================================================
    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();

        cb.tb_trigger_i   <= 1'b0;
        cb.tb_din_valid_i <= 1'b0;
        cb.tb_din_i       <= '0;
        cb.tb_len_reg     <= 32'd10;
        cb.tb_dw_addr_reg <= '0;
        cb.tb_we_reg      <= 1'b0;
        wgt_if.tready <= 1'b1;

        cb.tb_rstn <= 1'b0;
        repeat(4) @(cb);
        cb.tb_rstn <= 1'b1;
        repeat(4) @(cb);
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    `SVUNIT_TESTS_BEGIN
    `include "matched_filter_tests.sv"
    `SVUNIT_TESTS_END

endmodule
