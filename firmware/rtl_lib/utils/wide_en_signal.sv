///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : wide_en_signal
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    wide_en_signal.sv
//!
//! @brief   Enable pulse generator for a wide enable signal.
//!
//! @details
//!
//! It serves as clock domain crossing (CDC) logic.
//!
//! @author  QICK Development Team
//!
//! @version 1.0
module wide_en_signal(
    input logic  i_clk    ,
    input logic  i_rstn   ,
    input logic  i_en     ,
    output logic o_en
);

 logic en_strobe;

    cdc_bit_sync#(
       .NB(1)
       ) u_sync(
          .i_clk      ( i_clk        ),
          .i_rstn     ( i_rstn       ),
          .i_async    ( i_en         ),
          .o_sync     ( en_strobe    )
          );

    rising_edge_det u_edge_detect(
       .i_clk      ( i_clk        ),
       .i_rstn     ( i_rstn       ),
       .i_strobe   ( en_strobe    ),
       .o_pulse    ( o_en         )
       );

endmodule
