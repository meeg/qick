
`include "svunit_defines.svh"
`include "svunit_assert_macros.svh"

module axis_skid_buffer_unit_test;
  import svunit_pkg::svunit_testcase;

  string name = "axis_skid_buffer_00_ut";
  svunit_testcase svunit_ut;

  // This is for utilize GTKwave to view the waveforms
  initial begin
    $dumpfile("skid_buffer.vcd");
    $dumpvars();
  end

  localparam CLOCK_FREQUENCY = 100e6; //[Hz]
  localparam PACKETS  = 7000;
  localparam NB_DATA  = 8;
  localparam TIME_OUT = 100;

  logic [NB_DATA-1:0]     vector_tdata_in [PACKETS-1:0];
  logic [NB_DATA-1:0]     random_data;
  logic [NB_DATA/8-1:0]   vector_tstrb_in [PACKETS-1:0];
  logic [NB_DATA/8-1:0]   vector_tkeep_in [PACKETS-1:0];
  logic [NB_DATA/8-1:0]   vector_tuser_in [PACKETS-1:0];

  logic               tb_clk = 1'b0;
  logic               tb_rstn = 1'b0;

  // Interface to drive the input signals
  axi4_stream_if#(
    .N_BYTES_TDATA  ($ceil(NB_DATA/8.0)),
    .HAS_TUSER      (1'b1),
    .HAS_TKEEP      (1'b1),
    .HAS_TSTRB      (1'b1)
  ) axis_input_if (
    .i_clk          (tb_clk), 
    .i_rstn         (tb_rstn)
  );

  // Interface to monitor the output signals
  axi4_stream_if#(
    .N_BYTES_TDATA  ($ceil(NB_DATA/8.0)),
    .HAS_TUSER      (1'b1),
    .HAS_TKEEP      (1'b1),
    .HAS_TSTRB      (1'b1)
  ) axis_output_if (
    .i_clk          (tb_clk), 
    .i_rstn         (tb_rstn)
  );

  // Clock generator
  clk_gen #(
    .FREQ       (CLOCK_FREQUENCY)
  ) u_clk_gen (
    .i_enable   (1'b1           ),
    .o_clk      (tb_clk         )
  );

  // DUT - Skid Buffer
  axis_skid_buffer #(
    .NB_DATA    (NB_DATA       )
  ) u_skid_buffer (
    .i_clk      (tb_clk        ),
    .i_rstn     (tb_rstn       ),
    .i_axis     (axis_input_if ),
    .o_axis     (axis_output_if)
  );

  // Build
  function void build();
    svunit_ut = new(name);
  endfunction

  // Setup task
  task setup();
    svunit_ut.setup();

    // Random data generation
    @(negedge tb_clk);
    for(int j=0; j<PACKETS; j=j+1) begin
      random_data = $urandom_range(0, 2**NB_DATA-1);
      vector_tdata_in[j] <= random_data;
      vector_tkeep_in[j] <= $urandom_range(0,NB_DATA/8);
      vector_tstrb_in[j] <= $urandom_range(0,NB_DATA/8);
      vector_tuser_in[j] <= $urandom_range(0,NB_DATA/8);
    end

    // Setting the principal signals
    axis_input_if.tdata     <= vector_tdata_in[0];
    axis_input_if.tvalid    <= 1'b0;

    // Setting optional signals to default value
    axis_input_if.tlast     <= 1'b0;
    axis_input_if.tstrb     <= {$ceil(NB_DATA/8.0){1'b0}};
    axis_input_if.tkeep     <= {$ceil(NB_DATA/8.0){1'b1}};
    axis_input_if.tuser     <= {$ceil(NB_DATA/8.0){1'b0}};

    // Consumer NOT ready
    axis_output_if.tready   <=   1'b0;

    // Reset and go
    tb_rstn                  <=   1'b0;
    repeat(5) @(negedge tb_clk);
    tb_rstn                  <=   1'b1;
    repeat(10) @(negedge tb_clk);
  endtask

  // Teardown task
  task teardown();
    svunit_ut.teardown();
  endtask

  integer wait_time;

  typedef struct packed {
    logic [NB_DATA-1:0]     tdata;
    logic [NB_DATA/8-1:0]   tstrb;
    logic [NB_DATA/8-1:0]   tkeep;
    logic [NB_DATA/8-1:0]   tuser;
    logic                   tlast;
  } axis_beat_t;

  axis_beat_t exp_q[$];


  // This task writes a random number of data packets
  task axis_write_frame;
    int i;
    int packets;
    axis_beat_t beat;

    begin
      packets = $urandom_range(PACKETS/2, PACKETS);

      axis_input_if.tvalid <= 1'b1;

      i = 0;
      while (i < packets || exp_q.size() != 0) begin

        // -----------------------
        // DRIVE INPUT
        // -----------------------
        if (i < packets) begin
          axis_input_if.tdata <= vector_tdata_in[i];
          axis_input_if.tstrb <= vector_tstrb_in[i];
          axis_input_if.tkeep <= vector_tkeep_in[i];
          axis_input_if.tuser <= vector_tuser_in[i];
          axis_input_if.tlast <= (i == packets-1);
        end else begin
          axis_input_if.tvalid <= 1'b0;
        end

        @(negedge tb_clk);

        // Input handshake → push expected data
        if (axis_input_if.tvalid && axis_input_if.tready) begin
          beat.tdata = axis_input_if.tdata;
          beat.tstrb = axis_input_if.tstrb;
          beat.tkeep = axis_input_if.tkeep;
          beat.tuser = axis_input_if.tuser;
          beat.tlast = axis_input_if.tlast;
          exp_q.push_back(beat);
          i++;
        end

        // -----------------------
        // CHECK OUTPUT
        // -----------------------
        if (axis_output_if.tvalid && axis_output_if.tready) begin
          beat = exp_q.pop_front();

          `ASSERT_IMMEDIATE(axis_output_if.tdata == beat.tdata);
          `ASSERT_IMMEDIATE(axis_output_if.tstrb == beat.tstrb);
          `ASSERT_IMMEDIATE(axis_output_if.tkeep == beat.tkeep);
          `ASSERT_IMMEDIATE(axis_output_if.tuser == beat.tuser);
          `ASSERT_IMMEDIATE(axis_output_if.tlast == beat.tlast);
        end
      end

      axis_input_if.tvalid <= 1'b0;
      axis_input_if.tlast  <= 1'b0;
    end
  endtask


  // =============================================
  // This task controls the slave's TREADY signal. 
  task axis_read;

    begin
      axis_output_if.tready <= 1;
            while(axis_output_if.tvalid == 0) @(negedge tb_clk);
            while(axis_output_if.tvalid == 1) @(negedge tb_clk);
      @ (negedge tb_clk);
      axis_output_if.tready <= 0;
    end
  endtask


  `SVUNIT_TESTS_BEGIN
  `include "tests.sv"
  `SVUNIT_TESTS_END 

endmodule
