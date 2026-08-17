`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module axi4_stream_fifo_unit_test;
    import svunit_pkg::svunit_testcase;

    string name = "axi4_stream_fifo_ut";
    svunit_testcase svunit_ut;

    localparam CLOCK_FREQUENCY = 100e6; //[Hz]

    localparam NB_DATA      = 32;
    localparam FIFO_DEPTH   = 16;

    logic tb_clk = 1'b0;
    logic tb_rst = 1'b0;

    logic [NB_DATA-1:0] data_payload = '0;
    logic [NB_DATA-1:0] data_payload_queue [$];

    axi4_stream_if
    #(
        .TDATA_WIDTH  (NB_DATA)
    ) 
    axis_in_if
    (
        .aclk          (tb_clk), 
        .aresetn       (~tb_rst)
    );

    axi4_stream_if
    #(
        .TDATA_WIDTH  (NB_DATA)
    ) 
    axis_out_if
    (
        .aclk          (tb_clk), 
        .aresetn       (~tb_rst)
    );

    clk_gen 
    #(
        .FREQ       ( CLOCK_FREQUENCY   )
    )
    u_clk_gen
    (
        .i_enable   ( 1'b1              ),
        .o_clk      ( tb_clk            )
    );

    axi4_stream_fifo 
    #(
        .DEPTH      ( FIFO_DEPTH        )
    )
    u_axi4_stream_fifo
    (
        .i_clk      ( tb_clk            ),
        .i_rst      ( tb_rst            ),
        .i_axis     ( axis_in_if        ),
        .o_axis     ( axis_out_if       )
    );

    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();

        axis_out_if.tready  = 1'b1;
        axis_in_if.tlast    = 1'b0;
        axis_in_if.tvalid   = 1'b0;
        axis_in_if.tdata    = '0;

        data_payload_queue  = {};

        tb_rst = 1'b1;
        repeat(1) @(posedge tb_clk);
        tb_rst = 1'b0;
        repeat(10) @(posedge tb_clk);
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    initial begin
        $dumpfile("axi4_stream_fifo.vcd");
        $dumpvars();
        #20ms;
        $display("INFO: Global timeout reached");
        $finish;
    end

    `SVUNIT_TESTS_BEGIN
        `include "tests.sv"
    `SVUNIT_TESTS_END

endmodule
