`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////
// Project: QICK
// Module : iq_gain
///////////////////////////////////////////////////////////////////////////////
//! @file    iq_gain.sv
//! @brief   Multiplies complex baseband samples (I,Q) by a programmable gain.
//! @details Multiplies I and Q by an unsigned gain (0-15).
//!           Includes saturation to prevent wrapping.
//!           Latency: 3 aclk cycles.
//! @author  @lharnaldi
//! @version 1.0

module iq_gain #(
    parameter int DW = 16,      // Data width (16-bit signed)
    parameter int GW = 4        // Gain width (4-bit unsigned)
)(
    input  logic                    aclk,
    input  logic                    aresetn,
    input  logic signed [DW-1:0]    i_in,
    input  logic signed [DW-1:0]    q_in,
    input  logic        [GW-1:0]    gain,
    output logic signed [DW-1:0]    i_out,
    output logic signed [DW-1:0]    q_out
);

    // Constants for saturation
    localparam logic signed [DW-1:0] MAXV = {1'b0, {(DW-1){1'b1}}}; // 32767
    localparam logic signed [DW-1:0] MINV = {1'b1, {(DW-1){1'b0}}}; // -32768

    // Pipeline Stage 0: Input registration
    logic signed [DW-1:0] i_in_r;
    logic signed [DW-1:0] q_in_r;
    logic        [GW-1:0] gain_r;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            i_in_r  <= '0;
            q_in_r  <= '0;
            gain_r  <= '0;
        end else begin
            i_in_r  <= i_in;
            q_in_r  <= q_in;
            gain_r  <= gain;
        end
    end

    // multiplication: Signed DW * Unsigned GW
    // We cast gain to signed to ensure the multiplier behaves correctly
    // The result width is DW + GW
    logic signed [DW+GW-1:0] i_mult;
    logic signed [DW+GW-1:0] q_mult;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            i_mult <= '0;
            q_mult <= '0;
        end else begin
            // Explicitly treat gain as a positive signed number
            i_mult <= i_in_r * $signed({1'b0, gain_r});
            q_mult <= q_in_r * $signed({1'b0, gain_r});
        end
    end

    // Saturation function
    function automatic logic signed [DW-1:0] saturate (input logic signed [DW+GW-1:0] val);
        if (val > MAXV)
            return MAXV;
        else if (val < MINV)
            return MINV;
        else
            return val[DW-1:0];
    endfunction

    // Pipeline Stage 1: Saturation and output registration
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            i_out <= '0;
            q_out <= '0;
        end else begin
            i_out <= saturate(i_mult);
            q_out <= saturate(q_mult);
        end
    end

endmodule

