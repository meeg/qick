///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
//
// Fermi National Accelerator Laboratory
//
// Module : sgv6_top
// Project: QICK arbitrary signal generator v6 (axis_signal_gen_v6)
///////////////////////////////////////////////////////////////////////////////
/**
 * @module sgv6_top
 * @brief Top-level of the v6 arbitrary signal generator.
 *
 * @description
 *   Assembles the v6 signal generator from verified building blocks:
 *     - fifo_sync         : waveform-descriptor FIFO (160-bit, depth 16).
 *     - axis_to_bram_sg_nt: AXI4-Stream envelope writer, one-hot per bank.
 *     - bram_tdp (xN_DDS) : dual-port, dual-clock envelope memories (real, and
 *                           imag when ENVELOPE_TYPE = "COMPLEX").
 *     - sgv6              : datapath (envelope x DDS, gain, output).
 *
 *   Two clock domains:
 *     - s0_axis_aclk : envelope loading (BRAM port A write side).
 *     - aclk         : descriptor FIFO, sgv6, BRAM port B read side,
 *                      and the output stream.
 *   The dual-clock BRAM (bram_tdp) resolves the crossing.
 *
 *   Envelope memory layout: N_DDS parallel banks, each 16 bits wide and 2**N
 *   deep. The envelope writer produces a shared write port (bram.we/addr/din)
 *   plus a one-hot bank select (mem_en). The 32-bit stream word is split:
 *     din[15:0]  -> real bank,  din[31:16] -> imag bank (COMPLEX only).
 *   All banks share the read address mem_addrb from sgv6; their outputs
 *   are concatenated into mem_dob_real / mem_dob_imag.
 *
 * @param N             Envelope-memory address width per bank (depth 2**N).
 * @param N_DDS         Number of parallel banks / DDS lanes.
 * @param GEN_DDS       "TRUE" up-converts with the DDS; "FALSE" baseband only.
 * @param ENVELOPE_TYPE "COMPLEX" instantiates real+imag banks; "REAL" only real
 *                      (imag output forced to zero).
 *
 * @port aresetn         Active-low reset (aclk domain).
 * @port aclk            Main clock (FIFO, sgv6, read side, output).
 * @port s0_axis_aresetn Active-low reset (envelope-load domain).
 * @port s0_axis_aclk    Envelope-load clock (BRAM port A).
 * @port s0_axis_tdata_i 32-bit envelope word: [15:0]=real, [31:16]=imag.
 * @port s0_axis_tvalid_i Envelope stream valid.
 * @port s0_axis_tready_o Envelope stream ready.
 * @port s1_axis_tdata_i 160-bit waveform descriptor.
 * @port s1_axis_tvalid_i Descriptor valid.
 * @port s1_axis_tready_o Descriptor ready (FIFO not full).
 * @port m_axis_tready_i  Output ready.
 * @port m_axis_tvalid_o  Output valid.
 * @port m_axis_tdata_o   N_DDS x 16-bit output samples.
 * @port start_addr_reg   Envelope write start address.
 * @port we_reg           Envelope write enable (capture).
 * @port o_sat            Saturation flag (1 if any output sample saturated).
 */
module sgv6_top #(
   parameter int    N             = 16,
   parameter int    N_DDS         = 16,
   parameter string GEN_DDS       = "TRUE",
   parameter string ENVELOPE_TYPE = "COMPLEX"
)(
   // Reset and clock (main domain).
   input  logic                 aresetn         ,
   input  logic                 aclk            ,
   // AXIS slave: envelope sample loading.
   input  logic                 s0_axis_aresetn ,
   input  logic                 s0_axis_aclk    ,
   input  logic [31:0]          s0_axis_tdata_i ,
   input  logic                 s0_axis_tvalid_i,
   output logic                 s0_axis_tready_o,
   // AXIS slave: waveform descriptor queue.
   input  logic [159:0]         s1_axis_tdata_i ,
   input  logic                 s1_axis_tvalid_i,
   output logic                 s1_axis_tready_o,
   // M_AXIS output.
   input  logic                 m_axis_tready_i ,
   output logic                 m_axis_tvalid_o ,
   output logic [N_DDS*16-1:0]  m_axis_tdata_o  ,
   // Registers.
   input  logic [31:0]          start_addr_reg  ,
   input  logic                 we_reg,
   output logic                 o_sat
);

   // --------------------------------------------------------------------------
   // FIFO signals.
   // --------------------------------------------------------------------------
   logic         fifo_wr_en;
   logic [159:0] fifo_din;
   logic         fifo_rd_en;
   logic [159:0] fifo_dout;
   logic         fifo_full;
   logic         fifo_empty;

   // --------------------------------------------------------------------------
   // Envelope memory: read side (aclk).
   // --------------------------------------------------------------------------
   logic [N-1:0]        mem_addrb;
   logic [N_DDS*16-1:0] mem_dob_real;
   logic [N_DDS*16-1:0] mem_dob_imag;

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

   // Per-bank write enable (one-hot) from the writer.
   logic [N_DDS-1:0] mem_en;

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
   // Envelope memories: N_DDS banks (real, + imag when COMPLEX).
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

         if (ENVELOPE_TYPE == "COMPLEX") begin : gen_imag
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
         else begin : gen_no_imag
            assign mem_dob_imag[i*16 +: 16] = 16'h0000;
         end
      end
   endgenerate

   // --------------------------------------------------------------------------
   // Signal generator datapath.
   // --------------------------------------------------------------------------
   sgv6 #(
      .N       (N),
      .N_DDS   (N_DDS),
      .GEN_DDS (GEN_DDS)
   ) sgv6_i (
      .i_rstn          (aresetn),
      .i_clk           (aclk),
      .o_fifo_rd_en    (fifo_rd_en),
      .i_fifo_empty    (fifo_empty),
      .i_fifo_dout     (fifo_dout),
      .o_mem_addr      (mem_addrb),
      .i_mem_dout_real (mem_dob_real),
      .i_mem_dout_imag (mem_dob_imag),
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
