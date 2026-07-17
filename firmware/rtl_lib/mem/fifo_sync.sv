///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : fifo_sync
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    fifo_sync.sv
//!
//! @brief   TODO: one-line description.
//!
//! @author  QICK Development Team
//!
//! @version 1.0
module fifo_sync #(
    parameter int    B                = 16,     // Data width
    parameter int    N                = 16,     // FIFO depth (Must be power of 2, minimum 16)
    parameter        USE_ADV_FEATURES = "1707", // Hex string to enable advanced features (untyped param for XPM compat)
    parameter bit    ENABLE_COUNTERS  = 1       // 1: Enable data counts (requires CNT_WIDTH), 0: Disabled (width=1)
)(
    input  logic         rstn,
    input  logic         clk,

    // Write I/F
    input  logic         wr_en,
    input  logic [B-1:0] din,

    // Read I/F
    input  logic         rd_en,
    output logic [B-1:0] dout,

    // Standard Flags
    output logic         full,
    output logic         empty,

    // Optional Advanced Features Ports (Hooked up dynamically)
    output logic [ (ENABLE_COUNTERS ? ($clog2(N)+1) : 1)-1:0] wr_data_count,
    output logic [ (ENABLE_COUNTERS ? ($clog2(N)+1) : 1)-1:0] rd_data_count,
    output logic         prog_full,
    output logic         prog_empty,
    output logic         wr_err,       // Overflow flag
    output logic         rd_err        // Underflow flag
);

    // Validate parameters at elaboration time
    initial begin
        if (N < 16 || (N & (N-1)) != 0) begin
            $error("fifo_sync: N must be a power of 2 and >= 16, got %0d", N);
            $finish;
        end
    end

    // Dynamically resolve counter width to satisfy Xilinx DRC rules
    localparam int CNT_WIDTH = ENABLE_COUNTERS ? ($clog2(N) + 1) : 1;

    // ============================================================
    // XPM FIFO internal signals
    // ============================================================
    logic [B-1:0] dout_i;
    logic         full_i;
    logic         empty_i;
    logic         wr_rst_busy;
    logic         rd_rst_busy;

  // ============================================================
  // XPM FIFO instance
  // ============================================================
  // =========================================================================
  // NOTE ON EFFECTIVE FIFO DEPTH (FWFT Mode Capacity)
  // =========================================================================
  // When configured in First-Word Fall-Through (FWFT) mode ("READ_MODE = fwft"
  // and "FIFO_READ_LATENCY = 0"), the XPM FIFO allocates additional internal
  // pipeline registers to expose the first written word immediately at 'dout'
  // without compromising timing closure.
  //
  // As a result, the effective storage capacity of the FIFO increases beyond
  // the user-specified parameter N (FIFO_WRITE_DEPTH). For instance, with N=16,
  // the FIFO actually stores up to N + 2 (18) words before asserting the 'full'
  // flag.
  //
  // This is the expected, native behavior of the Xilinx XPM memory macro.
  // Testbenches and downstream logic must dynamically rely on the 'full' and
  // 'empty' status flags rather than assuming a hardcoded capacity of exactly N.
  // =========================================================================
    xpm_fifo_sync #(
        .DOUT_RESET_VALUE      ("0"),
        .ECC_MODE              ("no_ecc"),
        .FIFO_MEMORY_TYPE      ("auto"),
        .FIFO_READ_LATENCY      (0),                 // 0 for FWFT mode
        .FIFO_WRITE_DEPTH      (N),
        .FULL_RESET_VALUE      (0),
        .PROG_EMPTY_THRESH     (5),                 // Safe default threshold
        .PROG_FULL_THRESH      (N-5),               // Safe default threshold
        .RD_DATA_COUNT_WIDTH   (CNT_WIDTH),         // Scaled dynamically
        .READ_DATA_WIDTH       (B),
        .READ_MODE             ("fwft"),            // First Word Fall Through
        .USE_ADV_FEATURES      (USE_ADV_FEATURES),  // Dynamic string assignment
        .WAKEUP_TIME           (0),
        .WRITE_DATA_WIDTH      (B),
        .WR_DATA_COUNT_WIDTH   (CNT_WIDTH)          // Scaled dynamically
    ) xpm_fifo_sync_inst (
        .sleep         (1'b0),

        // Write side
        .wr_clk        (clk),
        .wr_en         (wr_en & ~wr_rst_busy),
        .din           (din),
        .full          (full_i),
        .prog_full     (prog_full),
        .wr_data_count (wr_data_count),

        // Read side
        .rd_en         (rd_en & ~rd_rst_busy),
        .dout          (dout_i),
        .empty         (empty_i),
        .prog_empty    (prog_empty),
        .rd_data_count (rd_data_count),

        // Misc / Error flags
        .rst           (~rstn),
        .wr_rst_busy   (wr_rst_busy),
        .rd_rst_busy   (rd_rst_busy),
        .data_valid    (),
        .underflow     (rd_err),
        .overflow      (wr_err),
        .almost_full   (),
        .almost_empty  (),
        .sbiterr       (),
        .dbiterr       (),
        .injectsbiterr (1'b0),
        .injectdbiterr (1'b0)
    );

    // ============================================================
    // Output mapping
    // ============================================================
    assign dout  = dout_i;
    assign full  = full_i;
    assign empty = empty_i;

endmodule
