///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : tx_cmd
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    tx_cmd.sv
//!
//! @brief   Transmitter interface wrapper for the XCOM block. Synchronizes the
//!
//! @details
//!
//! xcom_link_tx block through the external i_sync signal.
//!
//! @author  QICK Development Team
//!
//! @version 1.0

module tx_cmd(
   input  logic          i_clk      ,
   input  logic          i_rstn     ,
   input  logic          i_sync     ,
   // Config
   input  logic [4-1:0]  i_cfg_tick ,
   // Transmission
   input  logic          i_req      ,
   input  logic [8-1:0]  i_header   ,
   input  logic [32-1:0] i_data     ,
   output logic          o_ready    ,
   // XCOM CNX
   output logic          o_data     ,
   output logic          o_clk      ,
   // XCOM TX DEBUG
   output logic  [2-1:0] o_dbg_state
   );

logic s_ready;
logic sync_dly_r, sync_dly_n;
logic s_tx_valid;
logic s_xcmd_sync;
logic s_sync;

typedef enum logic [2-1:0]{ IDLE  = 2'b00,
                            WSYNC = 2'b01,
                            WRDY  = 2'b10
} state_t;
state_t state_r, state_n;


// PULSE SYNC
///////////////////////////////////////////////////////////////////////////////
assign s_xcmd_sync  = ( i_header[7:4] == 4'b1000 ); // Sync Command

always_ff@(posedge i_clk) begin
    if (!i_rstn) sync_dly_r <= 1'b0;
    else         sync_dly_r <= sync_dly_n;
end

assign sync_dly_n = i_sync;
assign s_sync = !sync_dly_r & i_sync ;


// TX Control state
///////////////////////////////////////////////////////////////////////////////
always_ff @ (posedge i_clk) begin
   if ( !i_rstn ) state_r <= IDLE;
   else           state_r <= state_n;
end

always_comb begin
   state_n = state_r;
   s_tx_valid  = 1'b0;
   case (state_r)
      IDLE:  begin
         if ( i_req ) begin
            if ( s_xcmd_sync ) begin
               state_n = WSYNC;
            end else begin
               s_tx_valid = 1'b1;
               state_n    = WRDY;
               //state_n    = WVLD;
            end
         end
      end
      //WVLD: begin
      //   s_tx_valid = 1'b1;
      //   state_n    = WRDY;
      //end
      WSYNC:  begin
         if ( s_sync ) begin
            s_tx_valid = 1'b1;
            state_n    = WRDY;
         end
      end
      WRDY:  begin
         if ( !i_req & s_ready ) state_n = IDLE;
      end
      default: state_n = state_r;
   endcase
end

xcom_link_tx u_xcom_link_tx(
  .i_clk      ( i_clk      ),
  .i_rstn     ( i_rstn     ),
  .i_cfg_tick ( i_cfg_tick ),
  .i_valid    ( s_tx_valid ),
  .i_header   ( i_header   ),
  .i_data     ( i_data     ),
  .o_ready    ( s_ready    ),
  .o_data     ( o_data     ),
  .o_clk      ( o_clk      )
);

// OUTPUTS
assign o_ready     = s_ready;
assign o_dbg_state = state_r;

endmodule

