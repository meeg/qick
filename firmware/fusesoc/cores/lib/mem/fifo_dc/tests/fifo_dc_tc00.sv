// ============================================================================
// File: fifo_dc_tc00.sv
// Description: SVUnit testbench top-level for fifo_dc. Treated as a black
//   box across the write/read clock domains: pipeline latency through the
//   gray-pointer CDC + BRAM read register is not pinned down by hand, tests
//   instead poll the empty/full flags and search for the expected data
//   sequence as a contiguous, in-order run inside a generously long capture
//   trace (latency-agnostic, still checks strict FIFO ordering/values).
// ============================================================================
`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module fifo_dc_unit_test;
   import svunit_pkg::svunit_testcase;

   localparam int  FIFO_DW = 16;
   localparam int  FIFO_AW = 4; // 16 slots, so full/empty are reachable quickly

   string name = "fifo_dc_ut";
   svunit_testcase svunit_ut;

   localparam real WR_FREQ = 300e6;
   localparam real RD_FREQ = 100e6;

   logic                  tb_wr_clk  = 1'b0;
   logic                  tb_wr_rstn = 1'b1;
   logic                  tb_wr_en   = 1'b1;
   logic                  tb_push    = 1'b0;
   logic [FIFO_DW-1:0]    tb_data_i  = '0;
   logic                  tb_flush   = 1'b0;
   logic                  tb_full;

   logic                  tb_rd_clk  = 1'b0;
   logic                  tb_rd_rstn = 1'b1;
   logic                  tb_rd_en   = 1'b1;
   logic                  tb_pop     = 1'b0;
   logic [FIFO_DW-1:0]    tb_data_o;
   logic                  tb_empty;

   clk_gen #(.FREQ (WR_FREQ)) u_clk_wr (.i_enable(1'b1), .o_clk(tb_wr_clk));
   clk_gen #(.FREQ (RD_FREQ)) u_clk_rd (.i_enable(1'b1), .o_clk(tb_rd_clk));

   default clocking wr_cb @(posedge tb_wr_clk);
      output tb_wr_rstn;
      output tb_push;
      output tb_data_i;
      output tb_flush;
      input  tb_full;
   endclocking

   clocking rd_cb @(posedge tb_rd_clk);
      output tb_rd_rstn;
      output tb_pop;
      input  tb_data_o;
      input  tb_empty;
   endclocking

   initial begin
      $dumpfile("fifo_dc.vcd");
      $dumpvars(0, dut);
   end

   fifo_dc #(
      .FIFO_DW ( FIFO_DW ),
      .FIFO_AW ( FIFO_AW )
   ) dut (
      .wr_clk_i      ( tb_wr_clk  ),
      .wr_rst_ni     ( tb_wr_rstn ),
      .wr_en_i       ( tb_wr_en   ),
      .push_i        ( tb_push    ),
      .data_i        ( tb_data_i  ),
      .rd_clk_i      ( tb_rd_clk  ),
      .rd_rst_ni     ( tb_rd_rstn ),
      .rd_en_i       ( tb_rd_en   ),
      .pop_i         ( tb_pop     ),
      .data_o        ( tb_data_o  ),
      .flush_i       ( tb_flush   ),
      .async_empty_o ( tb_empty   ),
      .async_full_o  ( tb_full    )
   );

   // Push n consecutive values starting at base (one per wr_clk cycle);
   // relies on the FIFO not being full across the run (caller's job).
   task automatic push_seq(int base, int n);
      int k;
      for (k = 0; k < n; k++) begin
         wr_cb.tb_push   <= 1'b1;
         wr_cb.tb_data_i <= (base + k);
         @(wr_cb);
      end
      wr_cb.tb_push <= 1'b0;
      @(wr_cb);
   endtask

   // Hold pop_i for `cycles` rd_clk cycles, recording data_o every cycle.
   task automatic capture_trace(int cycles, output int trace[]);
      int k;
      trace = new[cycles];
      rd_cb.tb_pop <= 1'b1;
      for (k = 0; k < cycles; k++) begin
         @(rd_cb);
         trace[k] = rd_cb.tb_data_o;
      end
      rd_cb.tb_pop <= 1'b0;
      @(rd_cb);
   endtask

   // True if trace[] contains, somewhere, the exact contiguous run
   // base, base+1, ..., base+n-1 in that order.
   function automatic bit trace_contains_seq(int trace[], int base, int n);
      int start, k;
      for (start = 0; start <= trace.size() - n; start++) begin
         bit match_ok = 1'b1;
         for (k = 0; k < n; k++)
            if (trace[start+k] != base + k) match_ok = 1'b0;
         if (match_ok) return 1'b1;
      end
      return 1'b0;
   endfunction

   task automatic wait_empty(output bit timed_out);
      int cyc;
      timed_out = 1'b0;
      cyc = 0;
      while (rd_cb.tb_empty !== 1'b1) begin
         @(rd_cb);
         cyc++;
         if (cyc > 300) begin
            timed_out = 1'b1;
            return;
         end
      end
   endtask

   // Push continuously (incrementing data) until async_full_o asserts or
   // max_cycles is exceeded.
   task automatic fill_until_full(int max_cycles, output bit timed_out);
      int k;
      timed_out = 1'b1;
      wr_cb.tb_push <= 1'b1;
      for (k = 0; k < max_cycles; k++) begin
         wr_cb.tb_data_i <= k;
         @(wr_cb);
         if (wr_cb.tb_full === 1'b1) begin
            timed_out = 1'b0;
            break;
         end
      end
      wr_cb.tb_push <= 1'b0;
      @(wr_cb);
   endtask

   task automatic wait_full(output bit timed_out);
      int cyc;
      timed_out = 1'b0;
      cyc = 0;
      while (wr_cb.tb_full !== 1'b1) begin
         @(wr_cb);
         cyc++;
         if (cyc > 300) begin
            timed_out = 1'b1;
            return;
         end
      end
   endtask

   function void build();
      svunit_ut = new(name);
   endfunction

   task setup();
      svunit_ut.setup();
      wr_cb.tb_push  <= 1'b0;
      wr_cb.tb_data_i <= '0;
      wr_cb.tb_flush <= 1'b0;
      rd_cb.tb_pop   <= 1'b0;

      @(wr_cb);
      wr_cb.tb_wr_rstn <= 1'b0;
      rd_cb.tb_rd_rstn <= 1'b0;
      repeat(5) @(wr_cb);
      wr_cb.tb_wr_rstn <= 1'b1;
      rd_cb.tb_rd_rstn <= 1'b1;
      repeat(5) @(wr_cb);
   endtask

   task teardown();
      svunit_ut.teardown();
   endtask

   `SVUNIT_TESTS_BEGIN
   `include "fifo_dc_tests.sv"
   `SVUNIT_TESTS_END

endmodule
