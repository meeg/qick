///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : streamer
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    streamer.sv
//!
//! @brief   AXI4-Stream buffer: captures an input stream into a dual-clock FIFO
//!          and re-emits it in packets of nsamp_reg beats (for DMA readout).
//!
//! @details
//!
//! Register map (driven by the AXI-Lite wrapper):
//!   start_reg  RW  LEVEL enable. 0 = idle, 1 = capture and stream. It is not
//!                  a pulse: dropping it while running ends the run.
//!   flush_reg  RW  behaviour when leaving RUN with a partial packet held:
//!                  1 = drain what is left, final beat carries tlast;
//!                  0 = discard it, nothing more is emitted.
//!   mode_reg   RW  0 = one-shot (one packet, then wait for start_reg to be
//!                  toggled), 1 = continuous (back-to-back packets).
//!   nsamp_reg  RW  beats per packet. 0 keeps the block in IDLE.
//!   lost_reg   RO  input beats dropped because the FIFO was full, latched when
//!                  the block leaves RUN.
//!
//! OUTPUT BEAT REGISTER - read this before touching anything below
//!   One beat is held in {last_dout, last_dv, last_cnt}. tlast travels WITH the
//!   beat inside last_cnt, so backpressure can never separate the two.
//!
//!   In RUN, tlast is known at capture time: the popped word closes the packet
//!   when cnt == nsamp_reg_r-1. For a TRUNCATED packet (flush) it is not known
//!   at capture time: the held beat only becomes "the last one" once the FIFO
//!   has actually drained, one cycle later. last_rdy holds such a beat back
//!   until then. This is the same one-cycle stall the original had, but
//!   expressed without making tvalid depend on tready.
//!
//!   last_rdy is monotonic while a beat is held, so tvalid is never withdrawn
//!   without a handshake. The cost is one deliberate deviation from the
//!   original: with flush_reg = 0 a beat that is already on the bus completes
//!   its handshake instead of being dropped. See section 7.
//!
//! STOPPING IS NOT INSTANTANEOUS
//!   start_reg crosses two flops before the FSM sees it, so after software
//!   writes 0 the block keeps streaming normally for a few m_axis_aclk cycles.
//!   A driver must not assume the output stops on the next beat.
//!
//! BACKPRESSURE
//!   s_axis_tready is ~fifo_full and is deliberately NOT gated by the run state:
//!   this block is a passive tap and must never stall its producer. Beats
//!   offered while the block is idle are dropped silently and are NOT counted
//!   in lost_reg (only beats dropped while running are).
//!
//! PORT NAMES
//!   Do not rename the s_axis_* / m_axis_* ports: Vivado infers the AXI4-Stream
//!   interfaces from exactly these names when the IP is packaged.
//!
//! @author  QICK Development Team
//!
//! @version 2.0

