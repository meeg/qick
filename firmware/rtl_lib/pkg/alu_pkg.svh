// alu_pkg.svh
`ifndef ALU_PKG_SVH
`define ALU_PKG_SVH

package alu_pkg;
    // Data width default
    parameter int B = 16;

    // Operation codes for Arithmetic Unit
    typedef enum logic [3:0] {
        ARITH_ADD = 4'b0000,
        ARITH_SUB = 4'b0001,
        ARITH_MUL = 4'b0010
    } arith_op_e;

    // Operation codes for Bitwise Unit
    typedef enum logic [3:0] {
        BITW_AND   = 4'b0000,
        BITW_OR    = 4'b0001,
        BITW_XOR   = 4'b0010,
        BITW_NOT   = 4'b0011,
        BITW_LSHIFT = 4'b0100,
        BITW_RSHIFT = 4'b0101
    } bitw_op_e;
endpackage

`endif
