// ============================================================================
// File: axis_to_bram_sg.sv
// Source: axis_sg_int4_v2/src/data_writer.vhd
// Description: AXI4-Stream to single BRAM writer with configurable start
//   address. Receives a continuous stream and writes it to memory starting
//   at start_addr_reg. capture_reg enables/disables writing and may come
//   from a different clock domain — synchronised internally with sync_nxm.
//
// FSM: INIT_ST → READ_START_ADDR_ST → WAIT_TVALID_ST → RW_TDATA_ST
//
//   INIT_ST            : wait for capture_reg=1
//   READ_START_ADDR_ST : latch start_addr_reg into address counter (1 cycle)
//   WAIT_TVALID_ST     : assert tready, wait for first valid beat
//   RW_TDATA_ST        : stream active — write on every valid beat,
//                        return to WAIT_TVALID_ST if tvalid drops,
//                        return to INIT_ST if capture_reg deasserts
//
// Pipeline: 3 register stages (d1/d2/d3, v1/v2/v3) align tdata and tvalid
//   with the FSM state transitions before presenting data to the BRAM.
//
// Interfaces:
//   axis : axi4_stream_if.slave  — incoming data stream
//   bram : bram_if.master        — write-only BRAM port
//
// Parameters:
//   N : BRAM address width (depth = 2**N)
//   B : data width in bits
// ============================================================================
`timescale 1ns/1ps

module axis_to_bram_sg #(
    parameter int N = 16,
    parameter int B = 16
) (
    input  logic             rstn,
    input  logic             clk,

    // AXI4-Stream slave — incoming data
    axi4_stream_if.slave     axis,

    // BRAM master — write only
    bram_if.master           bram,

    // Registers (start_addr_reg may be wide; capture_reg may be CDC)
    input  logic [31:0]      start_addr_reg,
    input  logic             capture_reg
);

    // -------------------------------------------------------------------------
    // CDC: synchronise capture_reg into clk domain
    // -------------------------------------------------------------------------
    logic capture_sync;

    sync_nxm #(
        .N (2),
        .M (1)
    ) capture_sync_i (
        .i_clk  (clk),
        .i_rstn (rstn),
        .i_d    (capture_reg),
        .o_d    (capture_sync)
    );

    // -------------------------------------------------------------------------
    // FSM state encoding
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        INIT_ST            = 2'd0,
        READ_START_ADDR_ST = 2'd1,
        WAIT_TVALID_ST     = 2'd2,
        RW_TDATA_ST        = 2'd3
    } state_t;

    state_t state;

    // -------------------------------------------------------------------------
    // FSM output decode
    // -------------------------------------------------------------------------
    logic read_start_addr_state;
    logic rw_tdata_state;
    logic tready_i;

    // -------------------------------------------------------------------------
    // AXI4-Stream pipeline registers (3 stages)
    // -------------------------------------------------------------------------
    logic             tready_r;
    logic [B-1:0]     d1, d2, d3;
    logic             v1, v2, v3;

    // -------------------------------------------------------------------------
    // Memory address
    // -------------------------------------------------------------------------
    logic [N-1:0] mem_addr_full;
    logic [N-1:0] mem_addr_full_r;

    // -------------------------------------------------------------------------
    // Datapath registers
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rstn) begin
            tready_r       <= '0;
            d1             <= '0;
            d2             <= '0;
            d3             <= '0;
            v1             <= '0;
            v2             <= '0;
            v3             <= '0;
            mem_addr_full  <= '0;
            mem_addr_full_r <= '0;
        end else begin
            // Stage 1: sample AXI inputs
            tready_r <= tready_i;
            d1       <= axis.tdata[B-1:0];
            v1       <= axis.tvalid;

            // Stage 2 & 3: pipeline to align with FSM latency
            d2 <= d1; d3 <= d2;
            v2 <= v1; v3 <= v2;

            // Address: latch start address or increment
            if (read_start_addr_state)
                mem_addr_full <= start_addr_reg[N-1:0];
            else if (rw_tdata_state && v2)
                mem_addr_full <= mem_addr_full + 1'b1;

            mem_addr_full_r <= mem_addr_full;
        end
    end

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rstn) begin
            state <= INIT_ST;
        end else begin
            unique case (state)
                INIT_ST:
                    if (capture_sync) state <= READ_START_ADDR_ST;

                READ_START_ADDR_ST:
                    state <= WAIT_TVALID_ST;

                WAIT_TVALID_ST:
                    if (!capture_sync)
                        state <= INIT_ST;
                    else if (v1)
                        state <= RW_TDATA_ST;

                RW_TDATA_ST:
                    if (!capture_sync)
                        state <= INIT_ST;
                    else if (!v1)
                        state <= WAIT_TVALID_ST;

                default: state <= INIT_ST;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // FSM output decode (combinational)
    // -------------------------------------------------------------------------
    always_comb begin
        read_start_addr_state = 1'b0;
        rw_tdata_state        = 1'b0;
        tready_i              = 1'b0;

        unique case (state)
            INIT_ST:            ;
            READ_START_ADDR_ST: read_start_addr_state = 1'b1;
            WAIT_TVALID_ST:     tready_i              = 1'b1;
            RW_TDATA_ST: begin
                rw_tdata_state = 1'b1;
                tready_i       = 1'b1;
            end
            default: ;
        endcase
    end

    // -------------------------------------------------------------------------
    // BRAM interface output assignments
    // -------------------------------------------------------------------------
    assign axis.tready = tready_r;
    assign bram.en     = 1'b1;
    assign bram.we     = v3;
    assign bram.addr   = mem_addr_full_r;
    assign bram.din    = d3;

endmodule
