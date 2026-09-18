`timescale 1ns/1ps

module dma_engine (
    input  wire        CLK,
    input  wire        RSTN,

    input  wire        start,
    input  wire [31:0] src_addr,
    input  wire [31:0] dst_addr,
    input  wire [31:0] transfer_bytes,
    input  wire [7:0]  cfg_burst_beats,
    input  wire [1:0]  cfg_rd_out_limit,
    input  wire [1:0]  cfg_wr_out_limit,

    output wire        busy,
    output reg         done,
    output wire        error,
    output wire        read_busy,
    output wire        write_busy,
    output wire [31:0] read_beats,
    output wire [31:0] write_beats,

    // Stream from RDMA
    output wire [63:0] out_data,
    output wire        out_valid,
    input  wire        out_ready,
    output wire        out_last,

    // Stream to WDMA
    input  wire [63:0] in_data,
    input  wire        in_valid,
    output wire        in_ready,

    // AXI4 read address channel
    output wire [31:0] M_AXI_ARADDR,
    output wire [7:0]  M_AXI_ARLEN,
    output wire [2:0]  M_AXI_ARSIZE,
    output wire [1:0]  M_AXI_ARBURST,
    output wire        M_AXI_ARVALID,
    input  wire        M_AXI_ARREADY,

    // AXI4 read data channel
    input  wire [63:0] M_AXI_RDATA,
    input  wire [1:0]  M_AXI_RRESP,
    input  wire        M_AXI_RLAST,
    input  wire        M_AXI_RVALID,
    output wire        M_AXI_RREADY,

    // AXI4 write address channel
    output wire [31:0] M_AXI_AWADDR,
    output wire [7:0]  M_AXI_AWLEN,
    output wire [2:0]  M_AXI_AWSIZE,
    output wire [1:0]  M_AXI_AWBURST,
    output wire        M_AXI_AWVALID,
    input  wire        M_AXI_AWREADY,

    // AXI4 write data channel
    output wire [63:0] M_AXI_WDATA,
    output wire [7:0]  M_AXI_WSTRB,
    output wire        M_AXI_WLAST,
    output wire        M_AXI_WVALID,
    input  wire        M_AXI_WREADY,

    // AXI4 write response channel
    input  wire [1:0]  M_AXI_BRESP,
    input  wire        M_AXI_BVALID,
    output wire        M_AXI_BREADY
);

reg  run;
reg  start_error_reg;

wire start_error;
wire start_accept;
wire rdma_done;
wire wdma_done;
wire rdma_error;
wire wdma_error;

assign start_error = (src_addr[2:0] != 3'b000) || (dst_addr[2:0] != 3'b000) || (transfer_bytes == 32'd0) || (transfer_bytes[2:0] != 3'b000);

assign start_accept = start && !run && !start_error;

assign busy  = run;
assign error = start_error_reg || rdma_error || wdma_error;

// Overall DMA run flag
always @(posedge CLK) begin
    if (!RSTN)
        run <= 1'b0;
    else if (start_accept)
        run <= 1'b1;
    else if (wdma_done)
        run <= 1'b0;
end

// One-cycle done signal
always @(posedge CLK) begin
    if (!RSTN)
        done <= 1'b0;
    else begin
        done <= 1'b0;

        if (start && !run && start_error)
            done <= 1'b1;
        else if (wdma_done)
            done <= 1'b1;
    end
end

// Start error
always @(posedge CLK) begin
    if (!RSTN)
        start_error_reg <= 1'b0;
    else if (start && !run)
        start_error_reg <= start_error;
end

rdma u_rdma (
    .CLK(CLK),
    .RSTN(RSTN),

    .src_addr(src_addr),
    .transfer_bytes(transfer_bytes),
    .cfg_burst_beats(cfg_burst_beats),
    .cfg_rd_out_limit(cfg_rd_out_limit),

    .start(start_accept),
    .busy(read_busy),
    .done(rdma_done),
    .error(rdma_error),
    .read_beats(read_beats),

    .M_AXI_ARADDR(M_AXI_ARADDR),
    .M_AXI_ARLEN(M_AXI_ARLEN),
    .M_AXI_ARSIZE(M_AXI_ARSIZE),
    .M_AXI_ARBURST(M_AXI_ARBURST),
    .M_AXI_ARVALID(M_AXI_ARVALID),
    .M_AXI_ARREADY(M_AXI_ARREADY),

    .M_AXI_RDATA(M_AXI_RDATA),
    .M_AXI_RRESP(M_AXI_RRESP),
    .M_AXI_RLAST(M_AXI_RLAST),
    .M_AXI_RVALID(M_AXI_RVALID),
    .M_AXI_RREADY(M_AXI_RREADY),

    .out_data(out_data),
    .out_valid(out_valid),
    .out_ready(out_ready),
    .out_last(out_last)
);

wdma u_wdma (
    .CLK(CLK),
    .RSTN(RSTN),

    .dst_addr(dst_addr),
    .transfer_bytes(transfer_bytes),
    .cfg_burst_beats(cfg_burst_beats),
    .cfg_wr_out_limit(cfg_wr_out_limit),

    .start(start_accept),
    .busy(write_busy),
    .done(wdma_done),
    .error(wdma_error),
    .write_beats(write_beats),

    .in_data(in_data),
    .in_valid(in_valid),
    .in_ready(in_ready),

    .M_AXI_AWADDR(M_AXI_AWADDR),
    .M_AXI_AWLEN(M_AXI_AWLEN),
    .M_AXI_AWSIZE(M_AXI_AWSIZE),
    .M_AXI_AWBURST(M_AXI_AWBURST),
    .M_AXI_AWVALID(M_AXI_AWVALID),
    .M_AXI_AWREADY(M_AXI_AWREADY),

    .M_AXI_WDATA(M_AXI_WDATA),
    .M_AXI_WSTRB(M_AXI_WSTRB),
    .M_AXI_WLAST(M_AXI_WLAST),
    .M_AXI_WVALID(M_AXI_WVALID),
    .M_AXI_WREADY(M_AXI_WREADY),

    .M_AXI_BRESP(M_AXI_BRESP),
    .M_AXI_BVALID(M_AXI_BVALID),
    .M_AXI_BREADY(M_AXI_BREADY)
);

endmodule
