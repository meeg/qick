///////////////////////////////////////////////////////////////////////////////
// Module : dds_compiler_readout (behavioural wrapper, simulation only)
///////////////////////////////////////////////////////////////////////////////
/**
 * @module dds_compiler_readout
 * @brief Fixed-configuration wrapper around dds_compiler_model matching
 *        dds_compiler_readout.xci (Component_Name-renamed Xilinx IP).
 *        Used by: axis_readout_v1.
 *
 * @description
 *   Thin pass-through: fixes LATENCY/PHASE_WIDTH/DUAL_OUTPUT to this
 *   variant's values so parent RTL can instantiate this module by name
 *   with zero parameters.
 *
 *   Values sourced from dds_compiler_readout.xci: Latency=10,
 *   Phase_Width=16, Output_Selection=Sine_and_Cosine (32-bit packed output).
 */
module dds_compiler_readout (
   input  logic        aclk,
   input  logic        s_axis_phase_tvalid,
   input  logic [39:0] s_axis_phase_tdata,
   output logic        m_axis_data_tvalid,
   output logic [31:0] m_axis_data_tdata
);

   dds_compiler_model #(
      .LATENCY     (10),
      .PHASE_WIDTH (16),
      .DUAL_OUTPUT (1'b1)
   ) core_i (
      .aclk                (aclk),
      .s_axis_phase_tvalid (s_axis_phase_tvalid),
      .s_axis_phase_tdata  (s_axis_phase_tdata),
      .m_axis_data_tvalid  (m_axis_data_tvalid),
      .m_axis_data_tdata   (m_axis_data_tdata)
   );

endmodule
