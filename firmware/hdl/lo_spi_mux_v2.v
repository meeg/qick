// Module Name: lo_spi_mux_v2
// Converted from VHDL to SystemVerilog

module lo_spi_mux_v2 (
    input  logic [2:0] ss_in,
    output logic       ss0_out,
    output logic       ss1_out,
    output logic       ss2_out,
    input  logic       sdo0_in,
    input  logic       sdo1_in,
    input  logic       sdo2_in,
    output logic       sdo_out
);

// Assign ss outputs
assign ss0_out = ss_in[0];
assign ss1_out = ss_in[1];
assign ss2_out = ss_in[2];

// SDO mux
assign sdo_out = (ss_in == 3'b110) ? sdo0_in :
                 (ss_in == 3'b101) ? sdo1_in :
                 (ss_in == 3'b011) ? sdo2_in :
                 1'b1;

endmodule
