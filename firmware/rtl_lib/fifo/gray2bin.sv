// gray2bin.sv - Always_comb version

`timescale 1ns / 1ps

module gray2bin #(
    parameter int B = 8
)(
    input  logic [B-1:0] din,
    output logic [B-1:0] dout
);

    always_comb begin
        dout[B-1] = din[B-1];
        for (int i = B-2; i >= 0; i--) begin
            dout[i] = dout[i+1] ^ din[i];
        end
    end

endmodule
