// Module Name: lo_spi_mux
// Converted from VHDL to SystemVerilog

module lo_spi_mux (
    input  logic [1:0] ss_in,
    output logic       ss0_out,
    output logic       ss1_out,
    input  logic       sdo0_in,
    input  logic       sdo1_in,
    output logic       sdo_out
);

// Assign ss outputs
assign ss0_out = ss_in[0];
assign ss1_out = ss_in[1];

// SDO mux
assign sdo_out = (ss_in == 2'b10) ? sdo0_in :
                 (ss_in == 2'b01) ? sdo1_in :
                 1'b1;

endmodule
