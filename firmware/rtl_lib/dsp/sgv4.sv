///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
//
// Fermi National Accelerator Laboratory
//
// Module : sgv4
// Project: QICK arbitrary signal generator v4 (axis_signal_gen_v4)
///////////////////////////////////////////////////////////////////////////////
/**
 * @module sgv4
 * @brief Arbitrary signal generator datapath for v4 (8 lanes, complex output).
 *
 * @description
 *   Core datapath of the v4 signal generator. For each of N_DDS parallel lanes
 *   it reads an envelope sample from memory, up-converts it by multiplying with
 *   a DDS carrier, applies an output gain, and drives the 16-bit-per-lane
 *   complex AXI-Stream output. The ctrl_sgv4 control block sequences the
 *   operation from the waveform FIFO.
 *
 *   Differences from v6:
 *     - N_DDS = 8 (vs 16 in v6)
 *     - Complex output: I/Q pairs (32 bits per lane vs 16 bits)
 *     - DDS always present (no GEN_DDS parameter)
 *     - iqsel from descriptor bit 149 for I/Q output selection
 *
 * @param N       Envelope-memory address width in bits (default 16).
 * @param N_DDS   Number of parallel DDS lanes (default 8).
 *
 * @port i_rstn          Active-low synchronous reset.
 * @port i_clk           Clock.
 * @port o_fifo_rd_en    Read-enable to the waveform FIFO.
 * @port i_fifo_empty    FIFO empty flag.
 * @port i_fifo_dout     160-bit waveform descriptor.
 * @port o_mem_addr      Envelope-memory read address.
 * @port i_mem_dout_real N_DDS x 16-bit real (I) envelope samples.
 * @port i_mem_dout_imag N_DDS x 16-bit imag (Q) envelope samples.
 * @port i_axis_tready   Downstream ready (AXIS).
 * @port o_axis_tvalid   Output valid (AXIS).
 * @port o_axis_tdata    N_DDS x 32-bit output samples (I/Q pairs) (AXIS).
 * @port o_sat           Saturation flag.
 */
