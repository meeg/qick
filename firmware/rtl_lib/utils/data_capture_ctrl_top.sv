///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : data_capture_ctrl_top
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    data_capture_ctrl_top.sv
//!
//! @brief   TODO: one-line description.
//!
//! @author  QICK Development Team
//!
//! @version 1.0

module data_capture_ctrl_top #(
    //! memory depth as 2**N
    parameter int N = 10,  // Memory depth (2**N)
    //! memory data width
    parameter int B = 16   // Number of bits
  ) (
    // Reset and clock
    input  logic rstn,
    input  logic clk,

    // Trigger input
    input  logic trigger_i,

    // Data input
    input  logic din_valid_i,
    input  logic [2*B-1:0] din_i,

    // AXIS Master for output
    input  logic m_axis_aclk,
    input  logic m_axis_aresetn,
    output logic m_axis_tvalid,
    input  logic m_axis_tready,
    output logic [2*B-1:0] m_axis_tdata,
    output logic m_axis_tlast,

    // Registers (renamed to snake_case for lint)
    input  logic buf_start_reg,
    input  logic [N-1:0] buf_addr_reg,
    input  logic [N-1:0] buf_len_reg,
    input  logic         dr_start_reg,
    input  logic [N-1:0] dr_addr_reg,
    input  logic [N:0]   dr_len_reg
  );

  //////////////////////////////////////////////////////////////////////////////
  // Internal signals
  //////////////////////////////////////////////////////////////////////////////
  logic mem_we_int;
  logic [N-1:0] mem_addra_int, mem_addrb_int;
  logic [2*B-1:0] mem_di_int, mem_do_int;

  logic buf_start_reg_resync;
  logic dr_start_reg_resync;

  //////////////////////////////////////////////////////////////////////////////
  // Architecture
  //////////////////////////////////////////////////////////////////////////////

  // buf_start_reg_resync
  sync_nxm #(
              .N (2),
              .M (1)
            ) buf_start_reg_resync_i (
              .i_rstn (rstn),
              .i_clk  (clk),
              .i_d    (buf_start_reg),
              .o_d    (buf_start_reg_resync)
            );

  // dr_start_reg_resync
  sync_nxm #(
              .N (2),
              .M (1)
            ) dr_start_reg_resync_i (
              .i_rstn (m_axis_aresetn),
              .i_clk  (m_axis_aclk),
              .i_d    (dr_start_reg),
              .o_d    (dr_start_reg_resync)
            );

  // data_capture_ctrl block
  data_capture_ctrl #(
          .N (N),
          .B (B)
        ) data_capture_ctrl_i (
          // Reset and clock
          .rstn        (rstn),
          .clk         (clk),

          // Trigger input
          .trigger_i   (trigger_i),

          // Data input
          .din_valid_i (din_valid_i),
          .din_i       (din_i),

          // Memory interface
          .mem_we_o    (mem_we_int),
          .mem_addr_o  (mem_addra_int),
          .mem_di_o    (mem_di_int),

          // Registers
          .start_reg   (buf_start_reg_resync),
          .addr_reg    (buf_addr_reg),
          .len_reg     (buf_len_reg)
        );

  // Dual port BRAM
  bram_dp #(
            .N (N),
            .B (2*B)
          ) bram_i (
            .clka  (clk),
            .clkb  (m_axis_aclk),
            .ena   (1'b1),
            .enb   (1'b1),
            .wea   (mem_we_int),
            .web   (1'b0),
            .addra (mem_addra_int),
            .addrb (mem_addrb_int),
            .dia   (mem_di_int),
            .dib   ({2*B{1'b0}}), // Replaced 4*B with 2*B to match width, could also use '0
            .doa   (),
            .dob   (mem_do_int)
          );

  // Data reader
  data_reader #(
                .N (N),
                .B (2*B)
              ) data_reader_i (
                // Reset and clock
                .rstn      (m_axis_aresetn),
                .clk       (m_axis_aclk),

                // Memory I/F
                .mem_en    (),
                .mem_we    (),
                .mem_addr  (mem_addrb_int),
                .mem_dout  (mem_do_int),

                // Data out
                .dout      (m_axis_tdata),
                .dready    (m_axis_tready),
                .dvalid    (m_axis_tvalid),
                .dlast     (m_axis_tlast),

                // Registers
                .start_reg (dr_start_reg_resync),
                .addr_reg  (dr_addr_reg),
                .len_reg   (dr_len_reg)
              );

endmodule
