///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : bram_to_axis_nt
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    bram_to_axis_nt.sv
//!
//! @brief   BRAM reader to AXI4-Stream for NT-channel memories.
//!
//! @details
//!
//! Reads ALL channels from ALL BRAM addresses (full depth) and outputs
//! sequential data on AXI4-Stream. "NT" = No Top/No Length register
//! (only start_reg, no addr_reg or len_reg).
//!
//! The reader walks through:
//! 1. All addresses: 0 to 2**N-1
//! 2. All channels: 0 to NT-1 for each address
//!
//! Total words output = 2**N * NT
//! tlast is packed into the FIFO along with the data to guarantee
//! perfect synchronization and immunity to FIFO propagation latencies.
//!
//! FSM States:
//! INIT_ST        → Wait for start_reg
//! READ_ST        → Read BRAM data at current address
//! WRITE_ST       → Write current channel to FIFO, advance channel selector
//! READ_LAST_ST   → Read last BRAM address
//! WRITE_LAST_ST  → Write last channel to FIFO
//! FIFO_ST        → Drain FIFO to AXI Stream
//! END_ST         → Wait for start_reg to deassert
//!
//! Pipeline:
//!
//! - mem_dout_r registers BRAM output (one cycle latency)
//! - Channel mux selects NT channel based on sel_cnt
//! - FIFO decouples BRAM read from AXI output
//!
//! Interfaces:
//! bram   : bram_if.master       — read port (addr only, we=0)
//! axis   : axi4_stream_if.master — output data stream (width = B)
//!
//! @note    Ported from mr_buffer/data_reader.vhd
//!
//! @author  QICK Development Team
//!
//! @version 1.0

`timescale 1ns/1ps

module bram_to_axis_nt #(
    //! number of tables/channels (must be power of 2)
    parameter int NT = 8,           // Number of tables/channels (must be power of 2)
    //! address width per table (depth = 2**N)
    parameter int N  = 8,           // Address width per table (depth = 2**N)
    //! AXI data width in bits (output per channel)
    parameter int B  = 16           // Data width per channel (AXI output width)
) (
    // Reset and clock
    input  logic              rstn,
    input  logic              clk,

    // BRAM Interface (read-only, wide input: NT*B bits)
    output logic              mem_en,
    output logic              mem_we,
    output logic [N-1:0]      mem_addr,
    input  logic [NT*B-1:0]  mem_dout,
    output logic [NT*B-1:0]  mem_din,      // Not used, tied to 0

    // AXI4-Stream Master Interface (output)
    input  logic              m_axis_tready,
    output logic [B-1:0]      m_axis_tdata,
    output logic              m_axis_tvalid,
    output logic              m_axis_tlast,

    // Control register (only start_reg, no addr_reg or len_reg)
    input  logic              start_reg
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
    logic [N-1:0]        addr_cnt;       // Address counter (0 to DEPTH-1)
    logic [NT_LOG2-1:0]  sel_cnt;        // Channel selector (0 to NT-1)

    // Registered memory output (pipeline stage)
    logic [NT*B-1:0]     mem_dout_r;

    // FIFO signals (Widened by 1 bit to accommodate tlast)
    logic                fifo_wr_en;
    logic                fifo_rd_en;
    logic [B:0]          fifo_din;       // Bit [B] = tlast, Bits [B-1:0] = data
    logic [B:0]          fifo_dout;      // Bit [B] = tlast, Bits [B-1:0] = data
    logic                fifo_full;
    logic                fifo_empty;

    // Multiplexer intermediate data and tlast tag
    logic [B-1:0]        mux_data;
    logic                fifo_tlast_bit;

    // AXI handshake
    logic axis_handshake;

    // ---------------------------------------------------------------------
    // FIFO Instantiation (Expanded Width: B + 1)
    // ---------------------------------------------------------------------
    fifo_sync #(
        .B (B + 1),                     // Data width + 1 bit for tlast
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

    // FIFO write: from BRAM when in write states and FIFO not full
    assign fifo_wr_en = write_state && !fifo_full;

    // FIFO read: AXI handshake
    assign axis_handshake = m_axis_tvalid && m_axis_tready;
    assign fifo_rd_en = axis_handshake && stream_en;

    // BRAM interface: always enabled for reading
    assign mem_en = 1'b1;
    assign mem_we = 1'b0;
    assign mem_addr = addr_cnt;
    assign mem_din = '0;                // Not used in read mode

    // Multiplexer for slicing current channel data to mux_data variable
    always_comb begin
        mux_data = '0;
        for (int i = 0; i < NT; i++) begin
            if (sel_cnt == i) begin
                mux_data = mem_dout_r[(i+1)*B-1 -: B];
            end
        end
    end

    // Identify the very last word of the entire block transfer
    assign fifo_tlast_bit = (current_state == WRITE_LAST_ST) && (sel_cnt == NT-1);

    // Pack both signals together into the FIFO input bus
    assign fifo_din = {fifo_tlast_bit, mux_data};

    // AXI4-Stream outputs (Unpacked directly from the FIFO output)
    assign m_axis_tdata  = fifo_dout[B-1:0];
    assign m_axis_tlast  = fifo_dout[B];
    assign m_axis_tvalid = stream_en && !fifo_empty;

    // ---------------------------------------------------------------------
    // Sequential Logic
    // ---------------------------------------------------------------------
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            current_state <= INIT_ST;
            addr_cnt      <= '0;
            sel_cnt       <= '0;
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
            // WRITE states: increment channel selector
            else if (write_state && !fifo_full) begin
                sel_cnt <= sel_cnt + 1;
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
    // Output Control Signal Logic
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

