//------------------------------------------------------------------------------
// Module      : regfile
// Description : Register file with 7 read ports and 1 write port.
//              - Synchronous read and write (single clock cycle latency).
//              - Register address 0 always reads as 0 (hardwired zero).
//              - Parameterizable data width (B) and number of registers (2^N).
//
// Parameters:
//   B : data width in bits (default 16)
//   N : address width, number of registers = 2^N (default 4 → 16 registers)
//
// Ports:
//   clk   : clock
//   addr0..addr6 : read addresses (N bits each)
//   addr7 : write address (N bits)
//   din7  : write data (B bits)
//   wen7  : write enable
//   dout0..dout6 : read data outputs (B bits each)
//------------------------------------------------------------------------------
module regfile
#(
    parameter integer B = 16,
    parameter integer N = 4
)
(
    input  logic        clk,
    input  logic [N-1:0] addr0,
    input  logic [N-1:0] addr1,
    input  logic [N-1:0] addr2,
    input  logic [N-1:0] addr3,
    input  logic [N-1:0] addr4,
    input  logic [N-1:0] addr5,
    input  logic [N-1:0] addr6,
    input  logic [N-1:0] addr7,
    input  logic [B-1:0] din7,
    input  logic         wen7,
    output logic [B-1:0] dout0,
    output logic [B-1:0] dout1,
    output logic [B-1:0] dout2,
    output logic [B-1:0] dout3,
    output logic [B-1:0] dout4,
    output logic [B-1:0] dout5,
    output logic [B-1:0] dout6
);

    // Memory array
    logic [B-1:0] mem [2**N];

    //--------------------------------------------------------------------------
    // Write and read operations (synchronous)
    //--------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        // Write
        if (wen7)
            mem[addr7] <= din7;

        // Read port 0 (hardwired zero if address == 0)
        dout0 <= (addr0 == 0) ? '0 : mem[addr0];

        // Read port 1
        dout1 <= (addr1 == 0) ? '0 : mem[addr1];

        // Read port 2
        dout2 <= (addr2 == 0) ? '0 : mem[addr2];

        // Read port 3
        dout3 <= (addr3 == 0) ? '0 : mem[addr3];

        // Read port 4
        dout4 <= (addr4 == 0) ? '0 : mem[addr4];

        // Read port 5
        dout5 <= (addr5 == 0) ? '0 : mem[addr5];

        // Read port 6
        dout6 <= (addr6 == 0) ? '0 : mem[addr6];
    end

endmodule
