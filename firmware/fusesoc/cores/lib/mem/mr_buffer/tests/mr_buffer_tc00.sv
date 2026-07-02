// ============================================================================
// File: mr_buffer_tc00.sv
// Description: SVUnit testbench top-level for the mr_buffer module.
//
// Design overview:
//   mr_buffer captures NM parallel channels of B bits each into NM independent
//   BRAMs (depth = 2**N per BRAM) on the write side (s_axis_aclk domain).
//   On the read side (m_axis_aclk domain), bram_to_axis_nt serialises all
//   NM*2**N words into a single B-bit AXI4-Stream:
//
//     Output word order (TOTAL_WORDS = NM * 2**N words per read burst):
//       word 0            : ch0 @ addr 0
//       word 1            : ch1 @ addr 0
//       ...
//       word NM-1         : ch(NM-1) @ addr 0
//       word NM           : ch0 @ addr 1
//       ...
//       word NM*2**N - 1  : ch(NM-1) @ addr (2**N - 1)  ← tlast here
//
// IMPORTANT: every call to start_reader() starts a burst of exactly
// TOTAL_WORDS beats ending with tlast=1.  Always consume all TOTAL_WORDS
// beats before calling stop_reader(), otherwise the next start_reader() will
// see stale data from the previous incomplete burst still in the output FIFO.
// ============================================================================

