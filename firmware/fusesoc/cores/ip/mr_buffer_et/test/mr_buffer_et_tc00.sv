// ============================================================================
// File: mr_buffer_et_tc00.sv
// Description: SVUnit testbench top-level for mr_buffer_et.
//
// mr_buffer_et wraps mr_buffer with an AXI4-Lite slave (axil_slv) to expose
// control registers:
//
//   Register map (AXI_DW=32, AXI_AW=6, byte-addressed, ADDR_LSB=2):
//     0x00  reg 0  dw_capture_reg : bit 0 = capture enable
//     0x04  reg 1  dr_start_reg   : bit 0 = read start
//     0x3C  reg 15 debug_reg      : bit 0 = force trigger, bit 1 = tready force
//
// Three independent clock domains:
//   s_axi_aclk   (AXI_FREQ)    : AXI4-Lite register access
//   s_axis_aclk  (S_AXIS_FREQ) : write-side data capture
//   m_axis_aclk  (M_AXIS_FREQ) : read-side data output
//
// Read-burst protocol (bram_to_axis_nt):
//   One dr_start_reg write triggers a burst of TOTAL_WORDS = NM * 2**N beats.
//   Word order: ch0@addr0, ch1@addr0, ..., ch(NM-1)@addr0,
//               ch0@addr1, ..., ch(NM-1)@addr(2**N-1)  <- tlast
//   Always drain all TOTAL_WORDS beats before writing dr_start_reg again.
//
// NOTE: mr_buffer_et declares m_axis_tdata as [NM*B-1:0] but mr_buffer drives
// only the low B bits.  Tests read m_axis_if.tdata[B-1:0] for channel-0.
// ============================================================================

