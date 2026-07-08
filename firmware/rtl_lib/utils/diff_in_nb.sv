///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : diff_in_nb
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    diff_in_nb.sv
//!
//! @brief   A file containing a module that use the Xilinx
//!
//! @details
//!
//! IBUFDS primitive. The module is parametrizable,
//! allowing for easy adjustment of the bus width.
//! This module handles a differential input bus and
//! converts it to a single-ended output bus.
//! The bus width is controlled by the `NB` parameter.
//!
//! @author  QICK Development Team
//!
//! @version 1.0
module diff_in_nb#(
  parameter integer NB = 16 // The width of the differential bus.
)(
  input  logic [NB-1:0] i_diff_p, // Positive differential input
  input  logic [NB-1:0] i_diff_n, // Negative differential input
  output logic [NB-1:0] o_se      // Single-ended output
);

  // Use a `generate` block to instantiate the IBUFDS primitives for each bit.
  generate
    for (genvar i = 0; i < NB; i = i + 1) begin : g_ibufds
      IBUFDS ibuf_ds_inst (
        .O  (o_se[i]    ),
        .I  (i_diff_p[i]),
        .IB (i_diff_n[i])
      );
    end
  endgenerate

endmodule

