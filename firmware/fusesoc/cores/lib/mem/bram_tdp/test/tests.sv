//-------------------------------------------------------------------------
// TEST 1: Write and Read basic in the same port (Port A)
//-------------------------------------------------------------------------
`SVTEST(basic_write_read_port_a)
  
  // Write a value in Port A
  port_a_if.write_data(10'h004, 32'hDEADBEEF);
  
  // Read the data from Port A
  port_a_if.read_data(10'h004, read_val);
  
  // Verify
  `FAIL_IF_LOG(read_val !== 32'hDEADBEEF, "The data read from Port A does not match the data written");

`SVTEST_END


//-------------------------------------------------------------------------
// TEST 2: True Dual-Port (Write in Port A, Read in Port B)
//-------------------------------------------------------------------------
`SVTEST(tdp_cross_port_communication)
  
  // Write a value using Port A
  port_a_if.write_data(10'h010, 32'hCAFEF00D);
  
  // Read the data from Port B
  port_b_if.read_data(10'h010, read_val);
  
  // Verify that the data crosses correctly
  `FAIL_IF_LOG(read_val !== 32'hCAFEF00D, "Failed to cross data from Port A to Port B");

`SVTEST_END


//-------------------------------------------------------------------------
// TEST 3: Verify Byte-Enable functionality (Modify only one byte)
//-------------------------------------------------------------------------
`SVTEST(byte_enable_partial_write)
  
  // 1. Write a complete word initially
  port_a_if.write_data(10'h020, 32'h11223344);

  // 2. Simulate a manual write only of the most significant byte (MSB)
  @(cb);
  port_a_if.en   <= 1'b1;
  port_a_if.we   <= 4'b1000;         // Solo activamos el bit de enable del byte 3
  port_a_if.addr <= 10'h020;
  port_a_if.din  <= 32'hAA000000;    // Queremos inyectar 'AA' en la parte alta
  @(cb);
  port_a_if.en   <= 1'b0;
  port_a_if.we   <= 4'b0000;

  // 3. Read and verify the combined result
  port_a_if.read_data(10'h020, read_val);
  
  // Wait only high byte change: AA (new) 22 33 44 (old)
  `FAIL_IF_LOG(read_val !== 32'hAA223344, $sformatf("Failed in the byte-enable logic: Expected 0xAA223344, got 0x%08X", read_val));

`SVTEST_END