`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module mr_buffer_et_unit_test;

    import svunit_pkg::svunit_testcase;

    string name = "mr_buffer_et_tests";
    svunit_testcase svunit_ut;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real AXI_FREQ    = 100e6;
    localparam real S_AXIS_FREQ = 150e6;
    localparam real M_AXIS_FREQ = 200e6;

    localparam int NM         = 8;
    localparam int N          = 8;
    localparam int B          = 16;
    localparam int C_S_AXI_DW = 32;
    localparam int C_S_AXI_AW = 6;

    localparam int S_DATA_W    = NM * B;
    localparam int S_STRB_W    = (NM * B) / 8;
    localparam int M_DATA_W    = B;   // mr_buffer_et output bus width
    localparam int M_STRB_W    = B / 8;
    localparam int DEPTH       = 2**N;
    localparam int TOTAL_WORDS = DEPTH * NM;

    // AXI4-Lite register byte addresses
    localparam logic [C_S_AXI_AW-1:0] REG_DW_CAPTURE = 6'h00;
    localparam logic [C_S_AXI_AW-1:0] REG_DR_START   = 6'h04;
    localparam logic [C_S_AXI_AW-1:0] REG_DEBUG      = 6'h3C;

    // =========================================================================
    // Clocks & Resets
    // =========================================================================
    logic s_axi_aclk     = 1'b0;
    logic s_axi_aresetn  = 1'b1;
    logic s_axis_aclk    = 1'b0;
    logic s_axis_aresetn = 1'b1;
    logic m_axis_aclk    = 1'b0;
    logic m_axis_aresetn = 1'b1;

    logic trigger = 1'b0;

    // =========================================================================
    // Interfaces
    // =========================================================================
    axi4_lite_if #(
        .DATA_WIDTH (C_S_AXI_DW),
        .ADDR_WIDTH (C_S_AXI_AW)
    ) s_axi (
        .aclk    (s_axi_aclk),
        .aresetn (s_axi_aresetn)
    );

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
    clk_gen #(.FREQ (AXI_FREQ))    u_clk_axi (.i_enable(1'b1), .o_clk(s_axi_aclk));
    clk_gen #(.FREQ (S_AXIS_FREQ)) u_clk_s   (.i_enable(1'b1), .o_clk(s_axis_aclk));
    clk_gen #(.FREQ (M_AXIS_FREQ)) u_clk_m   (.i_enable(1'b1), .o_clk(m_axis_aclk));

    // =========================================================================
    // Waveform dump
    // =========================================================================
    initial begin
        $dumpfile("mr_buffer_et.vcd");
        $dumpvars(0, dut);
    end

    // =========================================================================
    // DUT
    // =========================================================================
    mr_buffer_et #(
        .NM         (NM),
        .N          (N),
        .B          (B),
        .C_S_AXI_DW (C_S_AXI_DW),
        .C_S_AXI_AW (C_S_AXI_AW),
        .DEBUG      (0)
    ) dut (
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
        .s_axis_aclk    (s_axis_aclk),
        .s_axis_aresetn (s_axis_aresetn),
        .s_axis_tdata   (s_axis_if.tdata),
        .s_axis_tstrb   (s_axis_if.tstrb),
        .s_axis_tvalid  (s_axis_if.tvalid),
        .s_axis_tlast   (s_axis_if.tlast),
        .s_axis_tready  (s_axis_if.tready),
        .m_axis_aclk    (m_axis_aclk),
        .m_axis_aresetn (m_axis_aresetn),
        .m_axis_tdata   (m_axis_if.tdata),
        .m_axis_tstrb   (m_axis_if.tstrb),
        .m_axis_tvalid  (m_axis_if.tvalid),
        .m_axis_tlast   (m_axis_if.tlast),
        .m_axis_tready  (m_axis_if.tready),
        .trigger        (trigger),
        .s_dbg_probe    (),
        .m_dbg_probe    ()
    );

    // =========================================================================
    // AXI4-Lite register access helpers
    //
    // axi4_lite_if tasks (axi_write, axi_read) operate on posedge aclk using
    // non-blocking assignments.  No separate clocking block is needed — the
    // interface handles timing internally.
    // =========================================================================

    task automatic set_capture(input logic val);
        s_axi.axi_write(REG_DW_CAPTURE, C_S_AXI_DW'({31'b0, val}));
    endtask

    task automatic set_start(input logic val);
        s_axi.write(REG_DR_START, C_S_AXI_DW'({31'b0, val}));
    endtask

    task automatic set_debug(input logic [C_S_AXI_DW-1:0] val);
        s_axi.write(REG_DEBUG, val);
    endtask

    task automatic read_reg(
        input  logic [C_S_AXI_AW-1:0]  addr,
        output logic [C_S_AXI_DW-1:0]  data
    );
        s_axi.read(addr, data);
    endtask

    // =========================================================================
    // Capture sequencing helpers
    // =========================================================================

    // arm_and_trigger: write capture=1 via AXI, wait for CDC, pulse trigger,
    // wait for trigger CDC + FSM to reach CAPTURE_ST.
    task automatic arm_and_trigger();
    set_capture(1'b1);
    // Wait for FSM to reach TRIGGER_ST — more reliable than counting cycles
    @(s_axis_if.m_cb);
    while (dut.mr_buffer_i.gen_channel[0].u_axis_to_bram_trig.current_state !== 1)
        @(s_axis_if.m_cb);
    repeat(2) @(s_axis_if.m_cb);  // margin

    @(s_axis_if.m_cb);
    trigger <= 1'b1;
    @(s_axis_if.m_cb);
    trigger <= 1'b0;
    // Wait for FSM to reach CAPTURE_ST
    @(s_axis_if.m_cb);
    while (dut.mr_buffer_i.gen_channel[0].u_axis_to_bram_trig.current_state !== 2)
        @(s_axis_if.m_cb);
    repeat(2) @(s_axis_if.m_cb);

    endtask

    // disarm: write capture=0 via AXI, wait for FSM to return to INIT_ST.
    // With the abort condition in axis_to_bram_trig (!capture_reg -> END_ST),
    // the FSM drains the FIFO and returns to INIT_ST automatically.
    task automatic disarm();
        set_capture(1'b0);
        @(s_axis_if.m_cb);
        while (dut.mr_buffer_i.gen_channel[0].u_axis_to_bram_trig.current_state !== 0)
            @(s_axis_if.m_cb);
        repeat(5) @(s_axis_if.m_cb);
    endtask

    // start_reader: write start=1 via AXI, wait for CDC into m_axis domain.
    // Starts a burst of TOTAL_WORDS beats on m_axis.
    task automatic start_reader();
    set_start(1'b1);
    // Wait for bram_to_axis_nt FSM to leave INIT_ST
    @(m_axis_if.s_cb);
    while (dut.mr_buffer_i.u_bram_to_axis_nt.current_state === 0)
        @(m_axis_if.s_cb);
    repeat(3) @(m_axis_if.s_cb);

    endtask 
    // stop_reader: write start=0 via AXI.
    // Only call AFTER consuming all TOTAL_WORDS beats including tlast.
    task automatic stop_reader();
        set_start(1'b0);
        repeat(5) @(m_axis_if.s_cb);
    endtask

    // build_word: pack NM channel values (B bits each) into S_DATA_W bits.
    // ch[0] -> bits [B-1:0] (lowest, first word on read side).
    function automatic logic [S_DATA_W-1:0] build_word(logic [B-1:0] ch [NM]);
        logic [S_DATA_W-1:0] w = '0;
        for (int i = 0; i < NM; i++)
            w[(i+1)*B-1 -: B] = ch[i];
        return w;
    endfunction

    // send_beat: transmit one S_DATA_W-bit beat on s_axis.
    // ch0_val goes to channel 0; other channels receive a distinct pattern.
    task automatic send_beat(input logic [B-1:0] ch0_val, input logic last);
    logic [B-1:0] ch [NM];
    ch[0] = ch0_val;
    for (int i = 1; i < NM; i++)
        ch[i] = ch0_val + B'(i * 16'h1000);
    // Set tstrb via clocking block before tx()
    s_axis_if.m_cb.tstrb <= '1;
    @(s_axis_if.m_cb);
    // tx() handles the full handshake correctly
    s_axis_if.tx(build_word(ch), last);
    endtask

    // do_capture: arm, trigger, send one beat, disarm, CDC margin.
    task automatic do_capture(input logic [B-1:0] ch0_val);
        arm_and_trigger();
        
        // Enviamos el dato asegurando el handshake de hardware
        send_beat(ch0_val, 1'b1);
        
        // Le damos 20 ciclos en el dominio s_axis para que la lógica termine 
        // de procesar el pipeline de escritura antes de apagar el bloque.
        repeat(20) @(s_axis_if.m_cb);
        
        disarm();
        
        // CDC margin para que el estado de disarm impacte en el lado de lectura
        repeat(50) @(m_axis_if.s_cb);
    endtask

    // drain_burst: consume all TOTAL_WORDS beats, capture ch0 of the first word,
    // verify tlast on the last beat and abort safely if tlast arrives early.
    // m_axis_tdata is M_DATA_W=NM*B wide; ch0 is in bits [B-1:0].
    task automatic drain_burst(output logic [B-1:0] first_word);
    logic [B-1:0] word;
    logic         last;
    int           pos_aaaa = -1;
    int           timeout_cnt;

    m_axis_if.s_cb.tready <= 1'b1;

    for (int i = 0; i < TOTAL_WORDS; i++) begin
        timeout_cnt = 0;
        // Wait for valid beat with timeout
        while (!m_axis_if.tvalid) begin
            @(m_axis_if.s_cb);
            if (++timeout_cnt > 500) begin
                $display("[ERROR] drain_burst: tvalid timeout at beat %0d", i);
                m_axis_if.s_cb.tready <= 1'b0;
                return;
            end
        end

        word = m_axis_if.tdata;
        last = m_axis_if.tlast;

        if (i == 0) first_word = word;
        if (word == 16'hAAAA && pos_aaaa == -1)
            pos_aaaa = i;

        if (last && i < TOTAL_WORDS - 1) begin
            $display("[WARN] drain_burst: tlast at beat %0d, expected %0d", i, TOTAL_WORDS-1);
            @(m_axis_if.s_cb);
            break;
        end

        @(m_axis_if.s_cb);
    end

    m_axis_if.s_cb.tready <= 1'b0;
    @(m_axis_if.s_cb);

    //if (pos_aaaa != -1)
    //    $display("[DEBUG] 0xAAAA found at beat %0d", pos_aaaa);
    //else
    //    $display("[DEBUG] 0xAAAA NOT found — write may not have reached BRAM before reader started");
    endtask

    // =========================================================================
    // SVUnit
    // =========================================================================
    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
        s_axis_if.m_cb.tstrb <= '1;  // all bytes valid
        s_axis_if.m_cb.tkeep <= '1;

        trigger <= 1'b0;

        // Reset all three domains simultaneously
        s_axi_aresetn    = 1'b0;
        s_axis_aresetn   = 1'b0;
        m_axis_aresetn   = 1'b0;
        repeat(50) @(posedge s_axi_aclk);
        s_axi_aresetn    = 1'b1;
        s_axis_aresetn   = 1'b1;
        m_axis_aresetn   = 1'b1;

        // Initialize AXI3-Lite master to idle
        s_axi.reset();
        // Allow XPM FIFOs, sync chains, and axil_slv to settle
        repeat(50) @(posedge s_axi_aclk);
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    // Global timeout
    initial begin
        #200_000_000;
        $display("INFO: Global timeout reached");
        $finish;
    end

    // =========================================================================
    // Test cases
    // =========================================================================
    `SVUNIT_TESTS_BEGIN
    `include "mr_buffer_et_tests.sv"
    `SVUNIT_TESTS_END

endmodule
