
///////////////////////////////////////////////////////////////////////////////
// Module : dds_compiler_signal_gen (behavioural wrapper, simulation only)
///////////////////////////////////////////////////////////////////////////////
/**
 * @module dds_compiler_signal_gen
 * @brief Fixed-configuration wrapper around dds_compiler_model matching
 *        dds_compiler_signal_gen.xci (Component_Name-renamed Xilinx IP,
 *        grupo "signal_gen": axis_sg_int4_v2, axis_signal_gen_v5,
 *        axis_signal_gen_v6).
 *
 * @description
 *   Thin pass-through: fixes LATENCY/PHASE_WIDTH/DUAL_OUTPUT to this
 *   variant's values so parent RTL can instantiate this module by name
 *   with zero parameters, identically whether the sim model or the real
 *   .xci is elaborated (FuseSoC target picks the fileset; the module name
 *   stays consistent either way).
 *
 *   Values sourced from dds_compiler_signal_gen.xci: Latency=10,
 *   Phase_Width=32, Output_Selection=Sine_and_Cosine (dual output).
 */
module dds_compiler_signal_gen (
   input  logic        aclk,
   input  logic        s_axis_phase_tvalid,
   input  logic [71:0] s_axis_phase_tdata,
   output logic        m_axis_data_tvalid,
   output logic [31:0] m_axis_data_tdata
);

   dds_compiler_model #(
      .LATENCY     (10),
      .PHASE_WIDTH (32),
      .DUAL_OUTPUT (1'b1)
   ) core_i (
      .aclk                (aclk),
      .s_axis_phase_tvalid (s_axis_phase_tvalid),
      .s_axis_phase_tdata  (s_axis_phase_tdata),
      .m_axis_data_tvalid  (m_axis_data_tvalid),
      .m_axis_data_tdata   (m_axis_data_tdata)
   );

endmodule
