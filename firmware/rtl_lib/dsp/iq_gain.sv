`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////
// Project: QICK
// Module : iq_gain
///////////////////////////////////////////////////////////////////////////////
//! @file    iq_gain.sv
//! @brief   Multiplies complex baseband samples (I,Q) by a programmable gain.
//! @details Multiplies I and Q by an signed gain (0-15).
//!           Includes saturation to prevent wrapping.
//!           Latency: 3 aclk cycles.
//! @author  @lharnaldi
//! @version 1.0

module iq_gain #(
    parameter int DW = 16,      // Data width (16-bit signed)
    parameter int GW = 16        // Gain width (16-bit signed)
)(
    input  logic                    aclk,
    input  logic                    aresetn,
    input  logic signed [DW-1:0]    i_in,
    input  logic signed [DW-1:0]    q_in,
    input  logic signed [GW-1:0]    gain_i,  // Independent Gain for I
    input  logic signed [GW-1:0]    gain_q,  // Independent Gain for Q
    output logic signed [DW-1:0]    i_out,
    output logic signed [DW-1:0]    q_out
);

    // Dynamical saturation constants dependent on the DW parameter
    // For DW=16: MAXV = 32767, MINV = -32768
    localparam signed [DW-1:0] MAXV = (1 << (DW-1)) - 1;
    localparam signed [DW-1:0] MINV = -(1 << (DW-1));

    // Stage 0: input register
    logic signed [DW-1:0] i_r, q_r;
    logic signed [GW-1:0] gain_i_r, gain_q_r;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            i_r      <= '0;
            q_r      <= '0;
            gain_i_r <= '0;
            gain_q_r <= '0;
        end else begin
            i_r      <= i_in;
            q_r      <= q_in;
            gain_i_r <= $signed(gain_i);  // interpretar como signed
            gain_q_r <= $signed(gain_q);  // interpretar como signed
        end
    end

    // Stage 1: multiplication (product of DW+GW bits)
    logic signed [DW+GW-1:0] i_prod, q_prod;
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            i_prod <= '0;
            q_prod <= '0;
        end else begin
            i_prod <= i_r * gain_i_r;
            q_prod <= q_r * gain_q_r;
        end
    end

    // Function for rounding + saturation
    function automatic logic signed [DW-1:0] scale_and_saturate(input logic signed [DW+GW-1:0] val);
        logic signed [DW+GW-1:0] rounded;
        logic signed [DW+GW-1:0] scaled; // Keep the full width to avoid truncation

        // Rounding: add half of the LSB of the part that will be kept
        // If we shift right by (GW-1), the most significant bit of the fractional part is at (GW-2)
        rounded = val + (1 << (GW-2));

        // Arithmetic right shift
        scaled = rounded >>> (GW-1);

        // Saturation
        if (scaled > MAXV)
            return MAXV;
        else if (scaled < MINV)
            return MINV;
        else
            return scaled[DW-1:0];
    endfunction

    // Stage 2: registered output
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            i_out <= '0;
            q_out <= '0;
        end else begin
            i_out <= scale_and_saturate(i_prod);
            q_out <= scale_and_saturate(q_prod);
        end
    end

endmodule
