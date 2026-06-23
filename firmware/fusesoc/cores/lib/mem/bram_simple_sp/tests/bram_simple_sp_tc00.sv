`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

//------------------------------------------------------------------------------
// Component: bram_simple_sp_unit_test
// Description: Unit testbench for Simple Single-Port BRAM.
//              Verifies reset/idle states, single and multi-address cycles,
//              write-first read-through, enable gating, and binary init.
//------------------------------------------------------------------------------
module bram_simple_sp_unit_test;
    import svunit_pkg::svunit_testcase;

    string name = "bram_sp_ut";
    svunit_testcase svunit_ut;

    //--------------------------------------------------------------------------
    // Testbench Parameters
    //--------------------------------------------------------------------------
    localparam CLOCK_FREQUENCY = 100e6; // 100 MHz clock source
    localparam int unsigned NB_DATA    = 32;
    localparam int unsigned NB_ADDR    = 4;
    localparam string MEM_BIN_FILE     = "bin_memory_file.mem";
    localparam int unsigned DEPTH      = 2**NB_ADDR;

    //--------------------------------------------------------------------------
    // Interface & Testbench Signals
    //--------------------------------------------------------------------------
    logic                  tb_clk   = 1'b0;
    logic                  tb_ena   = 1'b0;
    logic                  tb_wea   = 1'b0;
    logic [NB_ADDR-1 : 0]  tb_addra = '0;
    logic [NB_DATA-1 : 0]  tb_dia   = '0;
    logic [NB_DATA-1 : 0]  tb_doa;

    //--------------------------------------------------------------------------
    // VCD Waveform Generation
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("bram_simple_sp.vcd");
        $dumpvars();
    end

    //--------------------------------------------------------------------------
    // Clock Generator Instance
    //--------------------------------------------------------------------------
    clk_gen #(
        .FREQ (CLOCK_FREQUENCY)
    ) u_clk_gen (
        .i_enable (1'b1),
        .o_clk    (tb_clk)
    );

    //--------------------------------------------------------------------------
    // Default Clocking Block (Synchronous Stimulus Driving & Sampling)
    //--------------------------------------------------------------------------
    default clocking cb @(posedge tb_clk);
        default input #1step output #2;
        output tb_ena;
        output tb_wea;
        output tb_addra;
        output tb_dia;
        input  tb_doa;
    endclocking

    //--------------------------------------------------------------------------
    // Unit Under Test (UUT)
    //--------------------------------------------------------------------------
    bram_simple_sp #(
        .NB_DATA      (NB_DATA),
        .NB_ADDR      (NB_ADDR),
        .MEM_BIN_FILE (MEM_BIN_FILE)
    ) u_bram (
        .i_clk   (tb_clk),
        .i_ena   (tb_ena),
        .i_wea   (tb_wea),
        .i_addra (tb_addra),
        .i_dia   (tb_dia),
        .o_doa   (tb_doa)
    );

    //--------------------------------------------------------------------------
    // Concurrent Assertions
    //--------------------------------------------------------------------------

    // Write stability: When writing or when wea=0, untouched memory addresses must remain stable
  property wr_stable;
    @(posedge tb_clk)
    (!u_bram.i_wea) |=> 
    (u_bram.ram == $past(u_bram.ram));  // ninguna posición cambió
endproperty

    // Read stability: When clock enable is low, output data port must hold its value
    property rd_stable;
        @(cb) !u_bram.i_ena |=> $stable(u_bram.o_doa);
    endproperty 
    `ASSERT_CONCURRENT(rd_stable);

    // Write-first (read-through) behavior: Output data follows input data on write cycles
    property write_through;
        @(cb) (u_bram.i_ena && u_bram.i_wea) |=> (u_bram.o_doa == $past(u_bram.i_dia));
    endproperty 
    `ASSERT_CONCURRENT(write_through);

    //--------------------------------------------------------------------------
    // SVUnit Infrastructure (Build, Setup, Teardown)
    //--------------------------------------------------------------------------
    function void build();
        svunit_ut = new(name);
    endfunction

   task setup();
    svunit_ut.setup();
    init_memory(32'h0);    
    cb.tb_ena   <= 1'b0;
    cb.tb_wea   <= 1'b0;
    cb.tb_addra <= '0;
    cb.tb_dia   <= '0;
    repeat(5) @(cb);
endtask 

    task teardown();
        svunit_ut.teardown();
    endtask

    //--------------------------------------------------------------------------
    // Helper Tasks
    //--------------------------------------------------------------------------
    task init_memory(input logic [NB_DATA-1:0] value);
        for (int i = 0; i < DEPTH; i++) begin
            cb.tb_ena   <= 1'b1;
            cb.tb_wea   <= 1'b1;
            cb.tb_addra <= i[NB_ADDR-1:0];
            cb.tb_dia   <= value;
            @(cb);
        end
        cb.tb_ena <= 1'b0;
        cb.tb_wea <= 1'b0;
        @(cb);
    endtask

    //--------------------------------------------------------------------------
    // Test Cases Block Insertion
    //--------------------------------------------------------------------------
    `SVUNIT_TESTS_BEGIN
        `include "tests.sv"
    `SVUNIT_TESTS_END 

endmodule