// Description: BUFFER block is a FSM that receives an input stream of samples
// (din), and controls the interface to a memory to capture and store them.
// Capturing is initiated by an external trigger after the buffer has been
// enabled. Number of captured samples and address where to store them are
// configurable.  When number of captured samples is reached, it can be
// triggered again.
//
// Parameters: N: memory depth as 2**N; B: memory data width

// Data is I,Q.  I: lower B bits.  Q: upper B bits.
module buffer#(
    parameter int N = 10,  // Address width
    parameter int B = 16   // Data width
)(
    // Reset and clock
    input  logic             rstn,
    input  logic             clk,

    // Trigger input
    input  logic             trigger_i,

    // Data input
    input  logic             din_valid_i,
    input  logic [2*B-1:0]   din_i,

    // Memory interface
    output logic             mem_we_o,
    output logic [N-1:0]     mem_addr_o,
    output logic [2*B-1:0]   mem_di_o,

    // Registers
    input  logic             start_reg,
    input  logic [N-1:0]     addr_reg,
    input  logic [N-1:0]     len_reg
);

///////////////////////////////////////////////////////////////
// Internal signals
///////////////////////////////////////////////////////////////

// FSM states
typedef enum logic [2:0] {
    INIT_ST,
    START_ST,
    TRIGGER_ST,
    MEMW_ST,
    WAIT_TRIGGER_ST
} state_t;

// (* fsm_encoding = "one_hot" *)  // optional, it depends on tool
state_t state;

// Control signals
logic start_state;
logic trigger_state;
logic memw_state;

// Counter
logic [N-1:0] cnt;

// Registers
logic [N-1:0] addr_r;
logic [N-1:0] len_r;

///////////////////////////////////////////////////////////////
// Sequential logic
///////////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        state  <= INIT_ST;
        cnt    <= '0;
        addr_r <= '0;
        len_r  <= '0;
    end else begin
        // FSM
        unique case (state)
            INIT_ST: begin
                state <= START_ST;
            end

            START_ST: begin
                if (start_reg)
                    state <= TRIGGER_ST;
            end

            TRIGGER_ST: begin
                if (!start_reg)
                    state <= START_ST;
                else if (trigger_i)
                    state <= MEMW_ST;
            end

            MEMW_ST: begin
                if ((cnt == len_r) && din_valid_i)
                    state <= WAIT_TRIGGER_ST;
            end

            WAIT_TRIGGER_ST: begin
                if (!start_reg)
                    state <= START_ST;
                else if (!trigger_i)
                    state <= TRIGGER_ST;
            end

            default: state <= INIT_ST;
        endcase

        // Counter
        if (memw_state) begin
            if (din_valid_i)
                cnt <= cnt + 1;
        end else begin
            cnt <= '0;
        end

        // Registers
        if (start_state) begin
            addr_r <= addr_reg;
            len_r  <= (len_reg == 0) ? '0 : len_reg - 1;
        end else if (memw_state && din_valid_i) begin
            addr_r <= addr_r + 1;
        end
    end
end

///////////////////////////////////////////////////////////////
// Combinational logic
///////////////////////////////////////////////////////////////
always_comb begin
    start_state   = 1'b0;
    trigger_state = 1'b0;
    memw_state    = 1'b0;

    unique case (state)
        START_ST: begin
            start_state = 1'b1;
        end

        TRIGGER_ST: begin
            trigger_state = 1'b1;
        end

        MEMW_ST: begin
            memw_state = 1'b1;
        end

        default: ;
    endcase
end

///////////////////////////////////////////////////////////////
// Outputs
///////////////////////////////////////////////////////////////
assign mem_we_o   = memw_state && din_valid_i;
assign mem_addr_o = addr_r;
assign mem_di_o   = din_i;

endmodule
