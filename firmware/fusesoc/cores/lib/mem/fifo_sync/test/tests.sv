// =========================================================
// test00_reset
// =========================================================
`SVTEST(test00_reset)
  `ASSERT_IMMEDIATE(empty == 1);
`SVTEST_END

// =========================================================
// test01_fill_drain
// =========================================================
// =========================================================
// test01_fill_drain (Draining block correction)
// =========================================================
`SVTEST(test01_fill_drain)
  logic [B-1:0] exp;
  int           words_written;

  words_written = 0;
  model_q       = {};
  wr_en         = 0;
  rd_en         = 0;

  // Fill the FIFO until 'full' is asserted
  forever begin
    @(negedge clk); // Sample/drive on negedge to stay clear of the active clock edge
    if (full) begin
      wr_en = 0;
      break;
    end
    wr_en = 1;
    din   = $urandom;
    model_q.push_back(din);
    words_written++;
  end

  @(posedge clk);
  wr_en = 0;

  $display("Effective FIFO depth = %0d words", words_written);
  `ASSERT_IMMEDIATE(full == 1);

  // Drain — FWFT: current data is already waiting at 'dout'
  for (int i = 0; i < words_written; i++) begin
    exp = model_q.pop_front();
    
    @(negedge clk); // Wait for a stable negative edge before sampling dout
    `FAIL_UNLESS_EQUAL(dout, exp); // Check currently exposed data safely
    
    rd_en = 1;      // Tell FIFO to advance to the next word on the upcoming posedge
    @(posedge clk);
    rd_en = 0;      // Lower rd_en immediately after the edge
  end

  repeat(4) @(posedge clk);
  `ASSERT_IMMEDIATE(empty == 1);
  `ASSERT_IMMEDIATE(model_q.size() == 0);
`SVTEST_END

// =========================================================
// test02_random
// =========================================================
`SVTEST(test02_random)
  wr_en   = 0;
  rd_en   = 0;
  model_q = {};

  repeat (200) begin
    @(negedge clk); // Evaluate and drive safely on negedge

    // FWFT Rule: If FIFO is not empty, 'dout' must match the oldest item in the model
    if (!empty && model_q.size() > 0) begin
      `FAIL_UNLESS_EQUAL(dout, model_q[0]);
    end

    // Write Path Randomization
    if (!full && $urandom_range(0,1)) begin
      wr_en = 1;
      din   = $urandom;
      model_q.push_back(din);
    end else begin
      wr_en = 0;
    end

    // Read Path Randomization
    if (!empty && $urandom_range(0,1)) begin
      rd_en = 1;
      void'(model_q.pop_front());
    end else begin
      rd_en = 0;
    end
  end

  @(negedge clk);
  wr_en = 0;
  rd_en = 0;
  @(posedge clk);
`SVTEST_END