`SVTEST(test00_reset_test)
    repeat(10) @(posedge tb_clk);
    tb_rst <= 1'b1;
    repeat(1) @(posedge tb_clk);
    tb_rst <= 1'b0;
    repeat(10) @(posedge tb_clk);

    for (integer i = 0; i < 10; i = i + 1) begin
        `ASSERT_IMMEDIATE(axis_out_if.tvalid == 1'b0);
        `ASSERT_IMMEDIATE(axis_in_if.tready == 1'b1);

        axis_in_if.tdata <= $urandom();

        @(axis_in_if.m_cb);
        axis_in_if.tvalid <= 1'b1;
        while (axis_in_if.m_cb.tready == 1'b0) begin
            @(axis_in_if.m_cb);
        end
        @(axis_in_if.m_cb);
        axis_in_if.tvalid <= 1'b0;
        repeat(5) @(posedge tb_clk);

        `ASSERT_IMMEDIATE(axis_out_if.tvalid == 1'b0);
        `ASSERT_IMMEDIATE(axis_in_if.tready == 1'b1);

        tb_rst <= 1'b1;
        repeat(1) @(posedge tb_clk);
        tb_rst <= 1'b0;
        repeat(10) @(posedge tb_clk);
    end
`SVTEST_END

`SVTEST(test01_data_sanity_check)
    axis_out_if.tready = 1'b1;

    for (integer k = 0; k < 100; k = k + 1) begin
        data_payload = $urandom();
        axis_in_if.tdata  <= data_payload;

        @(axis_in_if.m_cb);
        axis_in_if.tvalid <= 1'b1;
        while (axis_in_if.m_cb.tready == 1'b0) begin
            @(axis_in_if.m_cb);
        end
        axis_in_if.tvalid <= 1'b0;

        @(axis_out_if.s_cb);
        if (axis_out_if.s_cb.tvalid !== 1'b1) begin
            `FAIL_IF_LOG(1, $sformatf("test01: tvalid never rose for k=%0d", k));
        end
        `ASSERT_IMMEDIATE(axis_out_if.s_cb.tdata == data_payload)
    end
`SVTEST_END

`SVTEST(test02_full_throughput_data_sanity_check)
    axis_out_if.tready = 1'b1;
    axis_in_if.tvalid  = 1'b1;
    fork
        begin
            for (integer k = 0; k < 100; k = k + 1) begin
                data_payload = $urandom();
                axis_in_if.tdata  <= data_payload;
                data_payload_queue.push_front(data_payload);
                @(axis_in_if.m_cb);
            end
        end
        begin
            for (integer l = 0; l < 100; l = l + 1) begin
                @(axis_out_if.s_cb);
                if (axis_out_if.s_cb.tvalid) begin
                    `ASSERT_IMMEDIATE(axis_out_if.s_cb.tdata == data_payload_queue.pop_back())
                end
            end
        end
    join
`SVTEST_END

`SVTEST(test03_throttle_test)
    axis_out_if.tready = 1'b1;
    axis_in_if.tvalid  = 1'b1;
    fork
        begin
            for (integer k = 0; k < 100; k = k + 1) begin
                data_payload = $urandom();
                axis_in_if.tdata  <= data_payload;
                @(axis_in_if.m_cb);
                axis_in_if.tvalid <= $urandom();
                if (axis_in_if.tready && axis_in_if.tvalid) begin
                    data_payload_queue.push_front(data_payload);
                end
            end
        end
        begin
            for (integer l = 0; l < 100; l = l + 1) begin
                @(axis_out_if.s_cb);
                if (axis_out_if.s_cb.tvalid && axis_out_if.tready) begin
                    `ASSERT_IMMEDIATE(axis_out_if.s_cb.tdata == data_payload_queue.pop_back())
                end
                axis_out_if.tready <= $urandom();
            end
        end
    join
`SVTEST_END

`SVTEST(test04_recovery)
    data_payload = $urandom();
    axis_in_if.tdata <= data_payload;
    axis_in_if.tvalid <= 1'b1;

    while (axis_in_if.tready == 1'b1) begin
        @(posedge tb_clk);
    end
    `ASSERT_IMMEDIATE(axis_in_if.tready == 1'b0);

    axis_out_if.tready <= 1'b1;

    while (axis_in_if.tready == 1'b0) begin
        @(posedge tb_clk);
    end
    axis_in_if.tvalid <= 1'b0;

    while (axis_out_if.tvalid != 1'b1) begin
        @(axis_out_if.s_cb);
    end
    `ASSERT_IMMEDIATE(axis_out_if.tvalid == 1'b1);

    repeat(20) @(posedge tb_clk);

    for (integer k = 0; k < 100; k = k + 1) begin
        data_payload = $urandom();
        axis_in_if.tdata <= data_payload;

        @(axis_in_if.m_cb);
        axis_in_if.tvalid <= 1'b1;
        while (axis_in_if.tready == 1'b0) begin
            @(axis_in_if.m_cb);
        end
        @(axis_in_if.m_cb);
        axis_in_if.tvalid <= 1'b0;

        while (axis_out_if.tvalid == 1'b0) begin
            @(axis_out_if.s_cb);
        end;
    end
`SVTEST_END

`SVTEST(test04_fifo_overflow_and_recovery)
    int timeout;
    int seed = 12345;
    logic [31:0] data_in, data_out;

    axis_in_if.tvalid <= 1'b1;
    timeout = 1000;

    fork
        begin
            while (axis_in_if.tready == 1'b1) begin
                data_in = $urandom(seed);
                axis_in_if.tdata <= data_in;
                @(posedge tb_clk);
            end
        end
        begin
            repeat(timeout) @(posedge tb_clk);
            `FAIL_IF_LOG(1, "Timeout: tready never dropped");
        end
    join_any
    disable fork;

    `FAIL_UNLESS_LOG(axis_in_if.tready == 1'b0, "FIFO should be full");

    axis_out_if.tready = 1'b1;

    timeout = 1000;
    fork
        begin
            while (axis_in_if.tready == 1'b0) begin
                @(posedge tb_clk);
            end
            @(posedge tb_clk);
            axis_in_if.tvalid = 1'b0;
        end
        begin
            repeat(timeout) @(posedge tb_clk);
            `FAIL_IF_LOG(1, "Timeout: FIFO never recovered");
        end
    join_any
    disable fork;

    `FAIL_UNLESS_LOG(axis_in_if.tready == 1'b1, "FIFO should accept data again");

    repeat (100) begin
        data_in = $urandom(seed);
        axis_in_if.tdata <= data_in;
        axis_in_if.tvalid <= 1'b1;

        timeout = 100;
        fork
            begin
                while (axis_in_if.tready == 1'b0) @(posedge tb_clk);
            end
            begin
                repeat(timeout) @(posedge tb_clk);
                `FAIL_IF_LOG(1, "Timeout: data not accepted");
            end
        join_any
        disable fork;

        axis_in_if.tvalid <= 1'b0;

        timeout = 100;
        fork
            begin
                while (axis_out_if.tvalid == 1'b0) @(axis_out_if.s_cb);
            end
            begin
                repeat(timeout) @(axis_out_if.s_cb);
                `FAIL_IF_LOG(1, "Timeout: no output data");
            end
        join_any
        disable fork;

        data_out = axis_out_if.s_cb.tdata;
        `FAIL_UNLESS_LOG(data_out == data_in, $sformatf("Data mismatch: sent 0x%0h, got 0x%0h", data_in, data_out));
    end

    axis_out_if.tready <= 1'b0;
    repeat(10) @(posedge tb_clk);
`SVTEST_END
