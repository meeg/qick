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
  parameter int DWIDTH = 32
)(
  input  logic         clk,
  input  logic         rstn,

  axi4_stream_if.slave s_axis,
  axi4_stream_if.master m_axis
);

  // Internal storage
  logic [DWIDTH-1:0] data_r;
  logic         full;

  // ===============================
  // READY logic
  // ===============================
  // Can accept if buffer empty
  // or downstream will consume this cycle
  assign s_axis.tready = !full || (m_axis.tready && m_axis.tvalid);

  // ===============================
  // Sequential storage
  // ===============================
  always_ff @(posedge clk) begin
    if (!rstn) begin
      full <= 1'b0;
    end else begin
      case ({s_axis.tvalid && s_axis.tready, m_axis.tready && m_axis.tvalid})
        2'b10: begin
          // push only
          data_r <= s_axis.tdata;
          full   <= 1'b1;
        end
        2'b01: begin
          // pop only
          full <= 1'b0;
        end
        2'b11: begin
          // push + pop (replace)
          data_r <= s_axis.tdata;
          full   <= 1'b1;
        end
        default: ; // idle
      endcase
    end
  end

  assign m_axis.tdata  = data_r;
  assign m_axis.tvalid = full;

endmodule

