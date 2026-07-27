///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : bram_tdp
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    bram_tdp.sv
//!
//! @brief   True dual-port block RAM (independent clocks and resets).
//!
//! @details
//!
//! - Memory of **NB_DATA** bits per word and **2^NB_ADDR** words.
//! - Each port (`port_a`, `port_b`) operates independently and may read or
//!   write on any clock cycle. Clocks and resets can differ (dual-clock RAM).
//! - If `MEM_BIN_FILE` is not empty the array is initialised at startup from
//!   that file; otherwise it is cleared, so unwritten locations read as 0 in
//!   simulation rather than X.
//!
//! READ LATENCY
//!
//! Each port has a mandatory read register, giving a 1-cycle read latency:
//! data presented on `addrX` during cycle n appears on `doX` in cycle n+1.
//!
//! `OUT_REG_A` / `OUT_REG_B` add a second, optional register on the
//! corresponding output, giving 2-cycle latency. This reproduces the behaviour
//! of the Xilinx `bram_dp_xpm` primitive with `OUT_REG_ENA = 1`, which several
//! QICK datapaths were originally timed against.
//!
//! Both default to 0, so existing instantiations are unaffected.
//!
//! Getting this wrong is silent: a datapath whose delay lines were sized for a
//! 2-cycle memory and is then fed by a 1-cycle one reads its data one cycle
//! early, and if consecutive addresses hold consecutive rows the whole result
//! is shifted by a row with no error anywhere. sgv6 hit exactly this when
//! `bram_dp_xpm` (OUT_REG_ENA=1) was replaced with `bram_tdp`; it instantiates
//! the envelope banks with `OUT_REG_B(1)`.
//!
//! The optional register shares the port's `en` input, matching the mandatory
//! stage: with `enX` low the output holds rather than advancing.
//!
//! @generic
//! NB_DATA      : unsigned int – data width of each word (default 32).
//! NB_ADDR      : unsigned int – number of address bits (default 10 -> 1024).
//! MEM_BIN_FILE : string – path to a hex initialisation file (optional).
//! OUT_REG_A    : bit – add a second output register on port A (default 0).
//! OUT_REG_B    : bit – add a second output register on port B (default 0).
//!
//! @author  QICK Development Team
//!
//! @version 1.1
module bram_tdp #(
    parameter int unsigned NB_DATA      = 32,
    parameter int unsigned NB_ADDR      = 10,
    parameter string       MEM_BIN_FILE = "",
    //! 0 = 1-cycle read latency on port A, 1 = 2 cycles
    parameter bit          OUT_REG_A    = 1'b0,
    //! 0 = 1-cycle read latency on port B, 1 = 2 cycles
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

    // Internal calculations for memory depth and byte count
    localparam int unsigned DEPTH     = 1 << NB_ADDR;
    localparam int unsigned NUM_BYTES = NB_DATA / 8;

    // Declaration of the memory with attribute to infer Block RAM physical
    (* ram_style = "block" *) logic [NB_DATA-1:0] ram [DEPTH];

    //! Mandatory read-register outputs (1-cycle latency)
    logic [NB_DATA-1:0] doa_r;
    logic [NB_DATA-1:0] dob_r;

    // Optional initialization of the memory (useful for ROMs or bootloaders)
    initial begin
        if (MEM_BIN_FILE != "") begin
            $display("Initializing BRAM from file: %s", MEM_BIN_FILE);
            $readmemh(MEM_BIN_FILE, ram); // Use $readmemb for binary files
        end else begin
            // If no initialization file is provided, clear the memory so that
            // unwritten locations read as 0 instead of X in simulation
            for (int i = 0; i < DEPTH; i++) begin
                ram[i] = '0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Port A — mandatory read register
    // -------------------------------------------------------------------------
    always_ff @(posedge clka) begin
        if (rsta) begin
            doa_r <= '0;
        end else if (ena) begin
            if (wea) begin
                // Writing
                ram[addra] <= dia;
                // In write-first mode, the read returns the newly written data.
                doa_r <= dia; // write-first
            end else begin
                // Reading
                doa_r <= ram[addra];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Port A — optional output register
    // -------------------------------------------------------------------------
    generate
        if (OUT_REG_A) begin : gen_doa_reg
            logic [NB_DATA-1:0] doa_rr;
            always_ff @(posedge clka) begin
                if (rsta)      doa_rr <= '0;
                else if (ena)  doa_rr <= doa_r;
            end
            assign doa = doa_rr;
        end else begin : gen_doa_comb
            assign doa = doa_r;
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Port B — mandatory read register
    // -------------------------------------------------------------------------
    always_ff @(posedge clkb) begin
        if (rstb) begin
            dob_r <= '0;
        end else if (enb) begin
            if (web) begin
                ram[addrb] <= dib;
                // In write-first mode, the read returns the newly written data.
                dob_r <= dib; // write-first
            end else begin
                dob_r <= ram[addrb];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Port B — optional output register
    // -------------------------------------------------------------------------
    generate
        if (OUT_REG_B) begin : gen_dob_reg
            logic [NB_DATA-1:0] dob_rr;
            always_ff @(posedge clkb) begin
                if (rstb)      dob_rr <= '0;
                else if (enb)  dob_rr <= dob_r;
            end
            assign dob = dob_rr;
        end else begin : gen_dob_comb
            assign dob = dob_r;
        end
    endgenerate

endmodule

