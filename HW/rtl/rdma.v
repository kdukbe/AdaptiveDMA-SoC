`timescale 1ns/1ps

module rdma (
    input  wire        CLK,
    input  wire        RSTN,

    input  wire [31:0] src_addr,
    input  wire [31:0] transfer_bytes,

    input  wire [7:0]  cfg_burst_beats,
    input  wire [1:0]  cfg_rd_out_limit,

    input  wire        start,
    output wire        busy,
    output wire        done,
    output reg         error,
    output reg  [31:0] read_beats,

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

    // Output stream
    output wire [63:0] out_data,
    output wire        out_valid,
    input  wire        out_ready,
    output wire        out_last
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

// AR channel
reg  [31:0] issue_addr;
reg  [31:0] issue_beats_left;
wire [12:0] bytes_until_4k;
wire [9:0]  beats_until_4k;
wire [31:0] max_limited_beats;
wire [31:0] next_burst_beats;
wire        ar_hs;

// AR FIFO
wire ar_fifo_ready;
wire ar_fifo_valid;
wire ar_fifo_pop;
reg  [2:0] read_pending;

// R channel
reg  [31:0] receive_beats_left;
wire        r_hs;
wire        r_burst_done;

// Main control

assign busy = (state == S_RUN);
assign done = (state == S_DONE);

assign start_error = (src_addr[2:0] != 3'b000) || (transfer_bytes[2:0] != 3'b000) || (transfer_bytes == 32'd0);

assign start_accept = (state == S_IDLE) && start && !start_error;
assign transfer_done = r_hs && (receive_beats_left == 32'd1);

always @(posedge CLK) begin
    if (!RSTN) begin
        state <= S_IDLE;
        error <= 1'b0;
    end else begin
        state <= n_state;

        if ((state == S_IDLE) && start)
            error <= start_error;
    end
end

always @(*) begin
    n_state = state;

    case (state)
        S_IDLE: begin
            if (start)
                n_state = start_error ? S_DONE : S_RUN;
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

    case (cfg_rd_out_limit)
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
    end else if (!M_AXI_ARVALID || ar_hs) begin
        active_burst_beats <= cfg_burst_value;
        active_out_limit   <= cfg_out_limit_value;
    end
end

// AR channel

assign bytes_until_4k = 13'd4096 - {1'b0, issue_addr[11:0]};
assign beats_until_4k = bytes_until_4k[12:3];

assign max_limited_beats = (issue_beats_left > {27'd0, active_burst_beats}) ? {27'd0, active_burst_beats} : issue_beats_left;

assign next_burst_beats = (max_limited_beats > {22'd0, beats_until_4k}) ? {22'd0, beats_until_4k} : max_limited_beats;

assign M_AXI_ARADDR  = issue_addr;
assign M_AXI_ARLEN   = next_burst_beats[7:0] - 1'b1;
assign M_AXI_ARSIZE  = 3'b011; // 8 bytes per beat
assign M_AXI_ARBURST = 2'b01;  // INCR
assign M_AXI_ARVALID = (state == S_RUN) && (issue_beats_left != 32'd0) && ar_fifo_ready && (read_pending < active_out_limit);

assign ar_hs = M_AXI_ARVALID && M_AXI_ARREADY;

always @(posedge CLK) begin
    if (!RSTN) begin
        issue_addr       <= 32'd0;
        issue_beats_left <= 32'd0;
    end else if (start_accept) begin
        issue_addr       <= src_addr;
        issue_beats_left <= transfer_bytes >> 3;
    end else if (ar_hs) begin
        issue_addr       <= issue_addr + (next_burst_beats << 3);
        issue_beats_left <= issue_beats_left - next_burst_beats;
    end
end

// AR FIFO
assign r_burst_done = r_hs && M_AXI_RLAST;
assign ar_fifo_pop  = r_burst_done;

// Number of accepted AR requests that have not received RLAST yet.
always @(posedge CLK) begin
    if (!RSTN) begin
        read_pending <= 3'd0;
    end else if (start_accept) begin
        read_pending <= 3'd0;
    end else begin
        case ({ar_hs, r_burst_done})
            2'b10: read_pending <= read_pending + 1'b1;
            2'b01: read_pending <= read_pending - 1'b1;
            default: read_pending <= read_pending;
        endcase
    end
end

FIFO #(
    .DATA_WIDTH(1),
    .FIFO_DEPTH(4),  // MOR 4
    .PTR_WIDTH(2)
) ar_fifo (
    .CLK(CLK),
    .RSTN(RSTN),

    .s_valid(ar_hs),
    .s_ready(ar_fifo_ready), // not full
    .s_data(1'b1),

    .m_valid(ar_fifo_valid), // not empty
    .m_ready(ar_fifo_pop),
    .m_data()
);

// R channel (bypass)

assign M_AXI_RREADY = (state == S_RUN) && ar_fifo_valid && out_ready;
assign r_hs         = M_AXI_RVALID && M_AXI_RREADY;

assign out_data  = M_AXI_RDATA;
assign out_valid = (state == S_RUN) && ar_fifo_valid && M_AXI_RVALID;
assign out_last  = out_valid && (receive_beats_left == 32'd1);

always @(posedge CLK) begin
    if (!RSTN) begin
        receive_beats_left <= 32'd0;
        read_beats         <= 32'd0;
    end else if ((state == S_IDLE) && start) begin
        receive_beats_left <= start_error ? 32'd0 : transfer_bytes >> 3;
        read_beats         <= 32'd0;
    end else if (r_hs) begin
        receive_beats_left <= receive_beats_left - 1'b1;
        read_beats         <= read_beats + 1'b1;
    end
end

endmodule
