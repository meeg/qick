`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : ctrl_dyn_ro
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    ctrl_dyn_ro.sv
//!
//! @brief   Phase-coherent DDS controller for axis_dyn_readout_v1.
//!
//! @details
//! Faithful port of ctrl_dyn_ro_v1.sv. Reads waveform (demodulation)
//! descriptors from an input FIFO and produces the per-lane DDS phase
//! control words plus the output-source selector, for N parallel
//! demodulator lanes (N=8 in axis_dyn_readout_v1).
//!
//! Descriptor layout (88 bits):
//!
//! | bits      | field   | width | meaning                                |
//! |-----------|---------|-------|----------------------------------------|
//! | 87 .. 84  | (unused)|   4   | -                                      |
//! | 83        | phrst   |   1   | phase reset                            |
//! | 82        | mode    |   1   | mode (1 = periodic/non-stop)           |
//! | 81 .. 80  | outsel  |   2   | output source: 0=prod,1=dds,2=input    |
//! | 79 .. 64  | nsamp   |  16   | number of output samples               |
//! | 63 .. 32  | phase   |  32   | initial phase                          |
//! | 31 ..  0  | freq    |  32   | phase increment (pinc), sets frequency |
//!
//! FSM (one-hot): READ_ST (assert fifo_rd_en; when mode is periodic or a
//! descriptor is available, latch it and move to CNT_ST) -> CNT_ST (count
//! samples; when cnt reaches nsamp-2, return to READ_ST).
//!
//! Phase generation is phase-coherent across descriptor updates, same
//! scheme as phase_ctrl_sgmux8/ctrl_sgv4: phase_v1[i] = phase_v0[i] +
//! phase_0, where phase_v0[i] = pinc*i (per-lane offset) and phase_0 =
//! pinc*cnt_n + phase (cnt_n is a free-running sample counter, reset only
//! on a phrst-qualified descriptor load).
//!
//! There is no output-enable/gain/steady-value output here (readout is a
//! continuous demodulator, not a pulsed generator) -- the legacy file's
//! en_reg logic is present but entirely commented out; not ported.
//!
//! @author  QICK Development Team
//!
//! @version 1.0
///////////////////////////////////////////////////////////////////////////////
module ctrl_dyn_ro #(
    parameter int N = 8  //! Number of parallel DDS/demodulator lanes.
)(
    input  logic             aresetn,     //! Synchronous active-low reset.
    input  logic             aclk,        //! Clock.

    // Fifo interface.
    output logic              fifo_rd_en,  //! Fifo read enable (pop).
    input  logic               fifo_empty,  //! Fifo empty flag.
    input  logic [87:0]        fifo_dout,   //! Fifo output: descriptor.

    // dds control.
    output logic [N*72-1:0]    dds_ctrl,    //! Per-lane DDS control words.

    // Output source selection.
    output logic [1:0]         outsel       //! Output source, latency 7.
);

    typedef enum logic [1:0] {
        READ_ST,
        CNT_ST
    } state_t;

    (* fsm_encoding = "one_hot" *) state_t state;

    // Fifo dout register.
    logic [87:0] fifo_dout_r;

    // Non-stop counter for time calculation (adds N samples each clock tick).
    logic [31:0] cnt_n;
    logic [31:0] cnt_n_reg;

    // Pinc/phase.
    logic [31:0] pinc_int;
    logic [31:0] pinc_r1;
    logic [31:0] pinc_r2;
    logic [31:0] pinc_n;
    logic [31:0] pinc_n_r1;
    logic [31:0] pinc_n_r2;
    logic [31:0] pinc_n_r3;
    logic [31:0] pinc_n_r4;
    logic [31:0] pinc_n_r5;
    logic [31:0] pinc_nm;
    logic [31:0] pinc_nm_r1;
    logic [31:0] pinc_nm_r2;
    logic [31:0] pinc_nm_r3;

    logic [31:0] phase_int;
    logic [31:0] phase_r1;
    logic [31:0] phase_r2;
    logic [31:0] phase_r3;
    logic [31:0] phase_r4;
    logic [31:0] phase_r5;
    logic [31:0] phase_0;
    logic [31:0] phase_0_r1;

    // Phase vectors.
    logic [31:0] phase_v0    [N];
    logic [31:0] phase_v0_r1 [N];
    logic [31:0] phase_v0_r2 [N];
    logic [31:0] phase_v0_r3 [N];
    logic [31:0] phase_v0_r4 [N];
    logic [31:0] phase_v1    [N];
    logic [31:0] phase_v1_r1 [N];

    // sync.
    logic sync_reg;
    logic sync_reg_r1;
    logic sync_reg_r2;
    logic sync_reg_r3;
    logic sync_reg_r4;
    logic sync_reg_r5;
    logic sync_reg_r6;
    logic sync_reg_r7;

    // Number of samples.
    logic [15:0] nsamp_int;

    // Output selection.
    logic [1:0] outsel_int;
    logic [1:0] outsel_r1;
    logic [1:0] outsel_r2;
    logic [1:0] outsel_r3;
    logic [1:0] outsel_r4;
    logic [1:0] outsel_r5;
    logic [1:0] outsel_r6;
    logic [1:0] outsel_r7;

    // Mode.
    logic mode_int;

    // Phase reset.
    logic phrst_int;

    // Load enable flag.
    logic load_int;
    logic load_r;

    // Fifo Read Enable.
    logic rd_en_int;
    logic rd_en_r1;
    logic rd_en_r2;

    // Counter.
    logic [31:0] cnt;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            state <= READ_ST;

            fifo_dout_r <= '0;

            cnt_n     <= '0;
            cnt_n_reg <= '0;

            pinc_r1 <= '0;
            pinc_r2 <= '0;
            pinc_n_r1 <= '0; pinc_n_r2 <= '0; pinc_n_r3 <= '0; pinc_n_r4 <= '0; pinc_n_r5 <= '0;
            pinc_nm_r1 <= '0; pinc_nm_r2 <= '0; pinc_nm_r3 <= '0;

            phase_r1 <= '0; phase_r2 <= '0; phase_r3 <= '0; phase_r4 <= '0; phase_r5 <= '0;
            phase_0_r1 <= '0;

            sync_reg <= 1'b0;
            sync_reg_r1 <= 1'b0; sync_reg_r2 <= 1'b0; sync_reg_r3 <= 1'b0;
            sync_reg_r4 <= 1'b0; sync_reg_r5 <= 1'b0; sync_reg_r6 <= 1'b0; sync_reg_r7 <= 1'b0;

            outsel_r1 <= '0; outsel_r2 <= '0; outsel_r3 <= '0; outsel_r4 <= '0;
            outsel_r5 <= '0; outsel_r6 <= '0; outsel_r7 <= '0;

            load_r <= 1'b0;

            rd_en_r1 <= 1'b0;
            rd_en_r2 <= 1'b0;

            cnt <= '0;
        end else begin
            // State register.
            case (state)
                READ_ST:
                    if (mode_int || !fifo_empty)
                        state <= CNT_ST;
                CNT_ST:
                    if (cnt == 32'(nsamp_int) - 32'd2)
                        state <= READ_ST;
                default:
                    state <= READ_ST;
            endcase

            // Fifo dout register.
            if (load_r)
                fifo_dout_r <= fifo_dout;

            // Non-stop counter for time calculation.
            if (sync_reg == 1'b1 && phrst_int == 1'b1)
                cnt_n <= '0;
            else
                cnt_n <= cnt_n + 32'(N);

            if (sync_reg_r1 == 1'b1)
                cnt_n_reg <= cnt_n;

            // Pinc/phase/sync.
            pinc_r1 <= pinc_int;
            pinc_r2 <= pinc_r1;
            pinc_n_r1 <= pinc_n;
            pinc_n_r2 <= pinc_n_r1;
            pinc_n_r3 <= pinc_n_r2;
            pinc_n_r4 <= pinc_n_r3;
            pinc_n_r5 <= pinc_n_r4;
            pinc_nm_r1 <= pinc_nm;
            pinc_nm_r2 <= pinc_nm_r1;
            pinc_nm_r3 <= pinc_nm_r2;

            phase_r1 <= phase_int;
            phase_r2 <= phase_r1;
            phase_r3 <= phase_r2;
            phase_r4 <= phase_r3;
            phase_r5 <= phase_r4;
            phase_0_r1 <= phase_0;

            sync_reg    <= load_r;
            sync_reg_r1 <= sync_reg;
            sync_reg_r2 <= sync_reg_r1;
            sync_reg_r3 <= sync_reg_r2;
            sync_reg_r4 <= sync_reg_r3;
            sync_reg_r5 <= sync_reg_r4;
            sync_reg_r6 <= sync_reg_r5;
            sync_reg_r7 <= sync_reg_r6;

            // Output selection.
            outsel_r1 <= outsel_int;
            outsel_r2 <= outsel_r1;
            outsel_r3 <= outsel_r2;
            outsel_r4 <= outsel_r3;
            outsel_r5 <= outsel_r4;
            outsel_r6 <= outsel_r5;
            outsel_r7 <= outsel_r6;

            // Load enable flag.
            load_r <= load_int;

            // Fifo Read Enable.
            rd_en_r1 <= rd_en_int;
            rd_en_r2 <= rd_en_r1;

            // Counter.
            if (rd_en_int)
                cnt <= '0;
            else
                cnt <= cnt + 32'd1;
        end
    end

    // FSM outputs.
    always_comb begin
        rd_en_int = 1'b0;
        case (state)
            READ_ST: rd_en_int = 1'b1;
            CNT_ST:  rd_en_int = 1'b0;
            default: rd_en_int = 1'b0;
        endcase
    end

    // Fifo output fields.
    assign pinc_int   = fifo_dout_r[31:0];
    assign phase_int  = fifo_dout_r[63:32];
    assign nsamp_int  = fifo_dout_r[79:64];
    assign outsel_int = fifo_dout_r[81:80];
    assign mode_int   = fifo_dout_r[82];
    assign phrst_int  = fifo_dout_r[83];

    // Frequency calculation.
    assign pinc_n = pinc_r2 * 32'(N);

    // Phase calculation.
    assign pinc_nm = pinc_r2 * cnt_n_reg;
    assign phase_0 = pinc_nm_r3 + phase_r5;

    // Phase vectors.
    for (genvar i = 0; i < N; i = i + 1) begin : g_phase
        always_ff @(posedge aclk) begin
            if (!aresetn) begin
                phase_v0_r1[i] <= '0;
                phase_v0_r2[i] <= '0;
                phase_v0_r3[i] <= '0;
                phase_v0_r4[i] <= '0;
                phase_v1_r1[i] <= '0;
            end else begin
                phase_v0_r1[i] <= phase_v0[i];
                phase_v0_r2[i] <= phase_v0_r1[i];
                phase_v0_r3[i] <= phase_v0_r2[i];
                phase_v0_r4[i] <= phase_v0_r3[i];
                phase_v1_r1[i] <= phase_v1[i];
            end
        end

        assign phase_v0[i] = pinc_r2 * 32'(i);
        assign phase_v1[i] = phase_v0_r4[i] + phase_0_r1;

        assign dds_ctrl[i*72+:72] = {7'h00, sync_reg_r7, phase_v1_r1[i], pinc_n_r5};
    end

    // load_int.
    assign load_int = rd_en_int & ~fifo_empty;

    // Assign outputs.
    assign fifo_rd_en = rd_en_int;
    assign outsel      = outsel_r7;

endmodule