`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module mr_buffer_unit_test;

    import svunit_pkg::svunit_testcase;

    string name = "mr_buffer_tests";
    svunit_testcase svunit_ut;

    // =========================================================================
    // Parameters — must match the DUT instantiation below
    // =========================================================================
    localparam real CLK_S_FREQ = 150e6;
    localparam real CLK_M_FREQ = 200e6;

    localparam int NM = 8;
    localparam int N  = 8;
    localparam int B  = 16;

    localparam int S_DATA_W  = NM * B;
    localparam int S_STRB_W  = (NM * B) / 8;
    localparam int M_DATA_W  = B;
    localparam int M_STRB_W  = B / 8;
    localparam int DEPTH     = 2**N;          // per-BRAM depth
    localparam int TOTAL_WORDS = DEPTH * NM;  // words per read burst

    // =========================================================================
    // Clocks & Resets
    // =========================================================================
    logic s_axis_aclk    = 1'b0;
    logic s_axis_aresetn = 1'b1;
    logic m_axis_aclk    = 1'b0;
    logic m_axis_aresetn = 1'b1;

    // =========================================================================
    // Control signals
    // =========================================================================
    logic        trigger        = 1'b0;
    logic        dw_capture_reg = 1'b0;
    logic        dr_start_reg   = 1'b0;
    logic [31:0] debug_reg      = '0;

    // Debug probes (wired but not checked in tests)
    logic [31:0] s_dbg_probe;
    logic [31:0] m_dbg_probe;

    // =========================================================================
    // AXI4-Stream interfaces
    // =========================================================================
    axi4_stream_if #(
        .TDATA_WIDTH (S_DATA_W),
        .HAS_TSTRB   (1'b1),
        .HAS_TKEEP   (1'b0),
        .HAS_TID     (1'b0),
        .HAS_TDEST   (1'b0),
        .HAS_TUSER   (1'b0)
    ) s_axis_if (
        .aclk    (s_axis_aclk),
        .aresetn (s_axis_aresetn)
    );

    axi4_stream_if #(
        .TDATA_WIDTH (M_DATA_W),
        .HAS_TSTRB   (1'b1),
        .HAS_TKEEP   (1'b0),
        .HAS_TID     (1'b0),
        .HAS_TDEST   (1'b0),
        .HAS_TUSER   (1'b0)
    ) m_axis_if (
        .aclk    (m_axis_aclk),
        .aresetn (m_axis_aresetn)
    );

    // =========================================================================
    // Clock generators
    // =========================================================================
    clk_gen #(.FREQ (CLK_S_FREQ)) u_clk_s (
        .i_enable (1'b1),
        .o_clk    (s_axis_aclk)
    );

    clk_gen #(.FREQ (CLK_M_FREQ)) u_clk_m (
        .i_enable (1'b1),
        .o_clk    (m_axis_aclk)
    );

    // =========================================================================
    // Waveform dump
    // =========================================================================
    initial begin
        $dumpfile("mr_buffer.vcd");
        $dumpvars(0, dut);
    end

    // =========================================================================
    // DUT
    // =========================================================================
    mr_buffer #(
        .NM (NM),
        .N  (N),
        .B  (B)
    ) dut (
        .trigger        (trigger),
        .s_axis_aclk    (s_axis_aclk),
        .s_axis_aresetn (s_axis_aresetn),
        .s_axis_tready  (s_axis_if.slave.tready),
        .s_axis_tdata   (s_axis_if.slave.tdata),
        .s_axis_tstrb   (s_axis_if.slave.tstrb),
        .s_axis_tlast   (s_axis_if.slave.tlast),
        .s_axis_tvalid  (s_axis_if.slave.tvalid),
        .m_axis_aclk    (m_axis_aclk),
        .m_axis_aresetn (m_axis_aresetn),
        .m_axis_tvalid  (m_axis_if.master.tvalid),
        .m_axis_tdata   (m_axis_if.master.tdata),
        .m_axis_tstrb   (m_axis_if.master.tstrb),
        .m_axis_tlast   (m_axis_if.master.tlast),
        .m_axis_tready  (m_axis_if.master.tready),
        .dw_capture_reg (dw_capture_reg),
        .dr_start_reg   (dr_start_reg),
        .debug_reg      (debug_reg),
        .s_dbg_probe    (s_dbg_probe),
        .m_dbg_probe    (m_dbg_probe)
    );

    // =========================================================================
    // Helper tasks
    // =========================================================================

    // arm_and_trigger: assert capture_reg and wait for CDC (2 cycles + margin),
    // then pulse trigger for one cycle and wait for CDC again.
    // After this returns all NM axis_to_bram_trig FSMs are in CAPTURE_ST.
    task automatic arm_and_trigger();
        @(s_axis_if.s_cb);
        dw_capture_reg <= 1'b1;
        repeat(5) @(s_axis_if.s_cb);  // capture_sync CDC settle

        trigger <= 1'b1;
        @(s_axis_if.s_cb);
        trigger <= 1'b0;
        repeat(5) @(s_axis_if.s_cb);  // trigger_resync CDC settle
    endtask

    // disarm: de-assert capture_reg.  With the abort condition in
    // axis_to_bram_trig (!capture_reg -> END_ST), the FSM will drain the
    // internal FIFO and return to INIT_ST.  Wait long enough for that
    // transition so the next arm_and_trigger() starts from a clean state.
    task automatic disarm();
        @(s_axis_if.s_cb);
        dw_capture_reg <= 1'b0;
        // Wait for FSM to reach INIT_ST (END_ST drains FIFO first)
        @(s_axis_if.s_cb);
        while (dut.gen_channel[0].u_axis_to_bram_trig.current_state !== 0)
            @(s_axis_if.s_cb);
        repeat(5) @(s_axis_if.s_cb);
    endtask

    // start_reader: assert dr_start_reg and wait for CDC into m_axis_aclk.
    // This starts a burst of exactly TOTAL_WORDS beats on m_axis.
    task automatic start_reader();
        @(m_axis_if.m_cb);
        dr_start_reg <= 1'b1;
        repeat(5) @(m_axis_if.m_cb);
    endtask

    // stop_reader: de-assert dr_start_reg.
    // Only call this AFTER consuming all TOTAL_WORDS beats (including tlast).
    task automatic stop_reader();
        @(m_axis_if.m_cb);
        dr_start_reg <= 1'b0;
        repeat(5) @(m_axis_if.m_cb);
    endtask

    // build_word: pack NM channel values (B bits each) into S_DATA_W bits.
    // ch[0] -> bits [B-1:0]  (lowest channel, first word on read side),
    // ch[i] -> bits [(i+1)*B-1 : i*B].
    function automatic logic [S_DATA_W-1:0] build_word(logic [B-1:0] ch [NM]);
        logic [S_DATA_W-1:0] w = '0;
        for (int i = 0; i < NM; i++)
            w[(i+1)*B-1 -: B] = ch[i];
        return w;
    endfunction

    // send_beat: transmit one S_DATA_W-bit AXI4-Stream beat.
    // ch0_val is written to channel 0; all other channels receive a
    // derived non-overlapping pattern so misrouting is detectable.
    task automatic send_beat(input logic [B-1:0] ch0_val, input logic last);
        logic [B-1:0] ch [NM];
        ch[0] = ch0_val;
        for (int i = 1; i < NM; i++)
            ch[i] = ch0_val + B'(i * 16'h1000);
        s_axis_if.tx(build_word(ch), last);
    endtask

    // do_capture: convenience wrapper — arm, trigger, send one beat, disarm.
    // After this returns the BRAM holds the captured data and the FSM is
    // back in INIT_ST, ready for the next capture.
    task automatic do_capture(input logic [B-1:0] ch0_val);
        arm_and_trigger();
        send_beat(ch0_val, 1'b1);
        // Give the internal FIFO time to drain into BRAM before disarming
        repeat(5) @(s_axis_if.s_cb);
        disarm();
        // CDC margin before the caller can start reading (150 -> 200 MHz)
        repeat(20) @(m_axis_if.m_cb);
    endtask

    // drain_burst: consume all TOTAL_WORDS beats of an ongoing read burst,
    // optionally capturing the first word into first_word.
    // tlast is verified on the last beat.
    task automatic drain_burst(output logic [B-1:0] first_word);
        logic [B-1:0] word;
        logic         last;
        for (int i = 0; i < TOTAL_WORDS; i++) begin
            m_axis_if.rx(word, last);
            if (i == 0) first_word = word;
            if (i == TOTAL_WORDS - 1)
                `FAIL_IF(last !== 1'b1);
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

        // Deassert all control signals
        dw_capture_reg <= 1'b0;
        dr_start_reg   <= 1'b0;
        trigger        <= 1'b0;
        debug_reg      <= '0;

        // Apply synchronous reset to both domains
        s_axis_aresetn = 1'b0;
        m_axis_aresetn = 1'b0;
        repeat(5) begin
            @(s_axis_if.s_cb);
            @(m_axis_if.m_cb);
        end
        s_axis_aresetn = 1'b1;
        m_axis_aresetn = 1'b1;

        // Allow XPM FIFOs and synchronisers to settle
        repeat(20) @(s_axis_if.s_cb);
        repeat(20) @(m_axis_if.m_cb);
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    // Global timeout
    initial begin
        #100_000_000;
        $display("INFO: Global timeout reached");
        $finish;
    end

    // =========================================================================
    // Test cases
    // =========================================================================
    `SVUNIT_TESTS_BEGIN
    `include "mr_buffer_tests.sv"
    `SVUNIT_TESTS_END

endmodule