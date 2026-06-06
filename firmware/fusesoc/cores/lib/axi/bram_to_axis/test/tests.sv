// ============================================================================
// tests.sv - Test suite for bram_to_axis module
// ============================================================================

`SVTEST(test_single_word)
    logic [B-1:0] expected[1];
    logic [B-1:0] actual[];
    expected[0] = B'(5);
    start_reader(N'(5), N'(1));
    read_all_data(1, actual);
    verify_data(expected, actual, "test_single_word");
`SVTEST_END

`SVTEST(test_multiple_words)
    logic [B-1:0] expected[5];
    logic [B-1:0] actual[];
    for (int i = 0; i < 5; i++) expected[i] = B'(10 + i);
    start_reader(N'(10), N'(5));
    read_all_data(5, actual);
    verify_data(expected, actual, "test_multiple_words");
`SVTEST_END

`SVTEST(test_dlast_assertion)
    logic [B-1:0] expected[3];
    logic [B-1:0] actual[];
    expected[0] = B'(20); expected[1] = B'(21); expected[2] = B'(22);
    start_reader(N'(20), N'(3));
    read_all_data(3, actual);
    verify_data(expected, actual, "test_dlast_assertion");
`SVTEST_END

`SVTEST(test_consecutive_reads)
    logic [B-1:0] expected1[3];
    logic [B-1:0] expected2[4];
    logic [B-1:0] actual[];
    for (int i = 0; i < 3; i++) expected1[i] = B'(40 + i);
    for (int i = 0; i < 4; i++) expected2[i] = B'(50 + i);
    start_reader(N'(40), N'(3));
    read_all_data(3, actual);
    verify_data(expected1, actual, "consecutive first");
    start_reader(N'(50), N'(4));
    read_all_data(4, actual);
    verify_data(expected2, actual, "consecutive second");
`SVTEST_END

`SVTEST(test_backpressure)
    logic [B-1:0] expected[6];
    logic [B-1:0] actual[];
    logic last;
    
    for (int i = 0; i < 6; i++) expected[i] = B'(30 + i);
    actual = new[6];
    
    start_reader(N'(30), N'(6));
    
    for (int i = 0; i < 6; i++) begin
        if (i < 5) begin
            read_with_backpressure(actual[i], last, 3);
        end else begin
            set_dready(1'b1);
            @(posedge tb_clk);
            while (!(axis_if_i.tvalid && axis_if_i.tready)) @(posedge tb_clk);
            actual[i] = axis_if_i.tdata;
            last = axis_if_i.tlast;
            set_dready(1'b0);
        end
        $display("[BKPR] data[%0d] = 0x%0h, last=%b", i, actual[i], last);
    end
    
    verify_data(expected, actual, "test_backpressure");
`SVTEST_END

`SVTEST(test_reset_during_operation)
    logic [B-1:0] expected[5];
    logic [B-1:0] actual[];
    for (int i = 0; i < 5; i++) expected[i] = B'(60 + i);
    start_reader(N'(60), N'(5));
    repeat(3) @(posedge tb_clk);
    reset_dut();
    start_reader(N'(60), N'(5));
    read_all_data(5, actual);
    verify_data(expected, actual, "after_reset");
`SVTEST_END

`SVTEST(test_address_relatch)
    logic [B-1:0] expected_a[2];
    logic [B-1:0] expected_b[2];
    logic [B-1:0] actual[];
    expected_a[0] = B'(100); expected_a[1] = B'(101);
    expected_b[0] = B'(200); expected_b[1] = B'(201);
    start_reader(N'(100), N'(2));
    read_all_data(2, actual);
    verify_data(expected_a, actual, "addr_relatch A");
    start_reader(N'(200), N'(2));
    read_all_data(2, actual);
    verify_data(expected_b, actual, "addr_relatch B");
`SVTEST_END

`SVTEST(test_zero_length)
    start_reader(N'(10), N'(0));
    repeat(10) @(posedge tb_clk);
    `FAIL_UNLESS(axis_if_i.tvalid == 1'b0);
`SVTEST_END

`SVTEST(test_fifo_full_stall)
    logic [B-1:0] expected[20];
    logic [B-1:0] actual[];
    logic last;
    
    for (int i = 0; i < 20; i++) expected[i] = B'(80 + i);
    actual = new[20];
    
    start_reader(N'(80), N'(20));
    
    for (int i = 0; i < 20; i++) begin
        if (i == 5) begin
            read_with_backpressure(actual[i], last, 50);
        end else begin
            set_dready(1'b1);
            @(posedge tb_clk);
            while (!(axis_if_i.tvalid && axis_if_i.tready)) @(posedge tb_clk);
            actual[i] = axis_if_i.tdata;
            last = axis_if_i.tlast;
            set_dready(1'b0);
        end
        $display("[READ] data[%0d] = 0x%0h, last=%b", i, actual[i], last);
    end
    
    verify_data(expected, actual, "test_fifo_full_stall");
`SVTEST_END

`SVTEST(test_concurrent_start_ignored)
    logic [B-1:0] expected[5];
    logic [B-1:0] actual[];
    for (int i = 0; i < 5; i++) expected[i] = B'(120 + i);
    start_reader(N'(120), N'(5));
    repeat(2) @(posedge tb_clk);
    tb_start_reg <= 1'b1;
    @(posedge tb_clk);
    tb_start_reg <= 1'b0;
    read_all_data(5, actual);
    verify_data(expected, actual, "test_concurrent_start_ignored");
`SVTEST_END

`SVTEST(test_memory_wrap)
    logic [B-1:0] expected[2];
    logic [B-1:0] actual[];
    expected[0] = B'(255);
    expected[1] = B'(0);
    start_reader(N'(255), N'(2));
    read_all_data(2, actual);
    verify_data(expected, actual, "test_memory_wrap");
`SVTEST_END
