`timescale 1ns/1ps

module counters (
    input  wire        CLK,
    input  wire        RSTN,
    input  wire        clear,
    input  wire        active,

    input  wire        arvalid,
    input  wire        arready,
    input  wire        rvalid,
    input  wire        rready,
    input  wire        awvalid,
    input  wire        awready,
    input  wire        wvalid,
    input  wire        wready,
    input  wire        bvalid,
    input  wire        bready,

    input  wire        r_wait_active,
    input  wire        w_wait_active,
    input  wire        r_window_done,
    input  wire        w_window_done,

    output reg  [31:0] stall_ar,
    output reg  [31:0] stall_r,
    output reg  [31:0] stall_aw,
    output reg  [31:0] stall_w,
    output reg  [31:0] stall_b,
    output reg  [31:0] read_txns,
    output reg  [31:0] write_txns,
    output reg  [31:0] r_wait_cycles,
    output reg  [31:0] w_wait_cycles,
    output reg  [31:0] r_windows,
    output reg  [31:0] w_windows
);

wire ar_stall;
wire r_stall;
wire aw_stall;
wire w_stall;
wire b_stall;
wire ar_hs;
wire aw_hs;

assign ar_stall = arvalid && !arready;
assign r_stall  = rvalid  && !rready;
assign aw_stall = awvalid && !awready;
assign w_stall  = wvalid  && !wready;
assign b_stall  = bvalid  && !bready;
assign ar_hs    = arvalid && arready;
assign aw_hs    = awvalid && awready;

// Each counter is cleared for a new DMA command and saturates on overflow.
always @(posedge CLK) begin
    if (!RSTN || clear)
        stall_ar <= 32'd0;
    else if (active && ar_stall && (stall_ar != 32'hFFFF_FFFF))
        stall_ar <= stall_ar + 1'b1;
end

always @(posedge CLK) begin
    if (!RSTN || clear)
        stall_r <= 32'd0;
    else if (active && r_stall && (stall_r != 32'hFFFF_FFFF))
        stall_r <= stall_r + 1'b1;
end

always @(posedge CLK) begin
    if (!RSTN || clear)
        stall_aw <= 32'd0;
    else if (active && aw_stall && (stall_aw != 32'hFFFF_FFFF))
        stall_aw <= stall_aw + 1'b1;
end

always @(posedge CLK) begin
    if (!RSTN || clear)
        stall_w <= 32'd0;
    else if (active && w_stall && (stall_w != 32'hFFFF_FFFF))
        stall_w <= stall_w + 1'b1;
end

always @(posedge CLK) begin
    if (!RSTN || clear)
        stall_b <= 32'd0;
    else if (active && b_stall && (stall_b != 32'hFFFF_FFFF))
        stall_b <= stall_b + 1'b1;
end

always @(posedge CLK) begin
    if (!RSTN || clear)
        read_txns <= 32'd0;
    else if (active && ar_hs && (read_txns != 32'hFFFF_FFFF))
        read_txns <= read_txns + 1'b1;
end

always @(posedge CLK) begin
    if (!RSTN || clear)
        write_txns <= 32'd0;
    else if (active && aw_hs && (write_txns != 32'hFFFF_FFFF))
        write_txns <= write_txns + 1'b1;
end

always @(posedge CLK) begin
    if (!RSTN || clear)
        r_wait_cycles <= 32'd0;
    else if (active && r_wait_active && (r_wait_cycles != 32'hFFFF_FFFF))
        r_wait_cycles <= r_wait_cycles + 1'b1;
end

always @(posedge CLK) begin
    if (!RSTN || clear)
        w_wait_cycles <= 32'd0;
    else if (active && w_wait_active && (w_wait_cycles != 32'hFFFF_FFFF))
        w_wait_cycles <= w_wait_cycles + 1'b1;
end

always @(posedge CLK) begin
    if (!RSTN || clear)
        r_windows <= 32'd0;
    else if (active && r_window_done && (r_windows != 32'hFFFF_FFFF))
        r_windows <= r_windows + 1'b1;
end

always @(posedge CLK) begin
    if (!RSTN || clear)
        w_windows <= 32'd0;
    else if (active && w_window_done && (w_windows != 32'hFFFF_FFFF))
        w_windows <= w_windows + 1'b1;
end

endmodule
