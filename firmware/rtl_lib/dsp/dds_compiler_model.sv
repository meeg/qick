///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : dds_compiler_model
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    dds_compiler_model.sv
//!
//! @brief   dds_compiler_model
//!
//! @details
//!
//!
//! Behavioural model of Xilinx DDS Compiler v6.0 (for sim/lint only).
//!
//! Same interface as the real Xilinx IP. Phase accumulator + sin/cos.
//! Generalized to cover all six QICK DDS Compiler configurations found
//! across the codebase (dyn_readout, signal_gen, signal_gen_int,
//! signal_gen_mixmux, signal_gen_mux, readout), which differ only in
//! PHASE_WIDTH, LATENCY, and single- vs dual-output selection. Each
//! instantiation site sets these three parameters to match its own
//! dds_compiler_<variant>.xci (see the parameter table maintained in
//! docs/dds_compiler_variants.md).
//!
//! s_axis_phase_tdata layout (matches the real Xilinx IP width exactly,
//! 2*PHASE_WIDTH+8 bits -- e.g. 72 bits for PHASE_WIDTH=32, 40 bits for
//! PHASE_WIDTH=16 -- so parent RTL that already packs/connects the full
//! descriptor width does not need any adaptation):
//! [2*PHASE_WIDTH-1 : PHASE_WIDTH] = phase (absolute, already accumulated
//! upstream, e.g. by ctrl_sg_v6)
//! [PHASE_WIDTH-1 : 0]             = pinc (unused here directly; phase
//! advance is already folded into the
//! per-cycle phase_in value upstream)
//!
//! m_axis_data_tdata:
//! DUAL_OUTPUT=1 (Output_Selection=Sine_and_Cosine): {sin[15:0],cos[15:0]}
//! DUAL_OUTPUT=0 (Output_Selection=Sine only):        sin[15:0]
//!
//! For a CONSTANT carrier (amplitude tests), drive the descriptor with a
//! fixed phase; phase=0 => cos=0x7FFF, sin=0.
//!
//! @author  QICK Development Team
//!
//! @version 1.0
module dds_compiler_model #(
   //! Output pipeline latency (default 10).
   parameter int LATENCY     = 10,
   //! Width of the phase/pinc fields packed into
   parameter int PHASE_WIDTH = 32,
   //! 1 = Sine_and_Cosine (32-bit packed output),
   parameter bit DUAL_OUTPUT = 1'b1,
   //! 1 = Streaming pinc (accumulate internally);
   parameter bit STREAMING   = 1'b0   //! 1 = Streaming pinc (accumulate internally);
                                      //! 0 = phase pre-accumulated upstream (signal_gen)
)(
   input  logic                       aclk,
   input  logic                       s_axis_phase_tvalid,
   input  logic [2*PHASE_WIDTH+8-1:0] s_axis_phase_tdata,
   output logic                       m_axis_data_tvalid,
   output logic [(DUAL_OUTPUT?32:16)-1:0] m_axis_data_tdata
);

   localparam int OUT_WIDTH = DUAL_OUTPUT ? 32 : 16;

   // Phase field: upper PHASE_WIDTH bits of the packed descriptor. The
   // absolute phase is already computed upstream (e.g. by ctrl_sg_v6's
   // phase_v1 pipeline), so we use it directly as the instantaneous phase.
   logic [PHASE_WIDTH-1:0] phase_in;
   logic [PHASE_WIDTH-1:0] phase_acc = '0;   // internal accumulator for streaming mode

   logic signed [15:0] cos_v, sin_v;
   real angle;
   always_comb begin
      angle = 2.0 * 3.14159265358979323846
              * real'(phase_in) / (2.0 ** PHASE_WIDTH);
      cos_v = $rtoi($cos(angle) * 32767.0);
      sin_v = $rtoi($sin(angle) * 32767.0);
   end

   generate
      if (STREAMING) begin : gen_streaming
         // Pinc is in the LOW bits; accumulate it each valid cycle (like the
         // real IP in Phase_Increment=Streaming mode).
         logic [PHASE_WIDTH-1:0] pinc;
         assign pinc = s_axis_phase_tdata[PHASE_WIDTH-1:0];
         always_ff @(posedge aclk) begin
            if (s_axis_phase_tvalid) phase_acc <= phase_acc + pinc;
         end
         assign phase_in = phase_acc;
      end
      else begin : gen_preaccumulated
         // Phase is absolute, in the HIGH bits (signal_gen / ctrl_sg_v6 path).
         assign phase_in = s_axis_phase_tdata[2*PHASE_WIDTH-1 -: PHASE_WIDTH];
      end
   endgenerate

   logic [OUT_WIDTH-1:0] sample;
   generate
      if (DUAL_OUTPUT) begin : gen_dual_output
         assign sample = {sin_v, cos_v};
      end
      else begin : gen_single_output
         assign sample = sin_v;
      end
   endgenerate

   logic [OUT_WIDTH-1:0] pipe [LATENCY];
   always_ff @(posedge aclk) begin
      pipe[0] <= sample;
      for (int k = 1; k < LATENCY; k++)
         pipe[k] <= pipe[k-1];
   end

   assign m_axis_data_tdata  = pipe[LATENCY-1];
   assign m_axis_data_tvalid = 1'b1;

endmodule

