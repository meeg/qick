///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : bram_simple_sp
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    bram_simple_sp.sv
//!
//! @brief   bram_simple_sp
//!
//! @details
//!
//!
//! Simple single-port block RAM.
//!
//!
//! - Memory of NB_DATA-bits by word and 2^NB_ADDR words.
//! - Single port interface for both reading and writing operations.
//! - Implements "Write-First" (Read-Through) behavior: when writing,
//! the output data is updated immediately with the written value.
//!
//!
//! - If MEM_BIN_FILE is not empty, the memory is initialized at
//! startup with the content of the binary file (raw binary format).
//!
//! @generic
//! NB_DATA      : unsigned int – data width of each data word (default 32).
//! NB_ADDR      : unsigned int – number of address bits (default 4 -> 16 words).
//! MEM_BIN_FILE : string – path to the binary initialization file (optional).
//!
//! @author  QICK Development Team
//!
//! @version 1.0
module bram_simple_sp
#(
    parameter int unsigned              NB_DATA         = 32,
    parameter int unsigned              NB_ADDR         = 4,
    parameter string                    MEM_BIN_FILE    = ""
)
(
    input   logic                       i_clk,
    input   logic                       i_ena,
    input   logic                       i_wea,
    input   logic   [NB_ADDR-1 : 0]     i_addra,
    input   logic   [NB_DATA-1 : 0]     i_dia,
    output  logic   [NB_DATA-1 : 0]     o_doa
);

localparam int unsigned DEPTH = 2**NB_ADDR;

    (* ram_style = "block" *) logic [NB_DATA-1:0] ram [DEPTH];

initial begin
    if(MEM_BIN_FILE != "") begin
        $display({"Reading ", MEM_BIN_FILE});
        $readmemb(MEM_BIN_FILE, ram);
    end
end

always_ff @(posedge i_clk) begin
    if (i_ena) begin
        if (i_wea) begin
            ram[i_addra] <= i_dia;
            o_doa        <= i_dia; // Write-First behaviour (Read-Through)
        end else begin
            o_doa        <= ram[i_addra];
        end
    end
end

endmodule
