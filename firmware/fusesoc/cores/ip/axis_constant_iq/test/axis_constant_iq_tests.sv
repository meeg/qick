// ============================================================================
// File: axis_constant_iq_tests.sv
// Description: SVUnit test cases for axis_constant_iq.
// ============================================================================

`SVTEST(reset_initialization)
    logic [AXI_DW-1:0] read_data;

    // Verify that after reset the tvalid is low
    `FAIL_UNLESS_EQUAL(axis_if.tvalid, 1'b0); 

    // Verify that all internal registers initialize to 0
    for (int i = 0; i < NUM_REGS; i++) begin
        s_axi.axi_read(.addr(i * 4), .data(read_data));
        `FAIL_IF(read_data !== 32'h0);
    end
`SVTEST_END


`SVTEST(successful_data_update_flow)
    logic [15:0] test_real = 16'h1234;
    logic [15:0] test_imag = 16'hABCD;

    // 1. Write values to the data registers
    s_axi.axi_write(.addr(32'h00), .data(test_real));
    s_axi.axi_write(.addr(32'h04), .data(test_imag));

    // Force a small delay in the AXI clock
    repeat(2) @(tb_cb);

    // Check that m_axis.tdata has not changed yet (missing the WE edge)
    `FAIL_UNLESS_EQUAL(axis_if.tdata, '0);

    // 2. Write 1 to the WE register to generate the rising edge
    s_axi.axi_write(.addr(32'h08), .data(32'h0001));

    // 3. Wait for the signal to pass through the 2-stage synchronizer in the AXIS domain
    repeat(10) @(posedge tb_axis_clk);

    // 4. Verify that all N parallel outputs reflect the correct data       
    for (int i = 0; i < NUM_CHANNELS; i++) begin
        // Verify real part
        `FAIL_UNLESS_EQUAL(axis_if.tdata[IQ_WIDTH + 2*IQ_WIDTH*i - 1 : 2*IQ_WIDTH*i], test_real);
        // Verify imaginary part
        `FAIL_UNLESS_EQUAL(axis_if.tdata[2*IQ_WIDTH + 2*IQ_WIDTH*i - 1 : 2*IQ_WIDTH*i + IQ_WIDTH], test_imag);
    end
`SVTEST_END


`SVTEST(no_update_without_we_edge)
    // 1. Load initial valid data
    s_axi.axi_write(.addr(32'h00), .data(32'h1111));
    s_axi.axi_write(.addr(32'h04), .data(32'h2222));
    s_axi.axi_write(.addr(32'h08), .data(32'h0001)); // WE = 1
    repeat(10) @(posedge tb_axis_clk);
    
    // Verify that the first data is registered
    `FAIL_UNLESS_EQUAL(axis_if.tdata[15:0], 16'h1111);

    // 2. Change the I/Q registers but keep the WE register at '1'
    s_axi.axi_write(.addr(32'h00), .data(32'h7777));
    s_axi.axi_write(.addr(32'h04), .data(32'h8888));
    
    repeat(10) @(posedge tb_axis_clk);

    // As there was no new rising edge on WE, the output data MUST NOT change
    `FAIL_UNLESS_EQUAL(axis_if.tdata[15:0], 16'h1111);
    `FAIL_IF_EQUAL(axis_if.tdata[15:0], 16'h7777);
`SVTEST_END


`SVTEST(we_edge_detection_clear_and_trigger)
    // 1. First shot (we write data and activate WE)
    s_axi.axi_write(.addr(32'h00), .data(32'hAAAA));
    s_axi.axi_write(.addr(32'h04), .data(32'hBBBB));
    s_axi.axi_write(.addr(32'h08), .data(32'h0001)); // WE = 1
    repeat(10) @(posedge tb_axis_clk);
    `FAIL_UNLESS_EQUAL(axis_if.tdata[15:0], 16'hAAAA);

    // 2. Modify the I/Q registers
    s_axi.axi_write(.addr(32'h00), .data(32'hCCCC));
    s_axi.axi_write(.addr(32'h04), .data(32'hDDDD));

    // 3. Clear the WE register (pull it down to 0) to allow a next edge
    s_axi.axi_write(.addr(32'h08), .data(32'h0000)); // WE = 0
    repeat(10) @(posedge tb_axis_clk); // Wait for the '0' to be synchronized

    // The output must still retain the old value (0xAAAA)
    `FAIL_UNLESS_EQUAL(axis_if.tdata[15:0], 16'hAAAA);

    // 4. Reactivate the WE register (Generates a new rising edge)
    s_axi.axi_write(.addr(32'h08), .data(32'h0001)); // WE = 1
    repeat(10) @(posedge tb_axis_clk);

    // Now the output should be updated to the new value (0xCCCC)
    `FAIL_UNLESS_EQUAL(axis_if.tdata[15:0], 16'hCCCC);
`SVTEST_END
