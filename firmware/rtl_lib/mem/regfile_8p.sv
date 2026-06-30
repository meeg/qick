//------------------------------------------------------------------------------
// Module      : regfile_8p
// Description : 8-page register file. Each page contains 32 registers (2^5).
//              - 7 read ports and 1 write port, all with one‑cycle latency.
//              - Page selection (pnum) selects which page is read; writes
//                go to the page indicated by pnum in the same cycle.
//              - A pipeline register (pnum_r) delays page selection for reads
//                to match the write latency (read data appears one cycle after
//                address is presented).
//              - Register address 0 always reads 0 in every page.
//
// Parameters:
//   B : data width in bits (default 16)
//
// Ports:
//   clk, rstn : clock and active-low reset
//   addr0..addr6 : read addresses (5 bits each)
//   addr7 : write address (5 bits)
//   din7  : write data (B bits)
//   wen7  : write enable
//   pnum  : page number (3 bits) – selects page for both read and write
//   dout0..dout6 : read data outputs (B bits each)
//------------------------------------------------------------------------------
module regfile_8p
#(
    parameter integer B = 16
)
(
    input  logic        clk,
    input  logic        rstn,
    input  logic [4:0]  addr0,
    input  logic [4:0]  addr1,
    input  logic [4:0]  addr2,
    input  logic [4:0]  addr3,
    input  logic [4:0]  addr4,
    input  logic [4:0]  addr5,
    input  logic [4:0]  addr6,
    input  logic [4:0]  addr7,
    input  logic [B-1:0] din7,
    input  logic         wen7,
    input  logic [2:0]  pnum,
    output logic [B-1:0] dout0,
    output logic [B-1:0] dout1,
    output logic [B-1:0] dout2,
    output logic [B-1:0] dout3,
    output logic [B-1:0] dout4,
    output logic [B-1:0] dout5,
    output logic [B-1:0] dout6
);

    // Internal signals for each page
    logic [B-1:0] dout0_p [8];
    logic [B-1:0] dout1_p [8];
    logic [B-1:0] dout2_p [8];
    logic [B-1:0] dout3_p [8];
    logic [B-1:0] dout4_p [8];
    logic [B-1:0] dout5_p [8];
    logic [B-1:0] dout6_p [8];

    logic wen7_p [8];
    logic [2:0] pnum_r;   // pipelined page selection for reads

    //--------------------------------------------------------------------------
    // Instantiate 8 regfile pages
    //--------------------------------------------------------------------------
    generate
        for (genvar i = 0; i < 8; i++) begin : gen_page
            regfile #(.B(B), .N(5)) regfile_inst (
                .clk  (clk),
                .addr0(addr0),
                .addr1(addr1),
                .addr2(addr2),
                .addr3(addr3),
                .addr4(addr4),
                .addr5(addr5),
                .addr6(addr6),
                .addr7(addr7),
                .din7 (din7),
                .wen7 (wen7_p[i]),
                .dout0(dout0_p[i]),
                .dout1(dout1_p[i]),
                .dout2(dout2_p[i]),
                .dout3(dout3_p[i]),
                .dout4(dout4_p[i]),
                .dout5(dout5_p[i]),
                .dout6(dout6_p[i])
            );
        end
    endgenerate

    // Write enables per page (decoded from pnum)
    always_comb begin
        wen7_p = '{default: 1'b0};
        wen7_p[pnum] = wen7;
    end

    //--------------------------------------------------------------------------
    // Pipeline register for page selection (reads appear one cycle later)
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn)
            pnum_r <= 3'b0;
        else
            pnum_r <= pnum;
    end

    //--------------------------------------------------------------------------
    // Read data muxes (using pipelined page number)
    //--------------------------------------------------------------------------
    always_comb begin
        dout0 = dout0_p[pnum_r];
        dout1 = dout1_p[pnum_r];
        dout2 = dout2_p[pnum_r];
        dout3 = dout3_p[pnum_r];
        dout4 = dout4_p[pnum_r];
        dout5 = dout5_p[pnum_r];
        dout6 = dout6_p[pnum_r];
    end

endmodule
