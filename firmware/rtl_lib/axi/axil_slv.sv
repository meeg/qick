///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
//
// Fermi National Accelerator Laboratory
//
// Module: axil_slv.sv
// Project: QICK
// Description:
// AXI4-Lite Slave interface for the XCOM core.
// I/O ports corresponds to the AXI4 Interface definition.
//
// Change history: 05/14/25 - v0.1.0 Started by @lharnaldi
//                 12/03/25 - @lharnaldi
//                            Fixed issues:
//                            1. awready_reg, wready_reg, arready_reg
//                               now properly initialized
//                            2. Ready signals have defined values in
//                               all FSM states
//                            3. Cleaner FSM structure with explicit
//                               defaults
//                 05/23/26 @lharnaldi
//                          Improvements over original version:
//                          1. Added aw_en logic to prevent overlapping transactions (like VHDL)
//                          2. Generic parameters for reusability
//                          3. Support for read-only registers
//                          4. Configurable register initialization
//                          5. Standard AXI interface for FuseSoC
///////////////////////////////////////////////////////////////////////////////
module axil_slv#(
  // AXI parameters
  parameter integer AXI_DW = 32,           // Data width (32 or 64 bits)
  parameter integer AXI_AW = 8,            // Address width
  parameter integer NUM_REGS = 16,         // Number of registers
  parameter bit [NUM_REGS-1:0][AXI_DW-1:0] REG_INIT_VAL = '{default: '0},  // Initial value

  // Protection parameters (optional)
  parameter bit ENABLE_AW_EN = 1'b1,       // Enable aw_en logic (VHDL compatibility)
  parameter bit AUTO_CLEAR_BIT0 = 1'b0     // Auto-clear bit 0 of register 0
)(
  // Global signals
  input  logic                                s_axi_aclk,
  input  logic                                s_axi_aresetn,

  // Write address channel
  input  logic [AXI_AW-1:0]                   s_axi_awaddr,
  input  logic [2:0]                          s_axi_awprot,
  input  logic                                s_axi_awvalid,
  output logic                                s_axi_awready,

  // Write data channel
  input  logic [AXI_DW-1:0]                   s_axi_wdata,
  input  logic [(AXI_DW/8)-1:0]               s_axi_wstrb,
  input  logic                                s_axi_wvalid,
  output logic                                s_axi_wready,

  // Write response channel
  output logic [1:0]                          s_axi_bresp,
  output logic                                s_axi_bvalid,
  input  logic                                s_axi_bready,

  // Read address channel
  input  logic [AXI_AW-1:0]                   s_axi_araddr,
  input  logic [2:0]                          s_axi_arprot,
  input  logic                                s_axi_arvalid,
  output logic                                s_axi_arready,

  // Read data channel
  output logic [AXI_DW-1:0]                   s_axi_rdata,
  output logic [1:0]                          s_axi_rresp,
  output logic                                s_axi_rvalid,
  input  logic                                s_axi_rready,

  // User registers interface
  output logic [AXI_DW-1:0]                   o_slv_regs [NUM_REGS],  // Writeable registers
  input  logic [AXI_DW-1:0]                   i_slv_regs [NUM_REGS],   // Read-only register values (external)
  input  logic [NUM_REGS-1:0]                 i_reg_is_readonly = '0   // Mask for read-only registers
);

  // AXI4-Lite internal signals
  logic                                axi_awready;
  logic                                axi_wready;
  logic [1:0]                          axi_bresp;
  logic                                axi_bvalid;
  logic                                axi_arready;
  logic [AXI_DW-1:0]                   axi_rdata;
  logic [1:0]                          axi_rresp;
  logic                                axi_rvalid;

  // Address latching
  logic [AXI_AW-1:0]                   axi_awaddr;
  logic [AXI_AW-1:0]                   axi_araddr;

  // Write enable control (from VHDL)
  logic                                aw_en;

  // Address decoding
  localparam integer BYTES_PER_WORD = AXI_DW / 8;
  localparam integer ADDR_LSB = $clog2(BYTES_PER_WORD);
  localparam integer ADDR_MSB = ADDR_LSB + $clog2(NUM_REGS) - 1;

  // Control signals
  logic                                slv_reg_wren;
  logic                                slv_reg_rden;

  // Register read data
  logic [AXI_DW-1:0]                   reg_data_out;

  // I/O connections assignment
  assign s_axi_awready = axi_awready;
  assign s_axi_wready  = axi_wready;
  assign s_axi_bresp   = axi_bresp;
  assign s_axi_bvalid  = axi_bvalid;
  assign s_axi_arready = axi_arready;
  assign s_axi_rdata   = axi_rdata;
  assign s_axi_rresp   = axi_rresp;
  assign s_axi_rvalid  = axi_rvalid;

  // ============================================
  // Write Address Channel with aw_en logic
  // (from VHDL for back-to-back transaction protection)
  // ============================================
  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      axi_awready <= 1'b0;
      aw_en <= 1'b1;
    end else begin
      if (ENABLE_AW_EN) begin
        // VHDL-compatible behavior with aw_en protection
        if (axi_awready == 1'b0 && s_axi_awvalid == 1'b1 &&
          s_axi_wvalid == 1'b1 && aw_en == 1'b1) begin
            axi_awready <= 1'b1;
            aw_en <= 1'b0;
          end else if (s_axi_bready == 1'b1 && axi_bvalid == 1'b1) begin
            aw_en <= 1'b1;
            axi_awready <= 1'b0;
          end else begin
            axi_awready <= 1'b0;
          end
      end else begin
        // Simplified version (assumes master follows protocol)
        if (~axi_awready && s_axi_awvalid && s_axi_wvalid) begin
          axi_awready <= 1'b1;
        end else begin
          axi_awready <= 1'b0;
        end
      end
    end
  end

  // Write address latching
  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      axi_awaddr <= {AXI_AW{1'b0}};
    end else begin
      if (ENABLE_AW_EN) begin
        // VHDL-compatible address latching
        if (axi_awready == 1'b0 && s_axi_awvalid == 1'b1 &&
          s_axi_wvalid == 1'b1 && aw_en == 1'b1) begin
            axi_awaddr <= s_axi_awaddr;
          end
      end else begin
        // Simplified version
        if (~axi_awready && s_axi_awvalid && s_axi_wvalid) begin
          axi_awaddr <= s_axi_awaddr;
        end
      end
    end
  end

  // ============================================
  // Write Data Channel
  // ============================================
  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      axi_wready <= 1'b0;
    end else begin
      if (ENABLE_AW_EN) begin
        // VHDL-compatible write ready
        if (axi_wready == 1'b0 && s_axi_wvalid == 1'b1 &&
          s_axi_awvalid == 1'b1 && aw_en == 1'b1) begin
            axi_wready <= 1'b1;
          end else begin
            axi_wready <= 1'b0;
          end
      end else begin
        // Simplified version
        if (~axi_wready && s_axi_wvalid && s_axi_awvalid) begin
          axi_wready <= 1'b1;
        end else begin
          axi_wready <= 1'b0;
        end
      end
    end
  end

  // Write enable generation
  assign slv_reg_wren = axi_wready && s_axi_wvalid && axi_awready && s_axi_awvalid;

  // ============================================
  // Register write logic with byte-enable support
  // and read-only register protection
  // ============================================
  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      // Initialize registers with parameterized values
      for (int i = 0; i < NUM_REGS; i++) begin
        o_slv_regs[i] <= REG_INIT_VAL[i];
      end
    end else begin
      if (slv_reg_wren) begin
        // Get register index from address
        automatic int reg_idx = axi_awaddr[ADDR_MSB:ADDR_LSB];

        // Only write if register is not read-only
        if (reg_idx < NUM_REGS && !i_reg_is_readonly[reg_idx]) begin
          for (int byte_index = 0; byte_index < BYTES_PER_WORD; byte_index++) begin
            if (s_axi_wstrb[byte_index]) begin
              o_slv_regs[reg_idx][(byte_index*8) +: 8] <=
                s_axi_wdata[(byte_index*8) +: 8];
            end
          end
        end
      end

      // Auto-clear bit 0 of register 0 if enabled (for pulse/software clear)
      if (AUTO_CLEAR_BIT0 && o_slv_regs[0][0]) begin
        o_slv_regs[0][0] <= 1'b0;
      end

      // Allow external updates to registers (e.g., from hardware)
      for (int i = 0; i < NUM_REGS; i++) begin
        // Note: This creates a driver conflict if o_slv_regs is also written
        // from elsewhere. Use only for read-only or dual-driven registers.
        // For typical use, comment this out.
        // o_slv_regs[i] <= i_slv_regs[i];
      end
    end
  end

  // ============================================
  // Write Response Channel
  // ============================================
  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      axi_bvalid <= 1'b0;
      axi_bresp  <= 2'b00;
    end else begin
      if (ENABLE_AW_EN) begin
        // VHDL-compatible response generation
        if (axi_awready == 1'b1 && s_axi_awvalid == 1'b1 &&
          axi_wready == 1'b1 && s_axi_wvalid == 1'b1 &&
          axi_bvalid == 1'b0) begin
            axi_bvalid <= 1'b1;
            axi_bresp  <= 2'b00;  // OKAY response
          end else if (s_axi_bready == 1'b1 && axi_bvalid == 1'b1) begin
            axi_bvalid <= 1'b0;
          end
      end else begin
        // Simplified version
        if (axi_awready && s_axi_awvalid && ~axi_bvalid &&
          axi_wready && s_axi_wvalid) begin
            axi_bvalid <= 1'b1;
            axi_bresp  <= 2'b00;
          end else if (s_axi_bready && axi_bvalid) begin
            axi_bvalid <= 1'b0;
          end
      end
    end
  end

  // ============================================
  // Read Address Channel
  // ============================================
  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      axi_arready <= 1'b0;
      axi_araddr  <= {AXI_AW{1'b0}};
    end else begin
      if (~axi_arready && s_axi_arvalid) begin
        axi_arready <= 1'b1;
        axi_araddr  <= s_axi_araddr;
      end else begin
        axi_arready <= 1'b0;
      end
    end
  end

  // ============================================
  // Read Data Channel
  // ============================================
  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      axi_rvalid <= 1'b0;
      axi_rresp  <= 2'b00;
    end else begin
      if (axi_arready && s_axi_arvalid && ~axi_rvalid) begin
        axi_rvalid <= 1'b1;
        axi_rresp  <= 2'b00;  // OKAY response
      end else if (axi_rvalid && s_axi_rready) begin
        axi_rvalid <= 1'b0;
      end
    end
  end

  // Read enable generation
  assign slv_reg_rden = axi_arready && s_axi_arvalid && ~axi_rvalid;

  // ============================================
  // Register read logic (combinational)
  // ============================================
  always_comb begin
    automatic int reg_idx = axi_araddr[ADDR_MSB:ADDR_LSB];

    if (reg_idx < NUM_REGS) begin
      reg_data_out = o_slv_regs[reg_idx];
    end else begin
      reg_data_out = {AXI_DW{1'b0}};
    end
  end

  // Register read output (sequential)
  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      axi_rdata <= {AXI_DW{1'b0}};
    end else begin
      if (slv_reg_rden) begin
        axi_rdata <= reg_data_out;
      end
    end
  end

endmodule
