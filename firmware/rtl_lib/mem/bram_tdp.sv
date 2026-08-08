///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : bram_tdp
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    bram_tdp.sv
//!
//! @brief   True dual-port block RAM (independent clocks and resets).
//!          Wraps Xilinx xpm_memory_tdpram for robust BRAM inference.
//!
//! @details
//!
//! - Memory of **NB_DATA** bits per word and **2^NB_ADDR** words.
//! - Each port (`port_a`, `port_b`) operates independently.
//! - Clocks and resets can differ (dual-clock RAM).
//! - Optional output register stages for latency matching.
//!
//! READ LATENCY: controlled by OUT_REG_A / OUT_REG_B parameters
//! - OUT_REG_A=0: 1-cycle latency on port A
//! - OUT_REG_A=1: 2-cycle latency on port A
//!
//! @generic
//! NB_DATA      : unsigned int – data width of each word (default 32).
//! NB_ADDR      : unsigned int – number of address bits (default 10 -> 1024).
//! MEM_BIN_FILE : string – path to a hex initialisation file (optional).
//! OUT_REG_A    : bit – optional output register on port A (default 0).
//! OUT_REG_B    : bit – optional output register on port B (default 0).
//! ENABLE_BYTE_WRITES : bit – enable byte-level writes (default 0).
//!
//! @author  QICK Development Team
//!
//! @version 2.0
`timescale 1ns / 1ps

module bram_tdp #(
    parameter bit ENABLE_BYTE_WRITES    = 1'b0,  // Future feature flag
    parameter int unsigned NB_DATA      = 32,
    parameter int unsigned NB_ADDR      = 10,
    parameter string       MEM_BIN_FILE = "",
    parameter bit          OUT_REG_A    = 1'b0,
    parameter bit          OUT_REG_B    = 1'b0
)(
    //port A signals
    input  logic  clka,
    input  logic  rsta,
    input  logic  ena,
    input  logic  wea,
    input  logic [NB_ADDR-1:0] addra,
    input  logic [NB_DATA-1:0] dia,
    output logic [NB_DATA-1:0] doa,

    //port B signals
    input  logic  clkb,
    input  logic  rstb,
    input  logic  enb,
    input  logic  web,
    input  logic [NB_ADDR-1:0] addrb,
    input  logic [NB_DATA-1:0] dib,
    output logic [NB_DATA-1:0] dob
);


    localparam int unsigned DEPTH      = 1 << NB_ADDR;
    localparam int unsigned MEMORY_SZ  = DEPTH * NB_DATA;
    localparam int BYTE_WRITE_WIDTH_A = ENABLE_BYTE_WRITES ? 8 : NB_DATA;
    localparam int BYTE_WRITE_WIDTH_B = ENABLE_BYTE_WRITES ? 8 : NB_DATA;

    // Map OUT_REG to xpm read latency (1 = default, 2 = with optional reg)
    localparam int READ_LATENCY_A = OUT_REG_A ? 2 : 1;
    localparam int READ_LATENCY_B = OUT_REG_B ? 2 : 1;

    // Internal signals
    logic [NB_DATA-1:0] doa_xpm, dob_xpm;

    // XPM memory instantiation
    // Note: MEMORY_INIT_FILE is omitted to avoid path resolution issues in simulation.
    // For designs that need initialization, use testbench methods or ROMs.
    //
    // Full-word write mode: wea/web are single bits (full data word or nothing).
    // This is more generic: regardless of NB_DATA (32, 64, 128...), the interface
    // is always wea=1 bit, web=1 bit. Byte-granular writes can be added later
    // via a separate parameter if needed.
    xpm_memory_tdpram #(
        .ADDR_WIDTH_A           (NB_ADDR),
        .ADDR_WIDTH_B           (NB_ADDR),
        .AUTO_SLEEP_TIME        (0),
        .BYTE_WRITE_WIDTH_A     (BYTE_WRITE_WIDTH_A),
        .BYTE_WRITE_WIDTH_B     (BYTE_WRITE_WIDTH_B),
        .CLOCKING_MODE          ("independent_clk"),
        .ECC_MODE               ("no_ecc"),
        .MEMORY_OPTIMIZATION    ("true"),
        .MEMORY_PRIMITIVE       ("block"),    // Request BRAM
        .MEMORY_SIZE            (MEMORY_SZ),
        .MESSAGE_CONTROL        (0),
        .READ_DATA_WIDTH_A      (NB_DATA),
        .READ_DATA_WIDTH_B      (NB_DATA),
        .READ_LATENCY_A         (READ_LATENCY_A),
        .READ_LATENCY_B         (READ_LATENCY_B),
        .READ_RESET_VALUE_A     ("0"),
        .READ_RESET_VALUE_B     ("0"),
        .RST_MODE_A             ("SYNC"),
        .RST_MODE_B             ("SYNC"),
        .SIM_ASSERT_CHK         (0),
        .WRITE_DATA_WIDTH_A     (NB_DATA),
        .WRITE_DATA_WIDTH_B     (NB_DATA),
        .WRITE_MODE_A           ("write_first"),
        .WRITE_MODE_B           ("write_first")
    )
    xpm_mem (
        // Port A
        .addra                  (addra),
        .addrb                  (addrb),
        .clka                   (clka),
        .clkb                   (clkb),
        .dina                   (dia),
        .dinb                   (dib),
        .douta                  (doa_xpm),
        .doutb                  (dob_xpm),
        .ena                    (ena),
        .enb                    (enb),
        .injectdbiterra         (1'b0),
        .injectdbiterrb         (1'b0),
        .rsta                   (rsta),
        .rstb                   (rstb),
        .sleep                  (1'b0),
        // Single-bit write enables (full-word writes)
        .wea                    (wea),
        .web                    (web),
        // Unused error outputs
        .dbiterrb               (),
        .dbiterra               (),
        .sbiterrb               (),
        .sbiterra               ()
    );

    // Drive outputs
    assign doa = doa_xpm;
    assign dob = dob_xpm;

endmodule
