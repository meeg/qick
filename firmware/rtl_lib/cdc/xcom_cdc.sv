///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : xcom_cdc
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    xcom_cdc.sv
//!
//! @brief   XCOM clock domain crossing synchronizer. Assumption here is that
//!
//! @details
//!
//! time_clk > core_clk > ps_clk
//!
//! @author  QICK Development Team
//!
//! @version 1.0
module xcom_cdc
(
   input  logic           i_ps_clk           ,
   input  logic           i_ps_rstn          ,
   input  logic           i_core_clk         ,
   input  logic           i_core_rstn        ,
   input  logic           i_time_clk         ,
   input  logic           i_time_rstn        ,
// QICK PERIPHERAL INTERFACE (i_core_clk)
   input  logic           i_core_en          ,
   input  logic  [5-1:0]  i_core_op          ,
   input  logic [32-1:0]  i_core_data1       ,
   input  logic [32-1:0]  i_core_data2       ,
   output logic           o_core_en_sync     ,
   output logic  [5-1:0]  o_core_op_sync     ,
   output logic [32-1:0]  o_core_data1_sync  ,
   output logic [32-1:0]  o_core_data2_sync  ,
   input  logic           i_core_ready       ,
   input  logic           i_core_valid       ,
   input  logic           i_core_flag        ,
   input  logic [32-1:0]  i_core_data1_core  ,
   input  logic [32-1:0]  i_core_data2_core  ,
   output logic           o_core_ready_sync  ,
   output logic           o_core_valid_sync  ,
   output logic           o_core_flag_sync   ,
   output logic [32-1:0]  o_core_data1_core  ,
   output logic [32-1:0]  o_core_data2_core  ,
// XCOM
   input  logic [ 4-1:0]  i_xcom_id          ,
   output logic [ 4-1:0]  o_xcom_id_sync     ,
// AXI-Lite DATA Slave I/F (i_ps_clk)
   input  logic [32-1:0]  i_xcom_ctrl        ,
   input  logic [32-1:0]  i_xcom_cfg         ,
   input  logic [32-1:0]  i_axi_data1        ,
   input  logic [32-1:0]  i_axi_data2        ,
   output logic [32-1:0]  o_xcom_ctrl_sync   ,
   output logic [32-1:0]  o_xcom_cfg_sync    ,
   output logic [32-1:0]  o_axi_data1_sync   ,
   output logic [32-1:0]  o_axi_data2_sync   ,

   output logic [32-1:0]  o_xcom_flag_sync   ,
   output logic [32-1:0]  o_xcom_data1_sync  ,
   output logic [32-1:0]  o_xcom_data2_sync  ,

   input  logic [32-1:0]   i_xcom_rx_data    ,
   input  logic [32-1:0]   i_xcom_tx_data    ,
   input  logic [32-1:0]   i_xcom_status     ,
   input  logic [32-1:0]   i_xcom_debug      ,
   output logic [32-1:0]   o_xcom_rx_data_sync,
   output logic [32-1:0]   o_xcom_tx_data_sync,
   output logic [32-1:0]   o_xcom_status_sync ,
   output logic [32-1:0]   o_xcom_debug_sync
);

//SYNC STAGES
///////////////////////////////////////////////////////////////////////////////
//Time domain -> PS domain
synchronizer#(
   .NB(4)
   ) sync_id_ps(
  .i_clk      ( i_ps_clk        ),
  .i_rstn     ( i_ps_rstn       ),
  .i_async    ( i_xcom_id       ),
  .o_sync     ( o_xcom_id_sync  )
);

synchronizer#(
   .NB(32)
   ) sync_rx_data_ps(
  .i_clk      ( i_ps_clk            ),
  .i_rstn     ( i_ps_rstn           ),
  .i_async    ( i_xcom_rx_data      ),
  .o_sync     ( o_xcom_rx_data_sync )
);

synchronizer#(
   .NB(32)
   ) sync_tx_data_ps(
  .i_clk      ( i_ps_clk            ),
  .i_rstn     ( i_ps_rstn           ),
  .i_async    ( i_xcom_tx_data      ),
  .o_sync     ( o_xcom_tx_data_sync )
);

synchronizer#(
   .NB(32)
   ) sync_status_ps(
  .i_clk      ( i_ps_clk           ),
  .i_rstn     ( i_ps_rstn          ),
  .i_async    ( i_xcom_status      ),
  .o_sync     ( o_xcom_status_sync )
);

synchronizer#(
   .NB(32)
   ) sync_debug_ps(
  .i_clk      ( i_ps_clk          ),
  .i_rstn     ( i_ps_rstn         ),
  .i_async    ( i_xcom_debug      ),
  .o_sync     ( o_xcom_debug_sync )
);

///////////////////////////////////////////////////////////////////////////////
//Core domain -> PS domain
synchronizer#(
   .NB(1)
   ) xcom_flag(
  .i_clk      ( i_ps_clk            ),
  .i_rstn     ( i_ps_rstn           ),
  .i_async    ( i_core_flag         ),
  .o_sync     ( o_xcom_flag_sync[0] )
);

