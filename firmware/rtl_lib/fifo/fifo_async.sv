//====================================================================
//  fifo_async.sv
//  Asynchronous FIFO based on XPM_FIFO_ASYNC
//  –  Parameters, port names and reset polarity match the SVUnit
//     test‑bench you are using.
//  –  XPM configuration follows the UG‑974 example (READ_MODE = "std",
//     FIFO_READ_LATENCY = 1, etc.).
//====================================================================

module fifo_async #(
    // -----------------------------------------------------------------
    //  Parameters – keep the same names that the test‑bench uses
    // -----------------------------------------------------------------
    parameter int B = 32,          // Data width  (WRITE/READ_DATA_WIDTH)
    parameter int N = 2048         // FIFO depth (FIFO_WRITE_DEPTH)
) (
    // -----------------------------------------------------------------
    //  Write domain (active‑low reset, as used by the test‑bench)
    // -----------------------------------------------------------------
    input  logic               wr_rstn,   // active‑low reset
    input  logic               wr_clk,
    input  logic               wr_en,
    input  logic [B-1:0]       din,
    output logic               full,
    output logic               wr_err,    // overflow flag

    // -----------------------------------------------------------------
    //  Read domain (active‑low reset)
    // -----------------------------------------------------------------
    input  logic               rd_rstn,   // active‑low reset
    input  logic               rd_clk,
    input  logic               rd_en,
    output logic [B-1:0]       dout,
    output logic               empty,
    output logic               data_valid // same meaning as XPM's "valid"
);

    // -----------------------------------------------------------------
    //  Convert active‑low resets to the active‑high version required by
    //  XPM_FIFO_ASYNC (XPM uses a single reset input named "rst").
    // -----------------------------------------------------------------
    logic rst;                     // active‑high reset for the XPM
    assign rst = ~wr_rstn | ~rd_rstn;   // OR of the two active‑low resets

    // -----------------------------------------------------------------
    //  Unused XPM signals (tied‑off)
    // -----------------------------------------------------------------
    logic sleep_i = 1'b0;
    logic wr_rst_busy, rd_rst_busy;

    // -----------------------------------------------------------------
    //  XPM_FIFO_ASYNC instance – exactly the parameter set you posted
    // -----------------------------------------------------------------
    xpm_fifo_async #(
        .CASCADE_HEIGHT      (0),
        .CDC_SYNC_STAGES     (2),
        .DOUT_RESET_VALUE    ("0"),
        .ECC_MODE            ("no_ecc"),
        .FIFO_MEMORY_TYPE    ("auto"),
        .FIFO_READ_LATENCY   (1),          // one‑cycle read latency (STD mode)
        .FIFO_WRITE_DEPTH    (N),
        .FULL_RESET_VALUE    (0),
        .PROG_EMPTY_THRESH   (10),
        .PROG_FULL_THRESH    (10),
        .RD_DATA_COUNT_WIDTH (1),
        .READ_DATA_WIDTH     (B),
        .READ_MODE           ("std"),      // matches the test‑bench expectations
        .RELATED_CLOCKS      (0),
        .SIM_ASSERT_CHK      (0),
        .USE_ADV_FEATURES    ("0707"),
        .WAKEUP_TIME         (0),
        .WRITE_DATA_WIDTH    (B),
        .WR_DATA_COUNT_WIDTH (1)
    ) u_fifo_async (
        // -------------------------------------------------------------
        //  Global control
        // -------------------------------------------------------------
        .rst          (rst),          // single active‑high reset
        .sleep        (sleep_i),

        // -------------------------------------------------------------
        //  Write side
        // -------------------------------------------------------------
        .wr_clk       (wr_clk),
        .wr_en        (wr_en & ~wr_rst_busy & ~full), // gated like in the original IP
        .din          (din),
        .full         (full),
        .overflow     (wr_err),
        .wr_ack       ( ),
        .wr_data_count( ),
        .prog_full    ( ),
        .wr_rst_busy  (wr_rst_busy),

        // -------------------------------------------------------------
        //  Read side
        // -------------------------------------------------------------
        .rd_clk       (rd_clk),
        .rd_en        (rd_en & ~rd_rst_busy & ~empty), // gated
        .dout         (dout),
        .empty        (empty),
        .data_valid   (data_valid),   // XPM's "valid" → test‑bench name
        .underflow    ( ),
        .rd_data_count( ),
        .prog_empty   ( ),
        .rd_rst_busy  (rd_rst_busy),

        // -------------------------------------------------------------
        //  Optional / unused ports
        // -------------------------------------------------------------
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr      ( ),
        .dbiterr      ( )
    );

endmodule