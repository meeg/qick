// ============================================================================
// File: data_reader.sv
// Description: Translates memory read sequences into AXI Stream via a FIFO.
// ============================================================================

module data_reader #(
    // Address map of memory
    parameter int N = 8,
    // Data width
    parameter int B = 16
  ) (
    // Reset and clock
    input  logic         rstn,
    input  logic         clk,

    // Memory I/F
    output logic         mem_en,
    output logic         mem_we,
    output logic [N-1:0] mem_addr,
    input  logic [B-1:0] mem_dout,

    // Data out
    output logic [B-1:0] dout,
    input  logic         dready,
    output logic         dvalid,
    output logic         dlast,

    // Registers (Now in lowercase)
    input  logic         start_reg,
    input  logic [N-1:0] addr_reg,
    input  logic [N-1:0] len_reg
  );

  // -------------------------------------------------------------------------
  // FSM State Encoding
  // -------------------------------------------------------------------------
  typedef enum logic [2:0] {
            INIT_ST       = 3'd0,
            REGS_ST       = 3'd1,
            READ_BRAM_ST  = 3'd2,
            WRITE_FIFO_ST = 3'd3,
            FIFO_ST       = 3'd4,
            END_ST        = 3'd5
          } state_t;

  state_t current_state, next_state;

  // -------------------------------------------------------------------------
  // Internal Signals
  // -------------------------------------------------------------------------
  logic init_state;
  logic regs_state;
  logic read_state;
  logic write_state;
  logic fifo_state;
  logic read_en;

  // Counters and Registers
  logic [N-1:0] cnt_wr;
  logic [N-1:0] cnt_rd;
  logic [N-1:0] addr_cnt;
  logic [N-1:0] len_r;

  // FIFO signals
  logic         fifo_wr_en;
  logic         fifo_rd_en;
  logic [B-1:0] fifo_din;
  logic [B-1:0] fifo_dout;
  logic         fifo_full;
  logic         fifo_empty;

  // -------------------------------------------------------------------------
  // FIFO Instantiation
  // -------------------------------------------------------------------------
  fifo_sync #(
              .B (B),
              .N (16)  // Changed from 4 to 16 to comply with the XPM requirement
            ) fifo_i (
              .rstn  (rstn),
              .clk   (clk),

              // Write I/F
              .wr_en (fifo_wr_en),
              .din   (fifo_din),

              // Read I/F
              .rd_en (fifo_rd_en),
              .dout  (fifo_dout),

              // Flags
              .full  (fifo_full),
              .empty (fifo_empty)
            );

  // -------------------------------------------------------------------------
  // Combinational Assignments
  // -------------------------------------------------------------------------
  // FIFO write connections
  assign fifo_wr_en = write_state & ~fifo_full;
  assign fifo_din   = mem_dout;

  // FIFO read connections (the pop only occurs if there is a complete handshake)
  assign fifo_rd_en = dvalid & dready;

  // Memory I/F constant assignments
  assign mem_en     = 1'b1;
  assign mem_we     = 1'b0;
  assign mem_addr   = addr_cnt;

  // Output assignments (AXI Compliant: valid is NOT ready dependent)
  assign dout       = fifo_dout;
  assign dvalid     = read_en & ~fifo_empty;
  assign dlast      = (cnt_rd == '0) ? 1'b1 : 1'b0;


  // -------------------------------------------------------------------------
  // Sequential Logic (Registers and FSM State)
  // -------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rstn)
  begin
    if (!rstn)
    begin
      current_state <= INIT_ST;

      cnt_wr        <= '0;
      cnt_rd        <= '0;
      addr_cnt      <= '0;
      len_r         <= '0;
    end
    else
    begin
      // State Update
      current_state <= next_state;

      // Memory address and data logic
      if (init_state)
      begin
        cnt_wr   <= '0;
        addr_cnt <= '0;
        len_r    <= '0;
      end
      else if (regs_state)
      begin
        cnt_wr   <= '0;
        addr_cnt <= addr_reg;
        len_r    <= len_reg;
        cnt_rd   <= len_reg - 1;
      end

      if (read_state)
      begin
        cnt_wr <= cnt_wr + 1;
      end

      if (fifo_rd_en && (addr_cnt > 0)) // Only decrement if there are more reads to be done
      begin
        cnt_rd <= cnt_rd - 1;
      end

      if (write_state && !fifo_full)
      begin
        addr_cnt <= addr_cnt + 1;
      end
    end
  end

  // -------------------------------------------------------------------------
  // Next State Logic (Combinational)
  // -------------------------------------------------------------------------
  always_comb
  begin
    // Default assignment to prevent latches
    next_state = current_state;

    case (current_state)
      INIT_ST:
      begin
        if (!start_reg)
          next_state = INIT_ST;
        else
          next_state = REGS_ST;
      end

      REGS_ST:
      begin
        if (len_reg == 0)
          next_state = END_ST; // Direct jump if there is nothing to read
        else
          next_state = READ_BRAM_ST;
      end

      READ_BRAM_ST:
      begin
        next_state = WRITE_FIFO_ST;
      end

      WRITE_FIFO_ST:
      begin
        if (fifo_full)
          next_state = WRITE_FIFO_ST;
        else if (cnt_wr < len_r)
          next_state = READ_BRAM_ST;
        else
          next_state = FIFO_ST;
      end

      FIFO_ST:
      begin
        // We just go out of this state if the last data has been accepted
        if (dvalid && dready)
        begin
          if (cnt_rd == 0)
            next_state = END_ST;
          else
            next_state = FIFO_ST;
        end
        else
        begin
          next_state = FIFO_ST; // Keep state until dready is 1
        end
      end

      END_ST:
      begin
        if (start_reg)
          next_state = END_ST;
        else
          next_state = INIT_ST;
      end

      default:
      begin
        next_state = INIT_ST;
      end
    endcase
  end

  // -------------------------------------------------------------------------
  // FSM Output Logic (Combinational)
  // -------------------------------------------------------------------------
  always_comb
  begin
    // Default assignments to prevent latches
    init_state  = 1'b0;
    regs_state  = 1'b0;
    read_state  = 1'b0;
    write_state = 1'b0;
    fifo_state  = 1'b0;
    read_en     = 1'b0;

    case (current_state)
      INIT_ST:
      begin
        init_state  = 1'b1;
      end

      REGS_ST:
      begin
        regs_state  = 1'b1;
      end

      READ_BRAM_ST:
      begin
        read_state  = 1'b1;
        read_en     = 1'b1;
      end

      WRITE_FIFO_ST:
      begin
        write_state = 1'b1;
        read_en     = 1'b1;
      end

      FIFO_ST:
      begin
        fifo_state  = 1'b1;
        read_en     = 1'b1;
      end

      END_ST:
      begin
        // No specific combinatorial flags asserted here
      end

      default:
        ;
    endcase
  end

endmodule
