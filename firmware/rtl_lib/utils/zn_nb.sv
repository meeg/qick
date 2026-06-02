///////////////////////////////////////////////////////////////////////////////
// Module: zn_nb.sv
// Description: N-stage B-bit shift register delay (z^-N).
//   Each cycle where s_axis_tvalid=1 the input is shifted in.
//   Output is the data that entered N valid-cycles ago.
//   m_axis_tvalid mirrors s_axis_tvalid (latency not compensated).
//
// Reset: synchronous, active-low (matches VHDL original).
//
// Parameters:
//   B : data width in bits  (default 16)
//   N : number of delay stages (default 4)
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module zn_nb #(
    parameter int B = 16,
    parameter int N = 4
) (
    input  logic             aclk,
    input  logic             aresetn,       // synchronous, active-low
    // S_AXIS input
    input  logic             s_axis_tvalid,
    input  logic [B-1:0]     s_axis_tdata,
    // M_AXIS output
    output logic             m_axis_tvalid,
    output logic [B-1:0]     m_axis_tdata
);

    // Shift register: index 0 holds the newest sample, N-1 the oldest.
    logic [B-1:0] shift_reg [N];

    always_ff @(posedge aclk) begin
        if (!aresetn) begin                          // synchronous reset
            for (int i = 0; i < N; i++)
                shift_reg[i] <= '0;
        end else begin
            if (s_axis_tvalid) begin
                for (int i = N-1; i > 0; i--)
                    shift_reg[i] <= shift_reg[i-1];
                shift_reg[0] <= s_axis_tdata;
            end
        end
    end

    assign m_axis_tdata  = shift_reg[N-1];
    assign m_axis_tvalid = s_axis_tvalid;

endmodule
