// ============================================================================
// File: axis_to_bram_trig.sv
// Source: mr_buffer_et/src/data_writer.vhd
// Description: Triggered AXI4-Stream to BRAM capture block. Waits for an
//   external hardware trigger, then captures exactly 2**N samples from the
//   AXI4-Stream input into memory starting at address 0. Uses an internal
//   FIFO to decouple the stream from memory timing.
//
// FSM: INIT_ST → TRIGGER_ST → CAPTURE_ST → END_ST
//
//   INIT_ST    : wait for capture_reg=1
//   TRIGGER_ST : wait for trigger pulse
//   CAPTURE_ST : capture 2**N samples via FIFO into BRAM
//   END_ST     : wait for capture_reg=0 and FIFO to drain before returning
//
// Interfaces:
//   axis  : axi4_stream_if.slave  — incoming data stream
//   bram  : bram_if.master        — write-only BRAM port (en=1, we gated)
//
// Parameters:
//   N : BRAM address width (capture depth = 2**N samples)
//   B : data width in bits (must match bram_if.NB_DATA and axis N_BYTES*8)
// ============================================================================
`timescale 1ns/1ps

module axis_to_bram_trig #(
    parameter int N = 8,
    parameter int B = 16
) (
    input  logic              rstn,
    input  logic              clk,

    // Hardware trigger
    input  logic              trigger,

    // AXI4-Stream slave — incoming data
    axi4_stream_if.slave      axis,

    // BRAM master — write only
    bram_if.master            bram,

    // Software control register
    input  logic              capture_reg
);

    // -------------------------------------------------------------------------
    // FSM state encoding
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        INIT_ST    = 2'd0,
        TRIGGER_ST = 2'd1,
        CAPTURE_ST = 2'd2,
        END_ST     = 2'd3
    } state_t;

    state_t current_state, next_state;

    // -------------------------------------------------------------------------
    // FSM output
    // -------------------------------------------------------------------------
    logic write_en;

    // -------------------------------------------------------------------------
    // Internal FIFO signals
    // -------------------------------------------------------------------------
    logic         fifo_wr_en;
    logic         fifo_rd_en;
    logic [B-1:0] fifo_dout;
    logic         fifo_full;
    logic         fifo_empty;

    // -------------------------------------------------------------------------
    // Address counter and registered memory outputs
    // -------------------------------------------------------------------------
    logic [N-1:0] addr_cnt;
    logic         mem_we_r;
    logic [N-1:0] mem_addr_r;
    logic [B-1:0] mem_di_r;

    // -------------------------------------------------------------------------
    // Internal FIFO (depth=16, FWFT mode)
    // -------------------------------------------------------------------------
    fifo_sync #(
        .B (B),
        .N (16)
    ) fifo_i (
        .rstn  (rstn),
        .clk   (clk),
        .wr_en (fifo_wr_en),
        .din   (axis.tdata[B-1:0]),
        .rd_en (fifo_rd_en),
        .dout  (fifo_dout),
        .full  (fifo_full),
        .empty (fifo_empty)
    );

    // -------------------------------------------------------------------------
    // FIFO control
    // -------------------------------------------------------------------------
    // Write to FIFO only when capturing and stream is valid
    assign fifo_wr_en = write_en & axis.tvalid;

    // Read FIFO during capture (write to BRAM) or end (drain leftovers)
    assign fifo_rd_en = (current_state == CAPTURE_ST ||
                         current_state == END_ST) && ~fifo_empty;

    // -------------------------------------------------------------------------
    // AXI4-Stream backpressure
    // -------------------------------------------------------------------------
    assign axis.tready = write_en & ~fifo_full;

    // -------------------------------------------------------------------------
    // Sequential: FSM + address counter + memory pipeline
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rstn) begin
            current_state <= INIT_ST;
            addr_cnt      <= '0;
            mem_we_r      <= '0;
            mem_addr_r    <= '0;
            mem_di_r      <= '0;
        end else begin
            current_state <= next_state;

            if (write_en) begin
                if (~fifo_empty) begin
                    // Capture pre-increment address and current FIFO output
                    mem_addr_r <= addr_cnt;
                    mem_we_r   <= 1'b1;
                    mem_di_r   <= fifo_dout;
                    addr_cnt   <= addr_cnt + 1'b1;
                end else begin
                    mem_we_r   <= 1'b0;
                end
            end else begin
                addr_cnt   <= '0;
                mem_we_r   <= 1'b0;
                mem_addr_r <= '0;
                mem_di_r   <= '0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Next-state logic (combinational)
    // -------------------------------------------------------------------------
    always_comb begin
        next_state = current_state;

        unique case (current_state)
            INIT_ST:
                if (capture_reg) next_state = TRIGGER_ST;

            TRIGGER_ST:
                if (trigger) next_state = CAPTURE_ST;

            CAPTURE_ST:
                // addr_cnt reaches all-ones after 2**N increments
                if ((addr_cnt == '1) && ~fifo_empty)
                    next_state = END_ST;

            END_ST:
                if (!capture_reg && fifo_empty) next_state = INIT_ST;

            default: next_state = INIT_ST;
        endcase
    end

    // -------------------------------------------------------------------------
    // FSM output decode (combinational)
    // -------------------------------------------------------------------------
    always_comb begin
        write_en = 1'b0;
        unique case (current_state)
            CAPTURE_ST: write_en = 1'b1;
            default:    write_en = 1'b0;
        endcase
    end

    // -------------------------------------------------------------------------
    // BRAM interface output assignments
    // -------------------------------------------------------------------------
    assign bram.en   = 1'b1;
    assign bram.we   = mem_we_r;
    assign bram.addr = mem_addr_r;
    assign bram.din  = mem_di_r;

endmodule
