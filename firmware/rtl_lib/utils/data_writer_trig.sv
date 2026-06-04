// ============================================================================
// File: data_writer_trig.sv
// Source: mr_buffer_et/src/data_writer.vhd
// Description: Triggered AXI Stream to BRAM capture block. Waits for an
//   external hardware trigger, then captures exactly 2**N samples from the
//   AXI Stream input into memory, starting at address 0. Uses an internal
//   FIFO to decouple the stream from memory timing.
//
// FSM: INIT_ST → TRIGGER_ST → CAPTURE_ST → END_ST
//
//   INIT_ST    : wait for CAPTURE_REG=1
//   TRIGGER_ST : wait for trigger pulse
//   CAPTURE_ST : capture 2**N samples via FIFO into BRAM
//   END_ST     : wait for CAPTURE_REG=0 and FIFO to drain before returning
//
// Key differences vs data_writer_sg / data_writer_sg_nt:
//   - Hardware trigger input instead of WE_REG
//   - Fixed capture length: always 2**N samples
//   - Address always starts at 0 (no START_ADDR_REG)
//   - Internal FIFO buffers incoming stream data
//   - s_axis_tready gated by write_en and FIFO not full
//
// Parameters:
//   N  : memory address width (capture depth = 2**N samples)
//   B  : data width in bits
// ============================================================================
`timescale 1ns/1ps

module data_writer_trig #(
    parameter int N = 8,
    parameter int B = 16
  ) (
    input  logic         rstn,
    input  logic         clk,

    // Hardware trigger
    input  logic         trigger,

    // AXI Stream input
    output logic         s_axis_tready,
    input  logic [B-1:0] s_axis_tdata,
    input  logic         s_axis_tvalid,

    // Memory interface
    output logic         mem_en,
    output logic         mem_we,
    output logic [N-1:0] mem_addr,
    output logic [B-1:0] mem_di,

    // Software register
    input  logic         capture_reg
  );

  // -------------------------------------------------------------------------
  // Derived parameter
  // -------------------------------------------------------------------------
  localparam logic [N:0] NPOW = (1 << N);

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
  // FSM output decode
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
  // Address counter
  // -------------------------------------------------------------------------
  logic [N-1:0] addr_cnt;
  logic         mem_we_r;
  logic [N-1:0] mem_addr_r;
  logic [B-1:0] mem_di_r;

  // -------------------------------------------------------------------------
  // Internal FIFO instantiation (depth=16, same as VHDL N=4 → 2**4=16)
  // -------------------------------------------------------------------------
  fifo_sync #(
              .B (B),
              .N (16)
            ) fifo_i (
              .rstn   (rstn),
              .clk    (clk),
              .wr_en  (fifo_wr_en),
              .din    (s_axis_tdata),
              .rd_en  (fifo_rd_en),
              .dout   (fifo_dout),
              .full   (fifo_full),
              .empty  (fifo_empty)
            );

  // -------------------------------------------------------------------------
  // FIFO control
  // -------------------------------------------------------------------------
  assign fifo_wr_en = write_en & s_axis_tvalid;
  // The FIFO is read to write to memory (CAPTURE_ST)
  // or to discard the remainder of the stream (END_ST)
  assign fifo_rd_en = (current_state == CAPTURE_ST || current_state == END_ST) && ~fifo_empty;

  // -------------------------------------------------------------------------
  // Sequential: state register and address counter
  // -------------------------------------------------------------------------
  always_ff @(posedge clk)
  begin
    if (!rstn)
    begin
      current_state <= INIT_ST;
      addr_cnt      <= '0;
      mem_we_r      <= '0;
      mem_addr_r    <= '0;
      mem_di_r      <= '0;
    end
    else
    begin
      current_state <= next_state;

      if (write_en)
      begin
        if (~fifo_empty)
        begin
          addr_cnt   <= addr_cnt + 1'b1;
          mem_addr_r <= addr_cnt;
          mem_we_r   <= 1'b1;
          mem_di_r   <= fifo_dout;
        end
        else
        begin
          mem_we_r   <= 1'b0;
        end
      end
      else
      begin
        addr_cnt   <= '0;
        mem_we_r   <= 1'b0;
        mem_addr_r <= '0;
      end
    end
  end

  // -------------------------------------------------------------------------
  // Next-state logic (combinational)
  // -------------------------------------------------------------------------
  always_comb
  begin
    next_state = current_state;

    unique case (current_state)
             INIT_ST:
               if (capture_reg)
                 next_state = TRIGGER_ST;

             TRIGGER_ST:
               if (trigger)
                 next_state = CAPTURE_ST;

             CAPTURE_ST:
               if ((addr_cnt == '1) && ~fifo_empty)
                 next_state = END_ST;

             END_ST:
               if (!capture_reg && fifo_empty)
                 next_state = INIT_ST;

             default:
               next_state = INIT_ST;
           endcase
         end

         // -------------------------------------------------------------------------
         // FSM output decode (combinational)
         // -------------------------------------------------------------------------
         always_comb
         begin
           write_en = 1'b0;

           unique case (current_state)
                    INIT_ST:
                      ;
                    TRIGGER_ST:
                      ;
                    CAPTURE_ST:
                      write_en = 1'b1;
                    END_ST:
                      ;
                    default:
                      ;
                  endcase
                end

                // -------------------------------------------------------------------------
                // Output assignments
                // -------------------------------------------------------------------------
                assign s_axis_tready = write_en & ~fifo_full;
  assign mem_en        = 1'b1;
  assign mem_we        = mem_we_r;
  assign mem_addr      = mem_addr_r;
  assign mem_di        = mem_di_r;

endmodule
