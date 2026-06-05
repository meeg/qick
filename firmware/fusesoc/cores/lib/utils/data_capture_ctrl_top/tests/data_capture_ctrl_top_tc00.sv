// ============================================================================
// File: data_capture_ctrl_top_tc00.sv
// Description: SVUnit testbench wrapper for data_capture_ctrl_top module.
// ============================================================================

`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module data_capture_ctrl_top_unit_test;

    import svunit_pkg::svunit_testcase;

    string name = "data_capture_ctrl_top_ut";
    svunit_testcase svunit_ut;

    // ------------------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------------------
    localparam real SYS_CLOCK_FREQ = 200e6;
    localparam real AXI_CLOCK_FREQ = 125e6;
    parameter int N = 10;
    parameter int B = 16;

    // ------------------------------------------------------------------------
    // Clock and Reset Signals
    // ------------------------------------------------------------------------
    logic clk;
    logic rstn;
    logic m_axis_aclk;
    logic m_axis_aresetn;

    // ------------------------------------------------------------------------
    // DUT Signals
    // ------------------------------------------------------------------------
    // Trigger and Data Input
    logic             trigger_i;
    logic             din_valid_i;
    logic [2*B-1:0]   din_i;

    // AXIS Master Output
    logic             m_axis_tvalid;
    logic             m_axis_tready;
    logic [2*B-1:0]   m_axis_tdata;
    logic             m_axis_tlast;

    // Control Registers
    logic             buf_start_reg;
    logic [N-1:0]     buf_addr_reg;
    logic [N-1:0]     buf_len_reg;
    logic             dr_start_reg;
    logic [N-1:0]     dr_addr_reg;
    logic [N:0]       dr_len_reg;

    // =========================================================================
    // Waveform dump
    // =========================================================================
    initial begin
        $dumpfile("data_capture_ctrl_top.vcd");
        $dumpvars();
    end

    // =========================================================================
    // Clock generators
    // =========================================================================
    clk_gen #(
        .FREQ (SYS_CLOCK_FREQ)
    ) u_sys_clk_gen (
        .i_enable (1'b1),
        .o_clk    (clk)
    );

    clk_gen #(
        .FREQ (AXI_CLOCK_FREQ)
    ) u_axi_clk_gen (
        .i_enable (1'b1),
        .o_clk    (m_axis_aclk)
    );

    // =========================================================================
    // Clocking blocks (One for each clock domain)
    // =========================================================================
    clocking sys_cb @(posedge clk);
        default input #1step output #2;
        output trigger_i, din_valid_i, din_i;
        output buf_start_reg, buf_addr_reg, buf_len_reg;
    endclocking

    clocking axi_cb @(posedge m_axis_aclk);
        default input #1step output #2;
        input  m_axis_tvalid, m_axis_tdata, m_axis_tlast;
        output m_axis_tready;
        output dr_start_reg, dr_addr_reg, dr_len_reg;
    endclocking

    // ------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation
    // ------------------------------------------------------------------------
    data_capture_ctrl_top #(
        .N(N),
        .B(B)
    ) DUT (
        .clk            (clk),
        .rstn           (rstn),

        .trigger_i      (trigger_i),
        .din_valid_i    (din_valid_i),
        .din_i          (din_i),

        .m_axis_aclk    (m_axis_aclk),
        .m_axis_aresetn (m_axis_aresetn),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tlast   (m_axis_tlast),

        .buf_start_reg  (buf_start_reg),
        .buf_addr_reg   (buf_addr_reg),
        .buf_len_reg    (buf_len_reg),
        .dr_start_reg   (dr_start_reg),
        .dr_addr_reg    (dr_addr_reg),
        .dr_len_reg     (dr_len_reg)
    );

    // ------------------------------------------------------------------------
    // SVUnit Setup & Teardown
    // ------------------------------------------------------------------------
    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();

        // Default Input Values
        trigger_i     = 1'b0;
        din_valid_i   = 1'b0;
        din_i         = '0;
        buf_start_reg = 1'b0;
        buf_addr_reg  = '0;
        buf_len_reg   = '0;
        dr_start_reg  = 1'b0;
        dr_addr_reg   = '0;
        dr_len_reg    = '0;
        m_axis_tready = 1'b0;

        // Reset Sequence
        rstn = 1'b0;
        m_axis_aresetn = 1'b0;
        repeat(5) @(posedge clk);
        rstn = 1'b1;
        m_axis_aresetn = 1'b1;
        repeat(5) @(posedge clk);
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    // ------------------------------------------------------------------------
    // Helper Tasks
    // ------------------------------------------------------------------------
    
    // Asynchronous reset of the DUT during simulation
    task reset_dut();
        rstn = 1'b0; 
        m_axis_aresetn = 1'b0;
        repeat(10) @(posedge clk);
        rstn = 1'b1; 
        m_axis_aresetn = 1'b1;
        repeat(10) @(posedge clk);
    endtask

    // Configure the buffer and issue a trigger pulse
    task arm_and_trigger(
        input logic [N-1:0] addr, 
        input logic [N-1:0] len
        );
        sys_cb.buf_addr_reg  <= addr;
        sys_cb.buf_len_reg   <= len;
        sys_cb.buf_start_reg <= 1'b1;
        repeat(4) @(sys_cb);
        sys_cb.trigger_i     <= 1'b1;
        @(sys_cb);
        sys_cb.trigger_i     <= 1'b0;
    endtask

    // inject_data: push count words into the system.
    task automatic inject_data(
        input int count,
        input logic [2*B-1:0] start_val
    );
        for (int i = 0; i < count; i++) begin
            sys_cb.din_i       <= start_val + i;
            sys_cb.din_valid_i <= 1'b1;
            @(sys_cb);
        end
        sys_cb.din_valid_i <= 1'b0;
        repeat(6) @(sys_cb);
    endtask

    // start_reader: assert start_reg for the data_reader in the AXI domain.
    task automatic start_reader(
        input logic [N-1:0] addr,
        input logic [32-1:0] len
    );
        axi_cb.dr_addr_reg  <= addr;
        axi_cb.dr_len_reg   <= len[N:0];  // truncate when connecting to the register
        @(axi_cb);
        axi_cb.dr_start_reg <= 1'b1;
        @(axi_cb);
        axi_cb.dr_start_reg <= 1'b0;
    endtask

    // Read data from the AXIS master interface
    task automatic read_m_data(
      input int expected_words, 
      output logic [2*B-1:0] data[], 
      output int timed_out, 
      output int tlast_err,
      input  int timeout_cycles = 500   
    );
        int count = 0;
        int timeout = 0;
        timed_out = 0;
        tlast_err = 0;
        data = new[expected_words];

        axi_cb.m_axis_tready <= 1'b1;

        while (count < expected_words) begin
            @(axi_cb);
            timeout++;
            if (m_axis_tvalid && m_axis_tready) begin
                data[count] = m_axis_tdata;
                $display("[READ M0] data[%0d] = 0x%0h (tlast=%b)", count, m_axis_tdata, m_axis_tlast);
                
                // --- Automatic tlast validation ---
                if (count == expected_words - 1) begin
                  if (!m_axis_tlast) begin
                        $display("[ERROR] read_m_data: tlast NOT asserted on the last word (word %0d)", count);
                        tlast_err++;
                  end
                end else begin
                    if (m_axis_tlast) begin 
                      $display("[ERROR] read_m_data: tlast asserted EARLY at word %0d (expected at %0d)", count, expected_words - 1);
                      tlast_err++;
                    end
                end
                
                count++;
            end
            if (timeout > timeout_cycles) begin
                $display("[TIMEOUT] read_m_data: only got %0d of %0d words", count, expected_words);
                timed_out = 1;
                break;
            end
        end
    
        // Keep tready=1 until tvalid drops so the FSM can finish its last
        // handshake and return to IDLE cleanly.
        timeout = 0;
        while (m_axis_tvalid) begin
            @(axi_cb);
            timeout++;
            if (timeout > 50) begin
                $display("[TIMEOUT] read_m_data: tvalid stuck high after all data received");
                break;
            end
        end

        @(axi_cb);
        axi_cb.m_axis_tready <= 1'b0;
        repeat(5) @(axi_cb);
    endtask

    // ========================================================================
    // Include Test Cases
    // ========================================================================
    `SVUNIT_TESTS_BEGIN
        `include "tests.sv"
    `SVUNIT_TESTS_END

endmodule
