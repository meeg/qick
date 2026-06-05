// ============================================================================
// File: avg_top_tc00.sv
// Description: SVUnit testbench top-level for the avg_top module.
// ============================================================================

`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module avg_top_unit_test;

    import svunit_pkg::svunit_testcase;

    string name = "avg_top_ut";
    svunit_testcase svunit_ut;

    localparam real SYS_CLOCK_FREQ = 200e6;
    localparam real AXI_CLOCK_FREQ = 125e6;
    localparam int  N = 10;
    localparam int  B = 16;

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    logic tb_clk           = 1'b0;
    logic tb_rstn          = 1'b1;
    logic tb_m_axis_aclk   = 1'b0;
    logic tb_m_axis_aresetn= 1'b1;

    // =========================================================================
    // UUT interfaces
    // =========================================================================
    logic             tb_trigger_i = 1'b0;
    logic             tb_din_valid_i = 1'b0;
    logic [2*B-1:0]   tb_din_i = '0;

    logic             tb_m0_axis_tvalid;
    logic             tb_m0_axis_tready = 1'b0;
    logic [4*B-1:0]   tb_m0_axis_tdata;
    logic             tb_m0_axis_tlast;

    logic             tb_m1_axis_tvalid;
    logic             tb_m1_axis_tready = 1'b0;
    logic [4*B-1:0]   tb_m1_axis_tdata;

    // Registers
    logic             tb_avg_start_reg = 1'b0;
    logic [N-1:0]     tb_avg_addr_reg = '0;
    logic [31:0]      tb_avg_len_reg = '0;
    logic             tb_dr_start_reg = 1'b0;
    logic [N-1:0]     tb_dr_addr_reg = '0;
    logic [N:0]       tb_dr_len_reg = '0;
    logic             tb_avg_photon_mode_reg = 1'b0;
    logic [B-1:0]     tb_avg_h_thrsh_reg = '0;
    logic [B-1:0]     tb_avg_l_thrsh_reg = '0;

    // =========================================================================
    // Waveform dump
    // =========================================================================
    initial begin
        $dumpfile("avg_top.vcd");
        $dumpvars();
    end

    // =========================================================================
    // Clock generators
    // =========================================================================
    clk_gen #(
        .FREQ (SYS_CLOCK_FREQ)
    ) u_sys_clk_gen (
        .i_enable (1'b1),
        .o_clk    (tb_clk)
    );

    clk_gen #(
        .FREQ (AXI_CLOCK_FREQ)
    ) u_axi_clk_gen (
        .i_enable (1'b1),
        .o_clk    (tb_m_axis_aclk)
    );

    // =========================================================================
    // Clocking blocks (One for each clock domain)
    // =========================================================================
    default clocking sys_cb @(posedge tb_clk);
        default input #1step output #2;
        output tb_rstn;
        output tb_trigger_i;
        output tb_din_valid_i;
        output tb_din_i;
        output tb_avg_start_reg;
        output tb_avg_addr_reg;
        output tb_avg_len_reg;
        output tb_avg_photon_mode_reg;
        output tb_avg_h_thrsh_reg;
        output tb_avg_l_thrsh_reg;
    endclocking

    clocking axi_cb @(posedge tb_m_axis_aclk);
        default input #1step output #2;
        output tb_m_axis_aresetn;
        output tb_m0_axis_tready;
        output tb_m1_axis_tready;
        output tb_dr_start_reg;
        output tb_dr_addr_reg;
        output tb_dr_len_reg;
        input  tb_m0_axis_tvalid;
        input  tb_m0_axis_tdata;
        input  tb_m0_axis_tlast;
        input  tb_m1_axis_tvalid;
        input  tb_m1_axis_tdata;
    endclocking

    // =========================================================================
    // Unit Under Test
    // =========================================================================
    avg_top #(
        .N (N),
        .B (B)
    ) u_avg_top (
        .rstn                (tb_rstn),
        .clk                 (tb_clk),
        .trigger_i           (tb_trigger_i),
        .din_valid_i         (tb_din_valid_i),
        .din_i               (tb_din_i),
        .m_axis_aclk         (tb_m_axis_aclk),
        .m_axis_aresetn      (tb_m_axis_aresetn),
        .m0_axis_tvalid      (tb_m0_axis_tvalid),
        .m0_axis_tready      (tb_m0_axis_tready),
        .m0_axis_tdata       (tb_m0_axis_tdata),
        .m0_axis_tlast       (tb_m0_axis_tlast),
        .m1_axis_tvalid      (tb_m1_axis_tvalid),
        .m1_axis_tready      (tb_m1_axis_tready),
        .m1_axis_tdata       (tb_m1_axis_tdata),
        .avg_start_reg       (tb_avg_start_reg),
        .avg_addr_reg        (tb_avg_addr_reg),
        .avg_len_reg         (tb_avg_len_reg),
        .dr_start_reg        (tb_dr_start_reg),
        .dr_addr_reg         (tb_dr_addr_reg),
        .dr_len_reg          (tb_dr_len_reg),
        .avg_photon_mode_reg (tb_avg_photon_mode_reg),
        .avg_h_thrsh_reg     (tb_avg_h_thrsh_reg),
        .avg_l_thrsh_reg     (tb_avg_l_thrsh_reg)
    );

    // =========================================================================
    // Helper tasks
    // =========================================================================

    // reset_dut: apply synchronous reset sequence to both domains.
    task automatic reset_dut();
        sys_cb.tb_rstn <= 1'b0;
        axi_cb.tb_m_axis_aresetn <= 1'b0;
        
        // Hold reset for ~20 system clock cycles to guarantee it covers
        // at least 10 cycles of the slower 125MHz AXI clock.
        repeat(20) @(sys_cb); 
        
        sys_cb.tb_rstn <= 1'b1;
        axi_cb.tb_m_axis_aresetn <= 1'b1;
        
        // Allow XPM FIFOs time to complete their internal reset sequence
        // before injecting any data.
        repeat(50) @(sys_cb);
    endtask
    
    // pulse_trigger: fire a single trigger pulse.
    // Assumes FSM is already in WAIT_TRIGGER_ST -> TRIGGER_ST.
    // Does NOT re-latch config registers (start_reg stays high).
    task automatic pulse_trigger();
        sys_cb.tb_trigger_i <= 1'b1;
        @(sys_cb);
        sys_cb.tb_trigger_i <= 1'b0;
    endtask
    
    // wait_for_wait_trigger_st: wait until the FSM has completed
    // WRITE_MEM_ST and entered WAIT_TRIGGER_ST.
    // 3 cycles covers AVG_ST(last sample) -> QOUT_ST -> WRITE_MEM_ST.
    // The repeat(6) guard gives margin for CDC and pipeline latency.
    task automatic wait_for_wait_trigger_st();
        repeat(6) @(sys_cb);
    endtask

    // avg_arm_and_trigger: latch config, assert start_reg, wait one cycle for FSM
    // to reach TRIGGER_ST, then pulse trigger_i for one cycle.
    // Leaves FSM in AVG_ST with start_reg=1, trigger_i=0.
    task automatic avg_arm_and_trigger(
        input logic [N-1:0] addr,
        input logic [31:0]  len,
        input logic         photon_mode,
        input logic [B-1:0] h_thrsh,
        input logic [B-1:0] l_thrsh
    );
        sys_cb.tb_avg_addr_reg        <= addr;
        sys_cb.tb_avg_len_reg         <= len;
        sys_cb.tb_avg_photon_mode_reg <= photon_mode;
        sys_cb.tb_avg_h_thrsh_reg     <= h_thrsh;
        sys_cb.tb_avg_l_thrsh_reg     <= l_thrsh;
        sys_cb.tb_avg_start_reg       <= 1'b1;
        repeat(4) @(sys_cb); // FSM: START_ST -> TRIGGER_ST. Allow 4 cycles to ensure config registers are latched before trigger.
        sys_cb.tb_trigger_i <= 1'b1;
        @(sys_cb); // FSM: TRIGGER_ST -> AVG_ST
        sys_cb.tb_trigger_i <= 1'b0;
    endtask

    // inject_data: push count words into the system.
    task automatic inject_data(
        input int count,
        input logic [2*B-1:0] start_val
    );
        for (int i = 0; i < count; i++) begin
            sys_cb.tb_din_i       <= start_val + i;
            sys_cb.tb_din_valid_i <= 1'b1;
            @(sys_cb);
        end
        sys_cb.tb_din_valid_i <= 1'b0;
        repeat(6) @(sys_cb);
    endtask

    // start_reader: assert start_reg for the data_reader in the AXI domain.
    task automatic start_reader(
        input logic [N-1:0] addr,
        input logic [32-1:0] len
    );
        axi_cb.tb_dr_addr_reg  <= addr;
        axi_cb.tb_dr_len_reg   <= len[N:0];  // truncate when connecting to the register
        @(axi_cb);
        axi_cb.tb_dr_start_reg <= 1'b1;
        @(axi_cb);
        axi_cb.tb_dr_start_reg <= 1'b0;
    endtask

// read_m0_data: collect expected_count words from m0_axis (BRAM stream).
    task automatic read_m0_data(
        input  int                expected_count,
        output logic [4*B-1:0]   data[],
        output int                timed_out,
        output int                tlast_errors, // <-- Returns the tlast mismatch count
        input  int                timeout_cycles = 500   
    );
        int count = 0;
        int timeout = 0;
        timed_out = 0;
        tlast_errors = 0;
        data = new[expected_count];
    
        axi_cb.tb_m0_axis_tready <= 1'b1;
    
        while (count < expected_count) begin
            @(axi_cb);
            timeout++;
            if (tb_m0_axis_tvalid && tb_m0_axis_tready) begin
                data[count] = tb_m0_axis_tdata;
                $display("[READ M0] data[%0d] = 0x%0h (tlast=%b)", count, tb_m0_axis_tdata, tb_m0_axis_tlast);
                
                // --- Automatic tlast validation ---
                if (count == expected_count - 1) begin
                    if (!tb_m0_axis_tlast) begin
                        $display("[ERROR] read_m0_data: tlast NOT asserted on the last word (word %0d)", count);
                        tlast_errors++;
                    end
                end else begin
                    if (tb_m0_axis_tlast) begin
                        $display("[ERROR] read_m0_data: tlast asserted EARLY at word %0d (expected at %0d)", count, expected_count - 1);
                        tlast_errors++;
                    end
                end
                
                count++;
            end
            if (timeout > timeout_cycles) begin
                $display("[TIMEOUT] read_m0_data: only got %0d of %0d words", count, expected_count);
                timed_out = 1;
                break;
            end
        end
    
        // Keep tready=1 until tvalid drops so the FSM can finish its last
        // handshake and return to IDLE cleanly.
        timeout = 0;
        while (tb_m0_axis_tvalid) begin
            @(axi_cb);
            timeout++;
            if (timeout > 50) begin
                $display("[TIMEOUT] read_m0_data: tvalid stuck high after all data received");
                break;
            end
        end
    
        @(axi_cb);
        axi_cb.tb_m0_axis_tready <= 1'b0;
        repeat(5) @(axi_cb);
    endtask

    // read_m1_data: collect expected_count words from m1_axis (Immediate stream).
    // Note: Remains unchanged as m1_axis does not feature a tlast line in the current RTL design.
    task automatic read_m1_data(
        input  int                expected_count,
        output logic [4*B-1:0]   data[],
        output int                timed_out
    );
        int count = 0;
        int timeout = 0;
        timed_out = 0;
        data = new[expected_count];

        axi_cb.tb_m1_axis_tready <= 1'b1;

        while (count < expected_count) begin
            @(axi_cb);
            timeout++;
            if (tb_m1_axis_tvalid && tb_m1_axis_tready) begin
                data[count] = tb_m1_axis_tdata;
                $display("[READ M1] data[%0d] = 0x%0h", count, tb_m1_axis_tdata);
                count++;
            end
            if (timeout > 500) begin
                $display("[TIMEOUT] read_m1_data: only got %0d of %0d words", count, expected_count);
                timed_out = 1;
                break;
            end
        end

        @(axi_cb);
        axi_cb.tb_m1_axis_tready <= 1'b0;
        repeat(5) @(axi_cb);
    endtask

    // verify_data: compare expected vs actual arrays, fail on mismatch.
    // Notice width is 4*B to match axis data output width.
    task automatic verify_data(
        input logic [4*B-1:0] expected[],
        input logic [4*B-1:0] actual[],
        input string          test_name
    );
        for (int i = 0; i < expected.size(); i++) begin
            if (expected[i] !== actual[i]) begin
                $display("MISMATCH %s [%0d]: expected 0x%0h got 0x%0h",
                         test_name, i, expected[i], actual[i]);
                `FAIL_IF(1);
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
        
        // Default consumer states
        axi_cb.tb_m0_axis_tready <= 1'b0;
        axi_cb.tb_m1_axis_tready <= 1'b0;

        // Default register states
        sys_cb.tb_trigger_i           <= 1'b0;
        sys_cb.tb_din_valid_i         <= 1'b0;
        sys_cb.tb_din_i               <= '0;
        sys_cb.tb_avg_start_reg       <= 1'b0;
        sys_cb.tb_avg_addr_reg        <= '0;
        sys_cb.tb_avg_len_reg         <= '0;
        axi_cb.tb_dr_start_reg        <= 1'b0;
        axi_cb.tb_dr_addr_reg         <= '0;
        axi_cb.tb_dr_len_reg          <= '0;
        sys_cb.tb_avg_photon_mode_reg <= 1'b0;
        sys_cb.tb_avg_h_thrsh_reg     <= '0;
        sys_cb.tb_avg_l_thrsh_reg     <= '0;
        
        @(sys_cb);
        reset_dut();
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    // =========================================================================
    // Test cases
    // =========================================================================
    `SVUNIT_TESTS_BEGIN
    `include "tests.sv"
    `SVUNIT_TESTS_END

endmodule
