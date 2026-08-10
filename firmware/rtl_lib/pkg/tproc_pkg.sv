`ifndef TPROC_PKG_SV
`define TPROC_PKG_SV

package tproc_pkg;
  //tProc v1 related constants/definitions
    // I-Type opcodes
    localparam logic [7:0] OP_PUSHI  = 8'b00010000;
    localparam logic [7:0] OP_POPI   = 8'b00010001;
    localparam logic [7:0] OP_MATHI  = 8'b00010010;
    localparam logic [7:0] OP_SETI   = 8'b00010011;
    localparam logic [7:0] OP_SYNCI  = 8'b00010100;
    localparam logic [7:0] OP_WAITI  = 8'b00010101;
    localparam logic [7:0] OP_BITWI  = 8'b00010110;
    localparam logic [7:0] OP_MEMRI  = 8'b00010111;
    localparam logic [7:0] OP_MEMWI  = 8'b00011000;
    localparam logic [7:0] OP_REGWI  = 8'b00011001;
    localparam logic [7:0] OP_SETBI  = 8'b00011010;
    // J-Type opcodes
    localparam logic [7:0] OP_LOOPNZ = 8'b00110000;
    localparam logic [7:0] OP_CONDJ  = 8'b00110001;
    localparam logic [7:0] OP_END    = 8'b00111111;
    // R-Type opcodes
    localparam logic [7:0] OP_MATH   = 8'b01010000;
    localparam logic [7:0] OP_SET    = 8'b01010001;
    localparam logic [7:0] OP_SYNC   = 8'b01010010;
    localparam logic [7:0] OP_READ   = 8'b01010011;
    localparam logic [7:0] OP_WAIT   = 8'b01010100;
    localparam logic [7:0] OP_BITW   = 8'b01010101;
    localparam logic [7:0] OP_MEMR   = 8'b01010110;
    localparam logic [7:0] OP_MEMW   = 8'b01010111;
    localparam logic [7:0] OP_SETB   = 8'b01011000;

    typedef enum {
        INIT_ST,
        PC_RST_ST,
        START_MC_ST,
        FETCH_ST,
        DECODE_ST,
        MATHI0_ST,
        MATHI1_ST,
        MATHI2_ST,
        MATHI3_ST,
        BITWI0_ST,
        BITWI1_ST,
        BITWI2_ST,
        BITWI3_ST,
        MATH0_ST,
        MATH1_ST,
        MATH2_ST,
        MATH3_ST,
        BITW0_ST,
        BITW1_ST,
        BITW2_ST,
        BITW3_ST,
        PUSHI0_ST,
        POPI0_ST,
        POPI1_ST,
        POPI2_ST,
        LOOPNZ0_ST,
        LOOPNZ1_ST,
        LOOPNZ2_ST,
        LOOPNZ3_ST,
        SETI0_ST,
        SETI1_ST,
        SET0_ST,
        SET1_ST,
        SYNCI0_ST,
        SYNCI1_ST,
        SYNC0_ST,
        SYNC1_ST,
        CONDJ0_ST,
        CONDJ1_ST,
        CONDJ2_ST,
        READ0_ST,
        MEMRI0_ST,
        MEMRI1_ST,
        MEMRI2_ST,
        MEMR0_ST,
        MEMR1_ST,
        MEMR2_ST,
        MEMWI0_ST,
        MEMW0_ST,
        REGWI0_ST,
        WAITI0_ST,
        WAITI1_ST,
        WAIT0_ST,
        WAIT1_ST,
        WAIT_ACK_ST,
        ERR_INSTR_ST,
        ERR_STACK_ST,
        END_ST
    } tpv1_ctrl_state_t;

    //--------------------------------------------------------------------------
    // Instruction Encoders
    //--------------------------------------------------------------------------

    // I-Type: opcode|page|ch|oper|ra|rb|rc|imm[30:0] (old names, left here for reference)
    // I-Type: opcode|page|ch|oper|rd|rs1|rs2|imm[30:0]
    function automatic logic [63:0] itype(
        input logic [7:0]  opcode,
        input logic [2:0]  page,
        input logic [2:0]  ch,
        input logic [3:0]  oper,
        input logic [4:0]  rd,   // Destination (addr7)
        input logic [4:0]  rs1,  // Source 1 (addr0 -> alu_a)
        input logic [4:0]  rs2,  // Source 2 (addr1 -> alu_b)
        input logic [30:0] imm
    );
        return {opcode, page, ch, oper, rd, rs1, rs2, imm};
    endfunction

    // J-Type: opcode|page|000|oper|ra|rb|rc|15'b0|addr[15:0] (old names, left here for reference)
    // J-Type: opcode|page|000|oper|rd|rs1|rs2|15'b0|addr[15:0]
    function automatic logic [63:0] jtype(
        input logic [7:0]  opcode,
        input logic [2:0]  page,
        input logic [3:0]  oper,
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [4:0]  rs2,
        input logic [15:0] addr
    );
        // Observation: in J-type we fill out the channel with 0 (3'b0)
        return {opcode, page, 3'b0, oper, rd, rs1, rs2, 15'b0, addr};
    endfunction

    // R-Type: opcode|page|ch|oper|ra|rb |rc |rd |re |rf |rg |rh |6'b0 (old names, left here for reference)
    // R-Type: opcode|page|ch|oper|rd|rs1|rs2|rs3|rs4|rs5|rs6|rs7|6'b0
    function automatic logic [63:0] rtype(
        input logic [7:0]  opcode,
        input logic [2:0]  page,
        input logic [2:0]  ch,
        input logic [3:0]  oper,
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [4:0]  rs2,
        input logic [4:0]  rs3,
        input logic [4:0]  rs4,
        input logic [4:0]  rs5,
        input logic [4:0]  rs6,
        input logic [4:0]  rs7
    );
        return {opcode, page, ch, oper, rd, rs1, rs2, rs3, rs4, rs5, rs6, rs7, 6'b0};
    endfunction

endpackage

`endif
