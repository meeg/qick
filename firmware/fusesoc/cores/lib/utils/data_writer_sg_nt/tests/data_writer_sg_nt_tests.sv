// ============================================================================
// File: data_writer_sg_nt_tests.sv
// Description: SVUnit test cases for data_writer_sg_nt.
// Included by data_writer_sg_nt_tc00.sv.
// ============================================================================

// ----------------------------------------------------------------------------
// TEST 01: Reset — no mem_we, no tready
// ----------------------------------------------------------------------------
`SVTEST(test_reset_no_write)
    repeat(5) @(cb);
    `FAIL_IF(tb_mem_we);
    `FAIL_IF(tb_s_axis_tready);
    `FAIL_IF(tb_mem_en !== '0);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 02: Enable writer — tready asserted after FSM reaches WAIT_TVALID_ST
// ----------------------------------------------------------------------------
`SVTEST(test_enable_asserts_tready)
    enable_writer(32'd0);
    repeat(2) @(cb);
    `FAIL_IF(!tb_s_axis_tready);
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 03: mem_en one-hot — only one table enabled per write
// With start_addr=0, successive writes target tables 0,1,2,3,0,1,...
// ----------------------------------------------------------------------------
`SVTEST(test_mem_en_one_hot)
    write_rec_t writes[];
    int total = NT * 2; // two full rotations through all tables

    enable_writer(32'd0);
    send_stream_capture(total, 16'h0001, writes);

    for (int i = 0; i < total; i++) begin
        // Exactly one bit must be set
        int bit_count = 0;
        for (int b = 0; b < NT; b++)
            if (writes[i].en[b]) bit_count++;
        if (bit_count !== 1) begin
            $display("[FAIL] test_mem_en_one_hot: write[%0d] en=0b%0b has %0d bits set",
                     i, writes[i].en, bit_count);
            `FAIL_IF(1);
        end
    end
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 04: Table rotation — consecutive writes cycle through tables 0..NT-1
// Starting at addr=0: write 0 → table 0, write 1 → table 1, ...
// ----------------------------------------------------------------------------
`SVTEST(test_table_rotation)
    write_rec_t writes[];
    int total = NT;

    enable_writer(32'd0);
    send_stream_capture(total, 16'h0001, writes);

    for (int i = 0; i < total; i++) begin
        logic [NT-1:0] expected_en = NT'(1 << i);
        if (writes[i].en !== expected_en) begin
            $display("[FAIL] test_table_rotation: write[%0d] en=0b%0b expected 0b%0b",
                     i, writes[i].en, expected_en);
            `FAIL_IF(1);
        end
    end
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 05: mem_addr increments for each complete table cycle
// Writes 0..NT-1 all go to mem_addr=start_high.
// Writes NT..2*NT-1 go to mem_addr=start_high+1.
// ----------------------------------------------------------------------------
`SVTEST(test_mem_addr_increment)
    write_rec_t writes[];
    localparam int START_HIGH = 2; // start_addr = START_HIGH * NT
    int total = NT * 3;

    enable_writer(32'(START_HIGH * NT));
    send_stream_capture(total, 16'h0001, writes);

    for (int i = 0; i < total; i++) begin
        logic [N-1:0] expected_addr = N'(START_HIGH + i/NT);
        if (writes[i].addr !== expected_addr) begin
            $display("[FAIL] test_mem_addr_increment: write[%0d] addr=0x%0h expected 0x%0h",
                     i, writes[i].addr, expected_addr);
            `FAIL_IF(1);
        end
    end
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 06: Data integrity — mem_di matches sent data in order
// ----------------------------------------------------------------------------
`SVTEST(test_data_integrity)
    write_rec_t writes[];
    localparam int COUNT = NT * 2;

    enable_writer(32'd0);
    send_stream_capture(COUNT, 16'h0100, writes);

    for (int i = 0; i < COUNT; i++) begin
        logic [B-1:0] expected = B'(16'h0100 + i);
        if (writes[i].data !== expected) begin
            $display("[FAIL] test_data_integrity: write[%0d] data=0x%0h expected 0x%0h",
                     i, writes[i].data, expected);
            `FAIL_IF(1);
        end
    end
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 07: Start address alignment — non-zero start_addr offsets both table
// selection and row address correctly.
// start_addr = NT+1 → first write goes to table 1, row 1.
// ----------------------------------------------------------------------------
`SVTEST(test_start_addr_alignment)
    logic [NT-1:0] expected_en; 
    logic [N-1:0]  expected_addr;
    write_rec_t writes[];
    // start_addr = NT + 1 → low bits = 1 (table 1), high bits = 1 (row 1)
    localparam int START = NT + 1;

    enable_writer(32'(START));
    send_stream_capture(1, 16'hFACE, writes);

    // Table selected by low NT_LOG2 bits of start_addr
    expected_en   = NT'(1 << (START % NT));
    expected_addr = N'(START / NT);

    if (writes[0].en !== expected_en) begin
        $display("[FAIL] test_start_addr_alignment: en=0b%0b expected 0b%0b",
                 writes[0].en, expected_en);
        `FAIL_IF(1);
    end
    if (writes[0].addr !== expected_addr) begin
        $display("[FAIL] test_start_addr_alignment: addr=0x%0h expected 0x%0h",
                 writes[0].addr, expected_addr);
        `FAIL_IF(1);
    end
`SVTEST_END

// ----------------------------------------------------------------------------
// TEST 08: Disable stops writes, all mem_en deassert
// ----------------------------------------------------------------------------
`SVTEST(test_disable_stops_writes)
    int writes_after = 0;

    enable_writer(32'd0);

    cb.tb_s_axis_tvalid <= 1'b1;
    cb.tb_s_axis_tdata  <= 16'h1234;
    repeat(3) @(cb);
    cb.tb_s_axis_tvalid <= 1'b0;

    disable_writer();

    repeat(10) @(cb) begin
        if (tb_mem_we) writes_after++;
    end

    `FAIL_IF(writes_after > 0);
    `FAIL_IF(tb_mem_en !== '0);
`SVTEST_END
