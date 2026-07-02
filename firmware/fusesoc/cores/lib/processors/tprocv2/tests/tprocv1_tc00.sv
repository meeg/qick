`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

//------------------------------------------------------------------------------
// Component : tproc64x32_x8_unit_test
// Origin    : Converted from VHDL tproc64x32_x8 (QICK tProcessor)
//             See tproc64x32_x8.sv for full architectural notes.
//
// Description:
//   Unit testbench for the full tProcessor (tproc64x32_x8). The DUT integrates:
//     - Program memory interface (pmem_addr, pmem_do)
//     - Data memory interface (dmem_we, dmem_addr, dmem_di, dmem_do)
//     - 4 AXI4-Stream slave inputs (64-bit)
//     - 8 AXI4-Stream master outputs (160-bit)
//     - Control unit (tpv1_ctrl)
//     - Register file (8 read, 1 write) with page selection
//     - Stack (tpv1_stack)
//     - ALU for arithmetic/bitwise ops (multi-cycle)
//     - Conditional unit (cond)
//     - Per‑channel FIFOs + timed_ictrl for timed instructions (wait/set/sync)
//     - Master clock counter (48‑bit) with sync capability
//
//   The testbench provides a clock, reset, and all external memories,
//   AXIS interfaces, and control inputs. It drives program and data memories
//   with preloaded content and verifies the DUT's behavior through
//   execution of a set of test instructions.
//
//   Test cases cover:
//     - Startup/reset sequence
//     - Arithmetic and bitwise operations (I‑type and R‑type)
//     - Stack operations (pushi, popi)
//     - Loops and conditional jumps (loopnz, condj)
//     - Timed instructions (seti, waiti, synci, set, wait, sync)
//     - Memory reads/writes (memri, memwi, memr, memw)
//     - Register writes (regwi)
//     - AXIS read (read)
//     - Error handling (unknown opcode, stack overflow/underflow)
//     - FIFO stalls and blocking handshakes (setbi, setb)
//
//   Naming note:
//     The module name 'tproc64x32_x8_unit_test' is chosen for consistency
//     with the existing QICK verification framework.
//------------------------------------------------------------------------------
module tproc64x32_x8_unit_test;
    import svunit_pkg::svunit_testcase;

    string name = "tproc64x32_x8_ut";
    svunit_testcase svunit_ut;

    //--------------------------------------------------------------------------
    // Testbench Parameters
    //--------------------------------------------------------------------------
    localparam real CLOCK_FREQUENCY = 100e6; // 100 MHz

    // Program memory depth (N) and data memory depth (M) must match DUT
    localparam N = 16;
    localparam M = 10;

    // Opcode constants (matching tpv1_ctrl)
    localparam logic [7:0] OP_PUSHI  = 8'h10;
    localparam logic [7:0] OP_POPI   = 8'h11;
    localparam logic [7:0] OP_MATHI  = 8'h12;
    localparam logic [7:0] OP_SETI   = 8'h13;
    localparam logic [7:0] OP_SYNCI  = 8'h14;
    localparam logic [7:0] OP_WAITI  = 8'h15;
    localparam logic [7:0] OP_BITWI  = 8'h16;
    localparam logic [7:0] OP_MEMRI  = 8'h17;
    localparam logic [7:0] OP_MEMWI  = 8'h18;
    localparam logic [7:0] OP_REGWI  = 8'h19;
    localparam logic [7:0] OP_SETBI  = 8'h1A;
    localparam logic [7:0] OP_LOOPNZ = 8'h30;
    localparam logic [7:0] OP_CONDJ  = 8'h31;
    localparam logic [7:0] OP_END    = 8'h3F;
    localparam logic [7:0] OP_MATH   = 8'h50;
    localparam logic [7:0] OP_SET    = 8'h51;
    localparam logic [7:0] OP_SYNC   = 8'h52;
    localparam logic [7:0] OP_READ   = 8'h53;
    localparam logic [7:0] OP_WAIT   = 8'h54;
    localparam logic [7:0] OP_BITW   = 8'h55;
    localparam logic [7:0] OP_MEMR   = 8'h56;
    localparam logic [7:0] OP_MEMW   = 8'h57;
    localparam logic [7:0] OP_SETB   = 8'h58;

    //--------------------------------------------------------------------------
    // Interface & Testbench Signals
    //--------------------------------------------------------------------------
    logic          tb_clk          = 1'b0;
    logic          tb_rstn         = 1'b0;
    logic          tb_start        = 1'b0;

    // Program Memory (TB drives pmem_do; DUT drives pmem_addr)
    logic [N-1:0]  tb_pmem_addr;
    logic [63:0]   tb_pmem_do = '0;

    // Data Memory (DUT drives dmem_we, addr, di; TB drives dmem_do)
    logic          tb_dmem_we;
    logic [M-1:0]  tb_dmem_addr;
    logic [31:0]   tb_dmem_di;
    logic [31:0]   tb_dmem_do = '0;

    // AXI4-Stream interfaces (slave inputs, master outputs)
    axi4_stream_if #(.DATA_WIDTH(64))  s0_axis(tb_clk);
    axi4_stream_if #(.DATA_WIDTH(64))  s1_axis(tb_clk);
    axi4_stream_if #(.DATA_WIDTH(64))  s2_axis(tb_clk);
    axi4_stream_if #(.DATA_WIDTH(64))  s3_axis(tb_clk);

    axi4_stream_if #(.DATA_WIDTH(160)) m0_axis(tb_clk);
    axi4_stream_if #(.DATA_WIDTH(160)) m1_axis(tb_clk);
    axi4_stream_if #(.DATA_WIDTH(160)) m2_axis(tb_clk);
    axi4_stream_if #(.DATA_WIDTH(160)) m3_axis(tb_clk);
    axi4_stream_if #(.DATA_WIDTH(160)) m4_axis(tb_clk);
    axi4_stream_if #(.DATA_WIDTH(160)) m5_axis(tb_clk);
    axi4_stream_if #(.DATA_WIDTH(160)) m6_axis(tb_clk);
    axi4_stream_if #(.DATA_WIDTH(160)) m7_axis(tb_clk);

    // Register control inputs
    logic          tb_START_SRC_REG = 1'b0;
    logic          tb_START_REG     = 1'b0;

    //--------------------------------------------------------------------------
    // VCD Waveform Generation
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("tproc64x32_x8.vcd");
        $dumpvars(0, tproc64x32_x8_unit_test);
    end

    //--------------------------------------------------------------------------
    // Clock Generator Instance
    //--------------------------------------------------------------------------
    clk_gen #(
        .FREQ (CLOCK_FREQUENCY)
    ) u_clk_gen (
        .i_enable (1'b1),
        .o_clk    (tb_clk)
    );

    //--------------------------------------------------------------------------
    // Default Clocking Block
    //--------------------------------------------------------------------------
    default clocking cb @(posedge tb_clk);
        default input #1step output #2;

        // TB drives
        output tb_rstn;
        output tb_start;
        output tb_pmem_do;
        output tb_dmem_do;
        output tb_START_SRC_REG;
        output tb_START_REG;

        // DUT drives
        input  tb_pmem_addr;
        input  tb_dmem_we;
        input  tb_dmem_addr;
        input  tb_dmem_di;

        // AXI interfaces are connected via modports; we drive/read through them.
        // For simplicity, we will drive/read directly through the interface signals
        // inside the tests, using the interface's clocking block.
    endclocking

    //--------------------------------------------------------------------------
    // Unit Under Test (DUT)
    //--------------------------------------------------------------------------
    tproc64x32_x8 #(
        .N (N),
        .M (M)
    ) u_dut (
        .clk            (tb_clk),
        .rstn           (tb_rstn),
        .start          (tb_start),
        .pmem_addr      (tb_pmem_addr),
        .pmem_do        (tb_pmem_do),
        .dmem_we        (tb_dmem_we),
        .dmem_addr      (tb_dmem_addr),
        .dmem_di        (tb_dmem_di),
        .dmem_do        (tb_dmem_do),
        .s0_axis        (s0_axis),
        .s1_axis        (s1_axis),
        .s2_axis        (s2_axis),
        .s3_axis        (s3_axis),
        .m0_axis        (m0_axis),
        .m1_axis        (m1_axis),
        .m2_axis        (m2_axis),
        .m3_axis        (m3_axis),
        .m4_axis        (m4_axis),
        .m5_axis        (m5_axis),
        .m6_axis        (m6_axis),
        .m7_axis        (m7_axis),
        .START_SRC_REG  (tb_START_SRC_REG),
        .START_REG      (tb_START_REG)
    );

    //--------------------------------------------------------------------------
    // Concurrent Assertions
    //--------------------------------------------------------------------------

    // pc_rst and pc_en must not be asserted simultaneously
    property no_pc_rst_and_en;
        @(posedge tb_clk) disable iff (!tb_rstn)
        !(u_dut.pc_rst_i && u_dut.pc_en_i);
    endproperty
    `ASSERT_CONCURRENT(no_pc_rst_and_en);

    // dmem_we and dmem_addr must be stable when we=1 (simple check)
    property dmem_we_stable;
        @(posedge tb_clk) disable iff (!tb_rstn)
        (u_dut.dmem_we == 1'b1) |=> (u_dut.dmem_addr == $past(u_dut.dmem_addr));
    endproperty
    `ASSERT_CONCURRENT(dmem_we_stable);

    // No simultaneous stack push and pop
    property no_stack_push_and_pop;
        @(posedge tb_clk) disable iff (!tb_rstn)
        !(u_dut.stack_en_i && (u_dut.stack_op_i ^ $past(u_dut.stack_op_i)));
    endproperty
    `ASSERT_CONCURRENT(no_stack_push_and_pop);

    //--------------------------------------------------------------------------
    // SVUnit Infrastructure (Build, Setup, Teardown)
    //--------------------------------------------------------------------------
    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
        cb.tb_rstn          <= 1'b0;
        cb.tb_start         <= 1'b0;
        cb.tb_pmem_do       <= '0;
        cb.tb_dmem_do       <= '0;
        cb.tb_START_SRC_REG <= 1'b0;
        cb.tb_START_REG     <= 1'b0;
        // Ensure AXIS interfaces are idle
        s0_axis.cb.tvalid   <= 1'b0;
        s1_axis.cb.tvalid   <= 1'b0;
        s2_axis.cb.tvalid   <= 1'b0;
        s3_axis.cb.tvalid   <= 1'b0;
        m0_axis.cb.tready   <= 1'b1;
        m1_axis.cb.tready   <= 1'b1;
        m2_axis.cb.tready   <= 1'b1;
        m3_axis.cb.tready   <= 1'b1;
        m4_axis.cb.tready   <= 1'b1;
        m5_axis.cb.tready   <= 1'b1;
        m6_axis.cb.tready   <= 1'b1;
        m7_axis.cb.tready   <= 1'b1;
        repeat(3) @(cb);
        cb.tb_rstn <= 1'b1;
        repeat(2) @(cb);
    endtask

    task teardown();
        svunit_ut.teardown();
        cb.tb_rstn          <= 1'b0;
        cb.tb_start         <= 1'b0;
        cb.tb_pmem_do       <= '0;
        cb.tb_dmem_do       <= '0;
        cb.tb_START_SRC_REG <= 1'b0;
        cb.tb_START_REG     <= 1'b0;
        s0_axis.cb.tvalid   <= 1'b0;
        s1_axis.cb.tvalid   <= 1'b0;
        s2_axis.cb.tvalid   <= 1'b0;
        s3_axis.cb.tvalid   <= 1'b0;
        m0_axis.cb.tready   <= 1'b1;
        m1_axis.cb.tready   <= 1'b1;
        m2_axis.cb.tready   <= 1'b1;
        m3_axis.cb.tready   <= 1'b1;
        m4_axis.cb.tready   <= 1'b1;
        m5_axis.cb.tready   <= 1'b1;
        m6_axis.cb.tready   <= 1'b1;
        m7_axis.cb.tready   <= 1'b1;
        repeat(2) @(cb);
    endtask

    //--------------------------------------------------------------------------
    // Helper Tasks
    //--------------------------------------------------------------------------

    // Build a 64-bit instruction word from fields
    function automatic logic [63:0] build_instruction(
        input logic [7:0]  opcode,
        input logic [2:0]  page,
        input logic [2:0]  channel,
        input logic [3:0]  oper,
        input logic [4:0]  ra,
        input logic [4:0]  rb,
        input logic [4:0]  rc,
        input logic [30:0] imm
    );
        return {opcode, page, channel, oper, ra, rb, rc, imm[30:16], imm[15:0]};
    endfunction

    // Load a program into the program memory (pmem_do is driven by TB)
    // This task stores an array of instructions and drives them one by one
    // as the DUT fetches (pmem_addr changes).
    // Simpler approach: use a large combinational memory modeled as an array.
    logic [63:0] pmem_array [0:2**N - 1];

    task automatic load_program(input logic [63:0] program[]);
        for (int i = 0; i < program.size(); i++) begin
            pmem_array[i] = program[i];
        end
        // Fill rest with NOP (or end)
        for (int i = program.size(); i < 2**N; i++) begin
            pmem_array[i] = {OP_END, 56'b0};
        end
    endtask

    // Drive pmem_do based on pmem_addr (combinational)
    always_comb begin
        tb_pmem_do = pmem_array[tb_pmem_addr];
    end

    // Data memory model (simple array)
    logic [31:0] dmem_array [0:2**M - 1];
    initial begin
        for (int i = 0; i < 2**M; i++) dmem_array[i] = '0;
    end

    // Drive dmem_do from array
    always_comb begin
        tb_dmem_do = dmem_array[tb_dmem_addr];
    end

    // Write to data memory when dmem_we is asserted (in the test, we need to
    // update the array on the same cycle? Actually, the DUT expects memory to
    // be synchronous or asynchronous. We'll model it as combinational read,
    // write on posedge clk with we=1.
    always_ff @(posedge tb_clk) begin
        if (tb_dmem_we) begin
            dmem_array[tb_dmem_addr] <= tb_dmem_di;
        end
    end

    // Helper to start the processor and wait until it reaches a given state
    task start_processor();
        cb.tb_start <= 1'b1;
        @(cb);
        @(cb); // Need two cycles due to clocking block skew
        // Wait until FETCH_ST (or DECODE_ST) to ensure it's running
        while (u_dut.ctrl_i.state.name != "FETCH_ST") @(cb);
        @(cb);
    endtask

    // Helper to check that DUT is in a specific state (using state.name)
    task wait_for_state(input string target_state, input int timeout_cycles = 100);
        int cnt = 0;
        while (u_dut.ctrl_i.state.name != target_state) begin
            @(cb);
            cnt++;
            if (cnt > timeout_cycles) begin
                $error("Timeout waiting for state %s (current state: %s)",
                       target_state, u_dut.ctrl_i.state.name);
                break;
            end
        end
        @(cb); // extra cycle for combinational outputs to settle
    endtask

    // Helper to check an output signal using internal DUT signal
    // (to avoid clocking block skew)
    function automatic logic get_signal(ref logic signal);
        return signal;
    endfunction

    //--------------------------------------------------------------------------
    // Test Cases Block Insertion
    //--------------------------------------------------------------------------
    `SVUNIT_TESTS_BEGIN
        `include "tproc64x32_x8_tests.sv"
    `SVUNIT_TESTS_END

endmodule
