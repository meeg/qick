`timescale 1ns / 1ps

module constant_iq #(
    parameter int IQ_WIDTH = 16, // Number of bits of I/Q
    parameter int NUM_CHANNELS = 4   // Number of parallel outputs
)(
    // AXI-Lite Slave I/F
    input logic s_axi_aclk,
    input logic s_axi_aresetn,
    axi4_lite_if.slave   s_axi,
    // AXIS Master I/F
    input logic m_axis_aclk,
    input logic m_axis_aresetn,
    axi4_stream_if.master m_axis
);

    // localparam for combined IQ width
    localparam int NUM_REGS = 4; // Number of registers (real, imag, we, reserved)

    // Registers
    logic [2*IQ_WIDTH-1:0] slv_regs_o [NUM_REGS];
    wire  [2*IQ_WIDTH-1:0] slv_regs_i [NUM_REGS];
    logic [2*IQ_WIDTH-1:0] real_reg;
    logic [2*IQ_WIDTH-1:0] imag_reg;
    logic           we_reg;

    // Internal signals
    logic we;
    logic we_r;
    logic we_int;
    logic [IQ_WIDTH-1:0] real_r;
    logic [IQ_WIDTH-1:0] imag_r;

    // ==========================================
    // AXI4-Lite Slave Instance
    // ==========================================
    axil_slv #(
        .AXI_DW(32),
        .AXI_AW(6),
        .NUM_REGS(NUM_REGS)
    ) axil_slv_i (
        .s_axi_aclk(s_axi_aclk),
        .s_axi_aresetn(s_axi_aresetn),
        .s_axi_awaddr(s_axi.awaddr),
        .s_axi_awprot(s_axi.awprot),
        .s_axi_awvalid(s_axi.awvalid),
        .s_axi_awready(s_axi.awready),
        .s_axi_wdata(s_axi.wdata),
        .s_axi_wstrb(s_axi.wstrb),
        .s_axi_wvalid(s_axi.wvalid),
        .s_axi_wready(s_axi.wready),
        .s_axi_bresp(s_axi.bresp),
        .s_axi_bvalid(s_axi.bvalid),
        .s_axi_bready(s_axi.bready),
        .s_axi_araddr(s_axi.araddr),
        .s_axi_arprot(s_axi.arprot),
        .s_axi_arvalid(s_axi.arvalid),
        .s_axi_arready(s_axi.arready),
        .s_axi_rdata(s_axi.rdata),
        .s_axi_rresp(s_axi.rresp),
        .s_axi_rvalid(s_axi.rvalid),
        .s_axi_rready(s_axi.rready),
        .o_slv_regs(slv_regs_o),
        .i_slv_regs(slv_regs_i),
        .i_reg_is_readonly({2*IQ_WIDTH{1'b0}}) // All registers are writable
    );

    //simple loopback for registers
    assign slv_regs_i[0] = real_reg;
    assign slv_regs_i[1] = imag_reg;
    assign slv_regs_i[2] = {{2*IQ_WIDTH-1{1'b0}}, we_reg};
    assign slv_regs_i[3] = '0;

    assign real_reg      = slv_regs_o[0][IQ_WIDTH-1:0]; // Extract real part from the register output
    assign imag_reg      = slv_regs_o[1][IQ_WIDTH-1:0]; // Extract imag part from the register output
    assign we_reg        = slv_regs_o[2][0]; // Extract we signal from the register output

    // ==========================================
    // Synchronizer Instance (for we_reg)
    // ==========================================
    sync_nxm #(.N(2), .M(1)) we_reg_sync (
        .i_clk(m_axis_aclk),
        .i_rstn(m_axis_aresetn),
        .i_d(we_reg),
        .o_d(we)
    );

    // ==========================================
    // Synchronizer Logic (Process equivalent)
    // ==========================================
    always_ff @(posedge m_axis_aclk or negedge m_axis_aresetn) begin
        if (!m_axis_aresetn) begin
            we_r <= 1'b0;
            real_r <= {IQ_WIDTH{1'b0}};
            imag_r <= {IQ_WIDTH{1'b0}};
        end else begin
            we_r <= we;
            if (we_int) begin
                real_r <= real_reg[IQ_WIDTH-1:0];
                imag_r <= imag_reg[IQ_WIDTH-1:0];
            end
        end
    end

    // ==========================================
    // we generation (Edge detection)
    // ==========================================
    assign we_int = ~we_r & we;

    // ==========================================
    // Output Generation (for m_axis_tdata)
    // ==========================================
    generate
        for (genvar i = 0; i < NUM_CHANNELS; i++) begin : gen_out
            assign m_axis.tdata[IQ_WIDTH + 2*IQ_WIDTH*i - 1 : 2*IQ_WIDTH*i] = real_r;
            assign m_axis.tdata[2*IQ_WIDTH + 2*IQ_WIDTH*i - 1 : 2*IQ_WIDTH*i + IQ_WIDTH] = imag_r;
        end
    endgenerate

    // ==========================================
    // Output Assignment
    // ==========================================
    //Add a register to enable tvalid only after the first write to ensure stable data on the bus
    logic stream_valid_r;
    always_ff @(posedge m_axis_aclk or negedge m_axis_aresetn) begin
        if (!m_axis_aresetn) begin
            stream_valid_r <= 1'b0;
        end else if (we_int) begin
            stream_valid_r <= 1'b1; // Set tvalid high after the first write
        end
    end
    assign m_axis.tvalid = stream_valid_r;
    assign m_axis.tlast = 1'b0; // Always 0 since we are streaming constant data

endmodule
