`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : fir_decim8_dynro
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    fir_decim8_dynro.sv
//!
//! @brief   Behavioural model of the Xilinx FIR Compiler instance used by
//!          axis_dyn_readout_v1 (for sim/lint only).
//!
//! @details
//! Same interface as the real Xilinx IP (fir_compiler_0.xci): decimate-by-8,
//! 120-tap symmetric linear-phase lowpass, 2 paths (I/Q). Coefficients
//! (from fir.coe, raw Q1.15-scale integers) hardcoded as the exact filter
//! this IP was generated with; NOT a general-purpose FIR core.
//!
//! s_axis_data_tdata packing: N_DDS=8 lanes x 32 bits, {imag[31:16],
//! real[15:0]} per lane, ALL VALID EVERY CYCLE (matches
//! down_conversion_dynro's m_axis_tdata_o -- one block of 8 time-consecutive
//! demodulated samples per clock, lane 0 = oldest, lane 7 = newest).
//! m_axis_data_tdata: one decimated {imag,real} sample, produced once per
//! input block (decimation-by-8 falls out naturally from consuming one
//! 8-lane block per output sample).
//!
//! Direct-form decimation: maintains a 120-sample history (I and Q
//! separately, oldest-to-newest), shifts in the new 8-lane block each
//! cycle, and convolves the FULL 120-tap coefficient set against the
//! history every cycle. Computed in real arithmetic (not bit/cycle-exact to
//! the Vivado core's internal MAC/rounding/polyphase structure, same
//! disclaimer as dds_compiler_model / fir_interp4_sgint), then rounded to a
//! signed Q1.15 sample.
//!
//! Latency (input block -> corresponding output sample): approximate,
//! LATENCY parameter (default 8) -- NOT validated against the real IP's
//! actual pipeline depth.
//!
//! s_axis_data_tvalid is expected tied high by the caller (matches
//! down_conversion_fir.v's `.s_axis_data_tvalid(1'b1)`); m_axis_data_tvalid
//! mirrors it (constant high once past reset), matching dds_compiler_model's
//! convention.
//!
//! @author  QICK Development Team
//!
//! @version 1.0
///////////////////////////////////////////////////////////////////////////////
module fir_decim8_dynro #(
    parameter int N_DDS   = 8,  //! Lanes per input block (fixed by the decimation rate: 8).
    parameter int LATENCY = 8   //! Input block -> output sample latency (cycles).
)(
    input  logic          aclk,
    input  logic          s_axis_data_tvalid,
    output logic          s_axis_data_tready,
    input  logic [N_DDS*32-1:0] s_axis_data_tdata,
    output logic          m_axis_data_tvalid,
    output logic [31:0]   m_axis_data_tdata
);

    localparam int NTAPS = 120;

    //! Filter coefficients (fir.coe, Radix=10 integer values, Q1.15-scaled).
    real h [NTAPS];
    initial begin
        h[0]=-56;    h[1]=-4;     h[2]=13;     h[3]=47;     h[4]=97;
        h[5]=166;    h[6]=252;    h[7]=353;    h[8]=463;    h[9]=573;
        h[10]=674;   h[11]=754;   h[12]=801;   h[13]=804;   h[14]=753;
        h[15]=643;   h[16]=473;   h[17]=249;   h[18]=-20;   h[19]=-314;
        h[20]=-611;  h[21]=-885;  h[22]=-1107; h[23]=-1248; h[24]=-1285;
        h[25]=-1201; h[26]=-989;  h[27]=-651;  h[28]=-206;  h[29]=318;
        h[30]=878;   h[31]=1425;  h[32]=1903;  h[33]=2254;  h[34]=2428;
        h[35]=2383;  h[36]=2094;  h[37]=1556;  h[38]=786;   h[39]=-172;
        h[40]=-1251; h[41]=-2364; h[42]=-3408; h[43]=-4271; h[44]=-4839;
        h[45]=-5010; h[46]=-4696; h[47]=-3838; h[48]=-2410; h[49]=-422;
        h[50]=2076;  h[51]=4993;  h[52]=8205;  h[53]=11560; h[54]=14889;
        h[55]=18012; h[56]=20758; h[57]=22971; h[58]=24523; h[59]=25322;
        h[60]=25322; h[61]=24523; h[62]=22971; h[63]=20758; h[64]=18012;
        h[65]=14889; h[66]=11560; h[67]=8205;  h[68]=4993;  h[69]=2076;
        h[70]=-422;  h[71]=-2410; h[72]=-3838; h[73]=-4696; h[74]=-5010;
        h[75]=-4839; h[76]=-4271; h[77]=-3408; h[78]=-2364; h[79]=-1251;
        h[80]=-172;  h[81]=786;   h[82]=1556;  h[83]=2094;  h[84]=2383;
        h[85]=2428;  h[86]=2254;  h[87]=1903;  h[88]=1425;  h[89]=878;
        h[90]=318;   h[91]=-206;  h[92]=-651;  h[93]=-989;  h[94]=-1201;
        h[95]=-1285; h[96]=-1248; h[97]=-1107; h[98]=-885;  h[99]=-611;
        h[100]=-314; h[101]=-20;  h[102]=249;  h[103]=473;  h[104]=643;
        h[105]=753;  h[106]=804;  h[107]=801;  h[108]=754;  h[109]=674;
        h[110]=573;  h[111]=463;  h[112]=353;  h[113]=252;  h[114]=166;
        h[115]=97;   h[116]=47;   h[117]=13;   h[118]=-4;   h[119]=-56;

        for (int k = 0; k < NTAPS; k++)
            h[k] = h[k] / 32768.0;
    end

    //! Sample history, oldest-to-newest, index NTAPS-1 = oldest.
    real hist_real [NTAPS];
    real hist_imag [NTAPS];

    logic signed [15:0] din_real [N_DDS];
    logic signed [15:0] din_imag [N_DDS];
    for (genvar g = 0; g < N_DDS; g = g + 1) begin : g_unpack
        assign din_real[g] = s_axis_data_tdata[g*32+:16];
        assign din_imag[g] = s_axis_data_tdata[g*32+16+:16];
    end

    //! Combinational dot-product against the CURRENT history (i.e. one
    //! cycle before the new block shifts in).
    real acc_real;
    real acc_imag;
    real sample_real;
    real sample_imag;
    always_comb begin
        acc_real = 0.0;
        acc_imag = 0.0;
        for (int k = 0; k < NTAPS; k++) begin
            acc_real += h[k] * hist_real[k];
            acc_imag += h[k] * hist_imag[k];
        end
        sample_real = acc_real * 32768.0;
        sample_imag = acc_imag * 32768.0;
    end

    logic signed [15:0] out_real;
    logic signed [15:0] out_imag;

    always_ff @(posedge aclk) begin
        // Shift the history by N_DDS (one full lane-block), oldest samples
        // fall off the end; newest block (lane 0 = oldest-of-block ..
        // lane N_DDS-1 = newest) appended at the front.
        for (int k = NTAPS-1; k >= N_DDS; k--) begin
            hist_real[k] <= hist_real[k-N_DDS];
            hist_imag[k] <= hist_imag[k-N_DDS];
        end
        for (int g = 0; g < N_DDS; g++) begin
            hist_real[N_DDS-1-g] <= real'(din_real[g]) / 32768.0;
            hist_imag[N_DDS-1-g] <= real'(din_imag[g]) / 32768.0;
        end

        out_real <= (sample_real >  32767.0) ? 16'sd32767 :
                    (sample_real < -32768.0) ? 16'sh8000  :
                    16'($rtoi(sample_real));
        out_imag <= (sample_imag >  32767.0) ? 16'sd32767 :
                    (sample_imag < -32768.0) ? 16'sh8000  :
                    16'($rtoi(sample_imag));
    end

    logic [31:0] sample_word;
    assign sample_word = {out_imag, out_real};

    logic [31:0] pipe [LATENCY];
    always_ff @(posedge aclk) begin
        pipe[0] <= sample_word;
        for (int k = 1; k < LATENCY; k++)
            pipe[k] <= pipe[k-1];
    end

    assign m_axis_data_tdata  = pipe[LATENCY-1];
    assign m_axis_data_tvalid = 1'b1;
    assign s_axis_data_tready = 1'b1;

endmodule
