// ============================================================================
// File: bram_to_axis_nt.sv
// Source: mr_buffer/data_reader.vhd
// Description: BRAM reader to AXI4-Stream for NT-channel memories.
//   Reads ALL channels from ALL BRAM addresses (full depth) and outputs
//   sequential data on AXI4-Stream. "NT" = No Top/No Length register
//   (only start_reg, no addr_reg or len_reg).
//
//   The reader walks through:
//     1. All addresses: 0 to 2**N-1
//     2. All channels: 0 to NT-1 for each address
//
//   Total words output = 2**N * NT
//   tlast is asserted on the very last word (last channel of last address)
//
// FSM States:
//   INIT_ST        → Wait for start_reg
//   READ_ST        → Read BRAM data at current address
//   WRITE_ST       → Write current channel to FIFO, advance channel selector
//   READ_LAST_ST   → Read last BRAM address
//   WRITE_LAST_ST  → Write last channel to FIFO
//   FIFO_ST        → Drain FIFO to AXI Stream
//   END_ST         → Wait for start_reg to deassert
//
// Pipeline:
//   - mem_dout_r registers BRAM output (one cycle latency)
//   - Channel mux selects NT channel based on sel_cnt
//   - FIFO decouples BRAM read from AXI output
//
// Interfaces:
//   bram   : bram_if.master       — read port (addr only, we=0)
//   axis   : axi4_stream_if.master — output data stream (width = B)
//
// Parameters:
//   NT         : number of tables/channels (must be power of 2)
//   N          : address width per table (depth = 2**N per table)
//   B          : AXI data width in bits (output per channel)
//   BRAM_WIDTH : total BRAM read width (= NT * B)
//
// ============================================================================

