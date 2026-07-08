///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : axis_constant
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    axis_constant.sv
//!
//! @brief   AXI4-Stream constant.
//!
//! @details
//!
//!
//! Interfaces:
//! m_axis : axi4_stream_if.master  — outgoing data stream
//!
//! @note    Ported from ip/axis_constant/src/axis_constant.vhd
//!
//! @author  QICK Development Team
//!
//! @version 1.0
`timescale 1ns/1ps

module axis_constant #(
    //! data width in bits
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
