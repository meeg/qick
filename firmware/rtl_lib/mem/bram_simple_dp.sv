/**
 * @module bram_simple_dp
 * @brief Simple dual-port block RAM (Dedicated write and read ports).
 *
 * @description
 *   - Memory of B-bits by word and 2^N words.
 *   - Simple Dual-Port architecture:
 *       * Port A: Dedicated to write operations.
 *       * Port B: Dedicated to read operations.
 *   - Both ports share the same clock signal.
 *   - Port A writing is conditioned by both 'ena' (port enable) and 'wea' (write enable).
 *   - Port B reading is conditioned by 'enb' (port enable).
 *
 * @generic
 *   N : unsigned int – number of address bits (default 16).
 *   B : unsigned int – data width of each data word (default 16).
 *
 * @port
 *   input  logic          clk   : Clock signal.
 *   input  logic          ena   : Enable for the write port (Port A).
 *   input  logic          enb   : Enable for the read port (Port B).
 *   input  logic          wea   : Write enable for Port A.
 *   input  logic [N-1:0]  addra : Write address for Port A.
 *   input  logic [N-1:0]  addrb : Read address for Port B.
 *   input  logic [B-1:0]  dia   : Data to be written (Port A).
 *   output logic [B-1:0]  dob   : Data read from memory (Port B).
 */
module bram_simple_dp #(
    parameter int N = 16,
    parameter int B = 16
)(
    input  logic          clk,
    input  logic          ena,
    input  logic          enb,
    input  logic          wea,
    input  logic [N-1:0]  addra,
    input  logic [N-1:0]  addrb,
    input  logic [B-1:0]  dia,
    output logic [B-1:0]  dob
);

    // RAM type
    typedef logic [B-1:0] ram_t [0:2**N-1];
    ram_t ram;

    // Write port (with enable)
    always_ff @(posedge clk) begin
        if (ena && wea) begin
            ram[addra] <= dia;
        end
    end

    // Read port (with enable)
    always_ff @(posedge clk) begin
        if (enb) begin
            dob <= ram[addrb];
        end
    end

endmodule
