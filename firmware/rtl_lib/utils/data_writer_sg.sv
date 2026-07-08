///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : data_writer_sg
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    data_writer_sg.sv
//!
//! @brief   AXI Stream to single BRAM writer with configurable start
//!
//! @details
//!
//! address. Receives a continuous stream and writes it to memory starting
//! at START_ADDR_REG. WE_REG enables/disables writing and comes from a
//! different clock domain — synchronised internally with sync_nxm.
//!
//! FSM: INIT_ST → READ_START_ADDR_ST → WAIT_TVALID_ST → RW_TDATA_ST
//!
//! Pipeline: 3 register stages (tdata_r/rr/rrr, tvalid_r/rr/rrr) align
//! data with the FSM state transitions before writing to memory.
//!
//! @note    Ported from axis_sg_int4_v2/src/data_writer.vhd
//!
//! @author  QICK Development Team
//!
//! @version 1.0
`timescale 1ns/1ps

module data_writer_sg #(
  //! memory address width (depth = 2**N)
  parameter int N = 16,
  //! data width in bits
  parameter int B = 16
) (
  input  logic             rstn,
  input  logic             clk,

  // AXI Stream input
  output logic             s_axis_tready,
  input  logic [B-1:0]     s_axis_tdata,
  input  logic             s_axis_tvalid,

  // Memory interface
  output logic             mem_en,
  output logic             mem_we,
  output logic [N-1:0]     mem_addr,
  output logic [B-1:0]     mem_di,

  // Registers (may come from a different clock domain)
  input  logic [31:0]      start_addr_reg,
  input  logic             we_reg
);

  // -------------------------------------------------------------------------
  // CDC: synchronise we_reg into clk domain
  // -------------------------------------------------------------------------
  logic we_reg_resync;

  sync_nxm #(
    .N (2),
    .M (1)
  ) we_reg_sync_i (
    .i_clk  (clk),
    .i_rstn (rstn),
    .i_d    (we_reg),
    .o_d    (we_reg_resync)
  );

  // -------------------------------------------------------------------------
  // FSM state encoding
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] {
    INIT_ST            = 2'd0,
    READ_START_ADDR_ST = 2'd1,
    WAIT_TVALID_ST     = 2'd2,
    RW_TDATA_ST        = 2'd3
  } state_t;

  state_t state;

  // -------------------------------------------------------------------------
  // FSM output decode
  // -------------------------------------------------------------------------
  logic read_start_addr_state;
  logic rw_tdata_state;
  logic tready_i;

  // -------------------------------------------------------------------------
  // AXI Stream pipeline registers
  // -------------------------------------------------------------------------
  logic             tready_r;
  logic [B-1:0]     tdata_r, tdata_rr, tdata_rrr;
  logic             tvalid_r, tvalid_rr, tvalid_rrr;

  // -------------------------------------------------------------------------
  // Memory address
  // -------------------------------------------------------------------------
  logic [N-1:0] mem_addr_full;
  logic [N-1:0] mem_addr_full_r;

  // -------------------------------------------------------------------------
  // Datapath registers
  // -------------------------------------------------------------------------
  always_ff @(posedge clk)
  begin
    if (!rstn)
    begin
      tready_r        <= '0;
      tdata_r         <= '0;
      tdata_rr        <= '0;
      tdata_rrr       <= '0;
      tvalid_r        <= '0;
      tvalid_rr       <= '0;
      tvalid_rrr      <= '0;
      mem_addr_full   <= '0;
      mem_addr_full_r <= '0;
    end
    else
    begin
      // Stage 1: sample AXI inputs
      tready_r  <= tready_i;
      tdata_r   <= s_axis_tdata;
      tvalid_r  <= s_axis_tvalid;

      // Stage 2 & 3: pipeline to align with FSM latency
      tdata_rr   <= tdata_r;
      tdata_rrr  <= tdata_rr;
      tvalid_rr  <= tvalid_r;
      tvalid_rrr <= tvalid_rr;

      // Address: latch start address or increment
      if (read_start_addr_state)
        mem_addr_full <= start_addr_reg[N-1:0];
      else if (rw_tdata_state && tvalid_rr)
        mem_addr_full <= mem_addr_full + 1'b1;

      mem_addr_full_r <= mem_addr_full;
    end
  end

  // -------------------------------------------------------------------------
  // FSM
  // -------------------------------------------------------------------------
  always_ff @(posedge clk)
  begin
    if (!rstn)
    begin
      state <= INIT_ST;
    end
    else
    begin
      unique case (state)
        INIT_ST:
          if (we_reg_resync)
            state <= READ_START_ADDR_ST;

        READ_START_ADDR_ST:
          state <= WAIT_TVALID_ST;

        WAIT_TVALID_ST:
          if (!we_reg_resync)
            state <= INIT_ST;
          else if (tvalid_r)
            state <= RW_TDATA_ST;

        RW_TDATA_ST:
          if (!we_reg_resync)
            state <= INIT_ST;
          else if (!tvalid_r)
            state <= WAIT_TVALID_ST;

        default:
          state <= INIT_ST;
      endcase
    end
  end

  // -------------------------------------------------------------------------
  // FSM output decode (combinational)
  // -------------------------------------------------------------------------
  always_comb
  begin
    read_start_addr_state = 1'b0;
    rw_tdata_state        = 1'b0;
    tready_i              = 1'b0;

    unique case (state)
      INIT_ST:
        ; // no outputs
      READ_START_ADDR_ST:
        read_start_addr_state = 1'b1;
      WAIT_TVALID_ST:
        tready_i              = 1'b1;
      RW_TDATA_ST:
        begin
          rw_tdata_state = 1'b1;
          tready_i       = 1'b1;
        end
      default:
        ;
    endcase
  end

  // -------------------------------------------------------------------------
  // Output assignments
  // -------------------------------------------------------------------------
  assign s_axis_tready = tready_r;
  assign mem_en        = 1'b1;
  assign mem_we        = tvalid_rrr;
  assign mem_addr      = mem_addr_full_r;
  assign mem_di        = tdata_rrr;

endmodule
