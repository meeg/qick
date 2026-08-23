`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : down_conversion_dynro
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    down_conversion_dynro.sv
//!
//! @brief   Digital down-conversion (real ADC sample x complex DDS) for
//!          axis_dyn_readout_v1.
//!
//! @details
//! Faithful port of down_conversion.v: N_DDS parallel lanes, each
//! multiplying one real 16-bit input sample by its own complex DDS output
//! (dds_compiler_dyn_readout), rounded to Q1.15, with an output-source mux
//! (0=product, 1=DDS only, 2=raw input, 3=zero) driven by ctrl_dyn_ro.
//!
//! No FIFO/decimation here -- this is the "before filter and decimation"
//! stage (legacy M0_AXIS); axis_dyn_readout_v1's top level feeds this
//! output into fir_decim8_dynro for the decimated M1_AXIS stream.
//!
//! s_axis_tready_o / m_axis_tvalid_o are both tied high (continuous
//! streaming, no backpressure), matching the legacy exactly.
//!
//! @author  QICK Development Team
//!
//! @version 1.0
///////////////////////////////////////////////////////////////////////////////
module down_conversion_dynro #(
    parameter int N_DDS = 8  //! Number of parallel demodulator lanes.
)(
    // Reset and clock.
    input  logic                 rstn,
    input  logic                 clk,

    // S_AXIS for input.
    output logic                 s_axis_tready_o,
    input  logic                 s_axis_tvalid_i,
    input  logic [N_DDS*16-1:0]  s_axis_tdata_i,

    // M_AXIS for output.
    input  logic                 m_axis_tready_i,
    output logic                 m_axis_tvalid_o,
    output logic [N_DDS*32-1:0]  m_axis_tdata_o,

    // Fifo interface.
    output logic          fifo_rd_en_o,
    input  logic          fifo_empty_i,
    input  logic [87:0]   fifo_dout_i
);

    //! 0.5 for rounding.
    localparam logic [31:0] RND_0P5 = 32'(2 ** 15);

    // DDS input control.
    logic                  dds_tvalid_r;
    logic [N_DDS*72-1:0]   dds_ctrl_int;
    logic [N_DDS*72-1:0]   dds_ctrl_int_r;

    // Output selection.
    logic [1:0] outsel_int;

    // DDS output.
    logic [31:0] dds_dout    [N_DDS];
    logic [31:0] dds_dout_r1 [N_DDS];
    logic [31:0] dds_dout_r2 [N_DDS];
    logic [31:0] dds_dout_r3 [N_DDS];
    logic [31:0] dds_dout_r4 [N_DDS];

    // Input data.
    logic        [15:0] din_r1 [N_DDS];
    logic signed [15:0] din_r2 [N_DDS];
    logic        [15:0] din_r3 [N_DDS];
    logic        [15:0] din_r4 [N_DDS];

    // Product.
    logic signed [15:0] pa_real          [N_DDS];
    logic signed [15:0] pa_imag          [N_DDS];
    logic signed [31:0] py_full_real     [N_DDS];
    logic signed [31:0] py_full_imag     [N_DDS];
    logic signed [31:0] py_full_real_r   [N_DDS];
    logic signed [31:0] py_full_imag_r   [N_DDS];
    logic signed [31:0] py_round_real    [N_DDS];
    logic signed [31:0] py_round_imag    [N_DDS];
    logic        [15:0] py_real          [N_DDS];
    logic        [15:0] py_imag          [N_DDS];
    logic        [31:0] py               [N_DDS];
    logic        [31:0] py_r             [N_DDS];

    // Muxed output.
    logic [31:0] dout_mux   [N_DDS];
    logic [31:0] dout_mux_r [N_DDS];

    // Control block.
    ctrl_dyn_ro #(
        .N (N_DDS)
    ) ctrl_i (
        .aresetn    (rstn),
        .aclk       (clk),
        .fifo_rd_en (fifo_rd_en_o),
        .fifo_empty (fifo_empty_i),
        .fifo_dout  (fifo_dout_i),
        .dds_ctrl   (dds_ctrl_int),
        .outsel     (outsel_int)
    );

    for (genvar i = 0; i < N_DDS; i = i + 1) begin : g_dds
        // DDS.
        dds_compiler_dyn_readout dds_i (
            .aclk                (clk),
            .s_axis_phase_tvalid (dds_tvalid_r),
            .s_axis_phase_tdata  (dds_ctrl_int_r[i*72+:72]),
            .m_axis_data_tvalid  (),
            .m_axis_data_tdata   (dds_dout[i])
        );

        always_ff @(posedge clk) begin
            if (!rstn) begin
                dds_dout_r1[i]   <= '0;
                dds_dout_r2[i]   <= '0;
                dds_dout_r3[i]   <= '0;
                dds_dout_r4[i]   <= '0;
                din_r1[i]        <= '0;
                din_r2[i]        <= '0;
                din_r3[i]        <= '0;
                din_r4[i]        <= '0;
                py_full_real_r[i] <= '0;
                py_full_imag_r[i] <= '0;
                py_r[i]           <= '0;
                dout_mux_r[i]     <= '0;
            end else begin
                // DDS output.
                dds_dout_r1[i] <= dds_dout[i];
                dds_dout_r2[i] <= dds_dout_r1[i];
                dds_dout_r3[i] <= dds_dout_r2[i];
                dds_dout_r4[i] <= dds_dout_r3[i];

                // Input data.
                din_r1[i] <= s_axis_tdata_i[i*16+:16];
                din_r2[i] <= din_r1[i];
                din_r3[i] <= din_r2[i];
                din_r4[i] <= din_r3[i];

                // Product.
                py_full_real_r[i] <= py_full_real[i];
                py_full_imag_r[i] <= py_full_imag[i];
                py_r[i]            <= py[i];

                // Muxed output.
                dout_mux_r[i] <= dout_mux[i];
            end
        end

        // Product.
        assign pa_real[i]      = dds_dout_r2[i][15:0];
        assign pa_imag[i]      = dds_dout_r2[i][31:16];
        assign py_full_real[i] = pa_real[i] * din_r2[i];
        assign py_full_imag[i] = pa_imag[i] * din_r2[i];
        assign py_round_real[i] = py_full_real_r[i] + $signed(RND_0P5);
        assign py_round_imag[i] = py_full_imag_r[i] + $signed(RND_0P5);
        assign py_real[i] = py_round_real[i][31:16];
        assign py_imag[i] = py_round_imag[i][31:16];
        assign py[i]      = {py_imag[i], py_real[i]};

        // Muxed output.
        assign dout_mux[i] = (outsel_int == 2'd0) ? py_r[i] :
                              (outsel_int == 2'd1) ? dds_dout_r4[i] :
                              (outsel_int == 2'd2) ? {16'h0000, din_r4[i]} :
                              32'h0000_0000;

        // Outputs.
        assign m_axis_tdata_o[i*32+:32] = dout_mux_r[i];
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            dds_tvalid_r   <= 1'b0;
            dds_ctrl_int_r <= '0;
        end else begin
            dds_tvalid_r   <= 1'b1;
            dds_ctrl_int_r <= dds_ctrl_int;
        end
    end

    // Outputs.
    assign s_axis_tready_o = 1'b1;
    assign m_axis_tvalid_o = 1'b1;

endmodule
