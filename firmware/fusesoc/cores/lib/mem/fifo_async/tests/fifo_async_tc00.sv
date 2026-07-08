// ============================================================================
// File: fifo_async_tc00.sv
// Description: SVUnit test runner wrapper module for async FIFO verification.
//              Updated parameters to pass absolute depth values to XPM.
// ============================================================================
`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module fifo_async_unit_test;
  import svunit_pkg::svunit_testcase;

  string name = "fifo_async_ut";
  svunit_testcase svunit_ut;

  // Passing the absolute depth value directly
  localparam int B = 32;     // Data Bit-Width matching template
  localparam int N = 2048;   // Absolute FIFO Depth (Passes 2048 directly to the DUT)

  // Independent asynchronous free-running clocks
  logic wr_clk = 0;
  logic rd_clk = 0;

  always #2 wr_clk = ~wr_clk; // 250 MHz Write Clock
  always #3 rd_clk = ~rd_clk; // 166.6 MHz Read Clock

  // Resets matching top-level active-low design
  logic wr_rstn = 0;
  logic rd_rstn = 0;

  // Interconnect signals mapping exactly to top-level wrapper ports
  logic         wr_en, rd_en;
  logic [B-1:0] din, dout;
  logic         full, empty;
  logic         data_valid;

  // Gold model tracking queue
  logic [B-1:0] model_q[$];


  // ============================================================
  // GTKWAVE CONFIGURATION (VCD Waveform Dump)
  // ============================================================
  initial begin
    $dumpfile("fifo_async_waveform.vcd"); // Target VCD filename
    $dumpvars(0, fifo_async_unit_test);    // Dumps all signals in this module and sub-modules
  end

  // ============================================================
  // Unit Under Test (DUT)
  // ============================================================
  // Instantiation aligned with the absolute configuration parameters
  fifo_async #(
    .B(B),
    .N(N) // This maps to DEPTH/FIFO_WRITE_DEPTH inside the wrapper
  ) dut (
    // Write Domain
    .wr_clk  (wr_clk),
    .wr_rstn (wr_rstn),
    .wr_en   (wr_en),
    .din     (din),
    .full    (full),
    
    // Read Domain
    .rd_clk  (rd_clk),
    .rd_rstn (rd_rstn),
    .rd_en   (rd_en),
    .dout    (dout),
    .empty   (empty),
    .data_valid(data_valid)
  );

  // Structural assertion safeguards for tracking testbench behavior
  // El overflow real sería: escribir efectivamente cuando ya estaba lleno el ciclo previo
  property p_no_overflow;
    @(posedge wr_clk) disable iff (!wr_rstn)
      (full && $past(full)) |-> !wr_en;
  endproperty
  assert property(p_no_overflow);
  
  property p_no_underflow;
    @(posedge rd_clk) disable iff (!rd_rstn)
      (empty && $past(empty)) |-> !rd_en;
  endproperty
  assert property(p_no_underflow);

  function void build();
    svunit_ut = new(name);
  endfunction

  task setup();
    svunit_ut.setup();

    wr_en = 0;
    rd_en = 0;
    din   = 0;

    // Apply active-low resets asynchronously
    wr_rstn = 0;
    rd_rstn = 0;
    repeat(10) @(posedge wr_clk);
    wr_rstn = 1;
    repeat(10) @(posedge rd_clk);
    rd_rstn = 1;

    // Give XPM cross-domain synchronizers enough clock cycles to stabilize
    repeat(40) @(posedge rd_clk);
  endtask

  task teardown();
    svunit_ut.teardown();
    model_q.delete();
  endtask

  `SVUNIT_TESTS_BEGIN
  `include "tests.sv"
  `SVUNIT_TESTS_END

endmodule
