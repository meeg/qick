// ============================================================================
// File: data_writer_trig_tc00.sv
// Description: SVUnit testbench top-level for data_writer_trig.
// ============================================================================

`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module data_writer_trig_unit_test;

    import svunit_pkg::svunit_testcase;

    string name = "data_writer_trig_ut";
    svunit_testcase svunit_ut;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real CLOCK_FREQUENCY = 200e6;
    localparam int N = 4;   // address width — capture depth = 2**4 = 16
    localparam int B = 16;  // data width
    localparam int DEPTH = 2**N;

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    logic tb_clk  = 1'b0;
    logic tb_rstn = 1'b0;

    // =========================================================================
    // DUT interfaces
    // =========================================================================
    logic          tb_trigger        = 1'b0;
    logic          tb_s_axis_tready;
    logic [B-1:0]  tb_s_axis_tdata  = '0;
    logic          tb_s_axis_tvalid = 1'b0;
    logic          tb_mem_en;
    logic          tb_mem_we;
    logic [N-1:0]  tb_mem_addr;
    logic [B-1:0]  tb_mem_di;
    logic          tb_capture_reg   = 1'b0;

    // =========================================================================
    // Waveform dump
    // =========================================================================
    initial begin
        $dumpfile("data_writer_trig.vcd");
        $dumpvars();
    end


    // =========================================================================
    // Clock generator: 200 MHz
    // =========================================================================
    //always #2.5 tb_clk = ~tb_clk;
    clk_gen #(
        .FREQ (CLOCK_FREQUENCY)
    ) u_clk_gen (
        .i_enable (1'b1),
        .o_clk    (tb_clk)
    );

    // =========================================================================
    // Clocking block
    // =========================================================================
    default clocking cb @(posedge tb_clk);
        default input #1step output #2;
        output tb_rstn;
        output tb_trigger;
        output tb_s_axis_tdata;
        output tb_s_axis_tvalid;
        output tb_capture_reg;
        input  tb_s_axis_tready;
        input  tb_mem_en;
        input  tb_mem_we;
        input  tb_mem_addr;
        input  tb_mem_di;
    endclocking

    // =========================================================================
    // DUT
    // =========================================================================
    data_writer_trig #(
        .N (N),
        .B (B)
    ) u_dut (
        .rstn           (tb_rstn),
        .clk            (tb_clk),
        .trigger        (tb_trigger),
        .s_axis_tready  (tb_s_axis_tready),
        .s_axis_tdata   (tb_s_axis_tdata),
        .s_axis_tvalid  (tb_s_axis_tvalid),
        .mem_en         (tb_mem_en),
        .mem_we         (tb_mem_we),
        .mem_addr       (tb_mem_addr),
        .mem_di         (tb_mem_di),
        .capture_reg    (tb_capture_reg)
    );

    // =========================================================================
    // Helper tasks
    // =========================================================================

    task automatic reset_dut();
        cb.tb_rstn          <= 1'b0;
        cb.tb_capture_reg   <= 1'b0;
        cb.tb_trigger       <= 1'b0;
        cb.tb_s_axis_tvalid <= 1'b0;
        cb.tb_s_axis_tdata  <= '0;
        repeat(10) @(cb);
        cb.tb_rstn <= 1'b1;
        repeat(5)  @(cb);
    endtask

    // arm: assert capture_reg and wait for FSM to reach TRIGGER_ST
    task automatic arm();
        cb.tb_capture_reg <= 1'b1;
        repeat(3) @(cb);
    endtask

    // disarm: de-assert capture_reg, FSM returns to INIT_ST after FIFO drains
    task automatic disarm();
        cb.tb_capture_reg <= 1'b0;
        repeat(5) @(cb);
    endtask

    // pulse_trigger: one-cycle trigger pulse → FSM TRIGGER_ST → CAPTURE_ST
    task automatic pulse_trigger();
        cb.tb_trigger <= 1'b1;
        @(cb);
        cb.tb_trigger <= 1'b0;
    endtask

    // stream_data: drive count samples continuously, incrementing from start_val.
    task automatic stream_data(input int count, input logic [B-1:0] start_val);
        for (int i = 0; i < count; i++) begin
            cb.tb_s_axis_tdata  <= start_val + B'(i);
            cb.tb_s_axis_tvalid <= 1'b1;
            @(cb);
            
            // The testbench blocks here until the DUT accepts the data (s_axis_tready), 
            // ensuring we don't overflow the FIFO in the testbench.
            while (!tb_s_axis_tready) @(cb); 
        end
        cb.tb_s_axis_tvalid <= 1'b0;
        cb.tb_s_axis_tdata  <= '0;
    endtask

    // capture_writes: monitor and collect all memory writes until count reached
    // or timeout expires.
    task automatic capture_writes(
        input  int           expected,
        output logic [N-1:0] addr_out[],
        output logic [B-1:0] data_out[],
        output int           got,
        input  int           timeout = 200
    );
        int t = 0;
        got = 0;
        addr_out = new[expected];
        data_out = new[expected];
    
        while (got < expected && t < timeout) begin
            @(cb);
            t++;
            // read mem_we signal directly, not through cb to avoid 
            // blocking on cb when mem_we is asserted
            if (tb_mem_we) begin         
                addr_out[got] = tb_mem_addr;
                data_out[got] = tb_mem_di;
                got++;
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
        disarm();
        repeat(5) @(cb);
    endtask

    // =========================================================================
    // Test cases
    // =========================================================================
    `SVUNIT_TESTS_BEGIN
    `include "data_writer_trig_tests.sv"
    `SVUNIT_TESTS_END

endmodule
