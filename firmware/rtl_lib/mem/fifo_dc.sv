///////////////////////////////////////////////////////////////////////////////
//  FERMI RESEARCH LAB
///////////////////////////////////////////////////////////////////////////////
//  Async dual-clock FIFO with flush.
//  Faithful port from qick_time_tagger's _qtt_mem.sv (module FIFO_DC).
//  Gray-code pointer CDC (via gcc) with combinational full/empty and a
//  two-sided flush handshake (both wr_clk_i and rd_clk_i domains must see
//  their synced pointer settle before the FIFO reports itself flushed).
//  The storage array reuses qick:mem:bram_tdp (true dual-port, independent
//  clocks, 1-cycle read latency) in place of the legacy BRAM_DP_DC_EN -
//  same NO_REG (1-cycle) read timing the legacy code always used here.
///////////////////////////////////////////////////////////////////////////////

module fifo_dc # (
   parameter int FIFO_DW = 32 ,
   parameter int FIFO_AW = 18
) (
   input  wire                   wr_clk_i    ,
   input  wire                   wr_rst_ni   ,
   input  wire                   wr_en_i     ,
   input  wire                   push_i      ,
   input  wire [FIFO_DW - 1:0]   data_i      ,
   input  wire                   rd_clk_i    ,
   input  wire                   rd_rst_ni   ,
   input  wire                   rd_en_i     ,
   input  wire                   pop_i       ,
   output wire  [FIFO_DW - 1:0]  data_o      ,
   input  wire                   flush_i     ,
   output wire                   async_empty_o  ,
   output wire                   async_full_o   );

// The WRITE_POINTER is on the Last Empty Value
// The READ_POINTER is on the Last Value
wire [FIFO_AW-1:0] rd_gptr_p1   ;
wire [FIFO_AW-1:0] wr_gptr_p1   ;
wire [FIFO_AW-1:0] rd_ptr, wr_ptr, rd_gptr, wr_gptr  ;
wire clr_wr, clr_rd, clear_all, clear_none, busy;
wire async_empty, async_full, do_pop, do_push;

// Sample Pointers
reg [FIFO_AW-1:0] wr_gptr_rcd, wr_gptr_r;
always_ff @(posedge rd_clk_i) begin
   wr_gptr_rcd      <= wr_gptr;
   wr_gptr_r        <= wr_gptr_rcd;
end

reg [FIFO_AW-1:0] rd_gptr_rcd, rd_gptr_r;
always_ff @(posedge wr_clk_i) begin
   rd_gptr_rcd      <= rd_gptr;
   rd_gptr_r        <= rd_gptr_rcd;
end


reg clr_fifo_req, clr_fifo_ack;
reg clr_rd_rdc, clr_rd_r;
always_ff @(posedge wr_clk_i, negedge wr_rst_ni) begin
   if (!wr_rst_ni) begin
      clr_fifo_req <= 0 ;
      clr_fifo_ack <= 0 ;
      clr_rd_rdc <= 0 ;
      clr_rd_r <= 0 ;
   end else begin
      clr_rd_rdc      <= clr_rd;
      clr_rd_r        <= clr_rd_rdc;
      if      ( flush_i      )      clr_fifo_req <= 1 ;
      else if ( clr_fifo_ack )      clr_fifo_req <= 0 ;
      if      ( clear_all    )      clr_fifo_ack <= 1 ;
      else if ( clr_fifo_ack & clear_none) clr_fifo_ack <= 0 ;
   end
end

assign clear_all  =  clr_rd_r &  clr_wr;
assign clear_none = !clr_rd_r & !clr_wr;

assign busy = clr_fifo_ack | clr_fifo_req ;

wire [FIFO_DW - 1:0] mem_dt;

//SYNC with POP (RD_CLK)
assign async_empty   = (rd_gptr == wr_gptr_r) ;

//SYNC with PUSH (WR_CLK)
assign async_full    = (rd_gptr_r == wr_gptr_p1) ;

assign do_pop  = pop_i & !async_empty;
assign do_push = push_i & !async_full;

assign async_empty_o = async_empty | busy; // While RESETTING, Shows EMPTY
assign async_full_o  = async_full  | busy;
assign data_o  = mem_dt;

//Gray Code Counters
gcc #(
   .DW   ( FIFO_AW )
) gcc_wr_ptr  (
   .clk_i            ( wr_clk_i     ) ,
   .rst_ni           ( wr_rst_ni    ) ,
   .async_clear_i    ( clr_fifo_req ) ,
   .clear_o          ( clr_wr       ) ,
   .cnt_en_i         ( do_push      ) ,
   .count_bin_o      ( wr_ptr       ) ,
   .count_gray_o     ( wr_gptr      ) ,
   .count_bin_p1_o   (     ) ,
   .count_gray_p1_o  ( wr_gptr_p1   ) );

gcc #(
   .DW   ( FIFO_AW )
) gcc_rd_ptr (
   .clk_i            ( rd_clk_i     ) ,
   .rst_ni           ( rd_rst_ni    ) ,
   .async_clear_i    ( clr_fifo_req ) ,
   .clear_o          ( clr_rd       ) ,
   .cnt_en_i         ( do_pop       ) ,
   .count_bin_o      ( rd_ptr       ) ,
   .count_gray_o     ( rd_gptr      ) ,
   .count_bin_p1_o   (     ) ,
   .count_gray_p1_o  ( rd_gptr_p1   ) );

// Data (bram_tdp: true dual-port, independent clocks, 1-cycle read latency
// on port B - matches BRAM_DP_DC_EN's legacy "NO_REG" timing exactly)
bram_tdp # (
   .NB_ADDR     ( FIFO_AW  ) ,
   .NB_DATA     ( FIFO_DW  ) ,
   .OUT_REG_A   ( 1'b0     ) ,
   .OUT_REG_B   ( 1'b0     )
) fifo_mem (
   .clka   ( wr_clk_i  ) ,
   .rsta   ( 1'b0      ) ,
   .ena    ( wr_en_i   ) ,
   .wea    ( do_push   ) ,
   .addra  ( wr_ptr    ) ,
   .dia    ( data_i    ) ,
   .doa    (           ) ,
   .clkb   ( rd_clk_i  ) ,
   .rstb   ( 1'b0      ) ,
   .enb    ( rd_en_i   ) ,
   .web    ( 1'b0      ) ,
   .addrb  ( rd_ptr    ) ,
   .dib    ( '0        ) ,
   .dob    ( mem_dt    ) );

endmodule
