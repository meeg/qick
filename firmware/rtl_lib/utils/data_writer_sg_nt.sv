///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : data_writer_sg_nt
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    data_writer_sg_nt.sv
//!
//! @brief   AXI Stream to NT BRAM writer. Identical FSM and pipeline to
//!
//! @details
//!
//! data_writer_sg but drives NT memories by splitting the full address into:
//!
//! mem_addr_full[NT_LOG2-1        : 0]       → mem_addr_low  → mem_en[NT]
//! mem_addr_full[NT_LOG2+N-1      : NT_LOG2] → mem_addr_high → mem_addr
//!
//! Only one of the NT mem_en lines is asserted per cycle; the low address
//! bits act as a one-hot demux. All NT memories share mem_we, mem_addr,
//! and mem_di.
//!
//! FSM: INIT_ST → READ_START_ADDR_ST → WAIT_TVALID_ST → RW_TDATA_ST
//! (identical to data_writer_sg)
//!
//! @note    Ported from axis_signal_gen_v6/src/data_writer.vhd
//!
//! @author  QICK Development Team
//!
//! @version 1.0
`timescale 1ns/1ps

module data_writer_sg_nt #(
  //! number of tables (must be a power of 2)
  parameter int NT = 16,
  //! address width per table (depth = 2**N)
  parameter int N  = 16,
  //! data width in bits
  parameter int B  = 16
) (
  input  logic              rstn,
  input  logic              clk,

  // AXI Stream input
  output logic              s_axis_tready,
  input  logic [B-1:0]      s_axis_tdata,
  input  logic              s_axis_tvalid,

  // Memory interface — NT independent enables, shared addr/data/we
  output logic [NT-1:0]     mem_en,
  output logic              mem_we,
  output logic [N-1:0]      mem_addr,
  output logic [B-1:0]      mem_di,

  // Registers (may come from a different clock domain)
  input  logic [31:0]       start_addr_reg,
  input  logic              we_reg
);

  // -------------------------------------------------------------------------
  // Derived parameter
  // -------------------------------------------------------------------------
  localparam int NT_LOG2 = $clog2(NT);

  // -------------------------------------------------------------------------
  // CDC: synchronise we_reg into clk domain
  // -------------------------------------------------------------------------
  logic we_reg_resync;

  cdc_gray_sync #(
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
  // Memory address signals
  // -------------------------------------------------------------------------
  logic [NT_LOG2+N-1:0] mem_addr_full;
  logic [NT_LOG2-1:0]   mem_addr_low;
  logic [N-1:0]         mem_addr_high;
  logic [N-1:0]         mem_addr_high_r;

  // mem_en combinational and registered
  logic [NT-1:0]        mem_en_i;
  logic [NT-1:0]        mem_en_r;

  // -------------------------------------------------------------------------
  // mem_en demux (combinational): assert bit I when mem_addr_low == I
  // -------------------------------------------------------------------------
  always_comb
  begin
    mem_en_i = '0;
    for (int i = 0; i < NT; i++)
    begin
      if (mem_addr_low == NT_LOG2'(i))
        mem_en_i[i] = 1'b1;
    end
  end

  // -------------------------------------------------------------------------
  // Address split (combinational)
  // -------------------------------------------------------------------------
  assign mem_addr_low  = mem_addr_full[NT_LOG2-1:0];
  assign mem_addr_high = mem_addr_full[NT_LOG2+N-1:NT_LOG2];

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
      mem_addr_high_r <= '0;
      mem_en_r        <= '0;
    end
    else
    begin
      if (!we_reg_resync && (state != RW_TDATA_ST))
      begin
        // If we_reg deasserts outside of RW_TDATA_ST, reset datapath registers
        // to ensure no writes occur and that we start with a clean slate
        // when we_reg next asserts. If we_reg deasserts during RW_TDATA_ST,
        // we allow the current write
        tvalid_r  <= 1'b0;
        tvalid_rr <= 1'b0;
        tvalid_rrr<= 1'b0;
        tdata_r   <= '0;
        tdata_rr  <= '0;
        tdata_rrr <= '0;
        mem_en_r  <= '0;
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
          mem_addr_full <= (NT_LOG2+N)'(start_addr_reg);
        else if (rw_tdata_state)
          mem_addr_full <= mem_addr_full + 1'b1;

        // Register high address and enable for output pipeline
        mem_addr_high_r <= mem_addr_high;
        mem_en_r        <= rw_tdata_state ? mem_en_i : '0;
      end
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
          if (!tvalid_r)
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
        ;
      READ_START_ADDR_ST:
        read_start_addr_state = 1'b1;
      //WAIT_TVALID_ST:     tready_i              = 1'b1;
      WAIT_TVALID_ST:
        tready_i              = we_reg_resync; // only ready when we_reg is still asserted
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
  // gate mem_en with we_reg to ensure no writes when we_reg deasserts
  assign mem_en        = mem_en_r & {NT{we_reg_resync}};
  assign mem_we        = tvalid_rrr & we_reg_resync;
  assign mem_addr      = mem_addr_high_r;
  assign mem_di        = tdata_rrr;

endmodule
