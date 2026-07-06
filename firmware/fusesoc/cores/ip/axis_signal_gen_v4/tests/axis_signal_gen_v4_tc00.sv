// ============================================================================
// File: axis_signal_gen_v4_tc00.sv
// Description: SVUnit integration testbench for the axis_signal_gen_v4 IP.
//
//   Full IP flow: configure registers via AXI4-Lite (start_addr, we, outsel),
//   load an envelope via S0, queue a descriptor via S1, observe M_AXIS output.
//   v4 differs from v6: real/imag output select is STATIC via OUTSEL_REG (not a
//   per-descriptor bit); no GEN_DDS / ENVELOPE_TYPE params.
//
//   Three clock domains: s_axi_aclk, s0_axis_aclk, aclk.
// ============================================================================
`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module axis_signal_gen_v4_unit_test;
    import svunit_pkg::svunit_testcase;
    string name = "axis_signal_gen_v4_ut";
    svunit_testcase svunit_ut;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real AXI_FREQ  = 100e6;
    localparam real S0_FREQ   = 100e6;
    localparam real ACLK_FREQ = 200e6;
    localparam int  N     = 8;           // small memory for sim
    localparam int  N_DDS = 16;
    localparam int  MAXV  = 2**15 - 2;

    // Register byte addresses (opción B: STATUS/CTRL igual a v6, OUTSEL nuevo).
    localparam logic [5:0] REG_START_ADDR = 6'h00;
    localparam logic [5:0] REG_WE         = 6'h04;
    localparam logic [5:0] REG_RNDQ       = 6'h08;   // dummy (deprecado)
    localparam logic [5:0] REG_STATUS     = 6'h0C;
    localparam logic [5:0] REG_CTRL       = 6'h10;
    localparam logic [5:0] REG_OUTSEL     = 6'h14;   // v4-only: 0=real, 1=imag

    // =========================================================================
    // Clocks & Resets (three domains)
    // =========================================================================
    logic s_axi_aclk    = 1'b0;
    logic s_axi_aresetn = 1'b1;
    logic s0_axis_aclk  = 1'b0;
    logic s0_axis_arstn = 1'b1;
    logic aclk          = 1'b0;
    logic aresetn       = 1'b1;

    clk_gen #(.FREQ (AXI_FREQ))  u_axi (.i_enable(1'b1), .o_clk(s_axi_aclk));
    clk_gen #(.FREQ (S0_FREQ))   u_s0  (.i_enable(1'b1), .o_clk(s0_axis_aclk));
    clk_gen #(.FREQ (ACLK_FREQ)) u_a   (.i_enable(1'b1), .o_clk(aclk));

    // =========================================================================
    // Interfaces
    // =========================================================================
    axi4_lite_if #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (6)
    ) s_axi (
        .aclk    (s_axi_aclk),
        .aresetn (s_axi_aresetn)
    );

    axi4_stream_if #(.TDATA_WIDTH(32))       s0_if (.aclk(s0_axis_aclk), .aresetn(s0_axis_arstn));
    axi4_stream_if #(.TDATA_WIDTH(160))      s1_if (.aclk(aclk),         .aresetn(aresetn));
    axi4_stream_if #(.TDATA_WIDTH(N_DDS*16)) m_if  (.aclk(aclk),         .aresetn(aresetn));

    // =========================================================================
    // Dump
    // =========================================================================
    initial begin
        $dumpfile("axis_signal_gen_v4.vcd");
        $dumpvars(0, dut);
    end

    // =========================================================================
    // DUT  (v4: NO GEN_DDS, NO ENVELOPE_TYPE)
    // =========================================================================
    axis_signal_gen_v4 #(
        .N     (N),
        .N_DDS (N_DDS)
    ) dut (
        // AXI-Lite
        .s_axi_aclk    (s_axi_aclk),
        .s_axi_aresetn (s_axi_aresetn),
        .s_axi_awaddr  (s_axi.awaddr),
        .s_axi_awprot  (s_axi.awprot),
        .s_axi_awvalid (s_axi.awvalid),
        .s_axi_awready (s_axi.awready),
        .s_axi_wdata   (s_axi.wdata),
        .s_axi_wstrb   (s_axi.wstrb),
        .s_axi_wvalid  (s_axi.wvalid),
        .s_axi_wready  (s_axi.wready),
        .s_axi_bresp   (s_axi.bresp),
        .s_axi_bvalid  (s_axi.bvalid),
        .s_axi_bready  (s_axi.bready),
        .s_axi_araddr  (s_axi.araddr),
        .s_axi_arprot  (s_axi.arprot),
        .s_axi_arvalid (s_axi.arvalid),
        .s_axi_arready (s_axi.arready),
        .s_axi_rdata   (s_axi.rdata),
        .s_axi_rresp   (s_axi.rresp),
        .s_axi_rvalid  (s_axi.rvalid),
        .s_axi_rready  (s_axi.rready),
        // S0 envelope
        .s0_axis_aclk    (s0_axis_aclk),
        .s0_axis_aresetn (s0_axis_arstn),
        .s0_axis_tdata   (s0_if.tdata),
        .s0_axis_tvalid  (s0_if.tvalid),
        .s0_axis_tready  (s0_if.tready),
        // aclk domain
        .aclk    (aclk),
        .aresetn (aresetn),
        // S1 descriptor
        .s1_axis_tdata  (s1_if.tdata),
        .s1_axis_tvalid (s1_if.tvalid),
        .s1_axis_tready (s1_if.tready),
        // M output
        .m_axis_tready (m_if.tready),
        .m_axis_tvalid (m_if.tvalid),
        .m_axis_tdata  (m_if.tdata),
        // Debug port
        .saturating    (/* observed via dut.saturating hierarchical ref */)
    );

    // =========================================================================
    // Descriptor builder (160-bit). outsel[145:144] = SRC (0=product,1=dds,2=mem).
    // NOTE v4: real/imag select is NOT here — it is the static OUTSEL_REG.
    // =========================================================================
    function automatic logic [159:0] build_descr(
        input logic [31:0] freq,  input logic [31:0] phase,
        input logic [15:0] addr,  input logic [15:0] gain,
        input logic [15:0] nsamp, input logic [1:0]  src,
        input logic mode, input logic stdysel, input logic phrst
    );
        logic [159:0] d = '0;
        d[31:0]=freq; d[63:32]=phase; d[79:64]=addr; d[111:96]=gain;
        d[143:128]=nsamp; d[145:144]=src; d[146]=mode;
        d[147]=stdysel; d[148]=phrst;
        return d;
    endfunction

    // =========================================================================
    // Register access (AXI-Lite).
    // =========================================================================
    task automatic reg_write(input logic [5:0] addr, input logic [31:0] data);
        s_axi.axi_write(addr, data);
    endtask
    task automatic reg_read(input logic [5:0] addr, output logic [31:0] data);
        s_axi.axi_read(addr, data);
    endtask

    // =========================================================================
    // Envelope load: set start_addr + we via AXI-Lite, stream via S0.
    // =========================================================================
    task automatic load_envelope(
        input int          count,
        input logic [15:0] re [],
        input logic [15:0] im []
    );
        reg_write(REG_START_ADDR, 32'd0);
        reg_write(REG_WE, 32'd1);
        repeat(10) @(posedge s0_axis_aclk);   // CDC margin for we_reg
        for (int k = 0; k < count; k++) begin
            s0_if.m_cb.tdata  <= {im[k], re[k]};
            s0_if.m_cb.tvalid <= 1'b1;
            @(s0_if.m_cb);
            while (!s0_if.m_cb.tready) @(s0_if.m_cb);
        end
        s0_if.m_cb.tvalid <= 1'b0;
        repeat(5) @(posedge s0_axis_aclk);
        reg_write(REG_WE, 32'd0);
        repeat(10) @(posedge s0_axis_aclk);
    endtask

    // Constant envelope with independent real/imag (needed for OUTSEL test).
    task automatic const_envelope_ri(
        input int count, input logic [15:0] rval, input logic [15:0] ival,
        output logic [15:0] re [], output logic [15:0] im []
    );
        re = new[count]; im = new[count];
        for (int k = 0; k < count; k++) begin re[k]=rval; im[k]=ival; end
    endtask

    // Back-compat: constant real, zero imag.
    task automatic const_envelope(
        input int count, input logic [15:0] val,
        output logic [15:0] re [], output logic [15:0] im []
    );
        const_envelope_ri(count, val, 16'h0000, re, im);
    endtask

    // =========================================================================
    // Descriptor queue (S1).
    // =========================================================================
    task automatic queue_descriptor(input logic [159:0] d);
        @(posedge aclk);
        s1_if.tdata  <= d;
        s1_if.tvalid <= 1'b1;
        @(posedge aclk);
        while (!s1_if.tready) @(posedge aclk);
        s1_if.tvalid <= 1'b0;
        @(posedge aclk);
    endtask

    // Capture the output burst, return the peak (lane 0).
    task automatic capture_burst(output logic [15:0] peak, input int timeout = 300);
        int t = 0, n = 0;
        peak = '0;
        m_if.s_cb.tready <= 1'b1;
        while (!m_if.tvalid && t < timeout) begin @(m_if.s_cb); t++; end
        while (m_if.tvalid && n < timeout) begin
            if ($signed(m_if.tdata[15:0]) > $signed(peak)) peak = m_if.tdata[15:0];
            n++;
            @(m_if.s_cb);
        end
    endtask

    // =========================================================================
    // SVUnit
    // =========================================================================
    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
        s_axi_aresetn <= 1'b0;
        s0_axis_arstn <= 1'b0;
        aresetn       <= 1'b0;
        s0_if.m_cb.tvalid <= 1'b0;
        s1_if.m_cb.tvalid <= 1'b0;
        m_if.s_cb.tready  <= 1'b0;
        repeat(20) @(posedge aclk);
        s_axi_aresetn <= 1'b1;
        s0_axis_arstn <= 1'b1;
        aresetn       <= 1'b1;
        s_axi.reset();
        repeat(20) @(posedge aclk);
    endtask

    task teardown();
        svunit_ut.teardown();
        s0_if.m_cb.tvalid <= 1'b0;
        s1_if.m_cb.tvalid <= 1'b0;
        repeat(10) @(posedge aclk);
    endtask

    initial begin
        #500_000_000;
        $display("INFO: Global timeout reached");
        $finish;
    end

    `SVUNIT_TESTS_BEGIN
    `include "axis_signal_gen_v4_tests.sv"
    `SVUNIT_TESTS_END
endmodule
