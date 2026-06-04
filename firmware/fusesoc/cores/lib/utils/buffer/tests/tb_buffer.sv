module tb();

  // Memory depth.
  parameter N = 10;

  // Number of bits.
  parameter B = 16;

  // Ports.
  reg					    rstn;
  reg					    clk;

  reg					    trigger_i;

  wire	[2*B-1:0]	din_i;

  wire				    mem_we_o;
  wire	[N-1:0]		mem_addr_o;
  wire 	[2*B-1:0]	mem_di_o;

  reg					    start_reg;
  reg		[N-1:0]		addr_reg;
  reg		[N-1:0]		len_reg;

  // Input data.
  reg		[B-1:0]		di_r,dq_r;

    // -------------------------------------------------------------------------
    // Waveform dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_buffer.vcd");
        $dumpvars();
    end

  // DUT.
  buffer#(
          .N	(N),
          .B	(B)
        )DUT(
          // Reset and clock.
          .rstn		(rstn		),
          .clk		(clk		),

          // Trigger input.
          .trigger_i	(trigger_i	),

          // Data input.
          .din_i		(din_i		),

          // Memory interface.
          .mem_we_o	(mem_we_o	),
          .mem_addr_o	(mem_addr_o	),
          .mem_di_o	(mem_di_o	),

          // Registers.
          .start_reg	(start_reg	),
          .addr_reg	(addr_reg	),
          .len_reg	(len_reg	)
        );

  assign din_i = {dq_r,di_r};

  initial
  begin
    rstn		<= 0;
    trigger_i	<= 0;
    di_r		<= 0;
    dq_r		<= 0;
    start_reg	<= 0;
    addr_reg	<= 0;
    len_reg		<= 0;
    #200;
    rstn		<= 1;

    #200;

    @(posedge clk);
    addr_reg	<= 0;
    len_reg		<= 10;

    #200;

    @(posedge clk);
    start_reg	<= 1;

    #1000;

    for (int i=0; i<10; i = i + 1)
    begin
      @(posedge clk);
      di_r		<= 2*i;
      dq_r		<= -5*i;
      trigger_i	<= 1;
      @(posedge clk);
      trigger_i	<= 0;

      #1000;
    end

    @(posedge clk);
    start_reg	<= 0;

    #1000;

    @(posedge clk);
    addr_reg	<= 10;
    len_reg		<= 100;

    @(posedge clk);
    start_reg	<= 1;
    di_r		<= 234;
    dq_r		<= -123;

    @(posedge clk);
    trigger_i	<= 1;
    @(posedge clk);
    trigger_i	<= 0;

    #10000;
  end

  always
  begin
    clk <= 0;
    #5;
    clk <= 1;
    #5;
  end

endmodule

