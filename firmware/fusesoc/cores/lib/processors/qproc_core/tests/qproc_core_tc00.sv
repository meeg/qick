// ============================================================================
// File: qproc_core_tc00.sv
// Description: SVUnit testbench top-level for qproc_core.
//
// Loads/reads PMEM and DMEM through the PS-side memory port (ps_mem_*,
// same encoding as qcore_mem: SEL_NONE=00, SEL_PMEM=01, SEL_DMEM=10,
// SEL_WMEM=11) to exercise the full loop: PS loads a program -> qcore_cpu
// fetches/executes it -> qcore_mem's DMEM write is readable back via the
// PS port. Instruction words use the same hand-encoding as qcore_cpu's own
// testbench (see its header for the exact bit layout).
// ============================================================================
`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module qproc_core_unit_test;
    import svunit_pkg::svunit_testcase;
    import tpv2_pkg::MEM_WR;
    import tpv2_pkg::PORT_DT;

    string name = "qproc_core_ut";
    svunit_testcase svunit_ut;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real CLOCK_FREQUENCY = 200e6;
    localparam int  IN_PORT_QTY = 1;
    localparam int  PMEM_AW = 8;
    localparam int  DMEM_AW = 8;
    localparam int  WMEM_AW = 8;

    localparam logic [1:0] SEL_NONE = 2'b00;
    localparam logic [1:0] SEL_PMEM = 2'b01;
    localparam logic [1:0] SEL_DMEM = 2'b10;

    // =========================================================================
    // Clock & reset (single clock drives c_clk_i/ps_clk_i, like qcore_mem's TB)
    // =========================================================================
    logic tb_clk    = 1'b0;
    logic tb_c_rstn  = 1'b1;
    logic tb_ps_rstn = 1'b1;

    clk_gen #(.FREQ (CLOCK_FREQUENCY)) u_clk_gen (
        .i_enable (1'b1),
        .o_clk    (tb_clk)
    );

    // =========================================================================
    // DUT signals
    // =========================================================================
    logic tb_en_i      = 1'b0;
    logic tb_restart_i = 1'b0;
    logic [1:0]  tb_lfsr_cfg_i = 2'b00;
    logic [31:0] tb_core_status_o, tb_core_debug_o, tb_lfsr_o;

    logic [63:0] tb_port_dt_i [IN_PORT_QTY] = '{default: '0};
    logic        tb_flag_i = 1'b0;

    logic [7:0]  tb_sreg_cfg_o, tb_sreg_ctrl_o;
    logic [31:0] tb_sreg_arith_i        = '0;
    logic [31:0] tb_sreg_div_i      [2] = '{default: '0};
    logic [31:0] tb_sreg_status_i       = '0;
    logic [31:0] tb_sreg_core_r_dt_i[2] = '{default: '0};
    logic [31:0] tb_sreg_time_dt_i      = '0;
    logic [31:0] tb_sreg_core_w_dt_o[2];

    logic        tb_usr_en_o;
    logic [7:0]  tb_usr_ctrl_o;
    logic [31:0] tb_usr_dt_a_o, tb_usr_dt_b_o, tb_usr_dt_c_o, tb_usr_dt_d_o;

    logic [1:0]   tb_ps_mem_sel_i  = SEL_NONE;
    logic         tb_ps_mem_we_i   = 1'b0;
    logic [15:0]  tb_ps_mem_addr_i = '0;
    logic [167:0] tb_ps_mem_w_dt_i = '0;
    logic [167:0] tb_ps_mem_r_dt_o;

    logic   tb_port_we_o;
    PORT_DT tb_port_o;
    logic [31:0] tb_core_do;

    initial begin
        $dumpfile("qproc_core.vcd");
        $dumpvars();
    end

    // =========================================================================
    // DUT
    // =========================================================================
    qproc_core #(
        .LFSR        (1),
        .IN_PORT_QTY (IN_PORT_QTY),
        .PMEM_AW     (PMEM_AW),
        .DMEM_AW     (DMEM_AW),
        .WMEM_AW     (WMEM_AW),
        .REG_AW      (4)
    ) u_dut (
        .c_clk_i   (tb_clk),
        .c_rst_ni  (tb_c_rstn),
        .ps_clk_i  (tb_clk),
        .ps_rst_ni (tb_ps_rstn),
        .en_i      (tb_en_i),
        .restart_i (tb_restart_i),
        .lfsr_cfg_i (tb_lfsr_cfg_i),
        .core_status_o (tb_core_status_o),
        .core_debug_o  (tb_core_debug_o),
        .lfsr_o        (tb_lfsr_o),
        .port_dt_i (tb_port_dt_i),
        .flag_i    (tb_flag_i),
        .sreg_cfg_o       (tb_sreg_cfg_o),
        .sreg_ctrl_o      (tb_sreg_ctrl_o),
        .sreg_arith_i     (tb_sreg_arith_i),
        .sreg_div_i       (tb_sreg_div_i),
        .sreg_status_i    (tb_sreg_status_i),
        .sreg_core_r_dt_i (tb_sreg_core_r_dt_i),
        .sreg_time_dt_i   (tb_sreg_time_dt_i),
        .sreg_core_w_dt_o (tb_sreg_core_w_dt_o),
        .usr_en_o   (tb_usr_en_o),
        .usr_ctrl_o (tb_usr_ctrl_o),
        .usr_dt_a_o (tb_usr_dt_a_o),
        .usr_dt_b_o (tb_usr_dt_b_o),
        .usr_dt_c_o (tb_usr_dt_c_o),
        .usr_dt_d_o (tb_usr_dt_d_o),
        .ps_mem_sel_i  (tb_ps_mem_sel_i),
        .ps_mem_we_i   (tb_ps_mem_we_i),
        .ps_mem_addr_i (tb_ps_mem_addr_i),
        .ps_mem_w_dt_i (tb_ps_mem_w_dt_i),
        .ps_mem_r_dt_o (tb_ps_mem_r_dt_o),
        .port_we_o (tb_port_we_o),
        .port_o    (tb_port_o),
        .core_do   (tb_core_do)
    );

    // =========================================================================
    // Instruction encoder (mirrors qcore_cpu's testbench)
    // =========================================================================
    // MEM_WR, DF=00, SO=0,TO=1: data forced to the DF=00 immediate = imm11,
    // address = ai ? imm11 : rs_a[0]+rs_a[1] (both 0 here).
    function automatic logic [71:0] mk_store_imm(input logic ai_bit, input logic [10:0] imm11);
        logic [15:0] op_code;
        logic [55:0] op_data;
        op_code = {MEM_WR, ai_bit, 2'b00, 3'b000, 1'b0, 1'b1, 5'b0};
        op_data = {imm11, 45'b0};
        mk_store_imm = {op_code, op_data};
    endfunction

    // =========================================================================
    // Helper tasks
    // =========================================================================
    task automatic reset_dut();
        tb_en_i      = 1'b0;
        tb_restart_i = 1'b0;
        tb_ps_mem_sel_i  = SEL_NONE;
        tb_ps_mem_we_i   = 1'b0;
        tb_ps_mem_addr_i = '0;
        tb_ps_mem_w_dt_i = '0;
        tb_c_rstn  = 1'b0;
        tb_ps_rstn = 1'b0;
        repeat(10) @(posedge tb_clk);
        tb_c_rstn  = 1'b1;
        tb_ps_rstn = 1'b1;
        repeat(5) @(posedge tb_clk);
    endtask

    task automatic ps_write(input logic [1:0] sel, input logic [15:0] addr, input logic [167:0] data);
        @(negedge tb_clk);
        tb_ps_mem_sel_i  = sel;
        tb_ps_mem_we_i   = 1'b1;
        tb_ps_mem_addr_i = addr;
        tb_ps_mem_w_dt_i = data;
        @(negedge tb_clk);
        tb_ps_mem_we_i  = 1'b0;
        tb_ps_mem_sel_i = SEL_NONE;
    endtask

    task automatic ps_read(input logic [1:0] sel, input logic [15:0] addr);
        @(negedge tb_clk);
        tb_ps_mem_sel_i  = sel;
        tb_ps_mem_we_i   = 1'b0;
        tb_ps_mem_addr_i = addr;
        @(negedge tb_clk); // BRAM read latency
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
    `include "qproc_core_tests.sv"
    `SVUNIT_TESTS_END

endmodule
