`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : kidsim
// Project: QICK / axis_kidsim_v3
///////////////////////////////////////////////////////////////////////////////
//! @file    kidsim.sv
//!
//! @brief   KID (Kinetic Inductance Detector) simulator datapath.
//!
//! @details
//!
//! Simulates a resonator's complex response by demodulating the input by a
//! (possibly chirped) DDS carrier, filtering with a 1-pole/1-zero IIR, and
//! remodulating back. One lane of the axis_kidsim_v3 IP.
//!
//! Datapath (OUTSEL = 0, main signal path):
//!   din -----------------------------[din_la]------------------\
//!                                                              prod0 = din * e^{-jw}
//!   dds_chirp --> dds_dout = e^{jw(t)} --------------------------/   (CONJB=1)
//!        |                                                           |
//!        |                                                        iir_iq  (resonator)
//!        |                                                           |
//!        \--[dds_dout_la]--> e^{jw} ----------------------------> prod1 = iir * e^{+jw}
//!                                                                    (CONJB=0)
//!
//!   OUTSEL:
//!     0 : prod1_dout        (full demod / filter / remod signal)
//!     1 : dds_dout_la_mux   (DDS carrier only)
//!     2 : din_la_mux        (input bypass)
//!     3 : 0
//!
//! LATENCY BALANCING (this is the fix for chirp alignment):
//!   The DDS block (dds_chirp) has latency DDS_LATENCY = 10 (dds_phase_ctrl 2
//!   + DDS IP 8). To multiply din by the carrier at the SAME time index in
//!   prod0, din must be delayed to match the carrier: din_la = DDS_LATENCY.
//!   The previous design used din_la = 2 (old dds latency), which left din and
//!   the carrier misaligned by 8 cycles. With a constant (CW) carrier that is
//!   only a harmless constant phase rotation, but with a CHIRP the carrier
//!   frequency changes over those 8 cycles, so din was demodulated by the
//!   wrong instantaneous frequency. Setting din_la = DDS_LATENCY fixes it.
//!
//!   Main path latency = DDS_LATENCY(10) + prod0(4) + iir_iq(4) + prod1(4) = 22.
//!   The mux bypass lines are balanced to the same 22 cycles.
//!
//! NUMERICAL FIDELITY (measured in simulation, IIR pass-through, CW & chirp):
//!   With C0=0, C1=0, G=32767 (~0.99997) the demod*remod chain recovers the
//!   input to within ~3 LSB worst-case over a full chirp sweep (input ~8000).
//!   Residual error sources: G = 32767/32768 (not exactly 1), IIR truncation,
//!   two cmult round-half-up stages, and DDS sine/cosine quantization.
//!
//! CARRIER CANCELLATION vs INPUT ALIGNMENT (design note):
//!   These are two SEPARATE timing constraints, do not confuse them:
//!   - demod/remod cancellation (e^{-jw}*e^{+jw}=1) is guaranteed by
//!     dds_dout_la = prod0_lat + iir_lat = 8, i.e. prod1 reuses the SAME
//!     carrier that prod0 used, delayed by the intervening pipeline. This
//!     holds for any din (even constant) and any DDS latency.
//!   - din_la = DDS_LATENCY = 10 aligns the INPUT SAMPLE with the carrier
//!     instant at prod0. It selects WHICH din sample is demodulated at each
//!     (possibly chirped) frequency. It only matters when din VARIES in time:
//!     with din_la wrong, a time-varying input is demodulated against the
//!     wrong instantaneous frequency during a chirp, distorting the result.
//!
//! @author  @lharnaldi
//!
//! @version 1.0
///////////////////////////////////////////////////////////////////////////////
module kidsim #(
    //! DDS block latency (dds_phase_ctrl 2 + DDS IP 8). Sets din alignment.
    parameter int DDS_LATENCY = 10
) (
    input  logic        i_clk,        //! Clock.
    input  logic        i_rstn,       //! Synchronous active-low reset.

    input  logic        i_trigger,    //! Modulation trigger (async, other domain).

    input  logic [31:0] i_din,        //! Input sample {Q[31:16], I[15:0]}.
    input  logic        i_din_valid,  //! Input valid.

    output logic [31:0] o_dout,       //! Output sample {Q[31:16], I[15:0]}.
    output logic        o_dout_valid, //! Output valid.

    // Register bank.
    input  logic [15:0] i_dds_bval_reg,   //! Chirp ramp start B.
    input  logic [15:0] i_dds_slope_reg,  //! Chirp ramp slope M.
    input  logic [15:0] i_dds_steps_reg,  //! Chirp ramp steps N.
    input  logic [15:0] i_dds_wait_reg,   //! Chirp ramp wait W.
    input  logic [15:0] i_dds_freq_reg,   //! DDS base frequency.
    input  logic [15:0] i_iir_c0_reg,     //! IIR coefficient C0.
    input  logic [15:0] i_iir_c1_reg,     //! IIR coefficient C1.
    input  logic [15:0] i_iir_g_reg,      //! IIR gain G.
    input  logic [ 1:0] i_outsel_reg      //! Output selection (0..3).
);

    //! Input data latency (aligned to the DDS carrier).
    logic [31:0] din_la;
    logic [31:0] din_la_mux;

    //! DDS output (carrier e^{jw(t)}).
    logic        dds_valid;
    logic [31:0] dds_dout;
    logic [31:0] dds_dout_la;
    logic [31:0] dds_dout_la_mux;

    //! Product 0 output (demod: din * e^{-jw}).
    logic        prod0_valid;
    logic [31:0] prod0_dout;

    //! IIR output (resonator).
    logic        iir_valid;
    logic [31:0] iir_dout;

    //! Product 1 output (remod: iir * e^{+jw}).
    logic        prod1_valid;
    logic [31:0] prod1_dout;

    //! Muxed output.
    logic [31:0] dout_mux;

    // ------------------------------------------------------------------------
    // DDS block (chirp carrier). Latency = DDS_LATENCY (10).
    // ------------------------------------------------------------------------
    dds_chirp dds_chirp_i (
        .i_clk        (i_clk),
        .i_rstn       (i_rstn),
        .i_trigger    (i_trigger),
        .i_din_valid  (i_din_valid),
        .o_dout_valid (dds_valid),
        .o_dout       (dds_dout),
        .i_bval_reg   (i_dds_bval_reg),
        .i_slope_reg  (i_dds_slope_reg),
        .i_steps_reg  (i_dds_steps_reg),
        .i_wait_reg   (i_dds_wait_reg),
        .i_freq_reg   (i_dds_freq_reg)
    );

    // ------------------------------------------------------------------------
    // Product 0: demodulate din by the conjugate carrier (e^{-jw}). Latency 4.
    // CONJB=1 conjugates dinb (the DDS). ROUND=1 (unbiased). SAT=1.
    // ------------------------------------------------------------------------
    cmult #(
        .BIN         (16),
        .BOUT        (16),
        .CONJA       (1'b0),
        .CONJB       (1'b1),
        .CONF_DYNAMIC(1'b0),
        .ROUND       (1'b1),
        .SAT         (1'b1)
    ) prod0_i (
        .i_clk   (i_clk),
        .i_rstn  (i_rstn),
        .i_conja (1'b0),          //! unused (CONF_DYNAMIC=0), tie low
        .i_conjb (1'b0),          //! unused (CONF_DYNAMIC=0), tie low
        .i_valid (dds_valid),
        .i_dina  (din_la),
        .i_dinb  (dds_dout),
        .o_valid (prod0_valid),
        .o_dout  (prod0_dout)
    );

    // ------------------------------------------------------------------------
    // IIR (resonator, per-I/Q 1-pole/1-zero). Latency 4.
    // ------------------------------------------------------------------------
    iir_iq #(
        .B  (16),
        .BA (20)
    ) iir_iq_i (
        .i_clk   (i_clk),
        .i_rstn  (i_rstn),
        .i_valid (prod0_valid),
        .i_data  (prod0_dout),
        .o_valid (iir_valid),
        .o_data  (iir_dout),
        .i_c0    (i_iir_c0_reg),
        .i_c1    (i_iir_c1_reg),
        .i_g     (i_iir_g_reg)
    );

    // ------------------------------------------------------------------------
    // Product 1: remodulate by the carrier (e^{+jw}). Latency 4.
    // CONJB=0 (no conjugate). ROUND=1. SAT=1.
    // ------------------------------------------------------------------------
    cmult #(
        .BIN         (16),
        .BOUT        (16),
        .CONJA       (1'b0),
        .CONJB       (1'b0),
        .CONF_DYNAMIC(1'b0),
        .ROUND       (1'b1),
        .SAT         (1'b1)
    ) prod1_i (
        .i_clk   (i_clk),
        .i_rstn  (i_rstn),
        .i_conja (1'b0),
        .i_conjb (1'b0),
        .i_valid (iir_valid),
        .i_dina  (iir_dout),
        .i_dinb  (dds_dout_la),
        .o_valid (prod1_valid),
        .o_dout  (prod1_dout)
    );

    // ------------------------------------------------------------------------
    // Latency lines.
    // ------------------------------------------------------------------------
    //! din delayed to align with the DDS carrier at prod0 (THE fix: = DDS_LATENCY).
    delay_line #(.N(DDS_LATENCY), .M(32)) din_la_i (
        .i_clk  (i_clk),
        .i_rstn (i_rstn),
        .i_data (i_din),
        .o_data (din_la)
    );

    //! din bypass path, balanced to the main path (total = 22).
    delay_line #(.N(12), .M(32)) din_la_mux_i (
        .i_clk  (i_clk),
        .i_rstn (i_rstn),
        .i_data (din_la),
        .o_data (din_la_mux)
    );

    //! DDS carrier delayed to align with iir_dout at prod1 (= prod0 + iir = 8).
    delay_line #(.N(8), .M(32)) dds_dout_la_i (
        .i_clk  (i_clk),
        .i_rstn (i_rstn),
        .i_data (dds_dout),
        .o_data (dds_dout_la)
    );

    //! DDS carrier bypass path, balanced to the main path (total = 22).
    delay_line #(.N(4), .M(32)) dds_dout_la_mux_i (
        .i_clk  (i_clk),
        .i_rstn (i_rstn),
        .i_data (dds_dout_la),
        .o_data (dds_dout_la_mux)
    );

    // ------------------------------------------------------------------------
    // Output mux.
    // ------------------------------------------------------------------------
    always_comb begin
        case (i_outsel_reg)
            2'd0:    dout_mux = prod1_dout;       //! demod/filter/remod signal
            2'd1:    dout_mux = dds_dout_la_mux;  //! DDS carrier only
            2'd2:    dout_mux = din_la_mux;       //! input bypass
            default: dout_mux = 32'h0000_0000;    //! off
        endcase
    end

    assign o_dout       = dout_mux;
    assign o_dout_valid = prod1_valid;

endmodule
