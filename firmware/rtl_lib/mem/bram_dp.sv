module bram_dp #(
    parameter int N = 16,  // Memory address size (2^N depth)
    parameter int B = 16   // Data width
)(
    input  logic          clka,
    input  logic          clkb,
    input  logic          ena,
    input  logic          enb,
    input  logic          wea,
    input  logic          web,
    input  logic [N-1:0]  addra,
    input  logic [N-1:0]  addrb,
    input  logic [B-1:0]  dia,
    input  logic [B-1:0]  dib,
    output logic [B-1:0]  doa,
    output logic [B-1:0]  dob
);

// RAM type - using big-endian order [0:2**N-1] instead of [2**N-1:0]
typedef logic [B-1:0] ram_t [0:2**N-1];
ram_t ram;

// Port A: Write and read
always_ff @(posedge clka) begin
    if (ena) begin
        if (wea) begin
            ram[addra] <= dia;
        end
        doa <= ram[addra];
    end
end

// Port B: Write and read
always_ff @(posedge clkb) begin
    if (enb) begin
        if (web) begin
            ram[addrb] <= dib;
        end
        dob <= ram[addrb];
    end
end

endmodule
