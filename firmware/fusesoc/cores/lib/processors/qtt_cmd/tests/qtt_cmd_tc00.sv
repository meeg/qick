// ============================================================================
// File: qtt_cmd_tc00.sv
// Description: SVUnit testbench top-level for qtt_cmd. Two clock domains
//   (clk_i = ADC/AXI, c_clk_i = tProc); no XPM primitive is instantiated
//   directly by this DUT's dependency chain (cdc_handshake/cdc_reg_sync/
//   sync_pulse->gcc are all hand-rolled), so the usual clocking-block style
//   is safe here.
// ============================================================================
`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module qtt_cmd_unit_test;
   import svunit_pkg::svunit_testcase;

   // Command opcodes, matching qtt_cmd.sv's decode table.
   localparam logic [4:0] OP_DISARM   = 5'b00000;
   localparam logic [4:0] OP_ARM      = 5'b00001;
   localparam logic [4:0] OP_POP      = 5'b00010;
   localparam logic [4:0] OP_PEEK     = 5'b00011;
   localparam logic [4:0] OP_SET_TH   = 5'b00100;
   localparam logic [4:0] OP_SET_INH  = 5'b00101;
   localparam logic [4:0] OP_RESET    = 5'b00111;

   string name = "qtt_cmd_ut";
   svunit_testcase svunit_ut;

   localparam real CLK_FREQ   = 300e6; // ADC/AXI domain
   localparam real C_CLK_FREQ = 150e6; // tProc domain

   logic        tb_clk    = 1'b0;
   logic        tb_rstn   = 1'b1;
   logic        tb_c_clk  = 1'b0;
   logic        tb_c_rstn = 1'b1;

   logic        tb_ext_arm = 1'b0;
   logic        tb_c_en    = 1'b0;
   logic [4:0]  tb_c_op    = '0;
   logic [31:0] tb_c_dt    = '0;
   logic        tb_p_en    = 1'b0;
   logic [4:0]  tb_p_op    = '0;
   logic [31:0] tb_p_dt    = '0;

   logic        tb_pop_req;
   logic        tb_rst_req;
   logic        tb_rst_ack = 1'b0;
   logic        tb_peek;
   logic        tb_arm;
   logic [15:0] tb_cmp_th;
   logic [7:0]  tb_cmp_inh;
   logic [7:0]  tb_cmd_cnt;

   clk_gen #(.FREQ (CLK_FREQ))   u_clk   (.i_enable(1'b1), .o_clk(tb_clk));
   clk_gen #(.FREQ (C_CLK_FREQ)) u_c_clk (.i_enable(1'b1), .o_clk(tb_c_clk));

   default clocking cb @(posedge tb_clk);
      output tb_rstn, tb_ext_arm, tb_p_en, tb_p_op, tb_p_dt, tb_rst_ack;
      input  tb_pop_req, tb_rst_req, tb_arm, tb_cmp_th, tb_cmp_inh, tb_cmd_cnt;
   endclocking

   clocking c_cb @(posedge tb_c_clk);
      output tb_c_rstn, tb_c_en, tb_c_op, tb_c_dt;
      input  tb_peek;
   endclocking

   initial begin
      $dumpfile("qtt_cmd.vcd");
      $dumpvars(0, dut);
   end

   qtt_cmd dut (
      .clk_i          ( tb_clk      ),
      .rst_ni         ( tb_rstn     ),
      .c_clk_i        ( tb_c_clk    ),
      .c_rst_ni       ( tb_c_rstn   ),
      .ext_arm_i      ( tb_ext_arm  ),
      .c_en_i         ( tb_c_en     ),
      .c_op_i         ( tb_c_op     ),
      .c_dt_i         ( tb_c_dt     ),
      .p_en_i         ( tb_p_en     ),
      .p_op_i         ( tb_p_op     ),
      .p_dt_i         ( tb_p_dt     ),
      .pop_req_o      ( tb_pop_req  ),
      .rst_req_o      ( tb_rst_req  ),
      .rst_ack_i      ( tb_rst_ack  ),
      .peek_o         ( tb_peek     ),
      .qtt_arm_o      ( tb_arm      ),
      .qtt_cmp_th_o   ( tb_cmp_th   ),
      .qtt_cmp_inh_o  ( tb_cmp_inh  ),
      .cmd_cnt_do     ( tb_cmd_cnt  )
   );

   // Pulse a Python/AXI-side command for a couple of clk_i cycles.
   task automatic send_p_cmd(logic [4:0] op, logic [31:0] dt);
      cb.tb_p_op <= op;
      cb.tb_p_dt <= dt;
      cb.tb_p_en <= 1'b1;
      repeat(2) @(cb);
      cb.tb_p_en <= 1'b0;
      @(cb);
   endtask

   // Pulse a tProc-side command for one c_clk_i cycle.
   task automatic send_c_cmd(logic [4:0] op, logic [31:0] dt);
      c_cb.tb_c_op <= op;
      c_cb.tb_c_dt <= dt;
      c_cb.tb_c_en <= 1'b1;
      @(c_cb);
      c_cb.tb_c_en <= 1'b0;
      @(c_cb);
   endtask

   task automatic wait_arm_eq(bit expected, output bit timed_out);
      int cyc;
      timed_out = 1'b0;
      cyc = 0;
      while (cb.tb_arm !== expected) begin
         @(cb);
         cyc++;
         if (cyc > 200) begin
            timed_out = 1'b1;
            return;
         end
      end
   endtask

   task automatic wait_pop_req(output bit timed_out);
      int cyc;
      timed_out = 1'b0;
      cyc = 0;
      while (cb.tb_pop_req !== 1'b1) begin
         @(cb);
         cyc++;
         if (cyc > 200) begin
            timed_out = 1'b1;
            return;
         end
      end
   endtask

   task automatic wait_peek(output bit timed_out);
      int cyc;
      timed_out = 1'b0;
      cyc = 0;
      while (c_cb.tb_peek !== 1'b1) begin
         @(c_cb);
         cyc++;
         if (cyc > 200) begin
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
      cb.tb_ext_arm  <= 1'b0;
      cb.tb_p_en     <= 1'b0;
      cb.tb_p_op     <= '0;
      cb.tb_p_dt     <= '0;
      cb.tb_rst_ack  <= 1'b0;
      c_cb.tb_c_en   <= 1'b0;
      c_cb.tb_c_op   <= '0;
      c_cb.tb_c_dt   <= '0;

      @(cb);
      cb.tb_rstn     <= 1'b0;
      c_cb.tb_c_rstn <= 1'b0;
      repeat(5) @(cb);
      cb.tb_rstn     <= 1'b1;
      c_cb.tb_c_rstn <= 1'b1;
      // Settle margin expressed on EACH domain's own clock - 5 cycles of
      // the faster clk_i is not necessarily even one c_clk_i edge.
      repeat(5) @(cb);
      repeat(5) @(c_cb);
   endtask

   task teardown();
      svunit_ut.teardown();
   endtask

   `SVUNIT_TESTS_BEGIN
   `include "qtt_cmd_tests.sv"
   `SVUNIT_TESTS_END

endmodule
