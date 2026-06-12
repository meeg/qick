/**
 * @module bram_tdp
 * @brief True‑dual‑port block RAM (independent clocks & resets).
 *
 * @description
 *   - Memoria de **NB_DATA**‑bits por palabra y **2^NB_ADDR** palabras.
 *   - Every port (`port_a`, `port_b`) works independently:
 *       * Can read or write at any clock cycle.
 *       * Clocks and resets can be different (dual‑clock RAM).
 *   - If `MEM_BIN_FILE` is not empty, the memory is initialized at
 *     startup with the content of the binary file (raw format).
 *
 * @generic
 *   NB_DATA      : unsigned int – data width of each data word (default 32).
 *   NB_ADDR      : unsigned int – number of address bits (default 10 → 1024 words).
 *   MEM_BIN_FILE : string – path to the binary initialization file (optional).
 *
 * @port
 *   input  logic                clk_a   : Clock of port A.
 *   input  logic                rst_a   : Reset synchronous active-high of port A.
 *   input  logic                clk_b   : Clock of port B.
 *   input  logic                rst_b   : Reset synchronous active-high of port B.
 *   bram_if.slave               port_a  : Interface of port A (see definition below).
 *   bram_if.slave               port_b  : Interface of port B (see definition below).
 *
 * @interface bram_if
 *   // Typical signals of a single-port RAM:
 *   logic                     en;      // Enable (read or write when high)
 *   logic                     we;      // Write enable (1 = write, 0 = read)
 *   logic [NB_ADDR-1:0]       addr;    // Address
 *   logic [NB_DATA-1:0]       din;     // Write data
 *   logic [NB_DATA-1:0]       dout;    // Read data (output from the RAM)
 */
module bram_tdp #(
    parameter int unsigned NB_DATA      = 32,
    parameter int unsigned NB_ADDR      = 10,
    parameter string       MEM_BIN_FILE = ""
)(
    //port A signals
    input  logic  clk_a,
    input  logic  rst_a,
    input  logic  ena,
    input  logic  wea,
    input  logic [NB_ADDR-1:0] addra,
    input  logic [NB_DATA-1:0] dia,
    output logic [NB_DATA-1:0] doa,

    //port B signals
    input  logic  clk_b,
    input  logic  rst_b, 
    input  logic  enb,
    input  logic  web,
    input  logic [NB_ADDR-1:0] addrb,
    input  logic [NB_DATA-1:0] dib,
    output logic [NB_DATA-1:0] dob
);

    // Internal calculations for memory depth and byte count
    localparam int unsigned DEPTH = 1 << NB_ADDR;
    localparam int unsigned NUM_BYTES = NB_DATA / 8;

    // Declaration of the memory with attribute to infer Block RAM physical
    (* ram_style = "block" *) logic [NB_DATA-1:0] ram [DEPTH];

    // Optional initialization of the memory (useful for ROMs or bootloaders)
    initial begin
        if (MEM_BIN_FILE != "") begin
            $display("Initializing BRAM from file: %s", MEM_BIN_FILE);
            $readmemh(MEM_BIN_FILE, ram); // Use $readmemb for binary files
        end else begin
            // If no initialization file is provided, clear the memory (optional)
            for (int i = 0; i < DEPTH; i++) begin
                ram[i] = '0;
            end
        end
    end 

    // -------------------------------------------------------------------------
    // Port A
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_a) begin
        if (rst_a) begin
            doa <= '0;
        end else if (ena) begin
            if (wea) begin
                // Writing
                ram[addra] <= dia;
                // In write‑first mode, the read returns the newly written data.
                doa <= dia; // write‑first
            end else begin
                // Reading
                doa <= ram[addra];
            end
        end
    end 

    // -------------------------------------------------------------------------
    // Port B
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_b) begin
        if (rst_b) begin
            dob <= '0;
        end else if (enb) begin
            if (web) begin
                ram[addrb] <= dib;
                // In write‑first mode, the read returns the newly written data.
                dob <= dib; // write‑first
            end else begin
                dob <= ram[addrb];
            end
        end
    end

endmodule
