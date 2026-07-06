/***********************************************
 *
 *  File: axil_ram_wr.sv
 *  Description: Interface between AXI4-Lite and DP BRAM block
 *
 *
 * ********************************************/

module axil_ram_wr#(
  parameter integer unsigned AXI_DWIDTH  = 32,
  parameter integer unsigned AXI_AWIDTH  = 16
)(
  input  logic                        i_clk,
  input  logic                        i_rst,

  // Slave side
  axi4_lite_if.slave                  i_axil,

  // BRAM port
  bram_if.master                      o_bram_if
);

  localparam integer ADDR_LSB = $clog2(AXI_DWIDTH/8);

  logic                    awready_s, awvalid_s;
  logic                    wready_s, wvalid_s;
  logic                    bready_s, bvalid_s;
  logic [AXI_AWIDTH-1:0]   awaddr_s;
  logic [AXI_DWIDTH-1:0]   wdata_s;
  logic [AXI_DWIDTH/8-1:0] wstrb_s;

  assign awready_s = wvalid_s & bready_s ;
  assign wready_s  = awvalid_s & bready_s;
  assign bvalid_s  = awvalid_s & wvalid_s;

  in_buffer #(
    .DWIDTH(AXI_AWIDTH)
  ) u_ibuf_0 (
    .i_clk    ( i_clk          ),
    .i_rstn   ( ~i_rst         ),
    .i_ready  ( i_axil.awready ),
    .i_data   ( i_axil.awaddr  ),
    .i_valid  ( i_axil.awvalid ),
    .o_ready  ( awready_s      ),
    .o_data   ( awaddr_s       ),
    .o_valid  ( awvalid_s      )
  );

  in_buffer #(
    .DWIDTH(AXI_DWIDTH + AXI_DWIDTH/8)
  ) u_ibuf_1 (
    .i_clk    (i_clk                        ),
    .i_rstn   (~i_rst                       ),
    .i_ready  (i_axil.wready                ),
    .i_data   ({i_axil.wstrb, i_axil.wdata} ),
    .i_valid  (i_axil.wvalid                ),
    .o_ready  (wready_s                     ),
    .o_data   ({wstrb_s, wdata_s}           ),
    .o_valid  (wvalid_s                     )
  );

  out_buffer #(
    .DWIDTH(1)
  ) u_obuf_0 (
    .i_clk     ( i_clk         ),
    .i_rstn    ( ~i_rst        ),
    .i_ready   ( bready_s      ),
    .i_data    ( 1'b0          ),
    .i_valid   ( bvalid_s      ),
    .o_ready   ( i_axil.bready ),
    .o_valid   ( i_axil.bvalid ),
    .o_data    (               )
  );

  assign i_axil.bresp = 2'd0;

  assign i_axil.arready = 1'b0;
  assign i_axil.rdata = {(AXI_DWIDTH){1'b0}};
  assign i_axil.rresp = 2'd0;
  assign i_axil.rvalid = 1'b0;

  assign o_bram_if.addr  = awaddr_s[ADDR_LSB+o_bram_if.NB_ADDR-1:ADDR_LSB];
  assign o_bram_if.dout  = wdata_s;
  assign o_bram_if.we    = bvalid_s ? wstrb_s : {(o_bram_if.NB_DATA/8){1'b0}};

endmodule
