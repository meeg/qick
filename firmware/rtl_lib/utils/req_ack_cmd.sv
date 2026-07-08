///////////////////////////////////////////////////////////////////////////////
// Fermi National Accelerator Laboratory
// Module : req_ack_cmd
// Project: QICK
///////////////////////////////////////////////////////////////////////////////
//! @file    req_ack_cmd.sv
//!
//! @brief   Block to determine if the command must be executed locally (LOC_REQ) to
//!
//! @details
//!
//! the board or if it should be executed through the network of
//! connected QICKs (NET_REQ).
//!
//! @author  QICK Development Team
//!
//! @version 1.0
module req_ack_cmd(
    input  logic          i_clk       ,
    input  logic          i_rstn      ,
    // Command Input
    input  logic          i_valid     ,
    input  logic [ 5-1:0] i_op        ,
    input  logic [ 4-1:0] i_addr      ,
    input  logic [32-1:0] i_data      ,
    // Command Execution
    input  logic          i_ack       ,
    output logic          o_req_loc   ,
    output logic          o_req_net   ,
    output logic [ 8-1:0] o_op        ,
    output logic [32-1:0] o_data      ,
    output logic [ 4-1:0] o_data_cntr
);

    logic [ 8-1:0]   cmd_op_r, cmd_op_n;
    logic [32-1:0]   cmd_dt_r, cmd_dt_n;
    logic [ 4-1:0]   cmd_cnt_r, cmd_cnt_n;
    logic            s_req_net, s_req_loc;

    typedef enum logic [2-1:0] {IDLE    = 2'b00,
                                LOC_REQ = 2'b01,
                                NET_REQ = 2'b10,
                                ACK     = 2'b11
    } state_t;

    state_t state_r, state_n;

    //State register
    always_ff @ (posedge i_clk) begin
        if ( !i_rstn ) state_r <= IDLE;
        else           state_r <= state_n;
    end

    //next state logic
    always_comb begin
        state_n   = state_r;
        s_req_loc = 1'b0;
        s_req_net = 1'b0;
        case (state_r)
            IDLE: begin
               if( i_valid )  begin
                 if (i_op[4]) begin
                    s_req_loc = 1'b1;
                    state_n   = LOC_REQ;
                 end else begin
                    s_req_net = 1'b1;
                    state_n   = NET_REQ;
                 end
               end else begin
                 state_n = IDLE;
               end
            end
            LOC_REQ:  begin
               s_req_loc = 1'b1;
               if (i_ack) state_n = ACK;
               else       state_n = LOC_REQ;
            end
            NET_REQ:  begin
               s_req_net = 1'b1;
               if (i_ack) state_n = ACK;
               else       state_n = NET_REQ;
            end
            ACK:  begin
               if (!i_ack) state_n = IDLE;
               else        state_n = ACK;
            end
            default:
                state_n = state_r;
        endcase
    end

    always_ff @(posedge i_clk)
        if (!i_rstn) begin
            cmd_op_r      <= '0;
            cmd_dt_r      <= '0;
            cmd_cnt_r     <= '0;
        end else begin
            cmd_op_r      <= cmd_op_n;
            cmd_dt_r      <= cmd_dt_n;
            cmd_cnt_r     <= cmd_cnt_n;
        end
    //next state logic
    assign cmd_op_n  = i_valid ? {i_op[3:0], i_addr} : cmd_op_r;
    assign cmd_dt_n  = i_valid ? i_data              : cmd_dt_r;
    assign cmd_cnt_n = i_ack   ? cmd_cnt_r + 1'b1    : cmd_cnt_r;

    // OUTPUTS
    ///////////////////////////////////////////////////////////////////////////////
    assign o_op   = cmd_op_r;
    assign o_data = cmd_dt_r;
    assign o_req_loc = s_req_loc;
    assign o_req_net = s_req_net;

    // DEBUG
    ///////////////////////////////////////////////////////////////////////////////
    assign o_data_cntr = cmd_cnt_r;

endmodule
