// ============================================================================
// File: data_writer_sg_tc00.sv
// Description: SVUnit testbench top-level for data_writer_sg.
// ============================================================================

`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module data_writer_sg_unit_test;

    import svunit_pkg::svunit_testcase;

    string name = "data_writer_sg_ut";
    svunit_testcase svunit_ut;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real CLOCK_FREQUENCY = 200e6;
    localparam int N = 8;   // address width — depth = 256
    localparam int B = 16;  // data width

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    logic tb_clk  = 1'b0;
    logic tb_rstn = 1'b0;

    // =========================================================================
    // DUT interfaces
    // =========================================================================
    // AXI Stream
    logic          tb_s_axis_tready;
    logic [B-1:0]  tb_s_axis_tdata  = '0;
    logic          tb_s_axis_tvalid = 1'b0;

    // Memory
    logic          tb_mem_en;
    logic          tb_mem_we;
    logic [N-1:0]  tb_mem_addr;
    logic [B-1:0]  tb_mem_di;

    // =========================================================================
    // Waveform dump
    // =========================================================================
    initial begin
        $dumpfile("data_writer_sg.vcd");
        $dumpvars();
    end


    // Registers
    logic [31:0]   tb_start_addr_reg = '0;
    logic          tb_we_reg         = 1'b0;

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
        output tb_s_axis_tdata;
        output tb_s_axis_tvalid;
        output tb_start_addr_reg;
        output tb_we_reg;
        input  tb_s_axis_tready;
        input  tb_mem_en;
        input  tb_mem_we;
        input  tb_mem_addr;
        input  tb_mem_di;
    endclocking

    // =========================================================================
    // DUT
    // =========================================================================
    data_writer_sg #(
        .N (N),
        .B (B)
    ) u_dut (
        .rstn            (tb_rstn),
        .clk             (tb_clk),
        .s_axis_tready   (tb_s_axis_tready),
        .s_axis_tdata    (tb_s_axis_tdata),
        .s_axis_tvalid   (tb_s_axis_tvalid),
        .mem_en          (tb_mem_en),
        .mem_we          (tb_mem_we),
        .mem_addr        (tb_mem_addr),
        .mem_di          (tb_mem_di),
        .start_addr_reg  (tb_start_addr_reg),
        .we_reg          (tb_we_reg)
    );

    // =========================================================================
    // Helper tasks
    // =========================================================================

    // reset_dut: synchronous active-low reset.
    task automatic reset_dut();
        cb.tb_rstn           <= 1'b0;
        cb.tb_we_reg         <= 1'b0;
        cb.tb_s_axis_tvalid  <= 1'b0;
        cb.tb_s_axis_tdata   <= '0;
        cb.tb_start_addr_reg <= '0;
        repeat(10) @(cb);
        cb.tb_rstn <= 1'b1;
        repeat(5)  @(cb);
    endtask

    // enable_writer: assert we_reg and wait for CDC + FSM to reach
    // READ_START_ADDR_ST → WAIT_TVALID_ST.
    // After this call the FSM is in WAIT_TVALID_ST with tready asserted.
    task automatic enable_writer(input logic [31:0] start_addr);
        cb.tb_start_addr_reg <= start_addr;
        cb.tb_we_reg         <= 1'b1;
        repeat(6) @(cb); // 2 CDC + FSM transitions
    endtask

    // disable_writer: de-assert we_reg, FSM returns to INIT_ST.
    task automatic disable_writer();
        cb.tb_we_reg <= 1'b0;
        repeat(6) @(cb);
    endtask

    // send_sample: drive one AXI handshake.
    task automatic send_sample(input logic [B-1:0] data);
        cb.tb_s_axis_tdata  <= data;
        cb.tb_s_axis_tvalid <= 1'b1;
        // Wait for tready
        @(cb iff tb_s_axis_tready);
        @(cb);
        cb.tb_s_axis_tvalid <= 1'b0;
        cb.tb_s_axis_tdata  <= '0;
    endtask

    // send_stream: send count samples starting at start_val, incrementing.
    // Captures (mem_addr, mem_di) pairs into addr_out[] and data_out[].
    task automatic send_stream(
        input  int           count,
        input  logic [B-1:0] start_val,
        output logic [N-1:0] addr_out [],
        output logic [B-1:0] data_out []
    );
        int captured = 0;
        addr_out = new[count];
        data_out = new[count];

        fork
            // Driver
            begin
                for (int i = 0; i < count; i++) begin
                    cb.tb_s_axis_tdata  <= start_val + B'(i);
                    cb.tb_s_axis_tvalid <= 1'b1;
                    @(cb iff tb_s_axis_tready);
                end
                @(cb);
                cb.tb_s_axis_tvalid <= 1'b0;
                cb.tb_s_axis_tdata  <= '0;
            end
            // Monitor: capture mem writes
            begin
                while (captured < count) begin
                    @(cb);
                    if (tb_mem_we) begin
                        addr_out[captured] = tb_mem_addr;
                        data_out[captured] = tb_mem_di;
                        captured++;
                    end
                end
            end
        join
        repeat(5) @(cb); // drain pipeline
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
        disable_writer();
        repeat(5) @(cb);
    endtask

    // =========================================================================
    // Test cases
    // =========================================================================
    `SVUNIT_TESTS_BEGIN
    `include "data_writer_sg_tests.sv"
    `SVUNIT_TESTS_END

endmodule
