///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : avg
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    avg.sv
//!
//! @brief   Fixed-point accumulator and photon edge counter for the QICK
//!
//! @details
//!
//! pipeline.
//!
//! Two operating modes selected by photon_mode_reg:
//! 0 - Accumulation mode: stores the sum of I and Q samples over len_reg
//! samples into memory at address addr_reg.
//! 1 - Photon edge counter mode: counts rising edges on the I channel
//! using hysteresis thresholds h_thrsh_reg (high) and l_thrsh_reg (low).
//!
//! Capture is initiated by an external trigger after start_reg is asserted.
//! start_reg must remain high through the entire capture cycle.
//! After WRITE_MEM_ST the FSM holds in WAIT_TRIGGER_ST until trigger_i
//! de-asserts, then returns to TRIGGER_ST ready for the next capture.
//! Asserting start_reg=0 at any point after TRIGGER_ST aborts back to START_ST.
//!
//! @author  QICK Development Team
//!
//! @version 1.0

module avg #(
  //! memory address width (depth = 2**N)
  parameter int N = 10,
  //! sample data width in bits
  parameter int B = 16
) (
  input  logic              rstn,
  input  logic              clk,

  // Trigger input
  input  logic              trigger_i,

  // Data input stream
  input  logic              din_valid_i,
  input  logic [2*B-1:0]   din_i,

  // Memory interface
  output logic              mem_we_o,
  output logic [N-1:0]      mem_addr_o,
  output logic [4*B-1:0]    mem_di_o,

  // Configuration registers (must be held stable while start_reg=1)
  input  logic              start_reg,
  input  logic [N-1:0]      addr_reg,
  input  logic [31:0]       len_reg,
  input  logic              photon_mode_reg,
  input  logic [B-1:0]      h_thrsh_reg,
  input  logic [B-1:0]      l_thrsh_reg
);

  // -------------------------------------------------------------------------
  // FSM state encoding
  // -------------------------------------------------------------------------
  typedef enum logic [2:0] {
    INIT_ST         = 3'd0,
    START_ST        = 3'd1,
    TRIGGER_ST      = 3'd2,
    AVG_ST          = 3'd3,
    QOUT_ST         = 3'd4,
    WRITE_MEM_ST    = 3'd5,
    WAIT_TRIGGER_ST = 3'd6
  } state_t;

  (* fsm_encoding = "one_hot" *) state_t state;

  // -------------------------------------------------------------------------
  // FSM output decode signals
  // -------------------------------------------------------------------------
  logic start_state;
  logic trigger_state;
  logic avg_state;
  logic write_mem_state;

  // -------------------------------------------------------------------------
  // Internal registers
  // -------------------------------------------------------------------------
  logic [31:0]           cnt;
  logic [N-1:0]          addr_r;
  logic [31:0]           len_r;
  logic                  photon_mode_r;
  logic signed [B-1:0]   h_thrsh_r;
  logic signed [B-1:0]   l_thrsh_r;

  // Accumulators
  logic signed [2*B-1:0] acc_i;
  logic signed [2*B-1:0] acc_q;
  logic        [4*B-1:0] acc_photon;

  // Quantized output register
  logic [4*B-1:0]        out_result_r;

  // Photon edge detection
  logic                  high_state;
  logic                  high_state_reg;

  // Input channel splits
  logic signed [B-1:0]   din_ii;
  logic signed [B-1:0]   din_qq;

  assign din_ii = din_i[B-1:0];
  assign din_qq = din_i[2*B-1:B];

  // -------------------------------------------------------------------------
  // FSM + datapath sequential block
  // -------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      state          <= INIT_ST;
      cnt            <= '0;
      addr_r         <= '0;
      len_r          <= '0;
      photon_mode_r  <= 1'b0;
      h_thrsh_r      <= '0;
      l_thrsh_r      <= '0;
      high_state     <= 1'b0;
      high_state_reg <= 1'b0;
      acc_i          <= '0;
      acc_q          <= '0;
      acc_photon     <= '0;
      out_result_r   <= '0;
    end else begin

      // -----------------------------------------------------------------
      // FSM next-state logic
      // -----------------------------------------------------------------
      unique case (state)
        INIT_ST: begin
          state <= START_ST;
        end

        START_ST: begin
          if (start_reg) state <= TRIGGER_ST;
        end

        TRIGGER_ST: begin
          if (!start_reg)      state <= START_ST;
          else if (trigger_i)  state <= AVG_ST;
        end

        // Transition when the LAST valid sample has been processed.
        // cnt is incremented in the same cycle as the valid sample,
        // so after len_r samples cnt == len_r.
        AVG_ST: begin
          if (!start_reg) begin
            state <= START_ST;   // abort capture if start_reg de-asserts
          end else if (din_valid_i && cnt == len_r) begin
            state <= QOUT_ST;
          end
        end

        QOUT_ST: begin
          if (!start_reg) state <= START_ST;
          else state <= WRITE_MEM_ST;
        end

        WRITE_MEM_ST: begin
          if (!start_reg) state <= START_ST;
          else state <= WAIT_TRIGGER_ST;
        end

        WAIT_TRIGGER_ST: begin
          if (!start_reg)   state <= START_ST;
          else if (!trigger_i) state <= TRIGGER_ST;
        end

        default: begin
          state <= INIT_ST;
        end
      endcase

      // -----------------------------------------------------------------
      // Sample counter
      // Reset in START_ST and TRIGGER_ST (preparing for new capture).
      // Increment on each valid sample in AVG_ST.
      // -----------------------------------------------------------------
      if (start_state || trigger_state) begin
        cnt <= '0;
      end else if (avg_state) begin
        if (!start_reg) begin
          cnt <= '0;
        end else if (din_valid_i) begin
          cnt <= cnt + 1;
        end
      end

      // -----------------------------------------------------------------
      // Config register latch (START_ST); address auto-increment
      // -----------------------------------------------------------------
      if (start_state) begin
        addr_r        <= addr_reg;
        len_r         <= (len_reg == '0) ? 32'd1 : len_reg - 1;
        photon_mode_r <= photon_mode_reg;
        h_thrsh_r     <= signed'(h_thrsh_reg);
        l_thrsh_r     <= signed'(l_thrsh_reg);
      end else if (write_mem_state) begin
        addr_r <= addr_r + 1;
      end

      // -----------------------------------------------------------------
      // Accumulator reset (TRIGGER_ST) and accumulate (AVG_ST)
      // -----------------------------------------------------------------
      if (trigger_state) begin
        acc_i          <= '0;
        acc_q          <= '0;
        acc_photon     <= '0;
        high_state     <= 1'b0;
        high_state_reg <= 1'b0;
      end else if (avg_state && !start_reg) begin
        acc_i          <= '0;
        acc_q          <= '0;
        acc_photon     <= '0;
        high_state     <= 1'b0;
        high_state_reg <= 1'b0;
      end else if (avg_state && din_valid_i && !photon_mode_r) begin
        acc_i <= acc_i + {{B{din_ii[B-1]}}, din_ii};
        acc_q <= acc_q + {{B{din_qq[B-1]}}, din_qq};
      end else if (avg_state && din_valid_i && photon_mode_r && high_state && !high_state_reg) begin
        acc_photon <= acc_photon + 1;
      end

      // -----------------------------------------------------------------
      // Photon edge detection — runs every cycle on valid samples only.
      // high_state_reg is updated one cycle after high_state so that
      // the rising edge (high_state=1, high_state_reg=0) is detected
      // on the cycle AFTER the first sample crosses h_thrsh.
      // -----------------------------------------------------------------
      if (din_valid_i) begin
        high_state_reg <= high_state;
        if (din_ii > h_thrsh_r)      high_state <= 1'b1;
        else if (din_ii < l_thrsh_r) high_state <= 1'b0;
      end

      // -----------------------------------------------------------------
      // Output result register — updated every cycle so WRITE_MEM_ST
      // sees the final accumulated value one cycle after QOUT_ST.
      // -----------------------------------------------------------------
      if (!photon_mode_r) begin
        out_result_r <= {acc_q, acc_i};
      end else begin
        out_result_r <= acc_photon;
      end
    end
  end

  // -------------------------------------------------------------------------
  // FSM output decode (combinational)
  // -------------------------------------------------------------------------
  always_comb begin
    start_state     = 1'b0;
    trigger_state   = 1'b0;
    avg_state       = 1'b0;
    write_mem_state = 1'b0;

    unique case (state)
      START_ST:     start_state     = 1'b1;
      TRIGGER_ST:   trigger_state   = 1'b1;
      AVG_ST:       avg_state       = 1'b1;
      WRITE_MEM_ST: write_mem_state = 1'b1;
      default:      ; // INIT_ST, QOUT_ST, WAIT_TRIGGER_ST: no outputs
    endcase
  end

  // -------------------------------------------------------------------------
  // Output assignments
  // -------------------------------------------------------------------------
  assign mem_we_o   = write_mem_state && start_reg; // only write when start_reg is still high (not aborted)
  assign mem_addr_o = addr_r;
  assign mem_di_o   = out_result_r;

endmodule
