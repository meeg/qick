module axis_tb_driver;

  // ------------------------------------------------------------
  // AXIS transmit
  // ------------------------------------------------------------
  task automatic axis_tx(
    ref axi4_stream_if axis,
    input logic [axis.N_BYTES_TDATA*8-1:0] data,
    input int unsigned TIMEOUT = 1000
  );
    int unsigned cycles = 0;

    axis.s_cb.tdata  <= data;
    axis.s_cb.tvalid <= 1'b1;

    do begin
      @(axis.s_cb);
      cycles++;
      if (cycles >= TIMEOUT)
        $fatal(1, "AXIS TX TIMEOUT");
    end while (!axis.s_cb.tready);

    @(axis.s_cb);
    axis.s_cb.tvalid <= 1'b0;
    axis.s_cb.tdata  <= '0;
  endtask


  // ------------------------------------------------------------
  // AXIS receive
  // ------------------------------------------------------------
  task automatic axis_rx(
    ref axi4_stream_if axis,
    output logic [axis.N_BYTES_TDATA*8-1:0] data,
    input int unsigned TIMEOUT = 1000
  );
    int unsigned cycles = 0;

    axis.m_cb.tready <= 1'b1;

    do begin
      @(axis.m_cb);
      cycles++;
      if (cycles >= TIMEOUT)
        $fatal(1, "AXIS RX TIMEOUT");
    end while (!axis.m_cb.tvalid);

    data = axis.m_cb.tdata;

    @(axis.m_cb);
    axis.m_cb.tready <= 1'b0;
  endtask

endmodule

