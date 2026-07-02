///////////////////////////////////////////////////////////////////////////////
// Module : dds_compiler_0 (behavioural model, simulation only)
///////////////////////////////////////////////////////////////////////////////
/**
 * @module dds_compiler_0
 * @brief Behavioural model of Xilinx DDS Compiler v6.0 (for sim/lint only).
 *
 * @description
 *   Same interface as the real Xilinx IP. Phase accumulator + sin/cos.
 *   Output {sin[15:0], cos[15:0]}, Full_Range 16-bit twos-complement, latency 10.
 *
 *   For a CONSTANT carrier (amplitude tests), drive the descriptor with freq=0
 *   (pinc=0) and a fixed phase: phase=0 => cos=0x7FFF, sin=0.
 *
 * @param LATENCY output pipeline latency (default 10).
 */
module dds_compiler_0 #(
   parameter int LATENCY = 10
)(
   input  logic        aclk,
   input  logic        s_axis_phase_tvalid,
   input  logic [71:0] s_axis_phase_tdata,
   output logic        m_axis_data_tvalid,
   output logic [31:0] m_axis_data_tdata
);
   // Packed: [63:32]=phase, [31:0]=pinc (from ctrl_sg_v6).
   logic [31:0] phase_in, pinc_in;
   assign phase_in = s_axis_phase_tdata[63:32];
   assign pinc_in  = s_axis_phase_tdata[31:0];

   // Phase accumulator: the absolute phase is already computed upstream, so we
   // use phase_in directly as the instantaneous phase (pinc drives its advance
   // through the per-lane phase words produced by ctrl_sg_v6).
   logic signed [15:0] cos_v, sin_v;
   real angle;
   always_comb begin
      angle = 2.0 * 3.14159265358979323846 * real'(phase_in) / 4294967296.0;
      cos_v = $rtoi($cos(angle) * 32767.0);
      sin_v = $rtoi($sin(angle) * 32767.0);
   end

   logic [31:0] pipe [LATENCY];
   always_ff @(posedge aclk) begin
      pipe[0] <= {sin_v, cos_v};
      for (int k = 1; k < LATENCY; k++)
         pipe[k] <= pipe[k-1];
   end

   assign m_axis_data_tdata  = pipe[LATENCY-1];
   assign m_axis_data_tvalid = 1'b1;

endmodule
