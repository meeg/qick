///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : rising_edge_det
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    rising_edge_det.sv
//!
//! @brief   Rising edge detection circuit.
//!
//! @details
//!
//! It serves as clock domain crossing (CDC) logic.
//!
//! @author  QICK Development Team
//!
//! @version 1.0
module rising_edge_det(
    input logic  i_clk    ,
    input logic  i_rstn   ,
    input logic  i_strobe ,
    output logic o_pulse
);

    logic delay_r, delay_n;

    always_ff @ (posedge i_clk) begin
     if(!i_rstn) begin
       delay_r <= '0;
     end else begin
       delay_r <= delay_n;
     end
    end

    //next-state logic
    assign delay_n = i_strobe;

    //output and decoding logic
    assign o_pulse = !delay_r & i_strobe;

endmodule
