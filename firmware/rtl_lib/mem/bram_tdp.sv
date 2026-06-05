///////////////////////////////////////////////////////////////////////////////
// Module: bram_tdp.sv
// Description:
// True Dual-Port BRAM inferred with byte-enable support and
// independent ports through the use of interfaces.
///////////////////////////////////////////////////////////////////////////////
module bram_tdp #(
    parameter int unsigned NB_DATA      = 32,
    parameter int unsigned NB_ADDR      = 10,
    parameter string       MEM_BIN_FILE = ""
)(
    bram_if.slave port_a,
    bram_if.slave port_b
);

    // Internal calculations for memory depth and byte count
    localparam int unsigned DEPTH = 2**NB_ADDR;
    localparam int unsigned NUM_BYTES = NB_DATA / 8;

    // Declaration of the memory with attribute to infer Block RAM physical
    (* ram_style = "block" *) logic [NB_DATA-1:0] ram [DEPTH];

    // Optional initialization of the memory (useful for ROMs or bootloaders)
    initial begin
        if (MEM_BIN_FILE != "") begin
            $display("Loading memory from: %s", MEM_BIN_FILE);
            $readmemb(MEM_BIN_FILE, ram);
        end
    end

    // -------------------------------------------------------------------------
    // Port A
    // -------------------------------------------------------------------------
    always_ff @(posedge port_a.i_clk) begin
        if (port_a.en) begin
            // Writing: Byte-enabled writes
            for (int i = 0; i < NUM_BYTES; i++) begin
                if (port_a.we[i]) begin
                    // We use the "+:" operator to select bytes
                    ram[port_a.addr][i*8 +: 8] <= port_a.din[i*8 +: 8];
                end
            end
            // Reading: Always deliver the data (standard BRAM behavior)
            port_a.dout <= ram[port_a.addr];
        end
    end

    // -------------------------------------------------------------------------
    // Port B
    // -------------------------------------------------------------------------
    always_ff @(posedge port_b.i_clk) begin
        if (port_b.en) begin
            // Writing: Byte-enabled writes
            for (int i = 0; i < NUM_BYTES; i++) begin
                if (port_b.we[i]) begin
                    ram[port_b.addr][i*8 +: 8] <= port_b.din[i*8 +: 8];
                end
            end
            // Reading: Always deliver the data (standard BRAM behavior)
            port_b.dout <= ram[port_b.addr];
        end
    end

endmodule
