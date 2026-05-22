module axis_data_concat #(
  parameter int NB_IN  = 16,
  parameter int NB_OFF = 16
)(
  input  logic i_clk,
  input  logic i_rstn,

  axi4_stream_if.slave  s_axis,
  axi4_stream_if.master m_axis,

  input logic [NB_OFF-1:0] i_offset
);

  // Handshake passes straight through
  assign m_axis.tvalid = s_axis.tvalid;
  assign s_axis.tready = m_axis.tready;

  // Payload transform
  assign m_axis.tdata  = {i_offset, s_axis.tdata};
  assign m_axis.tlast  = s_axis.tlast;

endmodule
