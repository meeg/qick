// ============================================================================
// File: sgv4_top_tc00.sv
// Description: SVUnit integration testbench for sgv4_top (signal gen v4 top).
//
//   End-to-end: load an envelope via S0, queue a descriptor via S1, and observe
//   the M_AXIS output.
//
//   Differences vs sgv6_top TB:
//     - sgv4_top has NO GEN_DDS / ENVELOPE_TYPE params (real+imag banks are
//       ALWAYS instantiated). Only N and N_DDS.
//     - N_DDS default = 8 (v4) vs 16 (v6).
//     - Extra static register outsel_reg (0=real, 1=imag). The per-descriptor
//       outsel field does NOT pick real/imag at the top; outsel_reg does.
//     - Output is ONE 16-bit value per lane (real OR imag per outsel_reg),
//       width N_DDS*16.
//
//   Envelope memory layout (via axis_to_bram_sg_nt one-hot demux):
//     stream sample k -> bank (k % N_DDS), row (k / N_DDS)
//   With N_DDS parallel banks, N_DDS consecutive samples fill one row across
//   all banks; the next N_DDS samples go to the next row.
//
//   NOTE: there is NO "envelope-ready" CDC handshake in sgv4_top. Load-then-
//   launch ordering is the driver's responsibility, mirrored here by
//   load_envelope() completing (with settle cycles) before queue_descriptor().
// ============================================================================
`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module sgv4_top_unit_test;
    import svunit_pkg::svunit_testcase;

    string name = "sgv4_top_ut";
    svunit_testcase svunit_ut;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real AXI_FREQ  = 100e6;   // envelope-load domain (s0_axis_aclk)
    localparam real ACLK_FREQ = 200e6;   // main domain (aclk)
    localparam int  N     = 8;           // small memory for sim (depth 256/bank)
    localparam int  N_DDS = 8;           // v4 default
    localparam int  MAXV  = 2**15 - 2;   // 32766

    // =========================================================================
    // Clocks & Resets (two domains)
    // =========================================================================
    logic tb_aclk    = 1'b0;
    logic tb_aresetn = 1'b1;
    logic tb_s0_aclk = 1'b0;
    logic tb_s0_arstn = 1'b1;

    clk_gen #(.FREQ (ACLK_FREQ)) u_aclk (.i_enable(1'b1), .o_clk(tb_aclk));
    clk_gen #(.FREQ (AXI_FREQ))  u_s0   (.i_enable(1'b1), .o_clk(tb_s0_aclk));

    // =========================================================================
    // DUT signals
    // =========================================================================
    // S0 (envelope load)
    logic [31:0] tb_s0_tdata  = '0;
    logic        tb_s0_tvalid = 1'b0;
    logic        tb_s0_tready;

    // S1 (descriptor)
    logic [159:0] tb_s1_tdata  = '0;
    logic         tb_s1_tvalid = 1'b0;
    logic         tb_s1_tready;

    // M_AXIS (output)
    logic                tb_m_tready = 1'b1;
    logic                tb_m_tvalid;
    logic [N_DDS*16-1:0] tb_m_tdata;

    // Registers
    logic [31:0] tb_start_addr = '0;
    logic        tb_we         = 1'b0;
    logic        tb_outsel_reg = 1'b0;   // 0=real, 1=imag  (v4-specific)
    logic        tb_sat;

    // =========================================================================
    // Dump
    // =========================================================================
    initial begin
        $dumpfile("sgv4_top.vcd");
        $dumpvars(0, dut);
    end

    // =========================================================================
    // DUT
    // =========================================================================
    sgv4_top #(
        .N     (N),
        .N_DDS (N_DDS)
    ) dut (
        .aresetn          (tb_aresetn),
        .aclk             (tb_aclk),
        .s0_axis_aresetn  (tb_s0_arstn),
        .s0_axis_aclk     (tb_s0_aclk),
        .s0_axis_tdata_i  (tb_s0_tdata),
        .s0_axis_tvalid_i (tb_s0_tvalid),
        .s0_axis_tready_o (tb_s0_tready),
        .s1_axis_tdata_i  (tb_s1_tdata),
        .s1_axis_tvalid_i (tb_s1_tvalid),
        .s1_axis_tready_o (tb_s1_tready),
        .m_axis_tready_i  (tb_m_tready),
        .m_axis_tvalid_o  (tb_m_tvalid),
        .m_axis_tdata_o   (tb_m_tdata),
        .start_addr_reg   (tb_start_addr),
        .we_reg           (tb_we),
        .outsel_reg       (tb_outsel_reg),   // v4-specific
        .o_sat            (tb_sat)
    );

    // =========================================================================
    // Descriptor builder (160-bit, v4 layout, same as ctrl_sgv4).
    //   NOTE: the per-descriptor `outsel` field is carried for ctrl_sgv4 but
    //   does NOT select real/imag at the top level in v4 — outsel_reg does.
    // =========================================================================
    function automatic logic [159:0] build_descr(
        input logic [31:0] freq,  input logic [31:0] phase,
        input logic [15:0] addr,  input logic [15:0] gain,
        input logic [15:0] nsamp, input logic [1:0]  outsel,
        input logic mode, input logic stdysel, input logic phrst
    );
        logic [159:0] d = '0;
        d[31:0]=freq; d[63:32]=phase; d[79:64]=addr; d[111:96]=gain;
        d[143:128]=nsamp; d[145:144]=outsel; d[146]=mode;
        d[147]=stdysel; d[148]=phrst;
        return d;
    endfunction

    // =========================================================================
    // Envelope load helper (S0 domain).
    //   Streams `count` (real, imag) samples starting at write address 0.
    //   Sample k goes to bank (k % N_DDS), row (k / N_DDS).
    // =========================================================================
    task automatic load_envelope(
        input int          count,
        input logic [15:0] re [],   // real samples
        input logic [15:0] im []    // imag samples
    );
        @(posedge tb_s0_aclk);
        tb_start_addr <= '0;
        tb_we         <= 1'b1;       // enable writes (capture)
        // give the writer's CDC + FSM time to reach the write state
        repeat(5) @(posedge tb_s0_aclk);
        for (int k = 0; k < count; k++) begin
            tb_s0_tdata  <= {im[k], re[k]};   // [31:16]=imag, [15:0]=real
            tb_s0_tvalid <= 1'b1;
            @(posedge tb_s0_aclk);
            while (!tb_s0_tready) @(posedge tb_s0_aclk);
        end
        tb_s0_tvalid <= 1'b0;
        repeat(5) @(posedge tb_s0_aclk);
        tb_we <= 1'b0;               // disable writes
        // settle: no envelope-ready CDC exists, let banks stabilise before read
        repeat(5) @(posedge tb_s0_aclk);
    endtask

    // =========================================================================
    // Descriptor queue helper (aclk domain).
    // =========================================================================
    task automatic queue_descriptor(input logic [159:0] d);
        @(posedge tb_aclk);
        tb_s1_tdata  <= d;
        tb_s1_tvalid <= 1'b1;
        @(posedge tb_aclk);
        while (!tb_s1_tready) @(posedge tb_aclk);
        tb_s1_tvalid <= 1'b0;
        @(posedge tb_aclk);
    endtask

    // Wait for the output to become valid; return lane-0 sample.
    task automatic wait_output(output logic [15:0] dout0, input int timeout = 200);
        int t = 0;
        while (!tb_m_tvalid && t < timeout) begin @(posedge tb_aclk); t++; end
        dout0 = tb_m_tdata[15:0];
    endtask

    // =========================================================================
    // SVUnit
    // =========================================================================
    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
        tb_aresetn   <= 1'b0;
        tb_s0_arstn  <= 1'b0;
        tb_s0_tvalid <= 1'b0;
        tb_s1_tvalid <= 1'b0;
        tb_m_tready  <= 1'b1;
        tb_we        <= 1'b0;
        tb_start_addr<= '0;
        tb_outsel_reg<= 1'b0;
        repeat(20) @(posedge tb_aclk);
        tb_aresetn  <= 1'b1;
        tb_s0_arstn <= 1'b1;
        repeat(20) @(posedge tb_aclk);
    endtask

    task teardown();
        svunit_ut.teardown();
        tb_we        <= 1'b0;
        tb_s0_tvalid <= 1'b0;
        tb_s1_tvalid <= 1'b0;
        repeat(10) @(posedge tb_aclk);
    endtask

    initial begin
        #500_000_000;
        $display("INFO: Global timeout reached");
        $finish;
    end

    `SVUNIT_TESTS_BEGIN
    `include "sgv4_top_tests.sv"
    `SVUNIT_TESTS_END
endmodule