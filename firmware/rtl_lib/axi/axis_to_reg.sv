`timescale 1ns/1ps

/**
 * @module axis_to_reg
 * @brief Simple AXI‑Stream receiver that stores the latest data word.
 *
 * @description
 *   This module implements a minimal AXI‑Stream slave that:
 *   * Accepts a data word of width **B** (default 16 bits) when *tvalid* is asserted.
 *   * Always asserts *tready* (`1`) → the master can always send data.
 *   * Stores the received word in a one‑cycle‑deep register (`data_r`).
 *   * Presents the registered value on the output port **dout**.
 *
 *   The design has a **latency of one clock cycle** from the moment the input
 *   data is captured (`tvalid` high) to when it appears on **dout**.
 *
 *   No flow‑control logic beyond the constant *tready* is required; therefore,
 *   this block is typically used in test‑bench environments or in pipelines
 *   where back‑pressure is not needed.
 *
 * @generic
 *   B : integer = 16
 *       Width of the AXI‑Stream data bus (must be >0).
 *
 * @port
 *   input  logic                 clk        : Clock.
 *   input  logic                 rstn       : Active‑low synchronous reset.
 *   input  logic [B-1:0]         s_axis_tdata : AXI‑Stream data.
 *   input  logic                 s_axis_tvalid: Data valid flag from master.
 *   output logic                 s_axis_tready: Ready flag (always 1).
 *   output logic [B-1:0]         dout       : Registered output data.
 */
module axis_to_reg #(
    parameter int B = 16
) (
    input  logic                 clk,
    input  logic                 rstn,
    axi4_stream_if               s_axis,
    output logic [B-1:0]         dout
);

    // --------------------------------------------------------------------
    // 1.  Internal register that holds the most recent data word
    // --------------------------------------------------------------------
    logic [B-1:0] data_r;

    // --------------------------------------------------------------------
    // 2.  Capture data on rising edge when tvalid = 1
    // --------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rstn) begin
            data_r <= '0;               // Reset to zero
        end else if (s_axis.tvalid) begin
            data_r <= s_axis.tdata;    // Latch incoming word
        end
    end

    // --------------------------------------------------------------------
    // 3.  AXI‑Stream handshake (always ready) and output assignment
    // --------------------------------------------------------------------
    assign s_axis.tready = 1'b1;   // Slave never stalls the master
    assign dout          = data_r; // Registered data appears one cycle later

endmodule : axis_to_reg

