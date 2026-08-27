`SVTEST(test00_fixed_packet_length_test)
    tb_packet_size <= 32'd256;
    axis_out_if.tready <= 1'b1;
    axis_in_if.tvalid <= 1'b0;
    axis_in_if.tdata <= $urandom();

    tb_rst <= 1'b1;
    @(posedge tb_clk);
    tb_rst <= 1'b0;
    repeat(4) @(posedge tb_clk);

    word_counter = '0;
    axis_in_if.tvalid <= 1'b1;
    @(posedge tb_clk);

    while (axis_out_if.tvalid && axis_out_if.tready && !axis_out_if.tlast) begin
        word_counter = word_counter + 1'b1;
        @(posedge tb_clk);
    end
    @(posedge tb_clk);
    `ASSERT_IMMEDIATE(word_counter == tb_packet_size - 1);
    axis_in_if.tvalid <= 1'b0;
`SVTEST_END

`SVTEST(test01_reset_and_variable_packet_length_test)
    axis_out_if.tready <= 1'b1;
    axis_in_if.tvalid <= 1'b0;

    for (integer i = 0; i < 5; i = i + 1) begin
        tb_packet_size <= 32'd100 + i * 10;
        tb_rst <= 1'b1;
        @(posedge tb_clk);
        tb_rst <= 1'b0;
        repeat(4) @(posedge tb_clk);

        word_counter = '0;
        axis_in_if.tvalid <= 1'b1;
        axis_in_if.tdata <= $urandom();
        @(posedge tb_clk);

        while (axis_out_if.tvalid && axis_out_if.tready && !axis_out_if.tlast) begin
            word_counter = word_counter + 1'b1;
            @(posedge tb_clk);
        end
        @(posedge tb_clk);
        `ASSERT_IMMEDIATE(word_counter == tb_packet_size - 1);
        axis_in_if.tvalid <= 1'b0;
        repeat(2) @(posedge tb_clk);
    end
`SVTEST_END

`SVTEST(test02_throttle_test)
    tb_packet_size <= 32'd64;
    axis_in_if.tvalid <= 1'b1;
    axis_in_if.tdata <= $urandom();
    repeat(3) @(posedge tb_clk);

    word_counter = '0;
    while (!(axis_out_if.tvalid && axis_out_if.tready && axis_out_if.tlast)) begin
        axis_out_if.tready <= $urandom_range(0, 1);
        if (axis_out_if.tvalid && axis_out_if.tready) begin
            word_counter = word_counter + 1'b1;
        end
        @(posedge tb_clk);
    end
    @(posedge tb_clk);
    `ASSERT_IMMEDIATE(word_counter == tb_packet_size - 1);
    axis_in_if.tvalid <= 1'b0;
    axis_out_if.tready <= 1'b0;
`SVTEST_END
