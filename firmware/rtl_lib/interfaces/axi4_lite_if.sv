///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
//
// Fermi National Accelerator Laboratory
//
// Module: axi4_lite_if.sv
// Project: AXI4 Lite Interface
// Description:
// AXI4-Lite Interface implementation with enhanced tasks for testbench usage
//
// Change history: 12/22/25 - Created by @lharnaldi
//                 01/26/26 - Added enhanced read/write tasks with timeouts
//
///////////////////////////////////////////////////////////////////////////////
interface axi4_lite_if#(
  parameter int DATA_WIDTH = 32,
  parameter int ADDR_WIDTH = 32
)(
  input logic aclk,
  input logic aresetn
);

  generate
    if ((DATA_WIDTH != 32) && (DATA_WIDTH != 64)) begin : g_check_data_width
      $fatal(1, "The AXI4-Lite data bus width must be 32 or 64 bits wide (%0d not supported).", DATA_WIDTH);
    end
  endgenerate

  logic                       awready;
  logic                       awvalid;
  logic [ADDR_WIDTH-1:0]      awaddr;
  logic [2:0]                 awprot;

  logic                       wready;
  logic                       wvalid;
  logic [DATA_WIDTH-1:0]      wdata;
  logic [DATA_WIDTH/8-1:0]    wstrb;

  logic                       bready;
  logic                       bvalid;
  logic [1:0]                 bresp;

  logic                       arready;
  logic                       arvalid;
  logic [ADDR_WIDTH-1:0]      araddr;
  logic [2:0]                 arprot;

  logic                       rready;
  logic                       rvalid;
  logic [DATA_WIDTH-1:0]      rdata;
  logic [1:0]                 rresp;

  modport master (
    input  awready,
    output awvalid,
    output awaddr,
    output awprot,

    input  wready,
    output wvalid,
    output wdata,
    output wstrb,

    output bready,
    input  bvalid,
    input  bresp,

    input  arready,
    output arvalid,
    output araddr,
    output arprot,

    output rready,
    input  rvalid,
    input  rdata,
    input  rresp
  );

  modport slave (
    output awready,
    input  awvalid,
    input  awaddr,
    input  awprot,

    output wready,
    input  wvalid,
    input  wdata,
    input  wstrb,

    input  bready,
    output bvalid,
    output bresp,

    output arready,
    input  arvalid,
    input  araddr,
    input  arprot,

    input  rready,
    output rvalid,
    output rdata,
    output rresp
  );

  // ASSERTIONS
  `ifdef SYNTHESIS
  `elsif VERILATOR
  `else

    modport tb_master(clocking m_cb);
    modport tb_slave(clocking s_cb);

    clocking m_cb @(posedge aclk);
      default input #1step output #2;

      input  awready;
      output awvalid;
      output awaddr;
      output awprot;

      input  wready;
      output wvalid;
      output wdata;
      output wstrb;

      output bready;
      input  bvalid;
      input  bresp;

      input  arready;
      output arvalid;
      output araddr;
      output arprot;

      output rready;
      input  rvalid;
      input  rdata;
      input  rresp;
    endclocking

    clocking s_cb @(posedge aclk);
      default input #1step output #2;

      output awready;
      input  awvalid;
      input  awaddr;
      input  awprot;

      output wready;
      input  wvalid;
      input  wdata;
      input  wstrb;

      input  bready;
      output bvalid;
      output bresp;

      output arready;
      input  arvalid;
      input  araddr;
      input  arprot;

      input  rready;
      output rvalid;
      output rdata;
      output rresp;
    endclocking

  `endif //SYNTHESIS

  // ==========================================================================
  // BASIC TASKS (Simple - minimal checking)
  // ==========================================================================

  task automatic read (
    input  logic [ADDR_WIDTH-1:0] addr,
    output logic [DATA_WIDTH-1:0] data
  );
    begin
      araddr = addr;
      arvalid = 1'b1;
      rready = 1'b1;
      wait(arready);
      @(posedge aclk) #1;
      arvalid = 1'b0;
      wait(rvalid);
      data = rdata;
      @(posedge aclk) #1;
      rready = 1'b0;
    end
  endtask

  task automatic write (
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [DATA_WIDTH-1:0] data
  );
    begin
      wdata = data;
      awaddr = addr;
      awvalid = 1'b1;
      wvalid = 1'b1;
      wstrb = '1;
      bready = 1'b1;
      wait(awready && wready);
      @(posedge aclk) #1;
      awvalid = 1'b0;
      wvalid = 1'b0;
    end
  endtask

  task automatic write_field (
    input logic [ADDR_WIDTH        -1:0] addr,
    input logic [DATA_WIDTH        -1:0] data,
    input logic [DATA_WIDTH        -1:0] mask,
    input logic [$clog2(ADDR_WIDTH)  :0] offset
  );
    begin
      logic [DATA_WIDTH-1:0] rd_data, wr_data;
      read(addr, rd_data);
      wr_data = (rd_data & ~mask) | ((data << offset) & mask);
      write(addr, wr_data);
    end
  endtask

  task automatic read_field (
    input  logic [ADDR_WIDTH        -1:0] addr,
    output logic [DATA_WIDTH        -1:0] data,
    input  logic [DATA_WIDTH        -1:0] mask,
    input  logic [$clog2(ADDR_WIDTH)  :0] offset
  );
    begin
      logic [DATA_WIDTH-1:0] tmp_data;
      read(addr, tmp_data);
      data = (tmp_data & mask) >> offset;
    end
  endtask

  // ==========================================================================
  // ENHANCED TASKS (Robust - with timeouts and error checking)
  // ==========================================================================

  // Enhanced write task with timeout and error checking
  task automatic axi_write(
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] data,
    input  int                    timeout = 100
  );
    int cycles_wait = 0;

    // Drive write address channel
    awaddr  = addr;
    awvalid = 1'b1;
    awprot  = 3'b000; // Default: unprivileged, secure, data access

    // Drive write data channel
    wdata   = data;
    wstrb   = {(DATA_WIDTH/8){1'b1}}; // All bytes enabled
    wvalid  = 1'b1;

    // Prepare to accept write response
    bready  = 1'b1;

    // Wait for both address and data to be accepted
    fork
      // Wait for address ready
      begin
        cycles_wait = 0;
        while (awvalid && !awready && cycles_wait < timeout) begin
          @(posedge aclk);
          cycles_wait++;
        end
        if (cycles_wait >= timeout) begin
          $error("[%0t] AXI Write: Timeout waiting for awready", $time);
        end
        awvalid = 1'b0;
      end

      // Wait for data ready
      begin
        cycles_wait = 0;
        while (wvalid && !wready && cycles_wait < timeout) begin
          @(posedge aclk);
          cycles_wait++;
        end
        if (cycles_wait >= timeout) begin
          $error("[%0t] AXI Write: Timeout waiting for wready", $time);
        end
        wvalid = 1'b0;
      end
    join

    // Wait for write response
    cycles_wait = 0;
    while (!bvalid && cycles_wait < timeout) begin
      @(posedge aclk);
      cycles_wait++;
    end

    if (cycles_wait >= timeout) begin
      $error("[%0t] AXI Write: Timeout waiting for bvalid", $time);
    end else if (bresp !== 2'b00) begin
      $warning("[%0t] AXI Write: Received error response: 'b%b", $time, bresp);
    end

    // Complete transaction
    @(posedge aclk);
    bready = 1'b0;

    // Wait one more cycle for clean state
    @(posedge aclk);
  endtask

  // Enhanced read task with timeout and error checking
  task automatic axi_read(
    input  logic [ADDR_WIDTH-1:0]  addr,
    output logic [DATA_WIDTH-1:0]  data,
    input  int                     timeout = 100
  );
    int cycles_wait = 0;

    // Drive read address channel
    araddr  = addr;
    arvalid = 1'b1;
    arprot  = 3'b000; // Default: unprivileged, secure, data access

    // Prepare to accept read data
    rready  = 1'b1;

    // Wait for address to be accepted
    cycles_wait = 0;
    while (arvalid && !arready && cycles_wait < timeout) begin
      @(posedge aclk);
      cycles_wait++;
    end

    if (cycles_wait >= timeout) begin
      $error("[%0t] AXI Read: Timeout waiting for arready", $time);
    end

    arvalid = 1'b0;

    // Wait for read data
    cycles_wait = 0;
    while (!rvalid && cycles_wait < timeout) begin
      @(posedge aclk);
      cycles_wait++;
    end

    if (cycles_wait >= timeout) begin
      $error("[%0t] AXI Read: Timeout waiting for rvalid", $time);
    end else if (rresp !== 2'b00) begin
      $warning("[%0t] AXI Read: Received error response: 'b%b", $time, rresp);
    end

    // Capture data
    data = rdata;

    // Complete transaction
    @(posedge aclk);
    rready = 1'b0;

    // Wait one more cycle for clean state
    @(posedge aclk);
  endtask

  // Bulk write - write multiple consecutive registers
  task automatic axi_bulk_write(
    input  logic [ADDR_WIDTH-1:0] base_addr,
    input  logic [DATA_WIDTH-1:0] data_array [],
    input  int                    timeout = 100
  );
    foreach (data_array[i]) begin
      axi_write(base_addr + (i * (DATA_WIDTH/8)), data_array[i], timeout);
    end
  endtask

  // Bulk read - read multiple consecutive registers
  task automatic axi_bulk_read(
    input  logic [ADDR_WIDTH-1:0]  base_addr,
    output logic [DATA_WIDTH-1:0]  data_array [],
    input  int                      num_regs,
    input  int                     timeout = 100
  );
    data_array = new[num_regs];
    for (int i = 0; i < num_regs; i++) begin
      axi_read(base_addr + (i * (DATA_WIDTH/8)), data_array[i], timeout);
    end
  endtask

  // Reset task - initialize all signals to default state
  task automatic reset();
    awaddr   = '0;
    awvalid  = 1'b0;
    awprot   = 3'b000;

    wdata    = '0;
    wstrb    = '0;
    wvalid   = 1'b0;

    bready   = 1'b0;

    araddr   = '0;
    arvalid  = 1'b0;
    arprot   = 3'b000;

    rready   = 1'b0;

    // Wait for reset to be deasserted
    if (aresetn === 1'b0) begin
      wait(aresetn === 1'b1);
    end

    @(posedge aclk);
  endtask

  // Wait for idle state - all channels idle
  task automatic wait_idle(int timeout = 100);
    int cycles_wait = 0;

    while ((awvalid || wvalid || arvalid || bready || rready) && cycles_wait < timeout) begin
      @(posedge aclk);
      cycles_wait++;
    end

    if (cycles_wait >= timeout) begin
      $warning("[%0t] AXI Interface not idle after timeout", $time);
    end
  endtask

      endinterface

      // Using the new tasks
      //module tb;
      //  logic aclk = 0;
      //  logic aresetn;
      //
      //  axi4_lite_if #(.DATA_WIDTH(32), .ADDR_WIDTH(8)) s_axi(aclk, aresetn);
      //
      //  initial begin
      //    // Reset
      //    aresetn = 0;
      //    s_axi.reset();
      //    #100 aresetn = 1;
      //
      //    // Writing with timeout
      //    s_axi.axi_write(8'h00, 32'h00000001); // Enable
      //    s_axi.axi_write(8'h04, 32'h00000001); // sel
      //    s_axi.axi_write(8'h08, 32'h00000001); // op_sel
      //
      //    // Reading
      //    logic [31:0] read_data;
      //    s_axi.axi_read(8'h00, read_data);
      //
      //    // Bulk operations
      //    logic [31:0] data_array[4];
      //    data_array = '{32'hA, 32'hB, 32'hC, 32'hD};
      //    s_axi.axi_bulk_write(8'h10, data_array);
      //
      //    logic [31:0] read_array[];
      //    s_axi.axi_bulk_read(8'h10, read_array, 4);
      //  end
      //
      //  always #5 aclk = ~aclk; // 100MHz clock
      //endmodule
