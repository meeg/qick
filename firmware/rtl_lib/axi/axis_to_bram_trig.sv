///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : axis_to_bram_trig
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    axis_to_bram_trig.sv
//!
//! @brief   Triggered AXI4-Stream to BRAM capture block. Waits for an
//!
//! @details
//!
//! external hardware trigger, then captures exactly 2**N samples from the
//! AXI4-Stream input into memory starting at address 0. Uses an internal
//! FIFO to decouple the stream from memory timing.
//!
//! FSM: INIT_ST → TRIGGER_ST → CAPTURE_ST → END_ST
//!
//! INIT_ST    : wait for capture_reg=1
//! TRIGGER_ST : wait for trigger pulse
//! CAPTURE_ST : capture 2**N samples via FIFO into BRAM
//! END_ST     : wait for capture_reg=0 and FIFO to drain before returning
//!
//! Interfaces:
//! axis  : axi4_stream_if.slave  — incoming data stream
//! bram  : bram_if.master        — write-only BRAM port (en=1, we gated)
//!
//! @note    Ported from mr_buffer_et/src/data_writer.vhd
//!
//! @author  QICK Development Team
//!
//! @version 1.0
`timescale 1ns/1ps

module axis_to_bram_trig #(
  //! BRAM address width (capture depth = 2**N samples)
  parameter int N = 8,
  //! data width in bits (must match bram_if.NB_DATA and axis N_BYTES*8)
  parameter int B = 16
) (
  input  logic         rstn,
  input  logic         clk,

  // Hardware trigger
  input  logic         trigger,

  // AXI4-Stream slave — incoming data
  output logic         s_axis_tready,
  input  logic [B-1:0] s_axis_tdata,
  input  logic         s_axis_tvalid,
  input  logic         s_axis_tlast,

  // BRAM master — write only
  output logic         mem_en,
  output logic         mem_we,
  output logic [N-1:0] mem_addr,
  output logic [B-1:0] mem_di,

  // Software control register
  input  logic         capture_reg
);

  // -------------------------------------------------------------------------
  // FSM state encoding
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] {
    INIT_ST    = 2'd0,
    TRIGGER_ST = 2'd1,
    CAPTURE_ST = 2'd2,
    END_ST     = 2'd3
  } state_t;

  state_t current_state, next_state;

  // -------------------------------------------------------------------------
  // FSM output
  // -------------------------------------------------------------------------
  logic write_en;

  // -------------------------------------------------------------------------
  // Internal FIFO signals
  // -------------------------------------------------------------------------
  logic         fifo_wr_en;
  logic         fifo_rd_en;
  logic [B-1:0] fifo_dout;
  logic         fifo_full;
  logic         fifo_empty;

  // -------------------------------------------------------------------------
  // Address counter and registered memory outputs
  // -------------------------------------------------------------------------
  logic [N-1:0] addr_cnt;
  logic         mem_we_r;
  logic [N-1:0] mem_addr_r;
  logic [B-1:0] mem_di_r;

  // -------------------------------------------------------------------------
  // Internal FIFO (depth=16, FWFT mode)
  // -------------------------------------------------------------------------
  fifo_sync #(
    .B (B),
    .N (16)
  ) fifo_i (
    .rstn  (rstn),
    .clk   (clk),
    .wr_en (fifo_wr_en),
    .din   (s_axis_tdata[B-1:0]),
    .rd_en (fifo_rd_en),
    .dout  (fifo_dout),
    .full  (fifo_full),
    .empty (fifo_empty)
  );

  // -------------------------------------------------------------------------
  // FIFO control
  // -------------------------------------------------------------------------
  // Write to FIFO only when capturing and stream is valid
  assign fifo_wr_en = write_en & s_axis_tvalid;

  // Read FIFO during capture (write to BRAM) or end (drain leftovers)
  assign fifo_rd_en = (current_state == CAPTURE_ST ||
                      current_state == END_ST) && ~fifo_empty;

  // -------------------------------------------------------------------------
  // AXI4-Stream backpressure
  // -------------------------------------------------------------------------
  assign s_axis_tready = write_en & ~fifo_full;

  // -------------------------------------------------------------------------
  // Sequential: FSM + address counter + memory pipeline
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rstn) begin
      current_state <= INIT_ST;
      addr_cnt      <= '0;
      mem_we_r      <= '0;
      mem_addr_r    <= '0;
      mem_di_r      <= '0;
    end else begin
      current_state <= next_state;

      if (write_en) begin
        if (~fifo_empty) begin
          // Capture pre-increment address and current FIFO output
          mem_addr_r <= addr_cnt;
          mem_we_r   <= 1'b1;
          mem_di_r   <= fifo_dout;
          addr_cnt   <= addr_cnt + 1'b1;
        end else begin
          mem_we_r   <= 1'b0;
        end
      end else begin
        addr_cnt   <= '0;
        mem_we_r   <= 1'b0;
        mem_addr_r <= '0;
        mem_di_r   <= '0;
      end
    end
  end

  // -------------------------------------------------------------------------
  // Next-state logic (combinational)
  // -------------------------------------------------------------------------
  always_comb begin
    next_state = current_state;

    unique case (current_state)
      INIT_ST:
        if (capture_reg) next_state = TRIGGER_ST;

      TRIGGER_ST:
        // Let the FSM abort if trigger is cancelled
        if (!capture_reg) next_state = INIT_ST;
        else if (trigger) next_state = CAPTURE_ST;

      CAPTURE_ST:
        // Abort if capture_reg goes low, or finish if BRAM is full
        if (!capture_reg)
          next_state = END_ST;
        else if ((addr_cnt == '1) && ~fifo_empty)
          next_state = END_ST;

      END_ST:
        if (!capture_reg && fifo_empty) next_state = INIT_ST;

      default: next_state = INIT_ST;
    endcase
  end

  // -------------------------------------------------------------------------
  // FSM output decode (combinational)
  // -------------------------------------------------------------------------
  always_comb begin
    write_en = 1'b0;
    unique case (current_state)
      CAPTURE_ST: write_en = 1'b1;
      default:    write_en = 1'b0;
    endcase
  end

  // -------------------------------------------------------------------------
  // BRAM interface output assignments
  // -------------------------------------------------------------------------
  assign mem_en   = 1'b1;
  assign mem_we   = mem_we_r;
  assign mem_addr = mem_addr_r;
  assign mem_di   = mem_di_r;

endmodule
