//--------------------------------------------------------------------------
// test00: Reset / idle state
//   Output should remain predictable or low when clock enable is deasserted.
//--------------------------------------------------------------------------
`SVTEST(test00_idle_state)
    @(cb);
    `FAIL_IF_LOG($isunknown(cb.tb_doa), "Output should not be X/Z when idle");
`SVTEST_END

//--------------------------------------------------------------------------
// test01: Single write and read back
//   Write a value, then read it back from the same address.
//--------------------------------------------------------------------------
`SVTEST(test01_write_read)
    logic [NB_DATA-1:0] data_in;
    logic [NB_ADDR-1:0] addr;

    data_in = 32'hDEADBEEF;
    addr    = 4'd5;

    // Execute Write Cycle
    cb.tb_ena   <= 1'b1;
    cb.tb_wea   <= 1'b1;
    cb.tb_addra <= addr;
    cb.tb_dia   <= data_in;
    @(cb);

    // Transition to Read Cycle (Targeting same address)
    cb.tb_wea   <= 1'b0;
    @(cb); // Capture cycle to advance the synchronous read architecture
    @(cb); // Sample output point after 1-cycle BRAM latency

    `FAIL_UNLESS_LOG(cb.tb_doa == data_in,
        $sformatf("Write/read mismatch: wrote 0x%08h, read 0x%08h", data_in, cb.tb_doa));

    cb.tb_ena <= 1'b0;
`SVTEST_END

//--------------------------------------------------------------------------
// test02: Write-first (read-through) behavior
//   During a write cycle, o_doa should match the driven data on the next edge.
//--------------------------------------------------------------------------
`SVTEST(test02_write_through)
    logic [NB_DATA-1:0] data_in;
    logic [NB_ADDR-1:0] addr;

    data_in = 32'hCAFEBABE;
    addr    = 4'd3;

    // Execute Write Cycle
    cb.tb_ena   <= 1'b1;
    cb.tb_wea   <= 1'b1;
    cb.tb_addra <= addr;
    cb.tb_dia   <= data_in;
    @(cb);

    // Next cycle: verify write-first transparent mode data routing
    @(cb);
    `FAIL_UNLESS_LOG(cb.tb_doa == data_in,
        $sformatf("Write-through fail: expected 0x%08h, got 0x%08h", data_in, cb.tb_doa));

    cb.tb_ena <= 1'b0;
`SVTEST_END

//--------------------------------------------------------------------------
// test03: Multiple addresses independence
//   Write different values to distinct addresses, verify no cross-talk.
//--------------------------------------------------------------------------
`SVTEST(test03_address_independence)
    logic [NB_DATA-1:0] val_a, val_b;

    val_a = 32'hAAAAAAAA;
    val_b = 32'hBBBBBBBB;

    // Write val_a to addr 2
    cb.tb_ena   <= 1'b1;
    cb.tb_wea   <= 1'b1;
    cb.tb_addra <= 4'd2;
    cb.tb_dia   <= val_a;
    @(cb);

    // Write val_b to addr 7
    cb.tb_addra <= 4'd7;
    cb.tb_dia   <= val_b;
    @(cb);

    // Set up Read for addr 2
    cb.tb_wea   <= 1'b0;
    cb.tb_addra <= 4'd2;
    @(cb); // Address accepted
    @(cb); // Output ready
    `FAIL_UNLESS_LOG(cb.tb_doa == val_a,
        $sformatf("Addr 2: expected 0x%08h, got 0x%08h", val_a, cb.tb_doa));

    // Set up Read for addr 7
    cb.tb_addra <= 4'd7;
    @(cb); // Address accepted
    @(cb); // Output ready
    `FAIL_UNLESS_LOG(cb.tb_doa == val_b,
        $sformatf("Addr 7: expected 0x%08h, got 0x%08h", val_b, cb.tb_doa));

    cb.tb_ena <= 1'b0;
