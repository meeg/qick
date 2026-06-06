///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
//
//
// Module: bram_if.sv
// Project: BRAM Interface
// Description:
// Single-port BRAM interface with byte-enable support.
// For True Dual-Port, instantiate this interface twice.
// For complete write: we = {(NB_DATA/8){1'b1}} — equivalent to we=1 for
// single-bit enables.
//
// Change history: 12/23/25 - Created by @lharnaldi
//
///////////////////////////////////////////////////////////////////////////////
interface bram_if #(
    parameter int unsigned NB_DATA = 32,
    parameter int unsigned NB_ADDR = 10
)(
    input logic i_clk,
    input logic i_rst
);
    logic                   en;
    logic                   we;
    //logic [(NB_DATA/8)-1:0] we;
    logic [NB_ADDR-1:0]     addr;
    logic [NB_DATA-1:0]     din;
    logic [NB_DATA-1:0]     dout;

    // Clocking block for testbench — solves the timing of synchronous BRAM
    clocking tb_cb @(posedge i_clk);
        default input #1step output #2;
        output en, we, addr, din;
        input  dout;
    endclocking

    modport master (
        output en, we, addr, din,
        input  dout
    );

    modport slave (
        input  en, we, addr, din,
        output dout
    );

    modport tb (
        clocking tb_cb
    );

    // Tasks use the clocking block — automatic correct timing
    task automatic write_data(
        input logic [NB_ADDR-1:0] w_addr,
        input logic [NB_DATA-1:0] w_data
    );
        tb_cb.en   <= 1'b1;
        tb_cb.we   <= 1'b1;
        //tb_cb.we   <= {(NB_DATA/8){1'b1}};
        tb_cb.addr <= w_addr;
        tb_cb.din  <= w_data;
        @(tb_cb);          // BRAM latch in this posedge
        tb_cb.en   <= 1'b0;
        tb_cb.we   <= '0;
        @(tb_cb);          // margin for BRAM to process the write before next operation
    endtask

    task automatic read_data(
        input  logic [NB_ADDR-1:0] r_addr,
        output logic [NB_DATA-1:0] r_data
    );
        tb_cb.en   <= 1'b1;
        tb_cb.we   <= '0;
        tb_cb.addr <= r_addr;
        @(tb_cb);          // BRAM registers addr, dout is updated in the next posedge
        tb_cb.en   <= 1'b0;
        @(tb_cb);          // dout stable — input #1step captures before the posedge
        r_data = tb_cb.dout;
    endtask

endinterface
