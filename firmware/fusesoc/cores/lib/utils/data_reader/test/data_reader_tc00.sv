// ============================================================================
// File: data_reader_tc00.sv
// Description: SVUnit testbench top-level for the data_reader module.
// ============================================================================

`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module data_reader_unit_test;

    import svunit_pkg::svunit_testcase;

    string name = "data_reader_ut";
    svunit_testcase svunit_ut;

    localparam real CLOCK_FREQUENCY = 200e6;
    localparam int  N = 8;
    localparam int  B = 16;

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    logic tb_clk  = 1'b0;
    logic tb_rstn = 1'b1;

    // =========================================================================
    // UUT interfaces
    // =========================================================================
    logic            tb_mem_en;
    logic            tb_mem_we;
    logic [N-1:0]    tb_mem_addr;
    logic [B-1:0]    tb_mem_dout;

    logic [B-1:0]    tb_dout;
    logic            tb_dready  = 1'b0;
    logic            tb_dvalid;
    logic            tb_dlast;

    logic            tb_start_reg = 1'b0;
    logic [N-1:0]    tb_addr_reg  = '0;
    logic [N-1:0]    tb_len_reg   = '0;

    // =========================================================================
    // Mock memory — 1-cycle registered read latency (matches real BRAM)
    // Initialized with mem[i] = i for predictable patterns.
    // =========================================================================
    logic [B-1:0] mem [0:2**N-1];

    initial begin
        for (int i = 0; i < 2**N; i++) mem[i] = B'(i);
    end

    always_ff @(posedge tb_clk) begin
        if (tb_mem_en) tb_mem_dout <= mem[tb_mem_addr];
    end

    // =========================================================================
    // Waveform dump
    // =========================================================================
    initial begin
        $dumpfile("data_reader.vcd");
        $dumpvars();
    end

    // =========================================================================
    // Clock generator
    // =========================================================================
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
        output tb_rstn;
        output tb_dready;
        output tb_start_reg;
        output tb_addr_reg;
        output tb_len_reg;
        input  tb_mem_en;
        input  tb_mem_we;
        input  tb_mem_addr;
        input  tb_dout;
        input  tb_dvalid;
        input  tb_dlast;
    endclocking

    // =========================================================================
    // Unit Under Test
    // =========================================================================
    data_reader #(
        .N (N),
        .B (B)
    ) u_data_reader (
        .rstn      (tb_rstn),
        .clk       (tb_clk),
        .mem_en    (tb_mem_en),
        .mem_we    (tb_mem_we),
        .mem_addr  (tb_mem_addr),
        .mem_dout  (tb_mem_dout),
        .dout      (tb_dout),
        .dready    (tb_dready),
        .dvalid    (tb_dvalid),
        .dlast     (tb_dlast),
        .start_reg (tb_start_reg),
        .addr_reg  (tb_addr_reg),
        .len_reg   (tb_len_reg)
    );

    // =========================================================================
    // Helper tasks
    // =========================================================================

    // reset_dut: apply synchronous reset sequence.
    task automatic reset_dut();
        cb.tb_rstn <= 1'b0;
        repeat(3) @(cb);
        cb.tb_rstn <= 1'b1;
        repeat(5) @(cb);
    endtask

    // start_reader: assert start_reg for one cycle with address and length.
    // Does NOT wait for previous transfer — call wait_for_idle first if needed.
    task automatic start_reader(
        input logic [N-1:0] addr,
        input logic [N-1:0] len
    );
        cb.tb_addr_reg  <= addr;
        cb.tb_len_reg   <= len;
        cb.tb_start_reg <= 1'b1;
        @(cb);
        cb.tb_start_reg <= 1'b0;
    endtask

    // wait_for_idle: keep dready=1 until dvalid drops (FSM back in IDLE_ST).
    // This drains any outstanding data and ensures the FSM has fully completed.
    // Must be called with dready driven by the caller if data is not being
    // collected — use after read_all_data or between consecutive transfers.
    task automatic wait_for_idle(output int timed_out);
        int timeout;
        timed_out = 0;
        timeout   = 0;
        // Keep dready=1 so the FSM can complete its last handshake
        tb_dready <= 1'b1;
        @(cb); // allow one cycle for dvalid to potentially rise
        while (tb_dvalid) begin
            @(cb);
            timeout++;
            if (timeout > 100) begin
                timed_out = 1;
                return;
            end
        end
        // One extra settle cycle
        @(cb);
        tb_dready <= 1'b0;
        @(cb);
    endtask

    // read_all_data: collect expected_count words from the AXI stream.
    // Holds dready=1 throughout. Does NOT lower dready until after all words
    // are received AND dvalid has gone low, so the FSM completes cleanly.
    task automatic read_all_data(
        input  int           expected_count,
        output logic [B-1:0] data[]
    );
        int count;
        int timeout;
        count   = 0;
        timeout = 0;
        data    = new[expected_count];

        tb_dready <= 1'b1;

        while (count < expected_count) begin
            @(cb);
            timeout++;
            if (tb_dvalid && tb_dready) begin
                data[count] = tb_dout;
                $display("[READ] data[%0d] = 0x%0h", count, tb_dout);
                count++;
            end
            if (timeout > 200) begin
                $display("[TIMEOUT] read_all_data: only got %0d of %0d words",
                         count, expected_count);
                break;
            end
        end

        // Keep dready=1 until dvalid drops so the FSM can finish its last
        // handshake and return to IDLE_ST cleanly.
        timeout = 0;
        while (tb_dvalid) begin
            @(cb);
            timeout++;
            if (timeout > 50) begin
                $display("[TIMEOUT] read_all_data: dvalid stuck high after all data received");
                break;
            end
        end

        tb_dready <= 1'b0;
        @(cb);
    endtask

    // verify_data: compare expected vs actual arrays, fail on mismatch.
    task automatic verify_data(
        input logic [B-1:0] expected[],
        input logic [B-1:0] actual[],
        input string        test_name
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
        tb_dready    <= 1'b0;
        cb.tb_start_reg <= 1'b0;
        cb.tb_addr_reg  <= '0;
        cb.tb_len_reg   <= '0;
        @(cb);
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
