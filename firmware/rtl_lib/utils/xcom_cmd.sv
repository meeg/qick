///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : xcom_cmd
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    xcom_cmd.sv
//!
//! @brief   Wrapper and synchronizer block for the XCOM core.
//!
//! @author  QICK Development Team
//!
//! @version 1.0
module xcom_cmd(
  input  logic                  i_clk            ,
  input  logic                  i_rstn           ,
  // Command from tProcessor
  input  logic                  i_core_en       ,
  input  logic [ 5-1:0]         i_core_op       ,
  input  logic [2-1:0][32-1:0]  i_core_data     ,
  // Command from Python
  input  logic [ 6-1:0]         i_ps_ctrl        ,
  input  logic [2-1:0][32-1:0]  i_ps_data        ,
  // Command Execution
  output logic                  o_req_loc        ,
  input  logic                  i_ack_loc        ,
  output logic                  o_req_net        ,
  input  logic                  i_ack_net        ,
  output logic [ 8-1:0]         o_op             ,
  output logic [32-1:0]         o_data           ,
  output logic [ 4-1:0]         o_data_cntr
);

  logic          s_ack;
  logic          s_valid;
  logic  [5-1:0] s_op;
  logic  [4-1:0] s_addr;
  logic [32-1:0] s_data;

  //I/O selection - PS valid bit selects PS path
  assign s_valid = i_ps_ctrl[0] | i_core_en;
  assign s_op    = i_ps_ctrl[0] ? i_ps_ctrl[5:1]    : i_core_op;
  assign s_addr  = i_ps_ctrl[0] ? i_ps_data[0][3:0] : i_core_data[0][3:0];
  assign s_data  = i_ps_ctrl[0] ? i_ps_data[1]      : i_core_data[1];
  assign s_ack   = i_ack_loc ? i_ack_loc : i_ack_net;

  // Command Request
  ///////////////////////////////////////////////////////////////////////////////
  req_ack_cmd u_req_ack_cmd(
    .i_clk      ( i_clk       ),
    .i_rstn     ( i_rstn      ),
    .i_valid    ( s_valid     ),
    .i_op       ( s_op        ),
    .i_addr     ( s_addr      ),
    .i_data     ( s_data      ),
    .i_ack      ( s_ack       ),
    .o_req_loc  ( o_req_loc   ),
    .o_req_net  ( o_req_net   ),
    .o_op       ( o_op        ),
    .o_data     ( o_data      ),
    .o_data_cntr( o_data_cntr )
  );

endmodule
