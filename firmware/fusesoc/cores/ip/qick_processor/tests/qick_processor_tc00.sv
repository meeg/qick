// ============================================================================
// File: qick_processor_tc00.sv
// Description: SVUnit testbench top-level for qick_processor.
//
// Drives the flat AXI-Lite pins through a locally-instantiated axi4_lite_if
// (its axi_write/axi_read tasks), mirroring the interface<->pins wiring
// qick_processor.sv itself does internally. DEBUG=3 unlocks the raw
// debug buses (c_debug_do) so qproc_ctrl's FSM state is observable.
// Default parameters (IN_PORT_QTY=1, OUT_TRIG_QTY=2, OUT_DPORT_QTY=1,
// OUT_WPORT_QTY=1) exercise the "most pins are unused/tied-off" path.
// ============================================================================
`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module qick_processor_unit_test;
    import svunit_pkg::svunit_testcase;

    string name = "qick_processor_ut";
    svunit_testcase svunit_ut;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real CLOCK_FREQUENCY = 200e6;

    localparam logic [2:0] C_RUN = 3'd5; // core_st_ds encoding (qproc_ctrl.sv)

    // Register map (byte-addressed, matches qproc_axi_reg.sv's header).
    localparam int ADDR_TPROC_CTRL = 'h00;
    localparam int ADDR_TPROC_CFG  = 'h04;
    localparam int ADDR_CORE_CFG   = 'h1C;
    localparam int ADDR_FIXED_ID   = 'h24;

    // =========================================================================
    // Clock & reset
    // =========================================================================
    logic tb_clk  = 1'b0;
    logic tb_rstn = 1'b1;

    clk_gen #(.FREQ (CLOCK_FREQUENCY)) u_clk_gen (
        .i_enable (1'b1),
        .o_clk    (tb_clk)
    );

    // =========================================================================
    // AXI-Lite master interface (wired to the DUT's flat s_axi_* pins below)
    // =========================================================================
    axi4_lite_if #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (8)
    ) s_axi (
        .aclk    (tb_clk),
        .aresetn (tb_rstn)
    );

    // =========================================================================
    // DUT signals
    // =========================================================================
    logic tb_ext_flag_i    = 1'b0;
    logic tb_proc_start_i  = 1'b0;
    logic tb_proc_stop_i   = 1'b0;
    logic tb_core_start_i  = 1'b0;
    logic tb_core_stop_i   = 1'b0;
    logic tb_time_rst_i    = 1'b0;
    logic tb_time_init_i   = 1'b0;
    logic tb_time_updt_i   = 1'b0;
    logic [31:0] tb_time_dt_i = '0;
    logic [47:0] tb_t_time_abs_o;
    logic        tb_pulse_sync_o;

    logic        tb_qnet_en_o;
    logic [4:0]  tb_qnet_op_o;
    logic [31:0] tb_qnet_a_dt_o, tb_qnet_b_dt_o, tb_qnet_c_dt_o;
    logic        tb_qnet_rdy_i = 1'b0;
    logic [31:0] tb_qnet_dt1_i = '0, tb_qnet_dt2_i = '0;
    logic        tb_qnet_vld_i = 1'b0, tb_qnet_flag_i = 1'b0;

    logic        tb_qcom_en_o;
    logic [4:0]  tb_qcom_op_o;
    logic [31:0] tb_qcom_dt_o;
    logic        tb_qcom_rdy_i = 1'b0;
    logic [31:0] tb_qcom_dt1_i = '0, tb_qcom_dt2_i = '0;
    logic        tb_qcom_vld_i = 1'b0, tb_qcom_flag_i = 1'b0;

    logic        tb_qp1_en_o;
    logic [4:0]  tb_qp1_op_o;
    logic [31:0] tb_qp1_a_dt_o, tb_qp1_b_dt_o, tb_qp1_c_dt_o, tb_qp1_d_dt_o;
    logic        tb_qp1_rdy_i = 1'b0;
    logic [31:0] tb_qp1_dt1_i = '0, tb_qp1_dt2_i = '0;
    logic        tb_qp1_vld_i = 1'b0, tb_qp1_flag_i = 1'b0;

    logic        tb_qp2_en_o;
    logic [4:0]  tb_qp2_op_o;
    logic [31:0] tb_qp2_a_dt_o, tb_qp2_b_dt_o, tb_qp2_c_dt_o, tb_qp2_d_dt_o;
    logic        tb_qp2_rdy_i = 1'b0;
    logic [31:0] tb_qp2_dt1_i = '0, tb_qp2_dt2_i = '0;
    logic        tb_qp2_vld_i = 1'b0;

    logic [255:0] tb_s_dma_axis_tdata_i  = '0;
    logic         tb_s_dma_axis_tlast_i  = 1'b0;
    logic         tb_s_dma_axis_tvalid_i = 1'b0;
    logic         tb_s_dma_axis_tready_o;
    logic [255:0] tb_m_dma_axis_tdata_o;
    logic         tb_m_dma_axis_tlast_o;
    logic         tb_m_dma_axis_tvalid_o;
    logic         tb_m_dma_axis_tready_i = 1'b0;

    logic [63:0] tb_s0_axis_tdata = '0; logic tb_s0_axis_tvalid = 1'b0; logic tb_s0_axis_tready;
    logic [63:0] tb_s1_axis_tdata = '0; logic tb_s1_axis_tvalid = 1'b0; logic tb_s1_axis_tready;

    logic [167:0] tb_m0_axis_tdata; logic tb_m0_axis_tvalid; logic tb_m0_axis_tready = 1'b0;
    logic [167:0] tb_m1_axis_tdata; logic tb_m1_axis_tvalid; logic tb_m1_axis_tready = 1'b0;

    logic tb_trig_0_o, tb_trig_1_o, tb_trig_2_o, tb_trig_5_o, tb_trig_31_o;
    logic [3:0] tb_port_0_dt_o, tb_port_1_dt_o;

    logic [31:0] tb_ps_debug_do, tb_t_debug_do, tb_t_fifo_do;
    logic [31:0] tb_c_time_usr_do, tb_c_debug_do, tb_c_time_ref_do;
    logic [31:0] tb_c_proc_do, tb_c_port_do, tb_c_core_do;

    initial begin
        $dumpfile("qick_processor.vcd");
        $dumpvars();
    end

    // =========================================================================
    // DUT
    // =========================================================================
    qick_processor #(
        .DUAL_CORE     (0),
        .GEN_SYNC      (0),
        .DEBUG         (3),
        .LFSR          (1),
        .DIVIDER       (1),
        .ARITH         (1),
        .TIME_READ     (1),
        .FIFO_DEPTH    (8),
        .PMEM_AW       (8),
        .DMEM_AW       (8),
        .WMEM_AW       (8),
        .REG_AW        (4),
        .IN_PORT_QTY   (1),
        .OUT_TRIG_QTY  (2),
        .OUT_DPORT_QTY (1),
        .OUT_DPORT_DW  (4),
        .OUT_WPORT_QTY (1)
    ) u_dut (
        .t_clk_i   (tb_clk),
        .t_resetn  (tb_rstn),
        .c_clk_i   (tb_clk),
        .c_resetn  (tb_rstn),
        .ps_clk_i  (tb_clk),
        .ps_resetn (tb_rstn),
        .ext_flag_i   (tb_ext_flag_i),
        .proc_start_i (tb_proc_start_i),
        .proc_stop_i  (tb_proc_stop_i),
        .core_start_i (tb_core_start_i),
        .core_stop_i  (tb_core_stop_i),
        .time_rst_i   (tb_time_rst_i),
        .time_init_i  (tb_time_init_i),
        .time_updt_i  (tb_time_updt_i),
        .time_dt_i    (tb_time_dt_i),
        .t_time_abs_o (tb_t_time_abs_o),
        .pulse_sync_o (tb_pulse_sync_o),
        .qnet_en_o (tb_qnet_en_o), .qnet_op_o (tb_qnet_op_o),
        .qnet_a_dt_o (tb_qnet_a_dt_o), .qnet_b_dt_o (tb_qnet_b_dt_o), .qnet_c_dt_o (tb_qnet_c_dt_o),
        .qnet_rdy_i (tb_qnet_rdy_i), .qnet_dt1_i (tb_qnet_dt1_i), .qnet_dt2_i (tb_qnet_dt2_i),
        .qnet_vld_i (tb_qnet_vld_i), .qnet_flag_i (tb_qnet_flag_i),
        .qcom_en_o (tb_qcom_en_o), .qcom_op_o (tb_qcom_op_o), .qcom_dt_o (tb_qcom_dt_o),
        .qcom_rdy_i (tb_qcom_rdy_i), .qcom_dt1_i (tb_qcom_dt1_i), .qcom_dt2_i (tb_qcom_dt2_i),
        .qcom_vld_i (tb_qcom_vld_i), .qcom_flag_i (tb_qcom_flag_i),
        .qp1_en_o (tb_qp1_en_o), .qp1_op_o (tb_qp1_op_o),
        .qp1_a_dt_o (tb_qp1_a_dt_o), .qp1_b_dt_o (tb_qp1_b_dt_o), .qp1_c_dt_o (tb_qp1_c_dt_o), .qp1_d_dt_o (tb_qp1_d_dt_o),
        .qp1_rdy_i (tb_qp1_rdy_i), .qp1_dt1_i (tb_qp1_dt1_i), .qp1_dt2_i (tb_qp1_dt2_i),
        .qp1_vld_i (tb_qp1_vld_i), .qp1_flag_i (tb_qp1_flag_i),
        .qp2_en_o (tb_qp2_en_o), .qp2_op_o (tb_qp2_op_o),
        .qp2_a_dt_o (tb_qp2_a_dt_o), .qp2_b_dt_o (tb_qp2_b_dt_o), .qp2_c_dt_o (tb_qp2_c_dt_o), .qp2_d_dt_o (tb_qp2_d_dt_o),
        .qp2_rdy_i (tb_qp2_rdy_i), .qp2_dt1_i (tb_qp2_dt1_i), .qp2_dt2_i (tb_qp2_dt2_i),
        .qp2_vld_i (tb_qp2_vld_i),
        .s_dma_axis_tdata_i  (tb_s_dma_axis_tdata_i),
        .s_dma_axis_tlast_i  (tb_s_dma_axis_tlast_i),
        .s_dma_axis_tvalid_i (tb_s_dma_axis_tvalid_i),
        .s_dma_axis_tready_o (tb_s_dma_axis_tready_o),
        .m_dma_axis_tdata_o  (tb_m_dma_axis_tdata_o),
        .m_dma_axis_tlast_o  (tb_m_dma_axis_tlast_o),
        .m_dma_axis_tvalid_o (tb_m_dma_axis_tvalid_o),
        .m_dma_axis_tready_i (tb_m_dma_axis_tready_i),
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
        .s0_axis_tdata (tb_s0_axis_tdata), .s0_axis_tvalid (tb_s0_axis_tvalid), .s0_axis_tready (tb_s0_axis_tready),
        .s1_axis_tdata (tb_s1_axis_tdata), .s1_axis_tvalid (tb_s1_axis_tvalid), .s1_axis_tready (tb_s1_axis_tready),
        .s2_axis_tdata ('0), .s2_axis_tvalid (1'b0), .s2_axis_tready (),
        .s3_axis_tdata ('0), .s3_axis_tvalid (1'b0), .s3_axis_tready (),
        .s4_axis_tdata ('0), .s4_axis_tvalid (1'b0), .s4_axis_tready (),
        .s5_axis_tdata ('0), .s5_axis_tvalid (1'b0), .s5_axis_tready (),
        .s6_axis_tdata ('0), .s6_axis_tvalid (1'b0), .s6_axis_tready (),
        .s7_axis_tdata ('0), .s7_axis_tvalid (1'b0), .s7_axis_tready (),
        .s8_axis_tdata ('0), .s8_axis_tvalid (1'b0), .s8_axis_tready (),
        .s9_axis_tdata ('0), .s9_axis_tvalid (1'b0), .s9_axis_tready (),
        .s10_axis_tdata ('0), .s10_axis_tvalid (1'b0), .s10_axis_tready (),
        .s11_axis_tdata ('0), .s11_axis_tvalid (1'b0), .s11_axis_tready (),
        .s12_axis_tdata ('0), .s12_axis_tvalid (1'b0), .s12_axis_tready (),
        .s13_axis_tdata ('0), .s13_axis_tvalid (1'b0), .s13_axis_tready (),
        .s14_axis_tdata ('0), .s14_axis_tvalid (1'b0), .s14_axis_tready (),
        .s15_axis_tdata ('0), .s15_axis_tvalid (1'b0), .s15_axis_tready (),
        .m0_axis_tdata (tb_m0_axis_tdata), .m0_axis_tvalid (tb_m0_axis_tvalid), .m0_axis_tready (tb_m0_axis_tready),
        .m1_axis_tdata (tb_m1_axis_tdata), .m1_axis_tvalid (tb_m1_axis_tvalid), .m1_axis_tready (tb_m1_axis_tready),
        .m2_axis_tdata (), .m2_axis_tvalid (), .m2_axis_tready (1'b0),
        .m3_axis_tdata (), .m3_axis_tvalid (), .m3_axis_tready (1'b0),
        .m4_axis_tdata (), .m4_axis_tvalid (), .m4_axis_tready (1'b0),
        .m5_axis_tdata (), .m5_axis_tvalid (), .m5_axis_tready (1'b0),
        .m6_axis_tdata (), .m6_axis_tvalid (), .m6_axis_tready (1'b0),
        .m7_axis_tdata (), .m7_axis_tvalid (), .m7_axis_tready (1'b0),
        .m8_axis_tdata (), .m8_axis_tvalid (), .m8_axis_tready (1'b0),
        .m9_axis_tdata (), .m9_axis_tvalid (), .m9_axis_tready (1'b0),
        .m10_axis_tdata (), .m10_axis_tvalid (), .m10_axis_tready (1'b0),
        .m11_axis_tdata (), .m11_axis_tvalid (), .m11_axis_tready (1'b0),
        .m12_axis_tdata (), .m12_axis_tvalid (), .m12_axis_tready (1'b0),
        .m13_axis_tdata (), .m13_axis_tvalid (), .m13_axis_tready (1'b0),
        .m14_axis_tdata (), .m14_axis_tvalid (), .m14_axis_tready (1'b0),
        .m15_axis_tdata (), .m15_axis_tvalid (), .m15_axis_tready (1'b0),
        .trig_0_o (tb_trig_0_o), .trig_1_o (tb_trig_1_o), .trig_2_o (tb_trig_2_o),
        .trig_3_o (), .trig_4_o (), .trig_5_o (tb_trig_5_o), .trig_6_o (), .trig_7_o (),
        .trig_8_o (), .trig_9_o (), .trig_10_o (), .trig_11_o (), .trig_12_o (), .trig_13_o (),
        .trig_14_o (), .trig_15_o (), .trig_16_o (), .trig_17_o (), .trig_18_o (), .trig_19_o (),
        .trig_20_o (), .trig_21_o (), .trig_22_o (), .trig_23_o (), .trig_24_o (), .trig_25_o (),
        .trig_26_o (), .trig_27_o (), .trig_28_o (), .trig_29_o (), .trig_30_o (), .trig_31_o (tb_trig_31_o),
        .port_0_dt_o (tb_port_0_dt_o), .port_1_dt_o (tb_port_1_dt_o), .port_2_dt_o (), .port_3_dt_o (),
        .ps_debug_do (tb_ps_debug_do),
        .t_debug_do  (tb_t_debug_do),
        .t_fifo_do   (tb_t_fifo_do),
        .c_time_usr_do (tb_c_time_usr_do),
        .c_debug_do    (tb_c_debug_do),
        .c_time_ref_do (tb_c_time_ref_do),
        .c_proc_do     (tb_c_proc_do),
        .c_port_do     (tb_c_port_do),
        .c_core_do     (tb_c_core_do)
    );

    function automatic logic [2:0] core_st();
        return tb_c_debug_do[2:0];
    endfunction

    // =========================================================================
    // Helper tasks
    // =========================================================================
    task automatic reset_dut();
        tb_ext_flag_i   = 1'b0;
        tb_proc_start_i = 1'b0;
        tb_proc_stop_i  = 1'b0;
        tb_core_start_i = 1'b0;
        tb_core_stop_i  = 1'b0;
        tb_rstn = 1'b0;
        repeat(10) @(posedge tb_clk);
        tb_rstn = 1'b1;
        // Let the XPM FIFOs inside qproc_dispatcher clear wr_rst_busy (see
        // qproc_dispatcher's own testbench notes).
        repeat(100) @(posedge tb_clk);
    endtask

    task automatic wait_for_core_st(input logic [2:0] target, output bit reached, input int max_cycles = 200);
        reached = 1'b0;
        for (int n = 0; n < max_cycles; n++) begin
            @(posedge tb_clk);
            if (core_st() == target) begin
                reached = 1'b1;
                return;
            end
        end
    endtask

    // =========================================================================
    // SVUnit build / setup / teardown
    // =========================================================================
    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
        reset_dut();
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    // =========================================================================
    // Test cases
    // =========================================================================
    `SVUNIT_TESTS_BEGIN
    `include "qick_processor_tests.sv"
    `SVUNIT_TESTS_END

endmodule
