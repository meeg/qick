///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
// axis_pid.sv
//
// Fermi National Accelerator Laboratory
//
// Module: axis_pipe.sv
// Project: QICK
// Description: 
// AXI-Stream pipeline stage
//
//
// Change history: 01/27/26 - Created by @lharnaldi
//
///////////////////////////////////////////////////////////////////////////////
module axis_pipe #(
  parameter int W = 32
)(
  input  logic         clk,
  input  logic         rstn,

  input  logic [W-1:0] in_data,
  input  logic         in_valid,
  output logic         in_ready,

  output logic [W-1:0] out_data,
  output logic         out_valid,
  input  logic         out_ready
);

  // Internal storage
  logic [W-1:0] data_r;
  logic         full;

  // ===============================
  // READY logic
  // ===============================
  // Can accept if buffer empty
  // or downstream will consume this cycle
  assign in_ready = !full || (out_ready);

  // ===============================
  // Sequential storage
  // ===============================
  always_ff @(posedge clk) begin
    if (!rstn) begin
      full <= 1'b0;
    end else begin
      case ({in_valid && in_ready, out_ready && full})
        2'b10: begin
          // push only
          data_r <= in_data;
          full   <= 1'b1;
        end
        2'b01: begin
          // pop only
          full <= 1'b0;
        end
        2'b11: begin
          // push + pop (replace)
          data_r <= in_data;
          full   <= 1'b1;
        end
        default: ; // idle
      endcase
    end
  end

  assign out_data  = data_r;
  assign out_valid = full;

endmodule

