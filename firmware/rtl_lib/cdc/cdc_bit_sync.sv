///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
//
// Fermi National Accelerator Laboratory
//
// Module: cdc_bit_sync.sv
// Project: QICK
// Description: 2 FF, NB-bit data synchronizer.
//              It serves as clock domain crossing (CDC) logic.
//
// Change history: 04/29/25 - Created by @lharnaldi
//
///////////////////////////////////////////////////////////////////////////////
module cdc_bit_sync #(
   //number of bits in data
   parameter int NB = 1
)(
    input logic           i_clk ,
    input logic           i_rstn,
    input logic  [NB-1:0] i_async,
    output logic [NB-1:0] o_sync
);

    (* ASYNC_REG = "TRUE" *) logic [NB-1:0] meta_r, sync_r;
    logic [NB-1:0] meta_n, cdc_bit_sync;

    //two D FFs
    always_ff @ (posedge i_clk) begin
     if(!i_rstn) begin
       meta_r <= '0;
       sync_r <= '0;
     end else begin
       meta_r <= meta_n;
       sync_r <= cdc_bit_sync;
     end
    end

    //next-state logic
    assign meta_n = i_async;
    assign cdc_bit_sync = meta_r;

    //output logic
    assign o_sync = sync_r;

endmodule

