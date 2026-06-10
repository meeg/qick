// This is the file you point the IP Packager to.
`timescale 1 ns / 1 ps

module axis_constant_iq #(
    parameter int IQ_WIDTH = 16,
    parameter int NUM_CHANNELS = 4
)(
    // Standard AXI Ports
    input  wire                               s_axis_aclk,
    input  wire                               s_axis_aresetn,
    input  wire [4:0]                         s_axis_awaddr,
    input  wire [2:0]                         s_axis_awprot,
    input  wire                               s_axis_awvalid,
    output wire                               s_axis_awready,
    input  wire [31:0]                        s_axis_wdata,
    input  wire [3:0]                         s_axis_wstrb,
    input  wire                               s_axis_wvalid,
    output wire                               s_axis_wready,
    output wire [1:0]                         s_axis_bresp,
    output wire                               s_axis_bvalid,
    input  wire                               s_axis_bready,
    input  wire [4:0]                         s_axis_araddr,
    input  wire [2:0]                         s_axis_arprot,
    input  wire                               s_axis_arvalid,
    output wire                               s_axis_arready,
    output wire [31:0]                        s_axis_rdata,
    output wire [1:0]                         s_axis_rresp,
    output wire                               s_axis_rvalid,
    input  wire                               s_axis_rready,

    // AXI-Stream Ports
    input  wire                               m_axis_aclk,
    input  wire                               m_axis_aresetn,
    output wire [2*IQ_WIDTH*NUM_CHANNELS-1:0] m_axis_tdata,
    output wire                               m_axis_tvalid,
    output wire                               m_axis_tlast,
    input  wire                               m_axis_tready
);

    // Instantiate the actual interface
    axi4_lite_if #(.DATA_WIDTH(32), .ADDR_WIDTH(6)) s_axi_if(
        .aclk(s_axis_aclk),
        .aresetn(s_axis_aresetn)
    );

    // Connect the wrapper ports to the interface
    assign s_axi_if.awaddr  = s_axis_awaddr;
    assign s_axi_if.awprot  = s_axis_awprot;
    assign s_axi_if.awvalid = s_axis_awvalid;
    assign s_axis_awready   = s_axi_if.awready;
    assign s_axi_if.wdata   = s_axis_wdata;
    assign s_axi_if.wstrb   = s_axis_wstrb;
    assign s_axi_if.wvalid  = s_axis_wvalid;
    assign s_axis_wready    = s_axi_if.wready;
    assign s_axis_rresp     = s_axi_if.bresp;
    assign s_axis_rvalid    = s_axi_if.bvalid;
    assign s_axi_if.bready  = s_axis_bready;
    assign s_axi_if.araddr  = s_axis_araddr;
    assign s_axi_if.arprot  = s_axis_arprot;
    assign s_axi_if.arvalid = s_axis_arvalid;
    assign s_axis_arready   = s_axi_if.arready;
    assign s_axis_rdata     = s_axi_if.rdata;
    assign s_axis_rresp     = s_axi_if.rresp;
    assign s_axis_rvalid    = s_axi_if.rvalid;
    assign s_axi_if.rready  = s_axis_rready;

    // Instantiate the AXI-Stream Interface
    axi4_stream_if #(.tdata_WIDTH(2*IQ_WIDTH*NUM_CHANNELS)) m_axis_if(
        .aclk(m_axis_aclk),
        .aresetn(m_axis_aresetn)
    );

    // Connect the wrapper ports to the interface
    assign m_axis_tdata     = m_axis_if.tdata;
    assign m_axis_tvalid    = m_axis_if.tvalid;
    assign m_axis_tlast     = m_axis_if.tlast;
    assign m_axis_if.tready = m_axis_tready;

    // Instantiate your SystemVerilog module
    constant_iq #(
        .IQ_WIDTH      (IQ_WIDTH),
        .NUM_CHANNELS  (NUM_CHANNELS)
    ) u_axis_constant_iq (
        .s_axi_aclk    (s_axis_aclk),
        .s_axi_aresetn (s_axis_aresetn),
        .s_axi         (s_axi_if),       // Connect the AXI4-Lite interface
        .m_axis_aclk   (m_axis_aclk),
        .m_axis_arstn  (m_axis_aresetn),
        .m_axis        (m_axis_if)       // Connect the AXI-Stream interface
    );

endmodule
