`timescale 1ns / 1ps

module axis_constant_iq #(
    parameter int B = 16, // Number of bits of I/Q
    parameter int N = 4   // Number of parallel outputs
)(
    // AXI-Lite Slave I/F
    axi4_lite_if   s_axi,
    // AXIS Master I/F
    axi4_stream_if m_axis
);

    // localparam for combined IQ width
    localparam int BIQ = 2 * B;
    localparam int NUM_REGS = 4; // Number of registers (real, imag, we, reserved)

    // Registers
    logic [BIQ-1:0] slv_regs_o [NUM_REGS];
    wire  [BIQ-1:0] slv_regs_i [NUM_REGS];
    logic [BIQ-1:0] real_reg;
    logic [BIQ-1:0] imag_reg;
    logic           we_reg;

    // Internal signals
    logic we;
    logic we_r;
    logic we_int;
    logic [B-1:0] real_r;
    logic [B-1:0] imag_r;

    // ==========================================
    // AXI4-Lite Slave Instance
    // ==========================================
    axil_slv #(
        .AXI_DW(32),
        .AXI_AW(6),
        .NUM_REGS(NUM_REGS)
    ) axil_slv_i (
        .s_axi_aclk(s_axi.aclk),
        .s_axi_aresetn(s_axi.aresetn),
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
        .i_reg_is_readonly({BIQ{1'b0}}) // All registers are writable
    );

    //simple loopback for registers
    assign slv_regs_i[0] = real_reg;
    assign slv_regs_i[1] = imag_reg;
    assign slv_regs_i[2] = {{BIQ-1{1'b0}}, we_reg};

    assign real_reg      = slv_regs_o[0][B-1:0]; // Extract real part from the register output
    assign imag_reg      = slv_regs_o[1][B-1:0]; // Extract imag part from the register output
    assign we_reg        = slv_regs_o[2][0]; // Extract we signal from the register output

    // ==========================================
    // Synchronizer Instance (for we_reg)
    // ==========================================
    sync_nxm #(.N(2), .M(1)) we_reg_sync (
        .i_clk(m_axis.i_clk),
        .i_rstn(m_axis.i_rstn),
        .i_d(we_reg),
        .o_d(we)
    );

    // ==========================================
    // Synchronizer Logic (Process equivalent)
    // ==========================================
    always_ff @(posedge m_axis.i_clk or negedge m_axis.i_rstn) begin
        if (!m_axis.i_rstn) begin
            we_r <= 1'b0;
            real_r <= {B{1'b0}};
            imag_r <= {B{1'b0}};
        end else begin
            we_r <= we;
            if (we_int) begin
                real_r <= real_reg[B-1:0];
                imag_r <= imag_reg[B-1:0];
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
        for (genvar i = 0; i < N; i++) begin : gen_out
            assign m_axis.tdata[B + BIQ*i - 1 : BIQ*i] = real_r;
            assign m_axis.tdata[2*B + BIQ*i - 1 : BIQ*i + B] = imag_r;
        end
    endgenerate

    // ==========================================
    // Output Assignment
    // ==========================================
    //Add a register to enable tvalid only after the first write to ensure stable data on the bus
    logic stream_valid_r;
    always_ff @(posedge m_axis.i_clk or negedge m_axis.i_rstn) begin
        if (!m_axis.i_rstn) begin
            stream_valid_r <= 1'b0;
        end else if (we_int) begin
            stream_valid_r <= 1'b1; // Set tvalid high after the first write
        end
    end
    assign m_axis.tvalid = stream_valid_r;

endmodule
