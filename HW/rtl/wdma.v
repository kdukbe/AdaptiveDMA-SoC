`timescale 1ns/1ps

module wdma (
    input  wire        CLK,
    input  wire        RSTN,

    input  wire [31:0] dst_addr,
    input  wire [31:0] transfer_bytes,

    input  wire [7:0]  cfg_burst_beats,
    input  wire [1:0]  cfg_wr_out_limit,

    input  wire        start,
    output wire        busy,
    output wire        done,
    output reg         error,
    output reg  [31:0] write_beats,

    // Input stream
    input  wire [63:0] in_data,
    input  wire        in_valid,
    output wire        in_ready,

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

localparam S_IDLE = 2'd0;
localparam S_RUN  = 2'd1;
localparam S_DONE = 2'd2;

// Main control
reg  [1:0] state;
reg  [1:0] n_state;
wire       start_error;
wire       start_accept;
wire       transfer_done;

// Runtime configuration
reg  [4:0] cfg_burst_value;
reg  [2:0] cfg_out_limit_value;
reg  [4:0] active_burst_beats;
reg  [2:0] active_out_limit;

// AW channel
reg  [31:0] issue_addr;
reg  [31:0] issue_bytes_left;
wire [12:0] bytes_until_4k;
wire [31:0] active_burst_bytes;
wire [31:0] max_limited_bytes;
wire [31:0] next_burst_bytes;
wire [31:0] next_burst_beats;
reg  [7:0]  awlen_value;
wire        final_aw;
wire        aw_hs;
reg  [2:0]  write_pending;

// AW to W FIFO
wire       wfifo_in_ready;
wire       wfifo_out_valid;
wire       wfifo_out_ready;
wire [5:0] wfifo_out_data;
wire       wfifo_out_hs;

// W to B FIFO
wire       bfifo_in_ready;
wire       bfifo_out_valid;
wire       bfifo_out_ready;
wire       bfifo_out_data;
wire       bfifo_out_hs;

// W channel
reg         w_run;
reg  [4:0]  w_burst_beats;
reg  [4:0]  w_beat_count;
reg         w_final_burst;
reg         w_last;
reg  [7:0]  final_wstrb;
reg  [7:0]  wstrb_value;
wire        w_hs;
wire        w_can_send;

// B channel
wire b_hs;

// Main control

assign busy = (state == S_RUN);
assign done = (state == S_DONE);

assign start_error = (dst_addr[2:0] != 3'b000) || (transfer_bytes == 32'd0);

assign start_accept = (state == S_IDLE) && start && !start_error;
assign transfer_done = bfifo_out_hs && bfifo_out_data;

// Main state register
always @(posedge CLK) begin
    if (!RSTN)
        state <= S_IDLE;
    else
        state <= n_state;
end

// Error register
always @(posedge CLK) begin
    if (!RSTN) begin
        error <= 1'b0;
    end else begin
        if ((state == S_IDLE) && start)
            error <= start_error;
        else if (b_hs && (M_AXI_BRESP != 2'b00))
            error <= 1'b1;
    end
end

always @(*) begin
    n_state = state;

    case (state)
        S_IDLE: begin
            if (start) begin
                if (start_error)
                    n_state = S_DONE;
                else
                    n_state = S_RUN;
            end
        end

        S_RUN: begin
            if (transfer_done)
                n_state = S_DONE;
        end

        S_DONE: begin
            n_state = S_IDLE;
        end

        default: begin
            n_state = S_IDLE;
        end
    endcase
end

// Runtime configuration

always @(*) begin
    case (cfg_burst_beats)
        8'd1:    cfg_burst_value = 5'd1;
        8'd2:    cfg_burst_value = 5'd2;
        8'd4:    cfg_burst_value = 5'd4;
        8'd8:    cfg_burst_value = 5'd8;
        8'd16:   cfg_burst_value = 5'd16;
        default: cfg_burst_value = 5'd16;
    endcase

    case (cfg_wr_out_limit)
        2'b00:   cfg_out_limit_value = 3'd1;
        2'b01:   cfg_out_limit_value = 3'd2;
        2'b10:   cfg_out_limit_value = 3'd4;
        default: cfg_out_limit_value = 3'd4;
    endcase
end

always @(posedge CLK) begin
    if (!RSTN) begin
        active_burst_beats <= 5'd16;
        active_out_limit   <= 3'd4;
    end else if (start_accept) begin
        active_burst_beats <= cfg_burst_value;
        active_out_limit   <= cfg_out_limit_value;
    end else if (!M_AXI_AWVALID || aw_hs) begin
        active_burst_beats <= cfg_burst_value;
        active_out_limit   <= cfg_out_limit_value;
    end
end

// AW channel

assign bytes_until_4k = 13'd4096 - {1'b0, issue_addr[11:0]};
assign active_burst_bytes = {27'd0, active_burst_beats} << 3;

assign max_limited_bytes =
    (issue_bytes_left > active_burst_bytes) ? active_burst_bytes : issue_bytes_left;

assign next_burst_bytes =
    (max_limited_bytes > {19'd0, bytes_until_4k}) ? {19'd0, bytes_until_4k} : max_limited_bytes;

assign next_burst_beats = (next_burst_bytes + 32'd7) >> 3; // consider partial last beat
assign final_aw = (issue_bytes_left == next_burst_bytes);

always @(*) begin
    if (issue_bytes_left != 32'd0)
        awlen_value = next_burst_beats[7:0] - 1'b1;
    else
        awlen_value = 8'd0;
end

assign M_AXI_AWADDR  = issue_addr; // AW start adress
assign M_AXI_AWLEN   = awlen_value; // how many beats
assign M_AXI_AWSIZE  = 3'b011; // 8 bytes per beat
assign M_AXI_AWBURST = 2'b01;  // INCR
assign M_AXI_AWVALID = (state == S_RUN) && (issue_bytes_left != 32'd0) && wfifo_in_ready && (write_pending < active_out_limit);

assign aw_hs = M_AXI_AWVALID && M_AXI_AWREADY;

// Next AW address
always @(posedge CLK) begin
    if (!RSTN)
        issue_addr <= 32'd0;
    else if (start_accept)
        issue_addr <= dst_addr;
    else if (aw_hs)
        issue_addr <= issue_addr + next_burst_bytes;
end

// Bytes not issued through AW yet
always @(posedge CLK) begin
    if (!RSTN)
        issue_bytes_left <= 32'd0;
    else if (start_accept)
        issue_bytes_left <= transfer_bytes;
    else if (aw_hs)
        issue_bytes_left <= issue_bytes_left - next_burst_bytes;
end

// Number of accepted AW requests that have not received a B response yet.
always @(posedge CLK) begin
    if (!RSTN) begin
        write_pending <= 3'd0;
    end else if (start_accept) begin
        write_pending <= 3'd0;
    end else begin
        case ({aw_hs, b_hs})
            2'b10: write_pending <= write_pending + 1'b1;
            2'b01: write_pending <= write_pending - 1'b1;
            default: write_pending <= write_pending;
        endcase
    end
end

// AW to W FIFO

assign wfifo_out_ready = (state == S_RUN) && (!w_run || (w_hs && M_AXI_WLAST));

assign wfifo_out_hs = wfifo_out_valid && wfifo_out_ready;

FIFO #(
    .DATA_WIDTH(6),
    .FIFO_DEPTH(4),
    .PTR_WIDTH(2)
) u_wfifo (
    .CLK(CLK),
    .RSTN(RSTN),

    .s_valid(aw_hs),
    .s_ready(wfifo_in_ready),
    .s_data({final_aw, next_burst_beats[4:0]}),

    .m_valid(wfifo_out_valid),
    .m_ready(wfifo_out_ready),
    .m_data(wfifo_out_data)
);

// W to B FIFO

assign bfifo_out_ready = (state == S_RUN) && M_AXI_BVALID;

assign bfifo_out_hs = bfifo_out_valid && bfifo_out_ready;

FIFO #(
    .DATA_WIDTH(1),
    .FIFO_DEPTH(4),
    .PTR_WIDTH(2)
) u_bfifo (
    .CLK(CLK),
    .RSTN(RSTN),

    .s_valid(w_hs && M_AXI_WLAST),
    .s_ready(bfifo_in_ready),
    .s_data(w_final_burst),

    .m_valid(bfifo_out_valid),
    .m_ready(bfifo_out_ready),
    .m_data(bfifo_out_data)
);

// W channel

assign M_AXI_WDATA  = in_data;
assign M_AXI_WSTRB  = wstrb_value;
assign M_AXI_WLAST  = w_run && w_last;
assign w_can_send   = !M_AXI_WLAST || bfifo_in_ready; // fifo space left or not last
assign M_AXI_WVALID = (state == S_RUN) && w_run && in_valid && w_can_send;
assign in_ready     = (state == S_RUN) && w_run && M_AXI_WREADY && w_can_send;

assign w_hs = M_AXI_WVALID && M_AXI_WREADY;

always @(*) begin
    wstrb_value = 8'hFF;

    if (w_final_burst && M_AXI_WLAST)
        wstrb_value = final_wstrb;
end

// Prepare WLAST one beat early so the output does not depend on a counter
// comparison in the same cycle as the AXI handshake.
always @(posedge CLK) begin
    if (!RSTN)
        w_last <= 1'b0;
    else if (start_accept)
        w_last <= 1'b0;
    else if (wfifo_out_hs)
        w_last <= (wfifo_out_data[4:0] == 5'd1);
    else if (w_hs) begin
        if (M_AXI_WLAST)
            w_last <= 1'b0;
        else
            w_last <= (w_beat_count == (w_burst_beats - 2'd2));
    end
end

// Only the final beat can be partial. Calculate its strobe once when the
// command starts instead of decoding a 32-bit remaining-byte counter on every
// W beat.
always @(posedge CLK) begin
    if (!RSTN) begin
        final_wstrb <= 8'hFF;
    end else if ((state == S_IDLE) && start) begin
        case (transfer_bytes[2:0])
            3'd1: final_wstrb <= 8'h01;
            3'd2: final_wstrb <= 8'h03;
            3'd3: final_wstrb <= 8'h07;
            3'd4: final_wstrb <= 8'h0F;
            3'd5: final_wstrb <= 8'h1F;
            3'd6: final_wstrb <= 8'h3F;
            3'd7: final_wstrb <= 8'h7F;
            default: final_wstrb <= 8'hFF;
        endcase
    end
end

// W run flag
always @(posedge CLK) begin
    if (!RSTN)
        w_run <= 1'b0;
    else if (start_accept)
        w_run <= 1'b0;
    else if (wfifo_out_hs)
        w_run <= 1'b1;
    else if (w_hs && M_AXI_WLAST)
        w_run <= 1'b0;
end

// Current W burst information
always @(posedge CLK) begin
    if (!RSTN) begin
        w_burst_beats <= 5'd0;
        w_final_burst <= 1'b0;
    end else if (start_accept) begin
        w_burst_beats <= 5'd0;
        w_final_burst <= 1'b0;
    end else if (wfifo_out_hs) begin
        w_burst_beats <= wfifo_out_data[4:0];
        w_final_burst <= wfifo_out_data[5];
    end
end

// W burst count
always @(posedge CLK) begin
    if (!RSTN)
        w_beat_count <= 5'd0;
    else if (start_accept)
        w_beat_count <= 5'd0;
    else if (wfifo_out_hs)
        w_beat_count <= 5'd0;
    else if (w_hs) begin
        if (M_AXI_WLAST)
            w_beat_count <= 5'd0;
        else
            w_beat_count <= w_beat_count + 1'b1;
    end
end

// Total W handshake count
always @(posedge CLK) begin
    if (!RSTN)
        write_beats <= 32'd0;
    else if ((state == S_IDLE) && start)
        write_beats <= 32'd0;
    else if (w_hs)
        write_beats <= write_beats + 1'b1;
end

// B channel

assign M_AXI_BREADY = (state == S_RUN) && bfifo_out_valid;
assign b_hs = M_AXI_BVALID && M_AXI_BREADY;

endmodule