assign o_xcom_flag_sync[32-1:1] = '0;

synchronizer#(
   .NB(32)
   ) sync_data1_ps(
  .i_clk      ( i_ps_clk          ),
  .i_rstn     ( i_ps_rstn         ),
  .i_async    ( i_core_data1_core ),
  .o_sync     ( o_xcom_data1_sync )
);

synchronizer#(
   .NB(32)
   ) sync_data2_ps(
  .i_clk      ( i_ps_clk          ),
  .i_rstn     ( i_ps_rstn         ),
  .i_async    ( i_core_data2_core ),
  .o_sync     ( o_xcom_data2_sync )
);

///////////////////////////////////////////////////////////////////////////////
//PS domain -> Time domain
synchronizer#(
   .NB(6)
   ) sync_xcom_ctrl(
  .i_clk      ( i_time_clk       ),
  .i_rstn     ( i_time_rstn      ),
  .i_async    ( i_xcom_ctrl[6-1:0]      ),
  .o_sync     ( o_xcom_ctrl_sync[6-1:0] )
);
assign o_xcom_ctrl_sync[32-1:6] = '0;

synchronizer#(
   .NB(4)
   ) sync_xcom_cfg(
  .i_clk      ( i_time_clk       ),
  .i_rstn     ( i_time_rstn      ),
  .i_async    ( i_xcom_cfg[4-1:0]      ),
  .o_sync     ( o_xcom_cfg_sync[4-1:0] )
);
assign o_xcom_cfg_sync[32-1:4] = '0;

synchronizer#(
   .NB(32)
   ) sync_axi_data1(
  .i_clk      ( i_time_clk       ),
  .i_rstn     ( i_time_rstn      ),
  .i_async    ( i_axi_data1      ),
  .o_sync     ( o_axi_data1_sync )
);

synchronizer#(
   .NB(32)
   ) sync_axi_data2(
  .i_clk      ( i_time_clk       ),
  .i_rstn     ( i_time_rstn      ),
  .i_async    ( i_axi_data2      ),
  .o_sync     ( o_axi_data2_sync )
);

///////////////////////////////////////////////////////////////////////////////
//Core domain -> Time domain
wide_en_signal sync_core_en(
   .i_clk  ( i_time_clk     ),
   .i_rstn ( i_time_rstn    ),
   .i_en   ( i_core_en      ),
   .o_en   ( o_core_en_sync )
   );

synchronizer#(
   .NB(5)
   ) sync_core_op(
  .i_clk      ( i_time_clk       ),
  .i_rstn     ( i_time_rstn      ),
  .i_async    ( i_core_op        ),
  .o_sync     ( o_core_op_sync   )
);

synchronizer#(
   .NB(32)
   ) sync_core_data1(
  .i_clk      ( i_time_clk       ),
  .i_rstn     ( i_time_rstn      ),
  .i_async    ( i_core_data1      ),
  .o_sync     ( o_core_data1_sync )
);

synchronizer#(
   .NB(32)
   ) sync_core_data2(
  .i_clk      ( i_time_clk        ),
  .i_rstn     ( i_time_rstn       ),
  .i_async    ( i_core_data2      ),
  .o_sync     ( o_core_data2_sync )
);

///////////////////////////////////////////////////////////////////////////////
//Time domain -> Core domain
synchronizer#(
   .NB(1)
   ) sync_core_ready(
  .i_clk      ( i_core_clk        ),
  .i_rstn     ( i_core_rstn       ),
  .i_async    ( i_core_ready      ),
  .o_sync     ( o_core_ready_sync )
);

synchronizer#(
   .NB(1)
   ) sync_core_flag(
  .i_clk      ( i_core_clk       ),
  .i_rstn     ( i_core_rstn      ),
  .i_async    ( i_core_flag      ),
  .o_sync     ( o_core_flag_sync )
);

synchronizer#(
   .NB(1)
   ) sync_core_valid(
  .i_clk      ( i_core_clk        ),
  .i_rstn     ( i_core_rstn       ),
  .i_async    ( i_core_valid      ),
  .o_sync     ( o_core_valid_sync )
);

synchronizer#(
   .NB(32)
   ) sync_data1_core(
  .i_clk      ( i_core_clk        ),
  .i_rstn     ( i_core_rstn       ),
  .i_async    ( i_core_data1_core ),
  .o_sync     ( o_core_data1_core )
);

synchronizer#(
   .NB(32)
   ) sync_data2_core(
  .i_clk      ( i_core_clk        ),
  .i_rstn     ( i_core_rstn       ),
  .i_async    ( i_core_data2_core ),
  .o_sync     ( o_core_data2_core )
);

//end of SYNC STAGES
///////////////////////////////////////////////////////////////////////////////

endmodule