module sgv4 #(
   parameter int N     = 16,
   parameter int N_DDS = 8
)(
   // Reset and clock.
   input  logic                 i_rstn          ,
   input  logic                 i_clk           ,
   // FIFO interface.
   output logic                 o_fifo_rd_en    ,
   input  logic                 i_fifo_empty    ,
   input  logic [159:0]         i_fifo_dout     ,
   // Memory interface.
   output logic [N-1:0]         o_mem_addr      ,
   input  logic [N_DDS*16-1:0]  i_mem_dout_real ,
   input  logic [N_DDS*16-1:0]  i_mem_dout_imag ,
   // AXIS output (complex: I/Q pairs).
   input  logic                 i_axis_tready   ,
   output logic                 o_axis_tvalid   ,
   output logic [N_DDS*32-1:0]  o_axis_tdata    ,
   // Saturation flag.
   output logic                 o_sat
);

   // --------------------------------------------------------------------------
   // Internal signals.
   // --------------------------------------------------------------------------
   // Memory address.
   logic [N-1:0] mem_addr_int;
   logic [N-1:0] mem_addr_int_r;

   // DDS input control.
   logic                 dds_tvalid_r;
   logic [N_DDS*72-1:0]  dds_ctrl_int;
   logic [N_DDS*72-1:0]  dds_ctrl_int_r;

   // DDS output.
   logic [31:0] dds_dout    [N_DDS];
   logic [31:0] dds_dout_la [N_DDS];
   logic [15:0] dds_la_mux_i [N_DDS];
   logic [15:0] dds_la_mux_q [N_DDS];

   // Memory data.
   logic [15:0] mem_real_la [N_DDS];
   logic [15:0] mem_imag_la [N_DDS];
   logic [15:0] mem_la_mux_i [N_DDS];
   logic [15:0] mem_la_mux_q [N_DDS];

   // Product (complex multiplication).
   logic signed [15:0] prod_a_real     [N_DDS];
   logic signed [15:0] prod_a_imag     [N_DDS];
   logic signed [15:0] prod_b_real     [N_DDS];
   logic signed [15:0] prod_b_imag     [N_DDS];
   logic signed [31:0] prod_y_full_real_a [N_DDS];
   logic signed [31:0] prod_y_full_real_b [N_DDS];
   logic signed [31:0] prod_y_full_imag_a [N_DDS];
   logic signed [31:0] prod_y_full_imag_b [N_DDS];
   logic signed [31:0] prod_y_full_real   [N_DDS];
   logic signed [31:0] prod_y_full_imag   [N_DDS];
   logic        [15:0] prod_y_real        [N_DDS];
   logic        [15:0] prod_y_imag        [N_DDS];
   logic        [31:0] prod_y             [N_DDS];

   // Muxed output (I/Q pairs).
   logic [31:0] dout_mux    [N_DDS];

   // Product with gain (complex).
   logic        [15:0] gain_int;
   logic signed [15:0] gain_la;
   logic signed [15:0] prodg_a_real [N_DDS];
   logic signed [15:0] prodg_a_imag [N_DDS];
   logic signed [31:0] prodg_y_full_real [N_DDS];
   logic signed [31:0] prodg_y_full_imag [N_DDS];
   logic        [15:0] round_real [N_DDS];
   logic        [15:0] round_imag [N_DDS];

   // Output source selection.
   logic [1:0] src_int;
   logic [1:0] src_la;

   // Steady value selection.
   logic stdy_int;
   logic stdy_la;

   // Output enable.
   logic en_int;
   logic en_la;
   logic en_la_r;

   // Saturation detect (per lane).
   logic [N_DDS-1:0] sat_lane;

   // I/Q output selection (from descriptor).
   logic iqsel_la;

   // --------------------------------------------------------------------------
   // Control block (v4 version).
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
      .o_en         (en_int),
      .o_iqsel      (iqsel_la)   // v4 specific
   );

   // --------------------------------------------------------------------------
   // Per-lane datapath.
   // --------------------------------------------------------------------------
   generate
      for (genvar i = 0; i < N_DDS; i = i + 1) begin : gen_lane

         // DDS (Full_Range, 16-bit, latency 10). Output: {sin[15:0], cos[15:0]}.
         dds_compiler_0 dds_i (
            .aclk                (i_clk),
            .s_axis_phase_tvalid (dds_tvalid_r),
            .s_axis_phase_tdata  (dds_ctrl_int_r[i*72 +: 72]),
            .m_axis_data_tvalid  (),
            .m_axis_data_tdata   (dds_dout[i])
         );

         // Latency for dds_dout (product path).
         delay_line #(.N(1), .M(32)) dds_dout_latency_reg_i (
            .i_clk  (i_clk),
            .i_rstn (i_rstn),
            .i_data (dds_dout[i]),
            .o_data (dds_dout_la[i])
         );

         // Latency for dds_dout (mux path).
         delay_line #(.N(3), .M(16)) dds_mux_latency_reg_i (
            .i_clk  (i_clk),
            .i_rstn (i_rstn),
            .i_data (dds_dout_la[i][15:0]),   // I (cos)
            .o_data (dds_la_mux_i[i])
         );
         delay_line #(.N(3), .M(16)) dds_mux_latency_reg_q_i (
            .i_clk  (i_clk),
            .i_rstn (i_rstn),
            .i_data (dds_dout_la[i][31:16]),  // Q (sin)
            .o_data (dds_la_mux_q[i])
         );

         // Latency for real memory data (product path).
         delay_line #(.N(9), .M(16)) mem_real_latency_reg_i (
            .i_clk  (i_clk),
            .i_rstn (i_rstn),
            .i_data (i_mem_dout_real[i*16 +: 16]),
            .o_data (mem_real_la[i])
         );

         // Latency for imaginary memory data (product path).
         delay_line #(.N(9), .M(16)) mem_imag_latency_reg_i (
            .i_clk  (i_clk),
            .i_rstn (i_rstn),
            .i_data (i_mem_dout_imag[i*16 +: 16]),
            .o_data (mem_imag_la[i])
         );

         // Latency for real memory data (mux path).
         delay_line #(.N(3), .M(16)) mem_mux_latency_reg_i (
            .i_clk  (i_clk),
            .i_rstn (i_rstn),
            .i_data (mem_real_la[i]),
            .o_data (mem_la_mux_i[i])
         );

         // Latency for imaginary memory data (mux path).
         delay_line #(.N(3), .M(16)) mem_mux_latency_reg_q_i (
            .i_clk  (i_clk),
            .i_rstn (i_rstn),
            .i_data (mem_imag_la[i]),
            .o_data (mem_la_mux_q[i])
         );

         // -----------------------------------------------------------------
         // Registers for product pipeline.
         // -----------------------------------------------------------------
         logic signed [31:0] prod_y_full_real_a_r1, prod_y_full_real_b_r1;
         logic signed [31:0] prod_y_full_real_a_r2, prod_y_full_real_b_r2;
         logic signed [31:0] prod_y_full_imag_a_r1, prod_y_full_imag_b_r1;
         logic signed [31:0] prod_y_full_imag_a_r2, prod_y_full_imag_b_r2;
         logic [31:0] prod_y_r1;

         always_ff @(posedge i_clk) begin
            if (~i_rstn) begin
               prod_y_full_real_a_r1 <= '0;
               prod_y_full_real_b_r1 <= '0;
               prod_y_full_imag_a_r1 <= '0;
               prod_y_full_imag_b_r1 <= '0;
               prod_y_full_real_a_r2 <= '0;
               prod_y_full_real_b_r2 <= '0;
               prod_y_full_imag_a_r2 <= '0;
               prod_y_full_imag_b_r2 <= '0;
               prod_y_r1 <= '0;
            end
            else begin
               prod_y_full_real_a_r1 <= prod_y_full_real_a[i];
               prod_y_full_real_b_r1 <= prod_y_full_real_b[i];
               prod_y_full_imag_a_r1 <= prod_y_full_imag_a[i];
               prod_y_full_imag_b_r1 <= prod_y_full_imag_b[i];
               prod_y_full_real_a_r2 <= prod_y_full_real_a_r1;
               prod_y_full_real_b_r2 <= prod_y_full_real_b_r1;
               prod_y_full_imag_a_r2 <= prod_y_full_imag_a_r1;
               prod_y_full_imag_b_r2 <= prod_y_full_imag_b_r1;
               prod_y_r1 <= prod_y[i];
            end
         end

         // -----------------------------------------------------------------
         // Combinational assignments.
         // -----------------------------------------------------------------
         // Product: complex multiplication
         assign prod_a_real[i] = dds_dout_la[i][15:0];
         assign prod_a_imag[i] = dds_dout_la[i][31:16];
         assign prod_b_real[i] = mem_real_la[i];
         assign prod_b_imag[i] = mem_imag_la[i];

         // Partial products.
         assign prod_y_full_real_a[i] = prod_a_real[i] * prod_b_real[i];
         assign prod_y_full_real_b[i] = prod_a_imag[i] * prod_b_imag[i];
         assign prod_y_full_imag_a[i] = prod_a_real[i] * prod_b_imag[i];
         assign prod_y_full_imag_b[i] = prod_a_imag[i] * prod_b_real[i];

         // Complex product: (a_real*b_real - a_imag*b_imag) + j(a_real*b_imag + a_imag*b_real)
         assign prod_y_full_real[i] = prod_y_full_real_a_r2 - prod_y_full_real_b_r2;
         assign prod_y_full_imag[i] = prod_y_full_imag_a_r2 + prod_y_full_imag_b_r2;

         // FIX: [30:15] keeps full Q15 scale (was [31:16] in original v4).
         assign prod_y_real[i] = prod_y_full_real[i][30:15];
         assign prod_y_imag[i] = prod_y_full_imag[i][30:15];
         assign prod_y[i]      = {prod_y_imag[i], prod_y_real[i]};

         // Output source mux (I/Q pairs).
         assign dout_mux[i] = (src_la == 0) ? prod_y_r1 :
                              (src_la == 1) ? {dds_la_mux_q[i], dds_la_mux_i[i]} :
                              (src_la == 2) ? {mem_la_mux_q[i], mem_la_mux_i[i]} :
                              32'h0000_0000;

         // Product with gain (complex).
         logic [31:0] dout_mux_la;
         delay_line #(.N(2), .M(32)) dout_mux_gain_latency_reg_i (
            .i_clk  (i_clk),
            .i_rstn (i_rstn),
            .i_data (dout_mux[i]),
            .o_data (dout_mux_la)
         );

         assign prodg_a_real[i] = dout_mux_la[15:0];
         assign prodg_a_imag[i] = dout_mux_la[31:16];
         assign prodg_y_full_real[i] = prodg_a_real[i] * gain_la;
         assign prodg_y_full_imag[i] = prodg_a_imag[i] * gain_la;

         // Rounding with saturation (clamp to +/- MAXV).
         logic signed [16:0] round_ext_real, round_ext_imag;
         logic [15:0] prodg_real_r1, prodg_imag_r1;
         logic [15:0] prodg_real_r2, prodg_imag_r2;

         always_ff @(posedge i_clk) begin
            if (~i_rstn) begin
               prodg_real_r1 <= '0;
               prodg_imag_r1 <= '0;
               prodg_real_r2 <= '0;
               prodg_imag_r2 <= '0;
            end
            else begin
               prodg_real_r1 <= prodg_y_full_real[i][30:15];
               prodg_imag_r1 <= prodg_y_full_imag[i][30:15];
               prodg_real_r2 <= prodg_real_r1;
               prodg_imag_r2 <= prodg_imag_r1;
            end
         end

         assign round_ext_real = {prodg_real_r2[15], prodg_real_r2};
         assign round_ext_imag = {prodg_imag_r2[15], prodg_imag_r2};

         assign round_real[i] = (round_ext_real >  $signed(17'sd32766)) ? 16'sd32766 :
                                (round_ext_real < -$signed(17'sd32766)) ? -16'sd32766 :
                                prodg_real_r2;
         assign round_imag[i] = (round_ext_imag >  $signed(17'sd32766)) ? 16'sd32766 :
                                (round_ext_imag < -$signed(17'sd32766)) ? -16'sd32766 :
                                prodg_imag_r2;

         // Saturation flag for this lane.
         assign sat_lane[i] = en_la_r &
                              ((round_ext_real >  17'sd32766) ||
                               (round_ext_real < -17'sd32766) ||
                               (round_ext_imag >  17'sd32766) ||
                               (round_ext_imag < -17'sd32766));

         // Output: I/Q selection.
         logic [31:0] last_r;
         always_ff @(posedge i_clk) begin
            if (~i_rstn)
               last_r <= '0;
            else if (en_la)
               last_r <= {round_imag[N_DDS-1], round_real[N_DDS-1]};
         end

         // iqsel_la: 0 = I/Q output, 1 = I only (Q=0)
         assign o_axis_tdata[i*32 +: 32] = (en_la_r == 1'b1) ?
                                           ((iqsel_la == 1'b0) ? {round_imag[i], round_real[i]} :
                                                                  {16'h0000, round_real[i]}) :
                                           (stdy_la == 1'b0) ? last_r :
                                           32'h0000_0000;
      end
   endgenerate

   // --------------------------------------------------------------------------
   // Latency lines for control signals.
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
   // DDS input control register.
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
   // Memory address / output enable registers.
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
   // Outputs.
   // --------------------------------------------------------------------------
   assign o_mem_addr    = mem_addr_int_r;
   assign o_axis_tvalid = en_la_r;
   assign o_sat         = |sat_lane;

endmodule

