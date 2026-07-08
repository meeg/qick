`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : iir_1p1z
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    iir_1p1z.sv
//!
//! @brief   First-order IIR (1-pole / 1-zero), single real channel, fixed-point.
//!
//! @details
//!
//!
//! Direct-Form I first-order IIR filter.
//! H(z) = G * (1 - C0*z^-1) / (1 - C1*z^-1)
//! Coefficients C0, C1, G are signed Q(B-1) fixed-point in [-1, +1).
//! Internal datapath widened to BA bits for headroom; products are
//! BP = BA + B bits and re-quantized (drop duplicated sign bit).
//!
//! Pipeline latency = 4 valid cycles (i_valid -> o_valid).
//! Valid-gated: every datapath stage advances ONLY on its valid,
//! so the filter tolerates bubbles (non-continuous i_valid).
//!
//! NOTE: re-quantization uses TRUNCATION and NO SATURATION. Ensure the
//! feedback loop cannot overflow BA bits for the intended C1 range,
//! or add saturation (see project bitácora / open item).
//!
//! @author  QICK Development Team
//!
//! @version 1.0
module iir_1p1z #(
    /** @brief Sample and coefficient width in bits (Q(B-1) format). */
    parameter int B  = 16,
    /** @brief Internal accumulator/datapath width in bits (BA >= B). */
    parameter int BA = 20
)(
    // Clock and Reset
    /** @brief System clock; all logic on the rising edge. */
    input  logic                 i_clk,
    /** @brief Synchronous reset, active low. */
    input  logic                 i_rstn,

    // Input Data Stream
    /** @brief Input sample valid. */
    input  logic                 i_valid,
    /** @brief Input sample, signed Q(B-1). */
    input  logic signed [B-1:0]  i_data,

    // Output Data Stream
    /** @brief Output sample valid (latency = 4). */
    output logic                 o_valid,
    /** @brief Output sample, signed Q(B-1). */
    output logic signed [B-1:0]  o_data,

    // Coefficient / Gain Registers (signed Q(B-1))
    /** @brief Feed-forward (zero) coefficient C0. */
    input  logic signed [B-1:0]  i_c0,
    /** @brief Feed-back (pole) coefficient C1. */
    input  logic signed [B-1:0]  i_c1,
    /** @brief Output gain G. */
    input  logic signed [B-1:0]  i_g
);
    // Derived Parameters
    localparam int BP = BA + B;   // product width

    // Input registers
    logic signed [B-1:0]  din_r1;
    logic signed [B-1:0]  c0_r1;
    logic signed [B-1:0]  c1_r1;
    logic signed [B-1:0]  g_r1;

    // Valid pipeline
    logic valid_r1, valid_r2, valid_r3, valid_r4;

    // Sign-extended input
    logic signed [BA-1:0] xn;

    // Feed-forward filter (zero)
    logic signed [BA-1:0] xn_r1;
    logic signed [BP-1:0] p0;
    logic signed [BA-1:0] p0_q;
    logic signed [BA-1:0] y0;
    logic signed [BA-1:0] y0_r1;

    // Feed-back filter (pole)
    logic signed [BP-1:0] p1;
    logic signed [BA-1:0] p1_q;
    logic signed [BA-1:0] y1;
    logic signed [BA-1:0] y1_r1a;   // recursive pole state
    logic signed [BA-1:0] y1_r1b;   // feeds output gain stage

    // Output gain
    logic signed [BP-1:0] yg;
    logic signed [B-1:0]  yg_q;
    logic signed [B-1:0]  yg_q_r1;

    // Sign-extended input
    assign xn = {{(BA-B){din_r1[B-1]}}, din_r1};

    // Feed-forward filter: drop duplicated sign bit, then truncate to BA
    assign p0   = c0_r1 * xn_r1;
    assign p0_q = p0[BP-2 -: BA];
    assign y0   = xn - p0_q;

    // Feed-back filter
    assign p1   = c1_r1 * y1_r1a;
    assign p1_q = p1[BP-2 -: BA];
    assign y1   = y0_r1 + p1_q;

    // Output gain: re-quantize BA-domain product back to B bits
    assign yg   = g_r1 * y1_r1b;
    assign yg_q = yg[2*B-2 -: B];   // = yg[BP-2-(BA-B) -: B]

    // Sequential logic (SYNCHRONOUS active-low reset)
    always_ff @(posedge i_clk) begin
        if (~i_rstn) begin
            din_r1   <= '0;
            c0_r1    <= '0;
            c1_r1    <= '0;
            g_r1     <= '0;

            valid_r1 <= 1'b0;
            valid_r2 <= 1'b0;
            valid_r3 <= 1'b0;
            valid_r4 <= 1'b0;

            xn_r1    <= '0;
            y0_r1    <= '0;
            y1_r1a   <= '0;
            y1_r1b   <= '0;
            yg_q_r1  <= '0;
        end
        else begin
            // Input registers (coefficients registered every cycle).
            din_r1   <= i_data;
            c0_r1    <= i_c0;
            c1_r1    <= i_c1;
            g_r1     <= i_g;

            // Valid pipeline.
            valid_r1 <= i_valid;
            valid_r2 <= valid_r1;
            valid_r3 <= valid_r2;
            valid_r4 <= valid_r3;

            // Feed-forward stage (advances only on valid).
            if (valid_r1) begin
                xn_r1 <= xn;
                y0_r1 <= y0;
            end

            // Feed-back stage (advances only on valid).
            if (valid_r2) begin
                y1_r1a <= y1;
                y1_r1b <= y1;
            end

            // Output gain stage (advances only on valid).
            if (valid_r3) begin
                yg_q_r1 <= yg_q;
            end
        end
    end

    // Output assignments
    assign o_data  = yg_q_r1;
    assign o_valid = valid_r4;

`ifndef SYNTHESIS
    // Basic sanity: no output valid while in reset.
    // assert property (@(posedge i_clk) (~i_rstn) |-> ~o_valid);
`endif // SYNTHESIS
endmodule

