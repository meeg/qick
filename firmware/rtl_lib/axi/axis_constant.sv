// ============================================================================
// File: axis_constant.sv
// Source: ip/axis_constant/src/axis_constant.vhd
// Description: AXI4-Stream constant.
//
// Interfaces:
//   m_axis : axi4_stream_if.master  — outgoing data stream
//
// Parameters:
//   DATA_WIDTH : data width in bits
// ============================================================================
`timescale 1ns/1ps

module axis_constant #(
    parameter int DATA_WIDTH = 16
)(
    input logic             m_axis_aclk,
    input logic             m_axis_aresetn,
    // AXI4-Stream master — outgoing data
    axi4_stream_if.master   m_axis
);

    // Assign constant '0' to all outputs
    assign m_axis.tdata  = {DATA_WIDTH{1'b0}};
    assign m_axis.tstrb  = {(DATA_WIDTH/8){1'b0}};
    assign m_axis.tlast  = 1'b0;
    assign m_axis.tvalid = 1'b0;

endmodule
