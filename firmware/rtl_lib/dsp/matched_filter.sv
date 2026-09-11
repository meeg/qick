`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : matched_filter
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    matched_filter.sv
//!
//! @brief   Time-domain matched-filter complex multiplier for
//!          axis_weighted_buffer: multiplies the incoming I/Q stream by a
//!          DMA-loaded weight envelope, sample by sample.
//!
//! @details
//!
//! Faithful port of legacy matched_filter.vhd (axis_weighted_buffer v1.3).
//! Weight envelope is loaded via a separate AXI4-Stream (s_axis, write_clk
//! domain) into a dual-clock BRAM; din_i/dout_o run in the readout domain
//! (clk). Complex multiply: dout = din * envelope, i.e.
//!   dout_i = din_i*env_i - din_q*env_q   (ac - bd)
//!   dout_q = din_i*env_q + din_q*env_i   (ad + bc)
//! Each partial product is a signed BxB multiply, truncated (not rounded)
//! to the upper B bits of the 2B-bit product -- matches the legacy
//! `filt_*_quant <= filt_*(2*B-1 downto B)` bit-select exactly, no +0.5
//! rounding constant, no saturation.
//!
//! Weight writer: reuses axis_to_bram_sg (same block already used by
//! axis_sg_int4_v2 to load its envelope table) in place of the legacy
//! data_writer.vhd instance -- both are faithful ports of the identical
//! FSM (INIT_ST -> READ_START_ADDR_ST -> WAIT_TVALID_ST -> RW_TDATA_ST),
//! confirmed by direct diff of the legacy sources. Envelope memory reuses
//! bram_tdp (1-cycle mandatory read latency per port, matching legacy
//! bram_dp.vhd) in place of bram_dp.vhd, single NB_DATA=2*B bank holding
//! packed I/Q (unlike sg_int4_top's split real/imag banks).
//!
//! Each of the 4 partial-product multiplies is modeled as a 3-cycle
//! pipelined signed multiply (input register -> product register ->
//! output register), matching the legacy `dsp_macro_0` DSP48 IP
//! configured with C_LATENCY=-1 (auto) -- the VHDL's own DSP_LATENCY=3
//! constant is the only available ground truth for this IP's actual
//! register configuration (C_REG_CONFIG's bit-packed stage count was not
//! decodable from the checked-in .xci alone), so DSP_LATENCY=3 is taken
//! as authoritative and reproduced directly rather than re-derived.
//!
//! Latency bookkeeping (WGT_LATENCY=4 din_i delay, DSP_LATENCY=3 multiply
//! pipeline, faithfully reproduced from the legacy constants): din_i for
//! the k-th valid sample reaches the multiplier at cycle k+4 relative to
//! its arrival, while the corresponding envelope word (BRAM read + 1
//! extra register, 2 cycles total) is ready at cycle k+2 -- i.e. by the
//! time din_i(k) reaches the multiplier, the envelope bus has already
//! advanced to weight index (k+2), not weight index k. This 2-sample
//! skew is a property of the legacy design as checked into
//! axis_weighted_buffer v1.3 (WGT_LATENCY does not match the envelope
//! path's own 2-cycle latency); it is reproduced exactly here rather
//! than corrected, since this is a faithful port, not a redesign -- flag
//! to hardware owners if unintended.
//!
//! CONFIRMED IN SIMULATION -- a second, separate skew: dout_valid_o (the
//! dout_valid_reg/TOTAL_LATENCY=WGT_LATENCY+DSP_LATENCY=7 chain, tracking
//! raw din_valid_i) asserts ONE CYCLE BEFORE dout_o settles to its final
//! value. dout_o is driven by filt_ii_quant_r/filt_qq_quant_r, which adds
//! one more register on top of the multiplier's own registered output
//! (ac/bd/ad/bc, valid exactly TOTAL_LATENCY cycles after din_i/trigger_i)
//! -- a stage the legacy TOTAL_LATENCY constant does not account for.
//! Reproduced exactly (see matched_filter_tc00.sv's wait_for_output,
//! which samples dout_o one cycle after dout_valid_o first pulses) rather
//! than adding a compensating delay stage the legacy avg_buffer.v/
//! buffer_top.v consumers of dout_valid_o/dout_o do not have either.
//!
//! @author  QICK Development Team
//!
//! @version 1.0
module matched_filter #(
    //! envelope BRAM address width (depth = 2**N)
    parameter int N = 10,
    //! per-component (I or Q) data width in bits
    parameter int B = 16
) (
    //! readout datapath clock (din_i/dout_o domain)
    input  logic            clk,
    //! readout datapath reset -- NOT present in the legacy VHDL (which is
    //! reset-less in this clock domain, relying on FPGA power-up initial
    //! values only); added here to give the FSM/counters a clean, testable
    //! synchronous reset, matching this session's SV convention. Tie to the
    //! same s_axis_aresetn already used by the sibling avg_top/buffer_top
    //! in the composing weighted_buffer top level.
    input  logic            rstn,

    //! weight-write domain reset/clock
    input  logic            write_rstn,
    input  logic            write_clk,

    input  logic            trigger_i,
    output logic            trigger_o,

    //! AXI4-Stream weight-programming interface (write_clk domain)
    output logic            s_axis_tready,
    input  logic [2*B-1:0]  s_axis_tdata,
    input  logic            s_axis_tvalid,

    //! Readout data in/out (clk domain)
    input  logic            din_valid_i,
    input  logic [2*B-1:0]  din_i,
    output logic [2*B-1:0]  dout_o,
    output logic            dout_valid_o,

    //! Registers
    input  logic [31:0]     len_reg,
    input  logic [31:0]     dw_addr_reg,
    input  logic            we_reg
);

    // -------------------------------------------------------------------------
    // Weight-envelope writer (write_clk domain) -- reuses axis_to_bram_sg.
    // -------------------------------------------------------------------------
    axi4_stream_if #(.TDATA_WIDTH(2*B)) axis_wr (
        .aclk    (write_clk),
        .aresetn (write_rstn)
    );

    bram_if #(.NB_DATA(2*B), .NB_ADDR(N)) bram_wr (
        .i_clk (write_clk),
        .i_rst (~write_rstn)
    );

    assign axis_wr.tdata  = s_axis_tdata;
    assign axis_wr.tvalid = s_axis_tvalid;
    assign s_axis_tready  = axis_wr.tready;
    assign axis_wr.tlast  = 1'b0;

    axis_to_bram_sg #(
        .N (N),
        .B (2*B)
    ) writer_i (
        .rstn           (write_rstn),
        .clk            (write_clk),
        .axis           (axis_wr.slave),
        .bram           (bram_wr.master),
        .start_addr_reg (dw_addr_reg),
        .capture_reg    (we_reg),
        .o_overflow     ()
    );

    // -------------------------------------------------------------------------
    // Envelope memory: dual-clock, packed I/Q (matches legacy bram_dp #(N,2*B)).
    // -------------------------------------------------------------------------
    logic [2*B-1:0] envelope_iq;
    logic [2*B-1:0] envelope_iq_r;
    logic [N-1:0]   mem_envelope_addrb;

    bram_tdp #(
        .NB_DATA (2*B),
        .NB_ADDR (N)
    ) bram_envelope_iq_i (
        .clka  (write_clk),
        .rsta  (~write_rstn),
        .ena   (1'b1),
        .wea   (bram_wr.we),
        .addra (bram_wr.addr),
        .dia   (bram_wr.din),
        .doa   (),

        .clkb  (clk),
        .rstb  (~rstn),
        .enb   (1'b1),
        .web   (1'b0),
        .addrb (mem_envelope_addrb),
        .dib   ('0),
        .dob   (envelope_iq)
    );

    // -------------------------------------------------------------------------
    // Read-address FSM (clk domain): waits for trigger, then advances the
    // envelope read pointer once per accepted input sample until len_reg
    // samples have been consumed.
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        INIT_ST = 2'd0,
        WAIT_ST = 2'd1,
        READ_ST = 2'd2
    } state_t;

    state_t        state;
    logic [31:0]   cnt;
    logic [31:0]   length;

    assign length = len_reg;
    assign mem_envelope_addrb = cnt[N-1:0];

    always_ff @(posedge clk) begin
        if (!rstn) begin
            state <= INIT_ST;
        end else begin
            unique case (state)
                INIT_ST: state <= WAIT_ST;
                WAIT_ST: if (trigger_i) state <= READ_ST;
                READ_ST: if (cnt > length) state <= INIT_ST;
                default: state <= INIT_ST;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            cnt <= '0;
        end else if (state == READ_ST) begin
            if (din_valid_i) cnt <= cnt + 1'b1;
        end else begin
            cnt <= '0;
        end
    end

    // -------------------------------------------------------------------------
    // Latency compensation: delay din_i by WGT_LATENCY cycles; delay
    // trigger_i/din_valid_i by WGT_LATENCY+DSP_LATENCY cycles total.
    // -------------------------------------------------------------------------
    localparam int WGT_LATENCY = 4;
    localparam int DSP_LATENCY = 3;
    localparam int TOTAL_LATENCY = WGT_LATENCY + DSP_LATENCY;

    logic [2*B-1:0] din_reg   [WGT_LATENCY];
    logic           trigger_reg    [TOTAL_LATENCY];
    logic           dout_valid_reg [TOTAL_LATENCY];

    always_ff @(posedge clk) begin
        if (!rstn) begin
            for (int i = 0; i < WGT_LATENCY; i++) din_reg[i] <= '0;
            for (int i = 0; i < TOTAL_LATENCY; i++) begin
                trigger_reg[i]    <= 1'b0;
                dout_valid_reg[i] <= 1'b0;
            end
        end else begin
            din_reg[0] <= din_i;
            for (int i = 1; i < WGT_LATENCY; i++)
                din_reg[i] <= din_reg[i-1];

            trigger_reg[0]    <= trigger_i;
            dout_valid_reg[0] <= din_valid_i;
            for (int i = 1; i < TOTAL_LATENCY; i++) begin
                trigger_reg[i]    <= trigger_reg[i-1];
                dout_valid_reg[i] <= dout_valid_reg[i-1];
            end
        end
    end

    logic signed [B-1:0] din_ii, din_qq;
    assign din_ii = din_reg[WGT_LATENCY-1][2*B-1:B];
    assign din_qq = din_reg[WGT_LATENCY-1][B-1:0];

    always_ff @(posedge clk) begin
        if (!rstn) envelope_iq_r <= '0;
        else       envelope_iq_r <= envelope_iq;
    end

    logic signed [B-1:0] envelope_ii, envelope_qq;
    assign envelope_ii = envelope_iq_r[2*B-1:B];
    assign envelope_qq = envelope_iq_r[B-1:0];

    // -------------------------------------------------------------------------
    // Complex multiply: 4 partial products, each a 3-cycle pipelined signed
    // multiply (matches dsp_macro_0's DSP_LATENCY=3).
    // -------------------------------------------------------------------------
    logic signed [2*B-1:0] ac, bd, ad, bc;

    mult_pipe3 #(.B (B)) mult_ac_i (.clk (clk), .rstn (rstn), .a (din_ii), .b (envelope_ii), .p (ac));
    mult_pipe3 #(.B (B)) mult_bd_i (.clk (clk), .rstn (rstn), .a (din_qq), .b (envelope_qq), .p (bd));
    mult_pipe3 #(.B (B)) mult_ad_i (.clk (clk), .rstn (rstn), .a (din_ii), .b (envelope_qq), .p (ad));
    mult_pipe3 #(.B (B)) mult_bc_i (.clk (clk), .rstn (rstn), .a (din_qq), .b (envelope_ii), .p (bc));

    logic signed [2*B-1:0] filt_ii, filt_qq;
    assign filt_ii = ac - bd;
    assign filt_qq = ad + bc;

    // Keep only the MSBs (truncate, no rounding) -- matches legacy exactly.
    logic signed [B-1:0] filt_ii_quant, filt_qq_quant;
    assign filt_ii_quant = filt_ii[2*B-1:B];
    assign filt_qq_quant = filt_qq[2*B-1:B];

    logic signed [B-1:0] filt_ii_quant_r, filt_qq_quant_r;
    always_ff @(posedge clk) begin
        if (!rstn) begin
            filt_ii_quant_r <= '0;
            filt_qq_quant_r <= '0;
        end else begin
            filt_ii_quant_r <= filt_ii_quant;
            filt_qq_quant_r <= filt_qq_quant;
        end
    end

    assign dout_o       = {filt_ii_quant_r, filt_qq_quant_r};
    assign dout_valid_o = dout_valid_reg[TOTAL_LATENCY-1];
    assign trigger_o    = trigger_reg[TOTAL_LATENCY-1];

endmodule
