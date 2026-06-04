// ============================================================================
// File: data_writer_sg_nt_tc00.sv
// Description: SVUnit testbench top-level for data_writer_sg_nt.
// ============================================================================

`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module data_writer_sg_nt_unit_test;

    import svunit_pkg::svunit_testcase;

    string name = "data_writer_sg_nt_ut";
    svunit_testcase svunit_ut;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real CLOCK_FREQUENCY = 200e6;
    localparam int NT = 4;   // number of tables (power of 2)
    localparam int N  = 4;   // address width per table — depth = 16
    localparam int B  = 16;  // data width

    localparam int NT_LOG2 = $clog2(NT);

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    logic tb_clk  = 1'b0;
    logic tb_rstn = 1'b0;

    // =========================================================================
    // DUT interfaces
    // =========================================================================
    logic           tb_s_axis_tready;
    logic [B-1:0]   tb_s_axis_tdata  = '0;
    logic           tb_s_axis_tvalid = 1'b0;

    logic [NT-1:0]  tb_mem_en;
    logic           tb_mem_we;
    logic [N-1:0]   tb_mem_addr;
    logic [B-1:0]   tb_mem_di;

    logic [31:0]    tb_start_addr_reg = '0;
    logic           tb_we_reg         = 1'b0;

    // =========================================================================
    // Waveform dump
    // =========================================================================
    initial begin
        $dumpfile("data_writer_sg_nt.vcd");
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
    data_writer_sg_nt #(
        .NT (NT),
        .N  (N),
        .B  (B)
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
    // Captured write record
    // =========================================================================
    typedef struct {
        logic [NT-1:0] en;
        logic [N-1:0]  addr;
        logic [B-1:0]  data;
    } write_rec_t;

    // =========================================================================
    // Helper tasks
    // =========================================================================

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

    task automatic enable_writer(input logic [31:0] start_addr);
        cb.tb_start_addr_reg <= start_addr;
        cb.tb_we_reg         <= 1'b1;
        repeat(6) @(cb);
    endtask

    task automatic disable_writer();
        cb.tb_we_reg <= 1'b0;
        repeat(6) @(cb);
    endtask

    // send_stream_capture: send count samples and capture all memory writes.
    task automatic send_stream_capture(
        input  int           count,
        input  logic [B-1:0] start_val,
        output write_rec_t   writes[]
    );
        int captured = 0;
        writes = new[count];

        fork
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
            begin
                while (captured < count) begin
                    @(cb);
                    if (tb_mem_we) begin
                        writes[captured].en   = tb_mem_en;
                        writes[captured].addr = tb_mem_addr;
                        writes[captured].data = tb_mem_di;
                        captured++;
                    end
                end
            end
        join
        repeat(5) @(cb);
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
    `include "data_writer_sg_nt_tests.sv"
    `SVUNIT_TESTS_END

endmodule
