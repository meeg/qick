///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
//
// Fermi National Accelerator Laboratory
//
// Module: in_buffer.sv
// Project: UTILS
// Description: Common buffer interface for AXI4 signals
//
// Change history: 01/22/26 - Created by @lharnaldi
//
//
///////////////////////////////////////////////////////////////////////////////
module in_buffer#(
  parameter integer DWIDTH = 32
)(
  input  logic              i_clk,
  input  logic              i_rstn,

  input  logic [DWIDTH-1:0] i_data,
  input  logic              i_valid,
  output logic              i_ready,

  output logic [DWIDTH-1:0] o_data,
  output logic              o_valid,
  input  logic              o_ready
);

  logic [DWIDTH-1:0] data_reg, data_next;
  logic ready_reg, ready_next;
  logic valid_s;

  assign valid_s = ~ready_reg | i_valid;

  always_ff @ (posedge i_clk) begin
    if(!i_rstn) begin
      ready_reg <= 1'b1;
      data_reg  <= {(DWIDTH){1'b0}};
    end else begin
      ready_reg <= ready_next;
      data_reg  <= data_next;
    end
  end

  //next state logic
  assign ready_next = (valid_s)   ? o_ready : ready_reg;
  assign data_next  = (ready_reg) ? i_data  : data_reg;

  //output logic
  assign i_ready = ready_reg;
  assign o_data  = ready_reg ? i_data : data_reg;
  assign o_valid = valid_s;

endmodule
