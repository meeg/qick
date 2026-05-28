// ============================================================================
// File: tests.sv
// Description: Test cases handling Standard Mode latency with timeout guards.
// ============================================================================

// =========================================================
// test00_reset
// =========================================================
`SVTEST(test00_reset)
  repeat(10) @(posedge rd_clk);
  `ASSERT_IMMEDIATE(empty == 1'b1);
  `ASSERT_IMMEDIATE(full == 1'b0);
`SVTEST_END

// =========================================================
// test01_basic_flow
// =========================================================
`SVTEST(test01_basic_flow)
  logic [B-1:0] exp;
  int           words_written;
  logic [B-1:0] rand_data;
  int           timeout_cnt;

  words_written = 0;
  model_q       = {};
  wr_en         = 0;
  rd_en         = 0;

  repeat(10) @(posedge wr_clk);

  // 1. Write Burst Phase
  while (words_written < 50) begin
    @(posedge wr_clk);
    if (!full && !dut.wr_rst_busy) begin
      rand_data = $urandom;
      wr_en    <= 1'b1;
      din      <= rand_data;
      model_q.push_back(rand_data);
      words_written++;
    end else begin
      wr_en    <= 1'b0;
    end
  end

  @(posedge wr_clk);
  wr_en <= 1'b0;
  
  $display("[TEST] Successfully wrote %0d words into FIFO.", words_written);

  // 2. Timeout-guarded CDC Flag Synchronization Wait
  timeout_cnt = 0;
  while (empty === 1'b1) begin
    @(posedge rd_clk);
    timeout_cnt++;
    if (timeout_cnt > 100) begin
      `FAIL_IF_EQUAL(empty, 1'b1);
    end
  end
  repeat(5) @(posedge rd_clk);

  // 3. Read Burst Phase (Standard Latency Validation)
  for (int i = 0; i < words_written; i++) begin
    
    timeout_cnt = 0;
    while (empty === 1'b1) begin
      @(posedge rd_clk);
      timeout_cnt++;
      if (timeout_cnt > 50) begin
        `FAIL_IF_EQUAL(empty, 1'b1);
      end
    end
    
    rd_en <= 1'b1;
    @(posedge rd_clk); // Cycle N: Latches rd_en
    rd_en <= 1'b0;
    
    @(posedge rd_clk); // Cycle N+1: Data appears on dout
    
    exp = model_q.pop_front();
    `FAIL_UNLESS_EQUAL(dout, exp);
  end

  repeat(10) @(posedge rd_clk);
  `ASSERT_IMMEDIATE(empty == 1'b1);
`SVTEST_END

// =========================================================
// test02_random_stress
// =========================================================
// ============================================================================
// File: tests.sv (Updated test02_random_stress with race-condition guard)
// Description: Concurrent random stress test with strict clock-edge separation.
// ============================================================================

// ============================================================================
// File: tests.sv (Ultra-stable test02_random_stress)
// Description: Concurrent random stress test guarded against simulator
//              event scheduling shifts caused by VCD dumping activity.
// ============================================================================

`SVTEST(test02_random_stress)
  model_q = {};
  wr_en   = 0;
  rd_en   = 0;
  din     = 0;

  fork
    // --- PRODUCER THREAD (Write Domain) ---
    begin
      logic [B-1:0] dynamic_rand_data;
      repeat (400) begin
        @(posedge wr_clk);
        if (!full && !dut.wr_rst_busy && $urandom_range(0,1)) begin
          dynamic_rand_data = $urandom;
          wr_en            <= 1'b1;
          din              <= dynamic_rand_data;
          model_q.push_back(dynamic_rand_data);
        end else begin
          wr_en            <= 1'b0;
        end
      end
      @(posedge wr_clk);
      wr_en <= 1'b0;
    end

    // --- CONSUMER THREAD (Read Domain) ---
    begin
      logic [B-1:0] exp_data;
      bit           rd_requested_q1 = 0;
      bit           rd_requested_q2 = 0;

      repeat (600) begin
        // Force the evaluation loop to step EXACTLY onto the edge
        @(posedge rd_clk);
        
        // 1. Process data from a previously confirmed valid read command execution
        if (rd_requested_q1) begin
          if (model_q.size() > 0) begin
            exp_data = model_q.pop_front();
            `FAIL_UNLESS_EQUAL(dout, exp_data);
          end else begin
            $display("[ERROR] Scoreboard Error: Model queue underflow detected on read sync!");
            `FAIL_IF(1);
          end
        end

        // Advancing pipeline stage variables safely
        rd_requested_q1 = rd_requested_q2;
        rd_requested_q2 = 0;

        // 2. Drive the command interface safely using Non-Blocking Assignments (NBA)
        // We use a small #1ps delay check or rely on settled states to prevent edge races
        #1ps; 
        if (!empty && !dut.rd_rst_busy && (model_q.size() > 0) && $urandom_range(0,1)) begin
          rd_en           <= 1'b1;
          rd_requested_q2  = 1;
        end else begin
          rd_en           <= 1'b0;
        end
      end
      
      @(posedge rd_clk);
      rd_en <= 1'b0;
    end
  join

  // Cool-down cycle period to clear residual synchronization steps
  repeat(40) @(posedge rd_clk);
`SVTEST_END