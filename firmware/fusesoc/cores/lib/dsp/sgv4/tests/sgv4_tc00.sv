// ============================================================================
// File: sgv4_tc00.sv
// Description: SVUnit testbench for sgv4 (v4 signal generator datapath).
//
//   Adapted from sgv6 testbench for v4 specific features:
//   - 8 parallel lanes (N_DDS=8)
//   - Complex output (I/Q pairs, 32 bits per lane)
//   - OUTSEL selection (I only or I/Q)
//   - DDS always present
// ============================================================================
`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module sgv4_unit_test;
    import svunit_pkg::svunit_testcase;

    string name = "sgv4_ut";
    svunit_testcase svunit_ut;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real CLOCK_FREQUENCY = 200e6;
    localparam int  N     = 16;
    localparam int  N_DDS = 8;          // v4 has 8 lanes
    localparam int  MAXV  = 2**15 - 2;   // 32766

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    logic tb_clk  = 1'b0;
    logic tb_rstn = 1'b1;
    clk_gen #(.FREQ (CLOCK_FREQUENCY)) u_clk (.i_enable(1'b1), .o_clk(tb_clk));

    // =========================================================================
    // DUT signals
    // =========================================================================
    logic                tb_fifo_rd_en;
    logic                tb_fifo_empty = 1'b1;
    logic [159:0]        tb_fifo_dout  = '0;
    logic [N-1:0]        tb_mem_addr;
    logic [N_DDS*16-1:0] tb_mem_real = '0;
    logic [N_DDS*16-1:0] tb_mem_imag = '0;
    logic                tb_outsel_reg  = 1'b0;   // 0 = real, 1 = imag
    logic                tb_axis_tready = 1'b1;
    logic                tb_axis_tvalid;
    logic [N_DDS*16-1:0] tb_axis_tdata;           // v4: 16 bits per lane (real OR imag)
    logic                tb_sat;
    // =========================================================================
    // Dump
    // =========================================================================
    initial begin
        $dumpfile("sgv4.vcd");
        $dumpvars(0, dut);
    end

    // =========================================================================
    // DUT
    // =========================================================================
    sgv4 #(
        .N     (N),
        .N_DDS (N_DDS)
    ) dut (
        .i_rstn          (tb_rstn),
        .i_clk           (tb_clk),
        .o_fifo_rd_en    (tb_fifo_rd_en),
        .i_fifo_empty    (tb_fifo_empty),
        .i_fifo_dout     (tb_fifo_dout),
        .o_mem_addr      (tb_mem_addr),
        .i_mem_dout_real (tb_mem_real),
        .i_mem_dout_imag (tb_mem_imag),
        .i_outsel_reg    (tb_outsel_reg),
        .i_axis_tready   (tb_axis_tready),
        .o_axis_tvalid   (tb_axis_tvalid),
        .o_axis_tdata    (tb_axis_tdata),
        .o_sat           (tb_sat)
    );

    // =========================================================================
    // Helper: build a 160-bit waveform descriptor (v4 format).
    // =========================================================================
    function automatic logic [159:0] build_descr(
        input logic [31:0] freq,
        input logic [31:0] phase,
        input logic [15:0] addr,
        input logic [15:0] gain,
        input logic [15:0] nsamp,
        input logic [1:0]  outsel,
        input logic        mode,
        input logic        stdysel,
        input logic        phrst,
        input logic        iqsel
    );
        logic [159:0] d;
        d = '0;
        d[31:0]    = freq;
        d[63:32]   = phase;
        d[79:64]   = addr;
        d[111:96]  = gain;
        d[143:128] = nsamp;
        d[145:144] = outsel;
        d[146]     = mode;
        d[147]     = stdysel;
        d[148]     = phrst;
        d[149]     = iqsel;
        return d;
    endfunction

    // =========================================================================
    // Reference models (single lane, signed 16-bit operands, COMPLEX).
    // =========================================================================
    
    // Faithful model: reproduces the FIXED RTL amplitude chain (complex).
    function automatic logic [31:0] ref_rtl_prod_complex(
        input logic signed [15:0] env_re, input logic signed [15:0] env_im,
        input logic signed [15:0] cos,    input logic signed [15:0] sin,
        input logic signed [15:0] gain
    );
        logic signed [31:0] pa_re, pb_re, pa_im, pb_im;
        logic signed [31:0] pfull_re, pfull_im;
        logic        [15:0] pq_re_u, pq_im_u;
        logic signed [15:0] pq_re_s, pq_im_s;
        logic signed [31:0] pg_re, pg_im;
        logic signed [16:0] round_ext_re, round_ext_im;
        logic signed [15:0] out_re, out_im;
        begin
            // Complex product: (a_real*b_real - a_imag*b_imag) + j(a_real*b_imag + a_imag*b_real)
            pa_re = cos * env_re;
            pb_re = sin * env_im;
            pa_im = cos * env_im;
            pb_im = sin * env_re;
            
            pfull_re = pa_re - pb_re;
            pfull_im = pa_im + pb_im;
            
            // FIX: [30:15] keeps full Q15 scale
            pq_re_u = pfull_re[30:15];
            pq_im_u = pfull_im[30:15];
            pq_re_s = pq_re_u;
            pq_im_s = pq_im_u;
            
            // Gain stage
            pg_re = pq_re_s * gain;
            pg_im = pq_im_s * gain;
            
            // Rounding with saturation
            round_ext_re = pg_re[31:15];
            round_ext_im = pg_im[31:15];
            
            out_re = (round_ext_re >  17'sd32766) ? 16'sd32766 :
                     (round_ext_re < -17'sd32766) ? -16'sd32766 :
                     round_ext_re[15:0];
            out_im = (round_ext_im >  17'sd32766) ? 16'sd32766 :
                     (round_ext_im < -17'sd32766) ? -16'sd32766 :
                     round_ext_im[15:0];
            
            return {out_im, out_re};
        end
    endfunction

    // Ideal model: Q15 multiply chain with saturation (complex).
    function automatic logic [31:0] ref_ideal_prod_complex(
        input logic signed [15:0] env_re, input logic signed [15:0] env_im,
        input logic signed [15:0] cos,    input logic signed [15:0] sin,
        input logic signed [15:0] gain
    );
        logic signed [31:0] p1_re, p1_im, p2_re, p2_im;
        logic signed [31:0] q1_re, q1_im;
        logic signed [15:0] out_re, out_im;
        begin
            // Envelope * DDS (Q15*Q15 = Q30)
            p1_re = cos * env_re - sin * env_im;
            p1_im = cos * env_im + sin * env_re;
            q1_re = p1_re >>> 15;  // back to Q15
            q1_im = p1_im >>> 15;
            
            // Gain (Q15*Q15 = Q30)
            p2_re = q1_re * gain;
            p2_im = q1_im * gain;
            out_re = p2_re >>> 15;
            out_im = p2_im >>> 15;
            
            // Saturate
            if (out_re >  MAXV) out_re =  MAXV;
            if (out_re < -MAXV) out_re = -MAXV;
            if (out_im >  MAXV) out_im =  MAXV;
            if (out_im < -MAXV) out_im = -MAXV;
            
            return {out_im, out_re};
        end
    endfunction

    // Wrapper: gives half (real or imag) selected by outsel.
    function automatic logic [15:0] ref_rtl_sel(
        input logic signed [15:0] env_re, input logic signed [15:0] env_im,
        input logic signed [15:0] cos,    input logic signed [15:0] sin,
        input logic signed [15:0] gain,   input logic outsel
    );
        logic [31:0] full = ref_rtl_prod_complex(env_re, env_im, cos, sin, gain);
        return (outsel == 1'b0) ? full[15:0] : full[31:16];
    endfunction

    function automatic logic [15:0] ref_ideal_sel(
        input logic signed [15:0] env_re, input logic signed [15:0] env_im,
        input logic signed [15:0] cos,    input logic signed [15:0] sin,
        input logic signed [15:0] gain,   input logic outsel
    );
        logic [31:0] full = ref_ideal_prod_complex(env_re, env_im, cos, sin, gain);
        return (outsel == 1'b0) ? full[15:0] : full[31:16];
    endfunction

    // =========================================================================
    // FIFO model: present one descriptor.
    // =========================================================================
    task automatic load_descriptor(input logic [159:0] descr);
        tb_fifo_dout  <= descr;
        tb_fifo_empty <= 1'b0;
        @(posedge tb_clk);
        while (!tb_fifo_rd_en) @(posedge tb_clk);
        tb_fifo_empty <= 1'b1;
        @(posedge tb_clk);
    endtask

    // =========================================================================
    // Helper tasks
    // =========================================================================
    task automatic set_envelope(input logic [15:0] re, input logic [15:0] im);
        for (int i = 0; i < N_DDS; i++) begin
            tb_mem_real[i*16 +: 16] = re;
            tb_mem_imag[i*16 +: 16] = im;
        end
    endtask

    task automatic wait_output(output logic [31:0] dout0, input int timeout = 100);
        int t = 0;
        while (!tb_axis_tvalid && t < timeout) begin @(posedge tb_clk); t++; end
        dout0 = tb_axis_tdata[15:0];
    endtask

    // =========================================================================
    // SVUnit
    // =========================================================================
    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
        tb_rstn        <= 1'b0;
        tb_fifo_empty  <= 1'b1;
        tb_fifo_dout   <= '0;
        tb_mem_real    <= '0;
        tb_mem_imag    <= '0;
        tb_axis_tready <= 1'b1;
        repeat(15) @(posedge tb_clk);
        tb_rstn <= 1'b1;
        repeat(10) @(posedge tb_clk);
    endtask

    task teardown();
        svunit_ut.teardown();
        tb_fifo_empty <= 1'b1;
        repeat(10) @(posedge tb_clk);
    endtask

    initial begin
        #100_000_000;
        $display("INFO: Global timeout reached");
        $finish;
    end

    `SVUNIT_TESTS_BEGIN
    `include "sgv4_tests.sv"
    `SVUNIT_TESTS_END

endmodule
