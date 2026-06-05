`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module bram_tdp_unit_test;
  import svunit_pkg::svunit_testcase;

  string name = "bram_tdp_ut";
  svunit_testcase svunit_ut;

  localparam CLOCK_FREQUENCY = 250e6; //[Hz]

  // Parameters of our BRAM
  localparam int unsigned NB_DATA = 32;
  localparam int unsigned NB_ADDR = 10;

  logic tb_clk  = 1'b0;
  logic tb_rstn = 1'b1;

  // Auxiliary variable to capture read data
  logic [NB_DATA-1:0] read_val;

  initial begin
    $dumpfile("bram_tdp.vcd");
    $dumpvars();
  end

  // Clock generator
  clk_gen #(
    .FREQ      ( CLOCK_FREQUENCY   )
  ) u_clk_gen (
    .i_enable  ( 1'b1              ),
    .o_clk     ( tb_clk            )
  );

  default clocking cb @(posedge tb_clk);
  endclocking

  //===================================
  // Instantiate interfaces
  //===================================
  bram_if #(
    .NB_DATA(NB_DATA),
    .NB_ADDR(NB_ADDR)
  ) port_a_if (
    .i_clk ( tb_clk  ),
    .i_rst ( ~tb_rstn ) // Asume active-high reset in the interface
  );

  bram_if #(
    .NB_DATA(NB_DATA),
    .NB_ADDR(NB_ADDR)
  ) port_b_if (
    .i_clk ( tb_clk  ),
    .i_rst ( ~tb_rstn )
  );

  //===================================
  // UUT: True Dual-Port BRAM
  //===================================
  bram_tdp #(
    .NB_DATA(NB_DATA),
    .NB_ADDR(NB_ADDR)
  ) u_bram_tdp (
    .port_a ( port_a_if.slave ),
    .port_b ( port_b_if.slave )
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
    svunit_ut.setup();
    
    // Init signals to avoid "X"
    port_a_if.en   <= 1'b0;
    port_a_if.we   <= '0;
    port_a_if.addr <= '0;
    port_a_if.din  <= '0;

    port_b_if.en   <= 1'b0;
    port_b_if.we   <= '0;
    port_b_if.addr <= '0;
    port_b_if.din  <= '0;
  
    @(cb);
    tb_rstn <= 1'b0;
    repeat(2) @(cb);
    tb_rstn <= 1'b1;
    repeat(5) @(cb);
  endtask

  //===================================
  // Teardown
  //===================================
  task teardown();
    svunit_ut.teardown();
  endtask

  //===================================
  // SVUNIT Tests
  //===================================
  `SVUNIT_TESTS_BEGIN
    `include "tests.sv"
  `SVUNIT_TESTS_END 

endmodule