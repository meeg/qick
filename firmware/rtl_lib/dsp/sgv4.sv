///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : sgv4
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    sgv4.sv
//!
//! @brief   sgv4
//!
//! @details
//!
//!
//! Arbitrary signal generator datapath for v4 (real-or-imag output
//! selected by a static top-level register).
//!
//! Faithful migration of the real production signal_gen.v, with two
//! deliberate fixes applied (matching the same fixes already made in
//! sgv6):
//!
//! (1) SCALING: the legacy computes the envelope x DDS product using
//! [31:16] (step 1) then the gain stage using [30:15] (step 2) --
//! an inconsistent factor-of-2 between the two stages. Here the
//! product stage now uses [30:15] (full Q15 scale). The gain/round
//! stage takes [31:15] (17 bits): the value is quantised at bit 15
//! like the product, and the extra MSB (bit 31) feeds the overflow
//! detection of the saturation logic in fix (2) below.
//!
//! (2) SATURATION: the legacy has none -- the rounded output simply wraps
//! on overflow. Saturation to +/- MAXV (32766) is now applied to both
//! the real and imaginary rounded values, with o_sat asserted when
//! either would have clipped.
//!
//! A side effect of fix (2): the legacy's gain-stage pipeline register had
//! `if (en_int_r17) prodg_y_full_real_r[i] <= ...` without begin/end, so
//! only the real half was actually gated by en_int_r17 -- the imaginary
//! half updated unconditionally every cycle (a real bug in production,
//! whether intentional or not). Matching sgv6's already-fixed structure,
//! this stage is now updated unconditionally (both real and imaginary,
//! every cycle) with no en-gating at all -- eliminating the ambiguity
//! entirely rather than "fixing" it by guessing which behavior (gated
//! real / gated both / gated neither) was intended.
//!
//! Differences from v6 (by design, matching the real v4 hardware):
//!
//!
//! - Full complex product (I and Q) computed internally, but output
//! narrows to ONE 16-bit value per lane, selected by a static
//! top-level register (i_outsel_reg: 0=real, 1=imag) -- NOT a
//! per-descriptor bit. This is a genuine architectural difference
//! from v6 (which only ever computes/outputs the real component).
//!
//!
//! - o_axis_tdata is N_DDS*16 (not N_DDS*32) -- an earlier migration
//! pass incorrectly widened this to a 32-bit I/Q pair per lane; the
//! real hardware/driver interface is 16 bits/lane.
//!
//! Note on N_DDS: production hardware uses N_DDS = 16 (the shared Python
//! driver's SAMPS_PER_CLK = 16). The module is parameterised, so it may be
//! instantiated with other lane counts (e.g. the unit testbench exercises
//! N_DDS = 8); all lanes are structurally identical.
//!
//! @author  QICK Development Team
//!
//! @version 1.0
module sgv4 #(
   //! Envelope-memory address width in bits (default 16).
   parameter int N     = 16,
   //! Number of parallel DDS lanes (default 16).
   parameter int N_DDS = 16
)(
   // Reset and clock.
   input  logic                i_rstn          ,
   input  logic                i_clk           ,
   // FIFO interface.
   output logic                o_fifo_rd_en    ,
   input  logic                i_fifo_empty    ,
   input  logic [159:0]        i_fifo_dout     ,
   // Memory interface.
   output logic [N-1:0]        o_mem_addr      ,
   input  logic [N_DDS*16-1:0] i_mem_dout_real ,
   input  logic [N_DDS*16-1:0] i_mem_dout_imag ,
   // Static real/imag output select (top-level register, not per-waveform).
   input  logic                i_outsel_reg    ,
   // AXIS output (single value per lane: real or imag, per i_outsel_reg).
   input  logic                i_axis_tready   ,
   output logic                o_axis_tvalid   ,
   output logic [N_DDS*16-1:0] o_axis_tdata    ,
   // Saturation flag.
   output logic                o_sat
);

   // --------------------------------------------------------------------------
   // Internal signals.
   // --------------------------------------------------------------------------
   logic [N-1:0] mem_addr_int;
   logic [N-1:0] mem_addr_int_r;

   logic                 dds_tvalid_r;
   logic [N_DDS*72-1:0]  dds_ctrl_int;
   logic [N_DDS*72-1:0]  dds_ctrl_int_r;

   logic [31:0] dds_dout     [N_DDS];
   logic [31:0] dds_dout_r1  [N_DDS];
   logic [31:0] dds_dout_la  [N_DDS];
   logic [15:0] dds_la_mux_i [N_DDS];
   logic [15:0] dds_la_mux_q [N_DDS];

   logic [15:0] mem_real_r1  [N_DDS];
   logic [15:0] mem_imag_r1  [N_DDS];
   logic [15:0] mem_real_la  [N_DDS];
   logic [15:0] mem_imag_la  [N_DDS];
   logic [15:0] mem_la_mux_i [N_DDS];
   logic [15:0] mem_la_mux_q [N_DDS];

   logic signed [15:0] prod_a_real           [N_DDS];
   logic signed [15:0] prod_a_imag           [N_DDS];
   logic signed [15:0] prod_b_real           [N_DDS];
   logic signed [15:0] prod_b_imag           [N_DDS];
   logic signed [31:0] prod_y_full_real_a    [N_DDS];
   logic signed [31:0] prod_y_full_real_b    [N_DDS];
   logic signed [31:0] prod_y_full_imag_a    [N_DDS];
   logic signed [31:0] prod_y_full_imag_b    [N_DDS];
   logic signed [31:0] prod_y_full_real_a_r1 [N_DDS];
   logic signed [31:0] prod_y_full_real_b_r1 [N_DDS];
   logic signed [31:0] prod_y_full_imag_a_r1 [N_DDS];
   logic signed [31:0] prod_y_full_imag_b_r1 [N_DDS];
   logic signed [31:0] prod_y_full_real_a_r2 [N_DDS];
   logic signed [31:0] prod_y_full_real_b_r2 [N_DDS];
   logic signed [31:0] prod_y_full_imag_a_r2 [N_DDS];
   logic signed [31:0] prod_y_full_imag_b_r2 [N_DDS];
   logic signed [31:0] prod_y_full_real      [N_DDS];
   logic signed [31:0] prod_y_full_imag      [N_DDS];
   logic        [15:0] prod_y_real           [N_DDS];
   logic        [15:0] prod_y_imag           [N_DDS];
   logic        [31:0] prod_y                [N_DDS];
   logic        [31:0] prod_y_r1             [N_DDS];

   logic [31:0] dout_mux    [N_DDS];
   logic [31:0] dout_mux_la [N_DDS];

   logic        [15:0] gain_int;
   logic signed [15:0] gain_la;
   logic signed [15:0] prodg_a_real        [N_DDS];
   logic signed [15:0] prodg_a_imag        [N_DDS];
   logic signed [31:0] prodg_y_full_real   [N_DDS];
   logic signed [31:0] prodg_y_full_imag   [N_DDS];
   logic signed [31:0] prodg_y_full_real_r1[N_DDS];
   logic signed [31:0] prodg_y_full_imag_r1[N_DDS];
   logic signed [31:0] prodg_y_full_real_r2[N_DDS];
   logic signed [31:0] prodg_y_full_imag_r2[N_DDS];

   logic signed [16:0] round_ext_real      [N_DDS];
   logic signed [16:0] round_ext_imag      [N_DDS];
   logic        [15:0] round_real          [N_DDS];
   logic        [15:0] round_imag          [N_DDS];
   logic        [15:0] round_mux           [N_DDS];

   logic        [15:0] last_r              [N_DDS];

   logic [1:0] src_int;
   logic [1:0] src_la;

   logic stdy_int;
   logic stdy_la;

   logic en_int;
   logic en_la;
   logic en_la_r;

   logic [N_DDS-1:0] sat_lane;

   // --------------------------------------------------------------------------
   // Control block (v4 version -- identical to ctrl_sgv6).
   // --------------------------------------------------------------------------
   ctrl_sgv4 #(
      .N     (N),
      .N_DDS (N_DDS)
   ) ctrl_i (
      .i_rstn       (i_rstn),
      .i_clk        (i_clk),
      .o_fifo_rd_en (o_fifo_rd_en),
      .i_fifo_empty (i_fifo_empty),
      .i_fifo_dout  (i_fifo_dout),
      .o_dds_ctrl   (dds_ctrl_int),
      .o_mem_addr   (mem_addr_int),
      .o_gain       (gain_int),
      .o_src        (src_int),
      .o_stdy       (stdy_int),
      .o_en         (en_int)
   );

   // --------------------------------------------------------------------------
   // Per-lane datapath.
   // --------------------------------------------------------------------------
   generate
      for (genvar i = 0; i < N_DDS; i = i + 1) begin : gen_lane

         // DDS Compiler Instance
         dds_compiler_dyn_readout dds_i (
            .aclk                (i_clk),
            .s_axis_phase_tvalid (dds_tvalid_r),
            .s_axis_phase_tdata  (dds_ctrl_int_r[i*72 +: 72]),
            .m_axis_data_tvalid  (),
            .m_axis_data_tdata   (dds_dout[i])
         );

         delay_line #(.N(1), .M(32)) dds_dout_latency_reg_i (
            .i_clk  (i_clk),
            .i_rstn (i_rstn),
            .i_data (dds_dout_r1[i]),
            .o_data (dds_dout_la[i])
         );

         delay_line #(.N(3), .M(16)) dds_mux_latency_reg_i (
            .i_clk  (i_clk),
            .i_rstn (i_rstn),
            .i_data (dds_dout_la[i][15:0]),
            .o_data (dds_la_mux_i[i])
         );
         delay_line #(.N(3), .M(16)) dds_mux_latency_reg_q_i (
            .i_clk  (i_clk),
            .i_rstn (i_rstn),
            .i_data (dds_dout_la[i][31:16]),
            .o_data (dds_la_mux_q[i])
         );

         delay_line #(.N(9), .M(16)) mem_real_latency_reg_i (
            .i_clk  (i_clk),
            .i_rstn (i_rstn),
            .i_data (mem_real_r1[i]),
            .o_data (mem_real_la[i])
         );
         delay_line #(.N(9), .M(16)) mem_imag_latency_reg_i (
            .i_clk  (i_clk),
            .i_rstn (i_rstn),
            .i_data (mem_imag_r1[i]),
            .o_data (mem_imag_la[i])
         );

         delay_line #(.N(3), .M(16)) mem_mux_latency_reg_i (
            .i_clk  (i_clk),
            .i_rstn (i_rstn),
            .i_data (mem_real_la[i]),
            .o_data (mem_la_mux_i[i])
         );
         delay_line #(.N(3), .M(16)) mem_mux_latency_reg_q_i (
            .i_clk  (i_clk),
            .i_rstn (i_rstn),
            .i_data (mem_imag_la[i]),
            .o_data (mem_la_mux_q[i])
         );

         delay_line #(.N(2), .M(32)) dout_mux_latency_reg_i (
            .i_clk  (i_clk),
            .i_rstn (i_rstn),
            .i_data (dout_mux[i]),
            .o_data (dout_mux_la[i])
         );

         // -----------------------------------------------------------------
         // Sequential Logic
         // -----------------------------------------------------------------
         always_ff @(posedge i_clk) begin
            if (~i_rstn) begin
               dds_dout_r1[i] <= '0;
               prod_y_r1[i]   <= '0;
            end
            else begin
               dds_dout_r1[i] <= dds_dout[i];
               prod_y_r1[i]   <= prod_y[i];
            end
         end

         always_ff @(posedge i_clk) begin
            if (~i_rstn) begin
               prod_y_full_real_a_r1[i] <= '0;
               prod_y_full_real_b_r1[i] <= '0;
               prod_y_full_imag_a_r1[i] <= '0;
               prod_y_full_imag_b_r1[i] <= '0;
               prod_y_full_real_a_r2[i] <= '0;
               prod_y_full_real_b_r2[i] <= '0;
               prod_y_full_imag_a_r2[i] <= '0;
               prod_y_full_imag_b_r2[i] <= '0;
            end
            else begin
               prod_y_full_real_a_r1[i] <= prod_y_full_real_a[i];
               prod_y_full_real_b_r1[i] <= prod_y_full_real_b[i];
               prod_y_full_imag_a_r1[i] <= prod_y_full_imag_a[i];
               prod_y_full_imag_b_r1[i] <= prod_y_full_imag_b[i];
               prod_y_full_real_a_r2[i] <= prod_y_full_real_a_r1[i];
               prod_y_full_real_b_r2[i] <= prod_y_full_real_b_r1[i];
               prod_y_full_imag_a_r2[i] <= prod_y_full_imag_a_r1[i];
               prod_y_full_imag_b_r2[i] <= prod_y_full_imag_b_r1[i];
            end
         end

         always_ff @(posedge i_clk) begin
            if (~i_rstn) begin
               mem_real_r1[i] <= '0;
               mem_imag_r1[i] <= '0;
               last_r[i]      <= '0;
            end
            else begin
               mem_real_r1[i] <= i_mem_dout_real[i*16 +: 16];
               mem_imag_r1[i] <= i_mem_dout_imag[i*16 +: 16];
               if (en_la)
                  last_r[i]   <= round_mux[i]; // FIX (V2): per-lane indexing instead of N_DDS-1 broadcast
            end
         end

         always_ff @(posedge i_clk) begin
            if (~i_rstn) begin
               prodg_y_full_real_r1[i] <= '0;
               prodg_y_full_imag_r1[i] <= '0;
               prodg_y_full_real_r2[i] <= '0;
               prodg_y_full_imag_r2[i] <= '0;
            end
            else begin
               prodg_y_full_real_r1[i] <= prodg_y_full_real[i];
               prodg_y_full_imag_r1[i] <= prodg_y_full_imag[i];
               prodg_y_full_real_r2[i] <= prodg_y_full_real_r1[i];
               prodg_y_full_imag_r2[i] <= prodg_y_full_imag_r1[i];
            end
         end

         // -----------------------------------------------------------------
         // Combinational Datapath
         // -----------------------------------------------------------------
         assign prod_a_real[i] = dds_dout_la[i][15:0];
         assign prod_a_imag[i] = dds_dout_la[i][31:16];
         assign prod_b_real[i] = mem_real_la[i];
         assign prod_b_imag[i] = mem_imag_la[i];

         assign prod_y_full_real_a[i] = prod_a_real[i] * prod_b_real[i];
         assign prod_y_full_real_b[i] = prod_a_imag[i] * prod_b_imag[i];
         assign prod_y_full_imag_a[i] = prod_a_real[i] * prod_b_imag[i];
         assign prod_y_full_imag_b[i] = prod_a_imag[i] * prod_b_real[i];

         // Complex product: (I_dds*I_mem - Q_dds*Q_mem) + j(I_dds*Q_mem + Q_dds*I_mem)
         assign prod_y_full_real[i] = prod_y_full_real_a_r2[i] - prod_y_full_real_b_r2[i];
         assign prod_y_full_imag[i] = prod_y_full_imag_a_r2[i] + prod_y_full_imag_b_r2[i];

         // FIX (1): [30:15] preserves full signed Q15 scale
         assign prod_y_real[i] = prod_y_full_real[i][30:15];
         assign prod_y_imag[i] = prod_y_full_imag[i][30:15];
         assign prod_y[i]      = {prod_y_imag[i], prod_y_real[i]};

         // Output source mux
         assign dout_mux[i] = (src_la == 2'd0) ? prod_y_r1[i] :
                              (src_la == 2'd1) ? {dds_la_mux_q[i], dds_la_mux_i[i]} :
                              (src_la == 2'd2) ? {mem_la_mux_q[i], mem_la_mux_i[i]} :
                              32'h0000_0000;

         // Gain Stage Product
         assign prodg_a_real[i]      = dout_mux_la[i][15:0];
         assign prodg_a_imag[i]      = dout_mux_la[i][31:16];
         assign prodg_y_full_real[i] = prodg_a_real[i] * gain_la;
         assign prodg_y_full_imag[i] = prodg_a_imag[i] * gain_la;

         // FIX (V2): Explicit $signed() cast handles bit part-selects safely
         assign round_ext_real[i] = $signed(prodg_y_full_real_r2[i][31:15]);
         assign round_ext_imag[i] = $signed(prodg_y_full_imag_r2[i][31:15]);

         // Saturation Logic (+/- 32766)
         assign round_real[i] = (round_ext_real[i] >  $signed(17'sd32766)) ? 16'sd32766  :
                                (round_ext_real[i] < -$signed(17'sd32766)) ? -16'sd32766 :
                                round_ext_real[i][15:0];

         assign round_imag[i] = (round_ext_imag[i] >  $signed(17'sd32766)) ? 16'sd32766  :
                                (round_ext_imag[i] < -$signed(17'sd32766)) ? -16'sd32766 :
                                round_ext_imag[i][15:0];

         // Static I/O Selection Mux
         assign round_mux[i] = (i_outsel_reg == 1'b0) ? round_real[i] : round_imag[i];

         // Saturation Monitoring
         assign sat_lane[i] = en_la_r &
                              ((round_ext_real[i] >  $signed(17'sd32766)) ||
                              (round_ext_real[i] < -$signed(17'sd32766))  ||
                              (round_ext_imag[i] >  $signed(17'sd32766))  ||
                              (round_ext_imag[i] < -$signed(17'sd32766)));

         // Final Output Assignment per lane
         assign o_axis_tdata[i*16 +: 16] = (en_la_r == 1'b1) ? round_mux[i] :
                                           (stdy_la == 1'b0) ? last_r[i]    :
                                           16'h0000;
      end
   endgenerate

   // --------------------------------------------------------------------------
   // Latency matching lines for control signals.
   // --------------------------------------------------------------------------
   delay_line #(.N(16), .M(2)) src_latency_reg_i (
      .i_clk (i_clk), .i_rstn (i_rstn), .i_data (src_int), .o_data (src_la)
   );
   delay_line #(.N(18), .M(16)) gain_latency_reg_i (
      .i_clk (i_clk), .i_rstn (i_rstn), .i_data (gain_int), .o_data (gain_la)
   );
   delay_line #(.N(20), .M(1)) stdy_latency_reg_i (
      .i_clk (i_clk), .i_rstn (i_rstn), .i_data (stdy_int), .o_data (stdy_la)
   );
   delay_line #(.N(19), .M(1)) en_latency_reg_i (
      .i_clk (i_clk), .i_rstn (i_rstn), .i_data (en_int), .o_data (en_la)
   );

   // --------------------------------------------------------------------------
   // DDS Pipeline registers.
   // --------------------------------------------------------------------------
   always_ff @(posedge i_clk) begin
      if (~i_rstn) begin
         dds_tvalid_r   <= '0;
         dds_ctrl_int_r <= '0;
      end
      else begin
         dds_tvalid_r   <= 1'b1;
         dds_ctrl_int_r <= dds_ctrl_int;
      end
   end

   // --------------------------------------------------------------------------
   // Control Sync / Valid outputs.
   // --------------------------------------------------------------------------
   always_ff @(posedge i_clk) begin
      if (~i_rstn) begin
         mem_addr_int_r <= '0;
         en_la_r        <= '0;
      end
      else begin
         mem_addr_int_r <= mem_addr_int;
         en_la_r        <= en_la;
      end
   end

   // --------------------------------------------------------------------------
   // Top-Level Outputs.
   // --------------------------------------------------------------------------
   assign o_mem_addr    = mem_addr_int_r;
   assign o_axis_tvalid = en_la_r;
   assign o_sat         = |sat_lane;

endmodule

