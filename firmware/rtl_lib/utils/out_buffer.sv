///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
//
// Fermi National Accelerator Laboratory
//
// Module: out_buffer.sv
// Project: UTILS
// Description: Common buffer interface for AXI4 signals
//
// Change history: 01/22/26 - Created by @lharnaldi
//
//
///////////////////////////////////////////////////////////////////////////////
module out_buffer#(
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
  logic valid_reg, valid_next;
  logic ready_s;

  assign ready_s = ~valid_reg | o_ready;

  always_ff @ (posedge i_clk) begin
    if(!i_rstn) begin
      valid_reg <= 1'b0;
      data_reg  <= {(DWIDTH){1'b0}};
    end else begin
      valid_reg <= valid_next;
      data_reg  <= data_next;
    end
  end

  //next state logic
  assign valid_next = (ready_s) ? i_valid : valid_reg;
  assign data_next  = (ready_s) ? i_data  : data_reg;

  //output logic
  assign i_ready = ready_s;
  assign o_data  = data_reg;
  assign o_valid = valid_reg;

endmodule