`SVTEST_END

//--------------------------------------------------------------------------
// test04: Enable gating
//   When ena=0, no writes or reads should alter internal states or outputs.
//--------------------------------------------------------------------------
`SVTEST(test04_enable_gating)
    logic [NB_DATA-1:0] old_value;

    // Write a baseline value
    cb.tb_ena   <= 1'b1;
    cb.tb_wea   <= 1'b1;
    cb.tb_addra <= 4'd0;
    cb.tb_dia   <= 32'h11111111;
    @(cb);

    // Read back baseline value
    cb.tb_wea   <= 1'b0;
    @(cb);
    @(cb);
    old_value = cb.tb_doa;

    // Attempt a write transaction while clock enable is dropped
    cb.tb_ena   <= 1'b0;
    cb.tb_wea   <= 1'b1;
    cb.tb_dia   <= 32'h22222222;
    @(cb);

    // Re-verify that original value was safe from corruption
    cb.tb_ena   <= 1'b1;
    cb.tb_wea   <= 1'b0;
    cb.tb_addra <= 4'd0;
    @(cb);
    @(cb);

    `FAIL_UNLESS_LOG(cb.tb_doa == old_value,
        $sformatf("Enable gating fail: write with ena=0 should be ignored"));

    cb.tb_ena <= 1'b0;
`SVTEST_END

//--------------------------------------------------------------------------
// test05: Overwrite
//   Writing a new value to the same address overwrites the old value.
//--------------------------------------------------------------------------
`SVTEST(test05_overwrite)
    logic [NB_DATA-1:0] first, second;

    first  = 32'h12345678;
    second = 32'h9ABCDEF0;

    // Write primary value
    cb.tb_ena   <= 1'b1;
    cb.tb_wea   <= 1'b1;
    cb.tb_addra <= 4'd10;
    cb.tb_dia   <= first;
    @(cb);

    // Overwrite with secondary value
    cb.tb_dia   <= second;
    @(cb);

    // Set up read verification
    cb.tb_wea   <= 1'b0;
    @(cb);
    @(cb);

    `FAIL_UNLESS_LOG(cb.tb_doa == second,
        $sformatf("Overwrite fail: expected 0x%08h, got 0x%08h", second, cb.tb_doa));

    cb.tb_ena <= 1'b0;
`SVTEST_END

//--------------------------------------------------------------------------
// test06: Read stability (ena=0)
//   When ena=0, o_doa must lock and hold its previous state.
//--------------------------------------------------------------------------
`SVTEST(test06_read_stability)
    logic [NB_DATA-1:0] read_val;

    // Perform a valid memory read cycle
    cb.tb_ena   <= 1'b1;
    cb.tb_wea   <= 1'b1;
    cb.tb_addra <= 4'd15;
    cb.tb_dia   <= 32'hFFFF0000;
    @(cb);

    cb.tb_wea   <= 1'b0;
    @(cb);
    @(cb);
    read_val = cb.tb_doa;

    // Deassert clock enable; output register latch check
    cb.tb_ena   <= 1'b0;
    @(cb);
    @(cb);

    `FAIL_UNLESS_LOG(cb.tb_doa == read_val,
        "Output should hold value when ena=0");
`SVTEST_END

//--------------------------------------------------------------------------
// test07: Binary file initialization
//   Verify that MEM_BIN_FILE correctly initializes the hardware BRAM structure.
//--------------------------------------------------------------------------
`SVTEST(test07_binary_init)
    // 1. Use an static unpacked array 
    logic [NB_DATA-1:0] expected_mem [0:DEPTH-1];

    // 2. Clean up the array to zero just in case the file has less than DEPTH lines
    for (int i = 0; i < DEPTH; i++) expected_mem[i] = '0;

    // 3. Use readmemb to process the binary instruction
    $readmemb(MEM_BIN_FILE, u_bram.ram);
    $readmemb(MEM_BIN_FILE, expected_mem); 

    cb.tb_ena   <= 1'b1;
    cb.tb_wea   <= 1'b0;

    for (int i = 0; i < DEPTH; i++) begin
        cb.tb_addra <= i[NB_ADDR-1:0];
        @(cb); // Address setup
        @(cb); // Data latch
        
        `FAIL_UNLESS_LOG(cb.tb_doa == expected_mem[i],
            $sformatf("Init mismatch at addr %0d: expected 0x%08h, got 0x%08h",
                i, expected_mem[i], cb.tb_doa));
    end

    cb.tb_ena <= 1'b0;
`SVTEST_END