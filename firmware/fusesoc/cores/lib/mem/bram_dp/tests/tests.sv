//-------------------------------------------------------------------------------------------------//
// tests.sv  -  bram_dp dual-port BRAM
//
// Read latency = 1 clock: after presenting addr with en=1 at posedge N,
// the read data is valid on the output at posedge N+1.
// Read-before-write: writing and reading the same address in the same cycle
// returns the OLD contents on the data output.
//-------------------------------------------------------------------------------------------------//

// Write via port A, read back via port B
`SVTEST(test00_write_a_read_b)
  logic [B-1:0] wdata;
  wdata = 16'hBEEF;

  // Write on port A
  @(posedge tb_clk);
  ena   <= 1'b1;
  wea   <= 1'b1;
  addra <= 8'h10;
  dia   <= wdata;
  @(posedge tb_clk);
  wea   <= 1'b0;
  ena   <= 1'b0;

  // Read on port B (registered read, latency 1)
  @(posedge tb_clk);
  enb   <= 1'b1;
  web   <= 1'b0;
  addrb <= 8'h10;
  @(posedge tb_clk);      // read issued
  enb   <= 1'b0;
  @(negedge tb_clk);      // data settled on dob
  `FAIL_UNLESS_EQUAL(dob, wdata);
`SVTEST_END

//-------------------------------------------------------------------------------------------------//
// Write and read back on the SAME port (port A)
`SVTEST(test01_write_read_same_port)
  logic [B-1:0] wdata;
  wdata = 16'h1234;

  // Write
  @(posedge tb_clk);
  ena   <= 1'b1;
  wea   <= 1'b1;
  addra <= 8'h20;
  dia   <= wdata;
  @(posedge tb_clk);
  wea   <= 1'b0;

  // Read same address
  addra <= 8'h20;
  @(posedge tb_clk);      // read issued (latency 1)
  ena   <= 1'b0;
  @(negedge tb_clk);
  `FAIL_UNLESS_EQUAL(doa, wdata);
`SVTEST_END

//-------------------------------------------------------------------------------------------------//
// Fill several addresses and read them all back
`SVTEST(test02_multi_word)
  // Deterministic pattern: data at address i is (0xA000 + i). No model array needed.

  // ---------- WRITE PHASE (port A) ----------
  for (int i = 0; i < 16; i++) begin
    @(negedge tb_clk);
    ena   = 1'b1;
    wea   = 1'b1;
    addra = i[N-1:0];
    dia   = 16'hA000 + i[B-1:0];
    @(posedge tb_clk);   // write committed
  end
  @(negedge tb_clk);
  ena = 1'b0;
  wea = 1'b0;

  repeat(2) @(posedge tb_clk);   // settle

  // ---------- READ PHASE (port B) ----------
  enb = 1'b1;
  web = 1'b0;
  for (int i = 0; i < 16; i++) begin
    @(negedge tb_clk);
    addrb = i[N-1:0];
    @(posedge tb_clk);        // DUT registers ram[addrb] -> dob
    @(negedge tb_clk);        // dob settled
    if (dob !== (16'hA000 + i[B-1:0]))
      $display("[TEST02] i=%0d addr=0x%0h dob=0x%0h expected=0x%0h",
               i, i, dob, 16'hA000 + i[B-1:0]);
    `FAIL_UNLESS_EQUAL(dob, 16'hA000 + i[B-1:0]);
  end
  @(negedge tb_clk);
  enb = 1'b0;
`SVTEST_END

//-------------------------------------------------------------------------------------------------//
// Read-before-write behavior: same address, same cycle read returns OLD data
`SVTEST(test03_read_first)
  // Preload address 0x30 with 0x1111
  @(posedge tb_clk);
  ena <= 1'b1; wea <= 1'b1; addra <= 8'h30; dia <= 16'h1111;
  @(posedge tb_clk);

  // Now write 0x2222 to the same address and read it in the same cycle
  wea <= 1'b1; addra <= 8'h30; dia <= 16'h2222;
  @(posedge tb_clk);   // doa should capture the OLD value (0x1111)
  wea <= 1'b0; ena <= 1'b0;
  @(negedge tb_clk);
  `FAIL_UNLESS_EQUAL(doa, 16'h1111);   // read-before-write
`SVTEST_END

//-------------------------------------------------------------------------------------------------//
