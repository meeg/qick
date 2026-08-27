`timescale 1ns/1ps
module axis_skid_buffer#(
    parameter int NB_DATA = 0   // deprecated
)(
    input  logic            i_clk,
    input  logic            i_rstn,

    axi4_stream_if.slave    i_axis,
    axi4_stream_if.master   o_axis
);

    localparam int DW = i_axis.TDATA_WIDTH;

    // -----------------------------
    // Output register
    // -----------------------------
    logic out_valid;
    logic [DW-1:0] out_tdata;
    logic          out_tlast;
    logic [i_axis.TUSER_WIDTH-1:0] out_tuser;
    logic [(DW/8)-1:0] out_tkeep;
    logic [(DW/8)-1:0] out_tstrb;

    // -----------------------------
    // Skid register
    // -----------------------------
    logic skid_valid;
    logic [DW-1:0] skid_tdata;
    logic          skid_tlast;
    logic [i_axis.TUSER_WIDTH-1:0] skid_tuser;
    logic [(DW/8)-1:0] skid_tkeep;
    logic [(DW/8)-1:0] skid_tstrb;

    // -----------------------------
    // Handshake
    // -----------------------------
    wire out_fire = out_valid && o_axis.tready;
    wire in_fire  = i_axis.tvalid && i_axis.tready;

    assign o_axis.tvalid = out_valid;

    // READY: only block input if both registers are full
    assign i_axis.tready = !skid_valid || out_fire;

    // -----------------------------
    // Sequential logic
    // -----------------------------
    always_ff @(posedge i_clk) begin
        if (!i_rstn) begin
            out_valid  <= 1'b0;
            skid_valid <= 1'b0;
        end else begin

            //--------------------------------------
            // Case 1: output advances
            //--------------------------------------
            if (out_fire) begin
                if (skid_valid) begin
                    // skid → output
                    out_tdata <= skid_tdata;
                    out_tlast <= skid_tlast;
                    out_tuser <= skid_tuser;
                    out_tkeep <= skid_tkeep;
                    out_tstrb <= skid_tstrb;
                    out_valid <= 1'b1;
                    skid_valid <= 1'b0;
                end else begin
                    out_valid <= 1'b0;
                end
            end

            //--------------------------------------
            // Case 2: input accepted
            //--------------------------------------
            if (in_fire) begin
                if (!out_valid || out_fire) begin
                    // input → output
                    out_tdata <= i_axis.tdata;
                    out_tlast <= i_axis.tlast;
                    out_tuser <= i_axis.tuser;
                    out_tkeep <= i_axis.tkeep;
                    out_tstrb <= i_axis.tstrb;
                    out_valid <= 1'b1;
                end else begin
                    // input → skid
                    skid_tdata <= i_axis.tdata;
                    skid_tlast <= i_axis.tlast;
                    skid_tuser <= i_axis.tuser;
                    skid_tkeep <= i_axis.tkeep;
                    skid_tstrb <= i_axis.tstrb;
                    skid_valid <= 1'b1;
                end
            end
        end
    end

    // -----------------------------
    // Drive output
    // -----------------------------
    assign o_axis.tdata = out_tdata;
    assign o_axis.tlast = out_tlast;
    assign o_axis.tuser = out_tuser;
    assign o_axis.tkeep = out_tkeep;
    assign o_axis.tstrb = out_tstrb;

endmodule

