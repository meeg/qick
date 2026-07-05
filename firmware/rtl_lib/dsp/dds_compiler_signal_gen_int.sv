///////////////////////////////////////////////////////////////////////////////
// Module : dds_compiler_signal_gen_int (behavioural wrapper, simulation only)
///////////////////////////////////////////////////////////////////////////////
/**
 * @module dds_compiler_signal_gen_int
 * @brief Fixed-configuration wrapper around dds_compiler_model matching
 *        dds_compiler_signal_gen_int.xci (Component_Name-renamed Xilinx IP).
 *        Used by: axis_sg_int4_v1, axis_sg_mux4_v1.
 *
 * @description
 *   Thin pass-through: fixes LATENCY/PHASE_WIDTH/DUAL_OUTPUT to this
 *   variant's values so parent RTL can instantiate this module by name
 *   with zero parameters.
 *
 *   Values sourced from dds_compiler_signal_gen_int.xci: Latency=10,
 *   Phase_Width=16, Output_Selection=Sine_and_Cosine (32-bit packed output).
 */
module dds_compiler_signal_gen_int (
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
