`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module axil_ram_wr_unit_test;
    import svunit_pkg::svunit_testcase;

    string name = "axil_ram_wr_ut";
    svunit_testcase svunit_ut;

    localparam integer unsigned CLOCK_FREQUENCY = 250e6; //[Hz]
 
    localparam integer unsigned AXI_DWIDTH  = 32;
    localparam integer unsigned AXI_AWIDTH  = 16;
    localparam integer unsigned BRAM_DWIDTH = 32;
    localparam integer unsigned BRAM_AWIDTH = 10;

    logic tb_clk = 1'b0 ;
    logic tb_rst = 1'b0 ;

initial begin
  $dumpfile("axil_ram_wr.vcd");
  $dumpvars();
end

    axi4_lite_if#(
        .DATA_WIDTH  (AXI_DWIDTH),
        .ADDR_WIDTH  (AXI_AWIDTH)
    )axi4_lite_in_if(
        .aclk          (tb_clk),
        .aresetn       (tb_rst)
    );

    bram_if#(
        .NB_DATA  (BRAM_DWIDTH),
        .NB_ADDR  (BRAM_AWIDTH)
    )bram_out_if(
        .i_clk          (tb_clk),
        .i_rst          (tb_rst)
    );

    clk_gen#(
        .FREQ       ( CLOCK_FREQUENCY   )
    )u_clk_gen(
        .i_enable   ( 1'b1              ),
        .o_clk      ( tb_clk            )
    );
    
    default clocking cb @(posedge tb_clk);
    endclocking

    //===================================
    // This is the UUT that we're 
    // running the Unit Tests on
    //===================================

    axil_ram_wr#(
        .AXI_DWIDTH         ( AXI_DWIDTH            ),
        .AXI_AWIDTH         ( AXI_AWIDTH            )
    )u_axil_ram_wr(
        .i_clk              ( tb_clk                ),
        .i_rst              ( tb_rst                ),
        .i_axil             ( axi4_lite_in_if       ),
        .o_bram_if          ( bram_out_if           )
    );

    //===================================
    // Build
    //===================================
    function void build();
        svunit_ut = new(name);
    endfunction

    //===================================
    // Setup for running the Unit Tests
    //===================================
    task setup();
        repeat(10) @(negedge tb_clk);
        svunit_ut.setup();

        axi4_lite_in_if.awvalid = 1'b0;
        axi4_lite_in_if.awaddr  = '0;
        axi4_lite_in_if.awprot  = 3'b000;

        axi4_lite_in_if.wvalid  = 1'b0;
        axi4_lite_in_if.wdata   = '0;
        axi4_lite_in_if.wstrb   = '0;

        axi4_lite_in_if.bready  = 1'b0;

        axi4_lite_in_if.arvalid = 1'b0;
        axi4_lite_in_if.araddr  = '0;
        axi4_lite_in_if.arprot  = 3'b000;

        axi4_lite_in_if.rready  = 1'b0;

        tb_rst = 1'b1;
        @(negedge tb_clk);
        tb_rst = 1'b0;
        repeat(10) @(negedge tb_clk);
    endtask

    //===================================
    // Here we deconstruct anything we 
    // need after running the Unit Tests
    //===================================
    task teardown();
        svunit_ut.teardown();
    endtask

    //===================================
    // All tests are defined between the
    // SVUNIT_TESTS_BEGIN/END macros
    //
    // Each individual test must be
    // defined between `SVTEST(_NAME_)
    // `SVTEST_END
    //
    // i.e.
    //   `SVTEST(mytest)
    //     <test code>
    //   `SVTEST_END
    //===================================

    `SVUNIT_TESTS_BEGIN
        `include "tests.sv"
    `SVUNIT_TESTS_END

endmodule
