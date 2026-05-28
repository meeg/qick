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
