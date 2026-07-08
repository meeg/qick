`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module bram_dp_unit_test;
import svunit_pkg::svunit_testcase;

  string name = "bram_dp_ut";
  svunit_testcase svunit_ut;

  localparam CLOCK_FREQUENCY = 250e6; //[Hz]
  localparam int N = 8;   // address width (256 entries)
  localparam int B = 16;  // data width

  logic          tb_clk = 1'b0;

  // Port A
  logic          ena, wea;
  logic [N-1:0]  addra;
  logic [B-1:0]  dia, doa;
  // Port B
  logic          enb, web;
  logic [N-1:0]  addrb;
  logic [B-1:0]  dib, dob;

initial begin
  $dumpfile("bram_dp.vcd");
  $dumpvars();
end

clk_gen #(
  .FREQ     ( CLOCK_FREQUENCY )
) u_clk_gen (
  .i_enable ( 1'b1   ),
  .o_clk    ( tb_clk )
);

default clocking cb @(posedge tb_clk);
  default input #1step output #2;
endclocking

//===================================
// UUT — both ports share tb_clk here (single clock domain test)
//===================================
bram_dp #(
  .N (N),
  .B (B)
) u_bram_dp (
  .clka  (tb_clk), .clkb  (tb_clk),
  .ena   (ena),    .enb   (enb),
  .wea   (wea),    .web   (web),
  .addra (addra),  .addrb (addrb),
  .dia   (dia),    .dib   (dib),
  .doa   (doa),    .dob   (dob)
);

function void build();
  svunit_ut = new(name);
endfunction

task setup();
  svunit_ut.setup();
  ena = 1'b0; wea = 1'b0; addra = '0; dia = '0;
  enb = 1'b0; web = 1'b0; addrb = '0; dib = '0;
  repeat(4) @(posedge tb_clk);
endtask

task teardown();
  svunit_ut.teardown();
endtask

`SVUNIT_TESTS_BEGIN
`include "tests.sv"
`SVUNIT_TESTS_END

endmodule