// ============================================================================
// File: bram_to_axis.sv (formerly data_reader.sv)
// Description: Reads sequential data from BRAM and outputs AXI4-Stream.
// ============================================================================

module bram_to_axis #(
  parameter int BRAM_ADDR_WIDTH = 8,           // Address width (BRAM_ADDR_WIDTH)
  parameter int BRAM_DATA_WIDTH = 16           // Data width in bits (BRAM_DATA_WIDTH)
)(
  input logic                        rstn,
  input logic                        clk,

  // BRAM Interface (single-port reader)
  output logic                       mem_en,
  output logic                       mem_we,
  output logic [BRAM_ADDR_WIDTH-1:0] mem_addr,
  input  logic [BRAM_DATA_WIDTH-1:0] mem_dout,
  output logic [BRAM_DATA_WIDTH-1:0] mem_din,

  // AXI4-Stream Interface (source)
  input  logic                       m_axis_tready,
  output logic [BRAM_DATA_WIDTH-1:0] m_axis_tdata,
  output logic                       m_axis_tvalid,
  output logic                       m_axis_tlast,

  // Control registers
  input logic                        start_reg,
  input logic [BRAM_ADDR_WIDTH-1:0]  addr_reg,
  input logic [BRAM_ADDR_WIDTH:0]    len_reg     // Note: BRAM_ADDR_WIDTH+1 bits to support
                                                 // up to 2^BRAM_ADDR_WIDTH length
);

  // ---------------------------------------------------------------------
  // FSM State Encoding
  // ---------------------------------------------------------------------
  typedef enum logic [2:0] {
    INIT_ST       = 3'd0,
    REGS_ST       = 3'd1,
    READ_BRAM_ST  = 3'd2,
    WRITE_FIFO_ST = 3'd3,
    STREAM_ST     = 3'd4,      // renamed from FIFO_ST
    END_ST        = 3'd5
  } state_t;

  state_t current_state, next_state;

  // ---------------------------------------------------------------------
  // Internal Signals
  // ---------------------------------------------------------------------
  logic init_state;
  logic regs_state;
  logic read_state;
  logic write_state;
  logic stream_state;
  logic stream_en;                // renamed from read_en

  // Counters
  logic [BRAM_ADDR_WIDTH:0]   wr_cnt;             // words written to FIFO
  logic [BRAM_ADDR_WIDTH:0]   rd_cnt;             // words remaining to read (down counter)
  logic [BRAM_ADDR_WIDTH-1:0] bram_addr;
  logic [BRAM_ADDR_WIDTH:0]   len_r;

  // FIFO signals
  logic                       fifo_wr_en;
  logic                       fifo_rd_en;
  logic [BRAM_DATA_WIDTH-1:0] fifo_din;
  logic [BRAM_DATA_WIDTH-1:0] fifo_dout;
  logic                       fifo_full;
  logic                       fifo_empty;

  // AXI handshake
  logic axis_handshake;

  // ---------------------------------------------------------------------
  // FIFO Instantiation (same as before)
  // ---------------------------------------------------------------------
  fifo_sync #(
    .B (BRAM_DATA_WIDTH),
    .N (16),
    .USE_ADV_FEATURES ("1707"),
    .ENABLE_COUNTERS (1)
  ) fifo_i (
    .rstn  (rstn),
    .clk   (clk),
    .wr_en (fifo_wr_en),
    .din   (fifo_din),
    .rd_en (fifo_rd_en),
    .dout  (fifo_dout),
    .full  (fifo_full),
    .empty (fifo_empty)
  );

  // ---------------------------------------------------------------------
  // Combinational Assignments
  // ---------------------------------------------------------------------

  // FIFO write: from BRAM when in write state and FIFO not full
  assign fifo_wr_en  = write_state && !fifo_full;
  assign fifo_din    = mem_dout;

  // FIFO read: AXI handshake (tvalid & tready)
  assign axis_handshake = m_axis_tvalid && m_axis_tready;
  assign fifo_rd_en     = axis_handshake;

  // BRAM interface: always enabled for reading
  assign mem_en   = 1'b1;
  assign mem_we   = 1'b0;
  assign mem_addr = bram_addr;
  assign mem_din  = '0;  // not used in read mode

  // AXI4-Stream output
  assign m_axis_tdata  = fifo_dout;
  assign m_axis_tvalid = stream_en && !fifo_empty;
  assign m_axis_tlast  = (rd_cnt == 1);  // last when rd_cnt will become 0 after this read

  // Optional AXI signals - set to defaults
  //assign m_axis_tkeep  = '1;   // all bytes valid
  //assign m_axis_tstrb  = '1;   // all strobes active
  //assign m_axis_tid    = '0;
  //assign m_axis_tdest  = '0;
  //assign m_axis_tuser  = '0;

  // ---------------------------------------------------------------------
  // Sequential Logic
  // ---------------------------------------------------------------------
  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      current_state <= INIT_ST;
      wr_cnt        <= '0;
      rd_cnt        <= '0;
      bram_addr     <= '0;
      len_r         <= '0;
    end else begin
      current_state <= next_state;

      // INIT state: clear counters
      if (init_state) begin
        wr_cnt    <= '0;
        bram_addr <= '0;
        len_r     <= '0;
      end

      // REGS state: latch control registers
      else if (regs_state) begin
        wr_cnt    <= '0;
        bram_addr <= addr_reg;
        len_r     <= len_reg;
        rd_cnt    <= len_reg;
      end

      // READ state: count writes to FIFO
      if (read_state) begin
        wr_cnt <= wr_cnt + 1;
      end

      // AXI handshake: decrement remaining count
      if (axis_handshake && (rd_cnt > 0)) begin
        rd_cnt <= rd_cnt - 1;
      end

      // WRITE state: advance BRAM address
      if (write_state && !fifo_full) begin
        bram_addr <= bram_addr + 1;
      end
    end
  end

  // ---------------------------------------------------------------------
  // Next State Logic
  // ---------------------------------------------------------------------
  always_comb begin
    next_state = current_state;

    case (current_state)
      INIT_ST: begin
        if (start_reg)
          next_state = REGS_ST;
      end

      REGS_ST: begin
        if (len_reg == 0)
          next_state = END_ST;
        else
          next_state = READ_BRAM_ST;
      end

      READ_BRAM_ST: begin
        next_state = WRITE_FIFO_ST;
      end

      WRITE_FIFO_ST: begin
        if (fifo_full)
          next_state = WRITE_FIFO_ST;
        else if (wr_cnt < len_r)
          next_state = READ_BRAM_ST;
        else
          next_state = STREAM_ST;
      end

      STREAM_ST: begin
        // Stay until all data has been acknowledged
        if (axis_handshake && (rd_cnt == 1))  // last beat just completed
          next_state = END_ST;
        else
          next_state = STREAM_ST;
      end

      END_ST: begin
        if (!start_reg)
          next_state = INIT_ST;
      end

      default: next_state = INIT_ST;
    endcase
  end

  // ---------------------------------------------------------------------
  // Output Logic
  // ---------------------------------------------------------------------
  always_comb begin
    init_state   = 1'b0;
    regs_state   = 1'b0;
    read_state   = 1'b0;
    write_state  = 1'b0;
    stream_state = 1'b0;
    stream_en    = 1'b0;

    case (current_state)
      INIT_ST:       init_state   = 1'b1;
      REGS_ST:       regs_state   = 1'b1;
      READ_BRAM_ST: begin
        read_state = 1'b1;
        stream_en  = 1'b1;
      end
      WRITE_FIFO_ST: begin
        write_state = 1'b1;
        stream_en   = 1'b1;
      end
      STREAM_ST: begin
        stream_state = 1'b1;
        stream_en    = 1'b1;
      end
      default: ;
    endcase
  end

endmodule