`timescale 1ns/1ps

module streamer #(
    parameter int B_TDATA = 16,   //! input data payload width
    parameter int B_TUSER = 8,    //! input user side-channel width
    parameter int B_AXIS  = 32,   //! output data bus width
    parameter int N_FIFO  = 16    //! internal FIFO depth (power of two, >= 16)
) (
    // AXI4-Stream slave (input), "s" clock domain
    input  logic                s_axis_aresetn,   //! active-low reset, s domain
    input  logic                s_axis_aclk,      //! input stream clock
    input  logic                s_axis_tvalid,    //! input beat valid
    output logic                s_axis_tready,    //! input beat ready
    input  logic [B_TDATA-1:0]  s_axis_tdata,     //! input payload
    input  logic [B_TUSER-1:0]  s_axis_tuser,     //! input side-channel

    // AXI4-Stream master (output), "m" clock domain
    input  logic                m_axis_aresetn,   //! active-low reset, m domain
    input  logic                m_axis_aclk,      //! output stream clock
    output logic                m_axis_tvalid,    //! output beat valid
    input  logic                m_axis_tready,    //! output beat ready
    output logic [B_AXIS-1:0]   m_axis_tdata,     //! output payload
    output logic                m_axis_tlast,     //! end of packet

    // Control registers, m domain
    input  logic                start_reg,        //! level enable
    input  logic                flush_reg,        //! drain (1) or discard (0)
    input  logic                mode_reg,         //! 0 = one-shot, 1 = continuous
    input  logic [31:0]         nsamp_reg,        //! beats per packet
    output logic [31:0]         lost_reg,         //! dropped input beats

    output logic [31:0]         dbg_probe         //! debug probe, see bottom
);

    // -----------------------------------------------------------------------
    // Local constants
    // -----------------------------------------------------------------------
    localparam int W_FIFO = B_TDATA + B_TUSER;    //! stored word width

    //! m_axis_aclk cycles the FIFO must read empty, with the write side already
    //! stopped, before a truncated packet is declared finished. See section 7.
    localparam int DRAIN_SETTLE = 4;
    localparam int DRAIN_W      = $clog2(DRAIN_SETTLE + 1);

    typedef enum logic [1:0] {
        IDLE_ST     = 2'd0,
        RUN_ST      = 2'd1,
        WAIT_END_ST = 2'd2,
        END_ST      = 2'd3
    } state_t;

    // -----------------------------------------------------------------------
    // Internal signals
    // -----------------------------------------------------------------------
    (* fsm_encoding = "one_hot" *) state_t state;

    logic               idle_state;
    logic               run_state;
    logic               wait_end_state;

    logic [31:0]        cnt;                //! beats popped in the current packet
    logic [31:0]        cnt_full;           //! running count of dropped beats

    logic               start_reg_resync;   //! start_reg in the m domain
    logic               run_state_sclk;     //! run_state in the s domain
    logic               run_state_sclk_d;   //! delayed, for edge detection
    logic               run_state_ack;      //! run_state_sclk back in the m domain

    logic               mode_reg_r;         //! latched while stopped
    logic [31:0]        nsamp_reg_r;        //! latched while stopped
    logic [31:0]        lost_reg_r;         //! latched when leaving RUN

    logic               fifo_wr_en;
    logic [W_FIFO-1:0]  fifo_din;
    logic               fifo_rd_en;
    logic [W_FIFO-1:0]  fifo_dout;
    logic               fifo_full;
    logic               fifo_empty;

    logic [W_FIFO-1:0]  last_dout;          //! held output beat
    logic               last_dv;            //! held beat is valid
    logic               last_cnt;           //! held beat carries tlast

    logic               last_rdy;           //! held beat may be presented
    logic               out_hs;             //! output beat handshake
    logic               beat_free;          //! beat register can take a word
    logic               discard_now;        //! held beat is about to be dropped
    logic               nsamp_valid;        //! nsamp_reg_r is usable
    logic               pkt_end_capture;    //! captured beat closes the packet

    logic [DRAIN_W-1:0] drain_cnt;          //! cycles the FIFO has read empty
    logic               drain_ready;        //! a drain may now be declared over

    // -----------------------------------------------------------------------
    // 1) Control CDC
    // -----------------------------------------------------------------------
    cdc_bit_sync #(.NSTAGES(2)) u_sync_start (
        .i_clk   (m_axis_aclk     ),
        .i_rstn  (m_axis_aresetn  ),
        .i_async (start_reg       ),
        .o_sync  (start_reg_resync)
    );

    cdc_bit_sync #(.NSTAGES(2)) u_sync_run_state (
        .i_clk   (s_axis_aclk     ),
        .i_rstn  (s_axis_aresetn  ),
        .i_async (run_state       ),
        .o_sync  (run_state_sclk  )
    );

    cdc_bit_sync #(.NSTAGES(2)) u_sync_run_ack (
        .i_clk   (m_axis_aclk     ),
        .i_rstn  (m_axis_aresetn  ),
        .i_async (run_state_sclk  ),
        .o_sync  (run_state_ack   )
    );

    // -----------------------------------------------------------------------
    // 2) Dual-clock FIFO
    // -----------------------------------------------------------------------
    //! READ_MODE must be "fwft": the read path below assumes dout already holds
    //! the head word when empty is low, and treats rd_en as a pop acknowledge.
    fifo_async #(
        .B                (W_FIFO       ),
        .N                (N_FIFO       ),
        .READ_MODE        ("fwft"       ),
        .FIFO_MEMORY_TYPE ("distributed"),
        .CDC_SYNC_STAGES  (2            )
    ) u_fifo_async (
        .wr_rstn    (s_axis_aresetn),
        .wr_clk     (s_axis_aclk   ),
        .wr_en      (fifo_wr_en    ),
        .din        (fifo_din      ),
        .full       (fifo_full     ),
        .wr_err     (              ),
        .rd_rstn    (m_axis_aresetn),
        .rd_clk     (m_axis_aclk   ),
        .rd_en      (fifo_rd_en    ),
        .dout       (fifo_dout     ),
        .empty      (fifo_empty    ),
        .data_valid (              )
    );

    // -----------------------------------------------------------------------
    // 3) FIFO write control, s domain
    // -----------------------------------------------------------------------
    assign fifo_wr_en = run_state_sclk & s_axis_tvalid;
    assign fifo_din   = {s_axis_tuser, s_axis_tdata};

    // -----------------------------------------------------------------------
    // 4) FIFO read control, m domain
    // -----------------------------------------------------------------------
    //! The beat register can accept a new word when it is empty, when it is
    //! being handed over in this very cycle, or when the word it holds is
    //! going to be discarded anyway. Gating the pop with this instead of with
    //! m_axis_tready is what stops an already-presented beat from being
    //! overwritten.
    assign discard_now = wait_end_state & ~flush_reg & ~last_rdy;
    assign beat_free   = ~last_dv | out_hs | discard_now;

    //! Popping is allowed in every state except END_ST. beat_free already
    //! enforces backpressure while flushing (it needs the handshake), and makes
    assign fifo_rd_en = ~fifo_empty & beat_free & (state != END_ST);

    // -----------------------------------------------------------------------
    // 5) Lost-sample counter, s domain
    // -----------------------------------------------------------------------
    always_ff @(posedge s_axis_aclk) begin
        if (!s_axis_aresetn) begin
            cnt_full         <= 32'd0;
            lost_reg_r       <= 32'd0;
            run_state_sclk_d <= 1'b0;
        end
        else begin
            run_state_sclk_d <= run_state_sclk;

            if (!run_state_sclk && run_state_sclk_d) begin
                // Falling edge of the run state: publish the count.
                lost_reg_r <= cnt_full;
                cnt_full   <= 32'd0;
            end
            else if (run_state_sclk && s_axis_tvalid && fifo_full) begin
                cnt_full <= cnt_full + 1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // 6) Packet counter and configuration latching, m domain
    // -----------------------------------------------------------------------
    assign nsamp_valid     = (nsamp_reg_r != 32'd0);
    assign pkt_end_capture = run_state & nsamp_valid & (cnt == nsamp_reg_r - 32'd1);

    always_ff @(posedge m_axis_aclk) begin
        if (!m_axis_aresetn) begin
            cnt         <= 32'd0;
            mode_reg_r  <= 1'b0;
            nsamp_reg_r <= 32'd0;
        end
        else begin
            if (!run_state) begin
                cnt <= 32'd0;
            end
            else if (fifo_rd_en) begin
                if (pkt_end_capture) cnt <= 32'd0;
                else                 cnt <= cnt + 1;
            end

            // Configuration is only sampled while the block is stopped, so it
            // is stable for the whole run.
            if (!start_reg_resync) begin
                mode_reg_r  <= mode_reg;
                nsamp_reg_r <= nsamp_reg;
            end
        end
    end

    // -----------------------------------------------------------------------
    // 7) Output beat register (holds data + tlast together)
    // -----------------------------------------------------------------------
    //! last_rdy is the key to an AXI-legal tvalid. It says "the tlast of the
    //! beat I am holding is resolved, so it may be presented". It is only ever
    //! SET while a beat is held, never cleared, so tvalid can never be
    //! withdrawn without a handshake.
    //!
    //!   captured in RUN      -> tlast known at capture time  -> ready at once
    //!   captured in WAIT_END -> unknown, we do not yet know whether another
    //!                           word follows, so the beat is held back until
    //!                           the FIFO reveals the answer, one cycle later
    always_ff @(posedge m_axis_aclk) begin
        if (!m_axis_aresetn) begin
            last_dout <= '0;
            last_dv   <= 1'b0;
            last_cnt  <= 1'b0;
            last_rdy  <= 1'b0;
        end
        else begin
            if (!idle_state && fifo_rd_en) begin
                //! beat_free guarantees the register is free or is being handed
                //! over right now, so nothing is ever overwritten unsent.
                last_dout <= fifo_dout;
                last_cnt  <= pkt_end_capture;
                last_dv   <= 1'b1;
                last_rdy  <= run_state;
            end
            else if (out_hs) begin
                last_dv   <= 1'b0;
                last_cnt  <= 1'b0;
                last_rdy  <= 1'b0;
            end
            else if (wait_end_state && flush_reg && last_dv && !last_rdy) begin
                if (!fifo_empty) begin
                    //! another word is queued behind it: not the last beat.
                    last_rdy <= 1'b1;
                end
                else if (!run_state_ack) begin
                    //! The FIFO drained and no write is in flight: this beat
                    //! closes the truncated packet.
                    last_cnt <= 1'b1;
                    last_rdy <= 1'b1;
                end
            end

            //! Partial packet dropped when flushing is disabled. ONLY a beat
            //! that was never presented may be dropped: withdrawing tvalid
            //! would violate AXI, so a beat already on the bus completes its
            //! handshake first. This is a deliberate deviation from the
            //! original implementation, which could only ever present a beat
            //! while tready was already high.
            if (discard_now) begin
                last_dv  <= 1'b0;
                last_cnt <= 1'b0;
            end
        end
    end

    // -----------------------------------------------------------------------
    // 8) FSM, m domain
    // -----------------------------------------------------------------------
    always_ff @(posedge m_axis_aclk) begin
        if (!m_axis_aresetn) begin
            state <= IDLE_ST;
        end
        else begin
            case (state)
                IDLE_ST: begin
                    //! nsamp_reg_r == 0 would make the packet-end condition
                    //! unreachable, so the block simply refuses to start.
                    if (start_reg_resync && nsamp_valid && fifo_empty) begin
                        state <= RUN_ST;
                    end
                end

                RUN_ST: begin
                    if (!start_reg_resync) begin
                        state <= WAIT_END_ST;
                    end
                    //! End of packet detected on the beat that was ACTUALLY
                    //! delivered, not on the cycle the word was popped.
                    else if (last_cnt && out_hs && !mode_reg_r) begin
                        state <= WAIT_END_ST;      // one-shot: one packet only
                    end
                end

                WAIT_END_ST: begin
                    //! Wait for the write side to have observed the stop, then
                    //! for the pipeline to be empty.
                    if (!run_state_ack && fifo_empty && !last_dv) begin
                        state <= END_ST;
                    end
                end

                END_ST: begin
                    if (!start_reg_resync) begin
                        state <= IDLE_ST;
                    end
                end

                default: state <= IDLE_ST;
            endcase
        end
    end

    always_comb begin
        idle_state     = 1'b0;
        run_state      = 1'b0;
        wait_end_state = 1'b0;

        case (state)
            IDLE_ST:     idle_state     = 1'b1;
            RUN_ST:      run_state      = 1'b1;
            WAIT_END_ST: wait_end_state = 1'b1;
            default:     ;                        // END_ST drives nothing
        endcase
    end

    // -----------------------------------------------------------------------
    // 9) Stream outputs
    // -----------------------------------------------------------------------
    assign out_hs = m_axis_tvalid & m_axis_tready;

    //! Neither term depends on m_axis_tready, and last_rdy is monotonic while
    //! a beat is held, so tvalid is asserted only once per beat and stays up
    //! until the handshake completes.
    assign m_axis_tvalid = last_dv & last_rdy;
    assign m_axis_tdata  = {{(B_AXIS-W_FIFO){1'b0}}, last_dout};
    assign m_axis_tlast  = last_cnt;

    assign s_axis_tready = ~fifo_full;
    assign lost_reg      = lost_reg_r;

    // -----------------------------------------------------------------------
    // 10) Debug probe
    // -----------------------------------------------------------------------
    //! [7:0]   flags, note bit 3 now exposes run_state_sclk so a testbench can
    //!         tell when the WRITE side has actually started capturing.
    assign dbg_probe[ 7: 0] = {fifo_full, fifo_empty, fifo_rd_en, fifo_wr_en,
                               run_state_sclk, mode_reg_r, flush_reg, start_reg_resync};
    assign dbg_probe[15: 8] = {6'b0, state};
    assign dbg_probe[23:16] = {lost_reg_r[3:0], nsamp_reg_r[3:0]};
    assign dbg_probe[31:24] = {cnt_full[3:0], cnt[3:0]};

endmodule
