`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// axis_set_reg
// -----------------------------------------------------------------------------
// Simple register that captures AXI‑Stream slave data when tvalid is high.
// The module always asserts tready = 1, i.e. it never back‑pressures the master.
// -----------------------------------------------------------------------------
// Parameters
//   DATA_WIDTH – Width of the AXI‑Stream data bus (default = 16)
// -----------------------------------------------------------------------------
// Ports
//   s_axis_aclk    – AXI‑Stream clock
//   s_axis_aresetn – Synchronous reset, active low
//   s_axis_tready  – Slave ready (always '1')
//   s_axis_tdata   – Data input
//   s_axis_tstrb   – Byte strobe (present for completeness, not used)
//   s_axis_tlast   – End‑of‑packet flag (present for completeness, not used)
//   s_axis_tvalid  – Data valid flag
//   dout           – Registered output data
// -----------------------------------------------------------------------------
// Author:   @lharnaldi
// Date:     05/01/2023 (creation date)
// -----------------------------------------------------------------------------
// Copyright: Fermi National Accelerator Laboratory (FNAL)
//
module axis_set_reg #(
    parameter int DATA_WIDTH = 16               // Data bus width
  ) (
    // AXI‑Stream slave interface
    input  logic                     s_axis_aclk,      // clock
    input  logic                     s_axis_aresetn,   // active‑low reset
    output logic                     s_axis_tready,    // always ready
    input  logic [DATA_WIDTH-1:0]    s_axis_tdata,     // data word
    input  logic [(DATA_WIDTH/8)-1:0] s_axis_tstrb,    // byte‑enable (unused)
    input  logic                     s_axis_tlast,     // last beat (unused)
    input  logic                     s_axis_tvalid,    // data valid
    // Registered output
    output logic [DATA_WIDTH-1:0]    dout              // registered data
  );

  // -------------------------------------------------------------------------
  // Internal register that stores the last captured data word
  // -------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] dout_r;

  // -------------------------------------------------------------------------
  // Sequential logic: on every rising clock edge capture s_axis_tdata
  // when tvalid is asserted. Reset clears the register.
  // -------------------------------------------------------------------------
  always_ff @(posedge s_axis_aclk)
  begin
    if (!s_axis_aresetn)
    begin
      dout_r <= '0;                     // wide zero reset
    end
    else if (s_axis_tvalid)
    begin
      dout_r <= s_axis_tdata;           // latch new data
    end
    // else: retain previous value
  end

  // -------------------------------------------------------------------------
  // The slave is always ready to accept data; no back‑pressure logic required.
  // -------------------------------------------------------------------------
  assign s_axis_tready = 1'b1;

  // -------------------------------------------------------------------------
  // Drive the output port with the registered data.
  // -------------------------------------------------------------------------
  assign dout = dout_r;

endmodule
