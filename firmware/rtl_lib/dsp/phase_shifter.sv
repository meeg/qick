`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : phase_shifter
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    phase_shifter.sv
//!
//! @brief   Rotates a complex baseband sample (I,Q) by a programmable phase.
//!
//! @details
//!
//!
//! Computes the complex rotation
//! I_out + j*Q_out = (I_in + j*Q_in) * e^{j*theta}
//! i.e.
//! I_out = I_in*cos(theta) - Q_in*sin(theta)
//! Q_out = I_in*sin(theta) + Q_in*cos(theta)
//!
//! The sin/cos coefficients come from a pre-generated Q1.15 lookup
//! table (2048 entries) addressed by the upper phase bits. The
//! products are computed in DSP48 blocks, then rounded, scaled back
//! to Q1.15 and saturated to +/-MAXV.
//!
//! Single clock domain (SYNCHRONOUS active-low reset). Fully
//! pipelined, data-valid-free (streaming, constant latency = 7 aclk):
//! s0 : input registration + phase de-glitch stage 1
//! s1 : data alignment 1 + phase de-glitch stage 2
//! s2 : data alignment 2 + phase registration (LUT address generation)
//! s3 : data alignment 3 + sin/cos LUT lookup (inferred BRAM)
//! s4 : four DSP multiplies (I*cos, I*sin, Q*cos, Q*sin)
//! s5 : add/subtract
//! s6 : round + arithmetic shift + saturate + output register
//!
//! @author  @lharnaldi
//!
//! @version 1.0
module phase_shifter #(
   //! Data / coefficient width (Q1.15, HW = 16).
   parameter int DW  = 16,
   //! Phase word width (HW = 16).
   parameter int PW  = 16,
   //! LUT address width (HW = 11 -> 2048 entries).
   parameter int LAW = 11
)(
   input  logic                    aclk,
   input  logic                    aresetn,
   input  logic signed [DW-1:0]    i_in,
   input  logic signed [DW-1:0]    q_in,
   input  logic        [PW-1:0]    phase,
   output logic signed [DW-1:0]    i_out,
   output logic signed [DW-1:0]    q_out
);
   // --------------------------------------------------------------------------
   // Local parameters.
   // --------------------------------------------------------------------------
   localparam int          LUT_DEPTH = (1 << LAW);   // 2048
   localparam int          PW_ROUND  = 15;           // Q2.30 -> Q1.15 shift
   localparam logic signed [2*DW-1:0] ROUND_CONST = (1 <<< (PW_ROUND-1)); // 2^14
   localparam logic signed [DW-1:0]   MAXV = {1'b0, {(DW-1){1'b1}}};      // +32767
   localparam logic signed [DW-1:0]   MINV = {1'b1, {(DW-1){1'b0}}};      // -32768

   // --------------------------------------------------------------------------
   // Stage 0: input registration, phase de-glitch, and data alignment.
   //   The phase word is pipelined by 3 stages (de-glitch / CDC-style buffer)
   //   before it addresses the LUT, and the LUT read adds one more stage.
   //   The coefficients therefore reach the s2 multiplier 4 clocks after
   //   'phase' is sampled, while I/Q reach it after only 2 (s0 reg + s1 reg).
   //   To keep each sample rotated by its own phase, I/Q are delayed by the
   //   two extra stages here (i_in_r/q_in_r feed a 2-deep alignment chain).
   // --------------------------------------------------------------------------
   logic signed [DW-1:0] i_in_r;
   logic signed [DW-1:0] q_in_r;
   logic        [PW-1:0] phase_buf1;
   logic        [PW-1:0] phase_buf2;
   logic        [PW-1:0] phase_r;

   always_ff @(posedge aclk) begin
      if (!aresetn) begin
         i_in_r     <= '0;
         q_in_r     <= '0;
         phase_buf1 <= '0;
         phase_buf2 <= '0;
         phase_r    <= '0;
      end else begin
         i_in_r     <= i_in;
         q_in_r     <= q_in;
         phase_buf1 <= phase;
         phase_buf2 <= phase_buf1;
         phase_r    <= phase_buf2;
      end
   end

   // LUT address: upper LAW bits of the de-glitched phase.
   logic [LAW-1:0] lut_addr;
   assign lut_addr = phase_r[PW-1 -: LAW];

   // --------------------------------------------------------------------------
   // Stage 1: sine/cosine lookup table (inferred as BRAM).
   //   Coefficients are Q1.15. Negative entries are stored as signed literals.
   // --------------------------------------------------------------------------
   logic signed [DW-1:0] cos_lut [LUT_DEPTH];
   logic signed [DW-1:0] sin_lut [LUT_DEPTH];

   // =========================== PASTE LUT INITIALIZATION HERE ================
   // Run: python3 generate_sincos_lut.py   (corrected, emits -16'sd... signed)
   // Paste the initial begin ... end block between these markers.
   // ==========================================================================
   initial begin
      $readmemh("cosine_table.mem", cos_lut);
      $readmemh("sine_table.mem", sin_lut);
   end

   logic signed [DW-1:0] cos_val;
   logic signed [DW-1:0] sin_val;

   always_ff @(posedge aclk) begin
      if (!aresetn) begin
         cos_val <= '0;
         sin_val <= '0;
      end else begin
         cos_val <= cos_lut[lut_addr];
         sin_val <= sin_lut[lut_addr];
      end
   end

   // Data alignment: match the 4-clock coefficient latency (2 already consumed
   // by i_in_r + i_stage1; add 2 here) so I/Q line up with cos/sin at s2.
   logic signed [DW-1:0] i_align1, i_align2;
   logic signed [DW-1:0] q_align1, q_align2;
   logic signed [DW-1:0] i_stage1;
   logic signed [DW-1:0] q_stage1;

   always_ff @(posedge aclk) begin
      if (!aresetn) begin
         i_align1 <= '0; i_align2 <= '0; i_stage1 <= '0;
         q_align1 <= '0; q_align2 <= '0; q_stage1 <= '0;
      end else begin
         // 2-stage alignment delay, then present alongside cos_val/sin_val.
         i_align1 <= i_in_r;   i_align2 <= i_align1;   i_stage1 <= i_align2;
         q_align1 <= q_in_r;   q_align2 <= q_align1;   q_stage1 <= q_align2;
      end
   end

   // --------------------------------------------------------------------------
   // Stage 2: four DSP multiplies (Q1.15 * Q1.15 -> Q2.30).
   // --------------------------------------------------------------------------
   logic signed [2*DW-1:0] i_cos;
   logic signed [2*DW-1:0] i_sin;
   logic signed [2*DW-1:0] q_cos;
   logic signed [2*DW-1:0] q_sin;

   always_ff @(posedge aclk) begin
      if (!aresetn) begin
         i_cos <= '0;
         i_sin <= '0;
         q_cos <= '0;
         q_sin <= '0;
      end else begin
         i_cos <= i_stage1 * cos_val;
         i_sin <= i_stage1 * sin_val;
         q_cos <= q_stage1 * cos_val;
         q_sin <= q_stage1 * sin_val;
      end
   end

   // --------------------------------------------------------------------------
   // Stage 3: complex add / subtract.
   //   I_out = I*cos - Q*sin
   //   Q_out = I*sin + Q*cos
   // --------------------------------------------------------------------------
   logic signed [2*DW-1:0] i_result;
   logic signed [2*DW-1:0] q_result;

   always_ff @(posedge aclk) begin
      if (!aresetn) begin
         i_result <= '0;
         q_result <= '0;
      end else begin
         i_result <= i_cos - q_sin;
         q_result <= i_sin + q_cos;
      end
   end

   // --------------------------------------------------------------------------
   // Stage 4: round, scale (Q2.30 -> Q1.15), saturate, and output register.
   // --------------------------------------------------------------------------
   function automatic logic signed [DW-1:0] saturate (input logic signed [2*DW-1:0] val);
      logic signed [2*DW-1:0] rounded;
      begin
         rounded = (val + ROUND_CONST) >>> PW_ROUND;   // Q2.30 -> Q1.15
         if (rounded > MAXV)
            saturate = MAXV;
         else if (rounded < MINV)
            saturate = MINV;
         else
            saturate = rounded[DW-1:0];
      end
   endfunction

   logic signed [DW-1:0] i_out_r;
   logic signed [DW-1:0] q_out_r;

   always_ff @(posedge aclk) begin
      if (!aresetn) begin
         i_out_r <= '0;
         q_out_r <= '0;
      end else begin
         i_out_r <= saturate(i_result);
         q_out_r <= saturate(q_result);
      end
   end

   assign i_out = i_out_r;
   assign q_out = q_out_r;
endmodule
