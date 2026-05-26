module sync_nxm#(
    parameter int N = 2,  // number of stages
    parameter int M = 8   // data width
  )(
    input logic          i_clk,
    input logic          i_rstn,
    input logic  [M-1:0] i_d,
    output logic [M-1:0] o_d
  );

  logic [M-1:0] d_r [N];
  logic [M-1:0] d_n [N];

  // ASYNC_REG attribute for proper CDC placement (Vivado)
  (* ASYNC_REG = "TRUE" *) logic [M-1:0] d_r_async [N];
  assign d_r_async = d_r;

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

  if (N == 1)
  begin
    assign d_n[0] = i_d;
  end
  else
  begin
    always_comb
    begin
      d_n[0] = i_d;
      for (int i = 1; i < N; i++)
      begin
        d_n[i] = d_r[i-1];
      end
    end
  end

  assign o_d = d_r[N-1];

endmodule
