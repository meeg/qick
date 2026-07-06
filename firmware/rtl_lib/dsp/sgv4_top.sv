`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
//
// Fermi National Accelerator Laboratory
// Module : sgv4_top
// Project: QICK arbitrary signal generator v4 (axis_signal_gen_v4)
///////////////////////////////////////////////////////////////////////////////
//! @file    sgv4_top.sv
//! @brief   Top-level of the v4 arbitrary signal generator.
//!
//! @details
//! Assembles the v4 signal generator from the same verified building blocks as
//! sgv6_top, differing in:
//!  - N_DDS default (8 lanes for v4, vs 16 for v6).
//!  - Datapath: sgv4 drives dds_compiler_dyn_readout and computes the full
//!    complex product internally, but OUTPUTS ONE 16-bit value per lane
//!    (real or imag), selected by the static i_outsel_reg register -- NOT by a
//!    per-descriptor bit. sgv4 has no GEN_DDS parameter; the DDS path is always
//!    present.
//!  - Envelope memory: real + imag banks are always instantiated (as in the
//!    legacy v4 top), so ENVELOPE_TYPE is not exposed.
//!
//! Building blocks:
//!  - fifo_sync          : waveform-descriptor FIFO (160-bit, depth 16).
//!  - axis_to_bram_sg_nt : AXI4-Stream envelope writer, one-hot per bank.
//!  - bram_tdp (xN_DDS)  : dual-port, dual-clock envelope memories (real+imag).
//!  - sgv4               : datapath (envelope x DDS, gain, saturation, static
//!                         real/imag output select).
//!
//! Two clock domains:
//!  - s0_axis_aclk : envelope loading (BRAM port A write side).
//!  - aclk         : descriptor FIFO, sgv4, BRAM port B read side, and output.
//! The dual-clock BRAM (bram_tdp) resolves the crossing.
//!
//! Envelope memory layout: N_DDS parallel banks, each 16 bits wide and 2**N
//! deep. The 32-bit stream word is split: din[15:0] -> real, din[31:16] -> imag.
//! All banks share the read address mem_addrb from sgv4; outputs are
//! concatenated into mem_dob_real / mem_dob_imag.
//!
//! Registers (from the top-level AXI-Lite slave, mirroring legacy):
//!  - start_addr_reg : envelope write start address.
//!  - we_reg         : envelope write enable (capture).
//!  - outsel_reg     : static real/imag output select (0=real, 1=imag).
//!                     Legacy name: OUTSEL_REG.
//! Legacy RNDQ_REG has been removed from the datapath (deprecated in the IP)
//! and is intentionally not carried here.
//!
//! @note   Reset convention: SYNCHRONOUS active-low, per clock domain.
//!
//! @author FNAL / QICK
//! @version 1.0
module sgv4_top #(
   parameter int N     = 16,  //! Envelope-memory address width per bank (depth 2**N).
   parameter int N_DDS = 8    //! Number of parallel banks / DDS lanes (v4 = 8).
)(
   // Reset and clock (main domain).
   input  logic                 aresetn         , //! Active-low synchronous reset (aclk domain).
   input  logic                 aclk            , //! Main clock (FIFO, sgv4, read side, output).
   // AXIS slave: envelope sample loading.
   input  logic                 s0_axis_aresetn , //! Active-low synchronous reset (envelope-load domain).
   input  logic                 s0_axis_aclk    , //! Envelope-load clock (BRAM port A).
   input  logic [31:0]          s0_axis_tdata_i , //! 32-bit envelope word: [15:0]=real, [31:16]=imag.
   input  logic                 s0_axis_tvalid_i, //! Envelope stream valid.
   output logic                 s0_axis_tready_o, //! Envelope stream ready.
   // AXIS slave: waveform descriptor queue.
   input  logic [159:0]         s1_axis_tdata_i , //! 160-bit waveform descriptor (v4 layout, see ctrl_sgv4).
   input  logic                 s1_axis_tvalid_i, //! Descriptor valid.
   output logic                 s1_axis_tready_o, //! Descriptor ready (FIFO not full).
   // M_AXIS output (one 16-bit value per lane: real or imag per outsel_reg).
   input  logic                 m_axis_tready_i , //! Output ready.
   output logic                 m_axis_tvalid_o , //! Output valid.
   output logic [N_DDS*16-1:0]  m_axis_tdata_o  , //! N_DDS x 16-bit output samples (real or imag per outsel_reg).
   // Registers.
   input  logic [31:0]          start_addr_reg  , //! Envelope write start address.
   input  logic                 we_reg          , //! Envelope write enable (capture).
   input  logic                 outsel_reg      , //! Static real/imag output select (0=real, 1=imag).
   output logic                 o_sat             //! Saturation flag (1 if any output sample saturated).
);
   // --------------------------------------------------------------------------
   // FIFO signals.
   // --------------------------------------------------------------------------
   logic         fifo_wr_en;   //! FIFO write enable (from descriptor stream).
   logic [159:0] fifo_din;     //! FIFO write data (descriptor).
   logic         fifo_rd_en;   //! FIFO read enable (from sgv4).
   logic [159:0] fifo_dout;    //! FIFO read data (descriptor to sgv4).
   logic         fifo_full;    //! FIFO full flag (drives backpressure).
   logic         fifo_empty;   //! FIFO empty flag (to sgv4).

   // --------------------------------------------------------------------------
   // Envelope memory: read side (aclk).
   // --------------------------------------------------------------------------
   logic [N-1:0]        mem_addrb;    //! Shared envelope read address (from sgv4).
   logic [N_DDS*16-1:0] mem_dob_real; //! Concatenated real envelope read data.
   logic [N_DDS*16-1:0] mem_dob_imag; //! Concatenated imag envelope read data.

   logic [N_DDS-1:0]    mem_en;       //! One-hot per-bank write enable (from writer).

   // --------------------------------------------------------------------------
   // Waveform descriptor FIFO.
   // --------------------------------------------------------------------------
   fifo_sync #(
      .B (160),
      .N (16)
   ) fifo_i (
      .rstn          (aresetn),
      .clk           (aclk),
      .wr_en         (fifo_wr_en),
      .din           (fifo_din),
      .rd_en         (fifo_rd_en),
      .dout          (fifo_dout),
      .full          (fifo_full),
      .empty         (fifo_empty),
      // Unused advanced flags.
      .wr_data_count (),
      .rd_data_count (),
      .prog_full     (),
      .prog_empty    (),
      .wr_err        (),
      .rd_err        ()
   );

   assign fifo_wr_en = s1_axis_tvalid_i;
   assign fifo_din   = s1_axis_tdata_i;

   // --------------------------------------------------------------------------
   // Envelope write interfaces (s0_axis_aclk domain).
   //   axis_wr : incoming 32-bit envelope stream (slave for the writer).
   //   bram_wr : shared write port produced by the writer.
   // --------------------------------------------------------------------------
   axi4_stream_if #(.TDATA_WIDTH(32)) axis_wr (
      .aclk    (s0_axis_aclk),
      .aresetn (s0_axis_aresetn)
   );

   bram_if #(.NB_DATA(32), .NB_ADDR(N)) bram_wr (
      .i_clk (s0_axis_aclk),
      .i_rst (~s0_axis_aresetn)
   );

   // Drive the writer's AXIS slave from the flat s0 ports.
   assign axis_wr.tdata    = s0_axis_tdata_i;
   assign axis_wr.tvalid   = s0_axis_tvalid_i;
   assign s0_axis_tready_o = axis_wr.tready;

   // --------------------------------------------------------------------------
   // Envelope writer: AXIS -> shared BRAM write port + one-hot bank select.
   // --------------------------------------------------------------------------
   axis_to_bram_sg_nt #(
      .NT (N_DDS),
      .N  (N),
      .B  (32)
   ) writer_i (
      .rstn           (s0_axis_aresetn),
      .clk            (s0_axis_aclk),
      .axis           (axis_wr.slave),
      .bram           (bram_wr.master),
      .mem_en         (mem_en),
      .start_addr_reg (start_addr_reg),
      .capture_reg    (we_reg)
   );

   // --------------------------------------------------------------------------
   // Envelope memories: N_DDS banks, real + imag (legacy v4 always instantiates
   // both -- no REAL-only mode, unlike sgv6_top's ENVELOPE_TYPE parameter).
   //   Port A (write, s0_axis_aclk): gated by mem_en[i]; din split real/imag.
   //   Port B (read, aclk):          shared mem_addrb; outputs concatenated.
   // --------------------------------------------------------------------------
   generate
      for (genvar i = 0; i < N_DDS; i = i + 1) begin : gen_mem
         // Real bank.
         bram_tdp #(
            .NB_DATA (16),
            .NB_ADDR (N)
         ) mem_real_i (
            .clka  (s0_axis_aclk),
            .rsta  (~s0_axis_aresetn),
            .ena   (mem_en[i]),
            .wea   (bram_wr.we & mem_en[i]),
            .addra (bram_wr.addr),
            .dia   (bram_wr.din[15:0]),
            .doa   (),
            .clkb  (aclk),
            .rstb  (~aresetn),
            .enb   (1'b1),
            .web   (1'b0),
            .addrb (mem_addrb),
            .dib   (16'h0000),
            .dob   (mem_dob_real[i*16 +: 16])
         );

         // Imaginary bank.
         bram_tdp #(
            .NB_DATA (16),
            .NB_ADDR (N)
         ) mem_imag_i (
            .clka  (s0_axis_aclk),
            .rsta  (~s0_axis_aresetn),
            .ena   (mem_en[i]),
            .wea   (bram_wr.we & mem_en[i]),
            .addra (bram_wr.addr),
            .dia   (bram_wr.din[31:16]),
            .doa   (),
            .clkb  (aclk),
            .rstb  (~aresetn),
            .enb   (1'b1),
            .web   (1'b0),
            .addrb (mem_addrb),
            .dib   (16'h0000),
            .dob   (mem_dob_imag[i*16 +: 16])
         );
      end
   endgenerate

   // --------------------------------------------------------------------------
   // Signal generator datapath.
   //   Static real/imag output select comes from outsel_reg (legacy OUTSEL_REG).
   // --------------------------------------------------------------------------
   sgv4 #(
      .N     (N),
      .N_DDS (N_DDS)
   ) sgv4_i (
      .i_rstn          (aresetn),
      .i_clk           (aclk),
      .o_fifo_rd_en    (fifo_rd_en),
      .i_fifo_empty    (fifo_empty),
      .i_fifo_dout     (fifo_dout),
      .o_mem_addr      (mem_addrb),
      .i_mem_dout_real (mem_dob_real),
      .i_mem_dout_imag (mem_dob_imag),
      .i_outsel_reg    (outsel_reg),
      .i_axis_tready   (m_axis_tready_i),
      .o_axis_tvalid   (m_axis_tvalid_o),
      .o_axis_tdata    (m_axis_tdata_o),
      .o_sat           (o_sat)
   );

   // --------------------------------------------------------------------------
   // Descriptor backpressure.
   // --------------------------------------------------------------------------
   assign s1_axis_tready_o = ~fifo_full;

endmodule