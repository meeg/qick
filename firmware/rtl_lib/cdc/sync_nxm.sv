///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
//
// Fermi National Accelerator Laboratory
//
// Module: sync_nxm.sv
// Project: QICK
// Description: N-stage, M-bit data synchronizer.
// This block is intended to use to sync gray coded vectors.
// NOTE: Do not use with generic vector data, as it may result
// in corrupted re-sync data.
//
// Change history: 04/29/25 - Created by @lharnaldi
//
//////////////////////////////////////////////////////////////////////////
module sync_nxm#(
    parameter int N = 2,  // number of stages
    parameter int M = 8   // data width
  )(
    input logic          i_clk,
    input logic          i_rstn,
    input logic  [M-1:0] i_d,
    output logic [M-1:0] o_d
  );

  // ASYNC_REG attribute for proper CDC placement (Vivado)
  (* ASYNC_REG = "TRUE" *) logic [M-1:0] d_r [N];
  logic [M-1:0] d_n [N];

  always_ff @(posedge i_clk)
  begin
    if (!i_rstn)
    begin
      d_r <= '{default:0};
    end
    else
    begin
      d_r <= d_n;
    end
  end

  always_comb
  begin
    d_n[0] = i_d;
    for (int i = 1; i < N; i++)
    begin
      d_n[i] = d_r[i-1];
    end
  end

  assign o_d = d_r[N-1];

endmodule