`timescale 1ns/1ps

module bram_to_axis_nt #(
    parameter int NT = 8,           // Number of tables/channels (must be power of 2)
    parameter int N  = 8,           // Address width per table (depth = 2**N)
    parameter int B  = 16           // Data width per channel (AXI output width)
) (
    // Reset and clock
    input  logic             rstn,
    input  logic             clk,

    // BRAM Interface (read-only, wide input: NT*B bits)
    output logic             mem_en,
    output logic             mem_we,
    output logic [N-1:0]     mem_addr,
    input  logic [NT*B-1:0]  mem_dout,
    output logic [NT*B-1:0]  mem_din,      // Not used, tied to 0

    // AXI4-Stream Master Interface (output)
    input  logic             m_axis_tready,
    output logic [B-1:0]     m_axis_tdata,
    output logic             m_axis_tvalid,
    output logic             m_axis_tlast,

    // Control register (only start_reg, no addr_reg or len_reg)
    input  logic             start_reg
);

    // ---------------------------------------------------------------------
    // Local parameters
    // ---------------------------------------------------------------------
    localparam int NT_LOG2 = $clog2(NT);
    localparam int DEPTH = 2 ** N;           // Memory depth per table

    // ---------------------------------------------------------------------
    // FSM State Encoding
    // ---------------------------------------------------------------------
    typedef enum logic [2:0] {
        INIT_ST,
        READ_ST,
        WRITE_ST,
        READ_LAST_ST,
        WRITE_LAST_ST,
        FIFO_ST,
        END_ST
    } state_t;

    state_t current_state, next_state;

    // ---------------------------------------------------------------------
    // Internal Signals
    // ---------------------------------------------------------------------
    logic init_state;
    logic read_state;
    logic write_state;
    logic fifo_state;
    logic stream_en;                    // Enable AXI streaming

    // Counters
    logic [N-1:0]       addr_cnt;       // Address counter (0 to DEPTH-1)
    logic [NT_LOG2-1:0] sel_cnt;        // Channel selector (0 to NT-1)
    logic [NT_LOG2-1:0] rd_cnt;         // Read counter for dlast generation

    // Registered memory output (pipeline stage)
    logic [NT*B-1:0]    mem_dout_r;

    // FIFO signals
    logic               fifo_wr_en;
    logic               fifo_rd_en;
    logic [B-1:0]       fifo_din;
    logic [B-1:0]       fifo_dout;
    logic               fifo_full;
    logic               fifo_empty;

    // AXI handshake
    logic axis_handshake;

    // dlast internal
    logic dlast_i;

    // ---------------------------------------------------------------------
    // FIFO Instantiation
    // ---------------------------------------------------------------------
    fifo_sync #(
        .B (B),
        .N (16),                        // FIFO depth
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
    assign fifo_wr_en = write_state && !fifo_full;

    // FIFO read: AXI handshake
    assign axis_handshake = m_axis_tvalid && m_axis_tready;
    assign fifo_rd_en = axis_handshake && stream_en;

    // BRAM interface: always enabled for reading
    assign mem_en = 1'b1;
    assign mem_we = 1'b0;
    assign mem_addr = addr_cnt;
    assign mem_din = '0;                // Not used in read mode

    // Multiplexer for FIFO input (select channel based on sel_cnt)
    always_comb begin
        fifo_din = '0;
        for (int i = 0; i < NT; i++) begin
            if (sel_cnt == i) begin
                fifo_din = mem_dout_r[(i+1)*B-1 -: B];
            end
        end
    end

    // dlast generation: asserted when reading the last channel
    assign dlast_i = (rd_cnt == NT-1) && fifo_state;

    // AXI4-Stream output
    assign m_axis_tdata = fifo_dout;
    assign m_axis_tvalid = stream_en && !fifo_empty;
    assign m_axis_tlast = dlast_i;

    // ---------------------------------------------------------------------
    // Sequential Logic
    // ---------------------------------------------------------------------
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            current_state <= INIT_ST;
            addr_cnt      <= '0;
            sel_cnt       <= '0;
            rd_cnt        <= '0;
            mem_dout_r    <= '0;
        end else begin
            current_state <= next_state;

            // INIT state: clear counters
            if (init_state) begin
                mem_dout_r <= '0;
                addr_cnt   <= '0;
                sel_cnt    <= '0;
            end
            // READ state: latch BRAM data and increment address
            else if (read_state) begin
                mem_dout_r <= mem_dout;
                addr_cnt   <= addr_cnt + 1;
            end
            // WRITE state: increment channel selector
            else if (write_state && !fifo_full) begin
                sel_cnt <= sel_cnt + 1;
            end

            // Read counter for dlast generation
            if (init_state) begin
                rd_cnt <= '0;
            end else if (axis_handshake && stream_en) begin
                rd_cnt <= rd_cnt + 1;
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
                    next_state = READ_ST;
            end

            READ_ST: begin
                next_state = WRITE_ST;
            end

            WRITE_ST: begin
                if (sel_cnt < NT-1 || fifo_full)
                    next_state = WRITE_ST;
                else if (addr_cnt < DEPTH-1)
                    next_state = READ_ST;
                else
                    next_state = READ_LAST_ST;
            end

            READ_LAST_ST: begin
                next_state = WRITE_LAST_ST;
            end

            WRITE_LAST_ST: begin
                if (sel_cnt < NT-1 || fifo_full)
                    next_state = WRITE_LAST_ST;
                else
                    next_state = FIFO_ST;
            end

            FIFO_ST: begin
                if (!fifo_empty)
                    next_state = FIFO_ST;
                else
                    next_state = END_ST;
            end

            END_ST: begin
                if (start_reg)
                    next_state = END_ST;
                else
                    next_state = INIT_ST;
            end

            default: next_state = INIT_ST;
        endcase
    end

    // ---------------------------------------------------------------------
    // Output Logic
    // ---------------------------------------------------------------------
    always_comb begin
        init_state  = 1'b0;
        read_state  = 1'b0;
        write_state = 1'b0;
        fifo_state  = 1'b0;
        stream_en   = 1'b0;

        case (current_state)
            INIT_ST: begin
                init_state = 1'b1;
            end

            READ_ST: begin
                read_state = 1'b1;
                stream_en  = 1'b1;
            end

            WRITE_ST: begin
                write_state = 1'b1;
                stream_en   = 1'b1;
            end

            READ_LAST_ST: begin
                read_state = 1'b1;
                stream_en  = 1'b1;
            end

            WRITE_LAST_ST: begin
                write_state = 1'b1;
                stream_en   = 1'b1;
            end

            FIFO_ST: begin
                fifo_state = 1'b1;
                stream_en  = 1'b1;
            end

            END_ST: begin
                // No outputs asserted
            end

            default: begin
                init_state  = 1'b0;
                read_state  = 1'b0;
                write_state = 1'b0;
                fifo_state  = 1'b0;
                stream_en   = 1'b0;
            end
        endcase
    end

endmodule
