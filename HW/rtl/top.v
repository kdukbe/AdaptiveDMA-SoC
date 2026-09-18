`timescale 1ns/1ps

module top #(
    parameter RBR_R_BYTES = 32'd256,
    parameter RBR_W_BYTES = 32'd256,
    parameter RBR_R_NOM   = 32'd32,
    parameter RBR_W_NOM   = 32'd32
)(
    input  wire        CLK,
    input  wire        RSTN,

    // AXI4-Lite slave
    input  wire [6:0]  S_AXI_AWADDR,
    input  wire        S_AXI_AWVALID,
    output wire        S_AXI_AWREADY,

    input  wire [31:0] S_AXI_WDATA,
    input  wire [3:0]  S_AXI_WSTRB,
    input  wire        S_AXI_WVALID,
    output wire        S_AXI_WREADY,

    output wire [1:0]  S_AXI_BRESP,
    output wire        S_AXI_BVALID,
    input  wire        S_AXI_BREADY,

    input  wire [6:0]  S_AXI_ARADDR,
    input  wire        S_AXI_ARVALID,
    output wire        S_AXI_ARREADY,

    output wire [31:0] S_AXI_RDATA,
    output wire [1:0]  S_AXI_RRESP,
    output wire        S_AXI_RVALID,
    input  wire        S_AXI_RREADY,

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

// Controller
wire        start_pulse;
wire        soft_reset_pulse;
wire [31:0] cfg_src_addr;
wire [31:0] cfg_dst_addr;
wire [31:0] cfg_transfer_bytes;
wire [7:0]  sw_burst_beats;
wire [1:0]  sw_rd_out_limit;
wire [1:0]  sw_wr_out_limit;
wire [15:0] sw_r_delta_q8;
wire [15:0] sw_w_delta_q8;
wire [1:0]  sw_rbr_enable;
wire [31:0] sw_r_threshold_bytes;
wire [31:0] sw_w_threshold_bytes;
wire [31:0] sw_r_nominal_cycles;
wire [31:0] sw_w_nominal_cycles;

wire [7:0]  cfg_burst_beats;
wire [1:0]  cfg_rd_out_limit;
wire [1:0]  cfg_wr_out_limit;
wire [15:0] cfg_r_delta_q8;
wire [15:0] cfg_w_delta_q8;
wire [1:0]  cfg_rbr_enable;
wire [31:0] cfg_r_threshold_bytes;
wire [31:0] cfg_w_threshold_bytes;
wire [31:0] cfg_r_nominal_cycles;
wire [31:0] cfg_w_nominal_cycles;

wire        adapt_enable;
wire        adapt_restart;
wire [31:0] adapt_latency_sample;
wire        adapt_sample_valid;
wire [15:0] adapt_low_limit;
wire [15:0] adapt_high_limit;
wire [7:0]  adapt_hold_samples;
wire [7:0]  adapt_low_confirm;
wire [7:0]  adapt_high_confirm;
wire [1:0]  adapt_initial_level;
(* mark_debug = "true" *) wire [1:0] adapt_level;
(* mark_debug = "true" *) wire       adapt_level_change;
wire        adapt_config_valid;

wire [7:0]  auto_burst_beats;
wire [1:0]  auto_rd_out_limit;
wire [1:0]  auto_wr_out_limit;
wire [15:0] auto_r_delta_q8;
wire [15:0] auto_w_delta_q8;
wire [1:0]  auto_rbr_enable;

wire        engine_busy;
wire        engine_done;
wire        engine_error;

reg  [31:0] cyc_total;
reg  [31:0] cyc_read;
reg  [31:0] cyc_write;

reg  [31:0] transfer_bytes;
reg         dma_start;
wire        core_rstn;
wire        fifo_rstn;

// DMA status
wire        rdma_busy;
wire        wdma_busy;
wire [31:0] read_beats;
wire [31:0] write_beats;

// Per-command AXI and RBR counters
wire [31:0] stall_ar;
wire [31:0] stall_r;
wire [31:0] stall_aw;
wire [31:0] stall_w;
wire [31:0] stall_b;
wire [31:0] read_txns;
wire [31:0] write_txns;
wire [31:0] r_wait_cycles;
wire [31:0] w_wait_cycles;
wire [31:0] r_windows;
wire [31:0] w_windows;

// Regulator results for ILA and later adaptive control.
// Sample copy_cycles and idle_cycles only when copy_valid is high.
(* mark_debug = "true" *) wire [31:0] r_copy_cycles;
(* mark_debug = "true" *) wire        r_copy_valid;
(* mark_debug = "true" *) wire [31:0] r_idle_cycles;
(* mark_debug = "true" *) wire        r_wait_active;
(* mark_debug = "true" *) wire [31:0] w_copy_cycles;
(* mark_debug = "true" *) wire        w_copy_valid;
(* mark_debug = "true" *) wire [31:0] w_idle_cycles;
(* mark_debug = "true" *) wire        w_wait_active;

// AXI data handshakes on the DMA side of the regulators
wire dma_rvalid;
wire dma_rready;
wire dma_wvalid;
wire dma_wready;

// DMA output stream
wire [63:0] dma_out_data;
wire        dma_out_valid;
wire        dma_out_ready;
wire        dma_out_last;

// DMA input stream
wire [63:0] dma_in_data;
wire        dma_in_valid;
wire        dma_in_ready;

// Adaptive mode replaces only the runtime traffic settings. Source,
// destination and transfer size always remain software-controlled.
assign cfg_burst_beats = adapt_enable ? auto_burst_beats : sw_burst_beats;
assign cfg_rd_out_limit = adapt_enable ? auto_rd_out_limit : sw_rd_out_limit;
assign cfg_wr_out_limit = adapt_enable ? auto_wr_out_limit : sw_wr_out_limit;
assign cfg_r_delta_q8 = adapt_enable ? auto_r_delta_q8 : sw_r_delta_q8;
assign cfg_w_delta_q8 = adapt_enable ? auto_w_delta_q8 : sw_w_delta_q8;
assign cfg_rbr_enable = adapt_enable ? auto_rbr_enable : sw_rbr_enable;
assign cfg_r_threshold_bytes = adapt_enable ? 32'd256 : sw_r_threshold_bytes;
assign cfg_w_threshold_bytes = adapt_enable ? 32'd256 : sw_w_threshold_bytes;
assign cfg_r_nominal_cycles = adapt_enable ? 32'd32 : sw_r_nominal_cycles;
assign cfg_w_nominal_cycles = adapt_enable ? 32'd32 : sw_w_nominal_cycles;

assign core_rstn = RSTN && !soft_reset_pulse;
assign fifo_rstn = core_rstn && !dma_start;

// Register the transfer size before starting the DMA.
always @(posedge CLK) begin
    if (!core_rstn) begin
        transfer_bytes <= 32'd0;
        dma_start      <= 1'b0;
    end else begin
        dma_start <= start_pulse;

        if (start_pulse)
            transfer_bytes <= cfg_transfer_bytes;
    end
end

// Total cycle count
always @(posedge CLK) begin
    if (!core_rstn)
        cyc_total <= 32'd0;
    else if (dma_start)
        cyc_total <= 32'd0;
    else if (engine_busy)
        cyc_total <= cyc_total + 1'b1;
end

// Read cycle count
always @(posedge CLK) begin
    if (!core_rstn)
        cyc_read <= 32'd0;
    else if (dma_start)
        cyc_read <= 32'd0;
    else if (rdma_busy)
        cyc_read <= cyc_read + 1'b1;
end

// Write cycle count
always @(posedge CLK) begin
    if (!core_rstn)
        cyc_write <= 32'd0;
    else if (dma_start)
        cyc_write <= 32'd0;
    else if (wdma_busy)
        cyc_write <= cyc_write + 1'b1;
end

controller #(
    .AW(7),
    .DW(32),
    .RBR_R_BYTES_DEFAULT(RBR_R_BYTES),
    .RBR_W_BYTES_DEFAULT(RBR_W_BYTES),
    .RBR_R_NOM_DEFAULT(RBR_R_NOM),
    .RBR_W_NOM_DEFAULT(RBR_W_NOM)
) u_controller (
    .CLK(CLK),
    .RSTN(RSTN),

    .AWADDR(S_AXI_AWADDR),
    .AWVALID(S_AXI_AWVALID),
    .AWREADY(S_AXI_AWREADY),

    .WDATA(S_AXI_WDATA),
    .WSTRB(S_AXI_WSTRB),
    .WVALID(S_AXI_WVALID),
    .WREADY(S_AXI_WREADY),

    .BRESP(S_AXI_BRESP),
    .BVALID(S_AXI_BVALID),
    .BREADY(S_AXI_BREADY),

    .ARADDR(S_AXI_ARADDR),
    .ARVALID(S_AXI_ARVALID),
    .ARREADY(S_AXI_ARREADY),

    .RDATA(S_AXI_RDATA),
    .RRESP(S_AXI_RRESP),
    .RVALID(S_AXI_RVALID),
    .RREADY(S_AXI_RREADY),

    .start_pulse(start_pulse),
    .soft_reset_pulse(soft_reset_pulse),

    .cfg_src_addr(cfg_src_addr),
    .cfg_dst_addr(cfg_dst_addr),
    .cfg_transfer_bytes(cfg_transfer_bytes),
    .cfg_burst_beats(sw_burst_beats),
    .cfg_rd_out_limit(sw_rd_out_limit),
    .cfg_wr_out_limit(sw_wr_out_limit),
    .cfg_r_delta_q8(sw_r_delta_q8),
    .cfg_w_delta_q8(sw_w_delta_q8),
    .cfg_rbr_enable(sw_rbr_enable),
    .cfg_r_threshold_bytes(sw_r_threshold_bytes),
    .cfg_w_threshold_bytes(sw_w_threshold_bytes),
    .cfg_r_nominal_cycles(sw_r_nominal_cycles),
    .cfg_w_nominal_cycles(sw_w_nominal_cycles),

    .adapt_enable(adapt_enable),
    .adapt_restart(adapt_restart),
    .adapt_latency_sample(adapt_latency_sample),
    .adapt_sample_valid(adapt_sample_valid),
    .adapt_low_limit(adapt_low_limit),
    .adapt_high_limit(adapt_high_limit),
    .adapt_hold_samples(adapt_hold_samples),
    .adapt_low_confirm(adapt_low_confirm),
    .adapt_high_confirm(adapt_high_confirm),
    .adapt_initial_level(adapt_initial_level),
    .adapt_level(adapt_level),
    .adapt_config_valid(adapt_config_valid),

    .engine_busy(engine_busy),
    .engine_done(engine_done),
    .engine_error(engine_error),

    .cyc_total(cyc_total),
    .cyc_read(cyc_read),
    .cyc_write(cyc_write),
    .read_beats(read_beats),
    .write_beats(write_beats),
    .stall_ar(stall_ar),
    .stall_r(stall_r),
    .stall_aw(stall_aw),
    .stall_w(stall_w),
    .stall_b(stall_b),
    .read_txns(read_txns),
    .write_txns(write_txns),
    .r_wait_cycles(r_wait_cycles),
    .w_wait_cycles(w_wait_cycles),
    .r_windows(r_windows),
    .w_windows(w_windows)
);

adaptive u_adaptive (
    .CLK(CLK),
    .RSTN(core_rstn),

    .enable(adapt_enable),
    .restart(adapt_restart),
    .latency_sample(adapt_latency_sample),
    .sample_valid(adapt_sample_valid),
    .low_limit(adapt_low_limit),
    .high_limit(adapt_high_limit),
    .hold_samples(adapt_hold_samples),
    .low_confirm(adapt_low_confirm),
    .high_confirm(adapt_high_confirm),
    .initial_level(adapt_initial_level),

    .config_valid(adapt_config_valid),
    .current_level(adapt_level),
    .level_change(adapt_level_change),

    .cfg_burst_beats(auto_burst_beats),
    .cfg_rd_out_limit(auto_rd_out_limit),
    .cfg_wr_out_limit(auto_wr_out_limit),
    .cfg_r_delta_q8(auto_r_delta_q8),
    .cfg_w_delta_q8(auto_w_delta_q8),
    .cfg_rbr_enable(auto_rbr_enable)
);

dma_engine u_dma (
    .CLK(CLK),
    .RSTN(core_rstn),

    .start(dma_start),
    .src_addr(cfg_src_addr),
    .dst_addr(cfg_dst_addr),
    .transfer_bytes(transfer_bytes),
    .cfg_burst_beats(cfg_burst_beats),
    .cfg_rd_out_limit(cfg_rd_out_limit),
    .cfg_wr_out_limit(cfg_wr_out_limit),

    .busy(engine_busy),
    .done(engine_done),
    .error(engine_error),
    .read_busy(rdma_busy),
    .write_busy(wdma_busy),
    .read_beats(read_beats),
    .write_beats(write_beats),

    .out_data(dma_out_data),
    .out_valid(dma_out_valid),
    .out_ready(dma_out_ready),
    .out_last(dma_out_last),

    .in_data(dma_in_data),
    .in_valid(dma_in_valid),
    .in_ready(dma_in_ready),

    .M_AXI_ARADDR(M_AXI_ARADDR),
    .M_AXI_ARLEN(M_AXI_ARLEN),
    .M_AXI_ARSIZE(M_AXI_ARSIZE),
    .M_AXI_ARBURST(M_AXI_ARBURST),
    .M_AXI_ARVALID(M_AXI_ARVALID),
    .M_AXI_ARREADY(M_AXI_ARREADY),

    .M_AXI_RDATA(M_AXI_RDATA),
    .M_AXI_RRESP(M_AXI_RRESP),
    .M_AXI_RLAST(M_AXI_RLAST),
    .M_AXI_RVALID(dma_rvalid),
    .M_AXI_RREADY(dma_rready),

    .M_AXI_AWADDR(M_AXI_AWADDR),
    .M_AXI_AWLEN(M_AXI_AWLEN),
    .M_AXI_AWSIZE(M_AXI_AWSIZE),
    .M_AXI_AWBURST(M_AXI_AWBURST),
    .M_AXI_AWVALID(M_AXI_AWVALID),
    .M_AXI_AWREADY(M_AXI_AWREADY),

    .M_AXI_WDATA(M_AXI_WDATA),
    .M_AXI_WSTRB(M_AXI_WSTRB),
    .M_AXI_WLAST(M_AXI_WLAST),
    .M_AXI_WVALID(dma_wvalid),
    .M_AXI_WREADY(dma_wready),

    .M_AXI_BRESP(M_AXI_BRESP),
    .M_AXI_BVALID(M_AXI_BVALID),
    .M_AXI_BREADY(M_AXI_BREADY)
);

// Read RBR: memory is the source and the DMA is the sink.
regulator u_rreg (
    .CLK(CLK),
    .RSTN(core_rstn),

    .enable(cfg_rbr_enable[0]),
    .threshold_bytes(cfg_r_threshold_bytes),
    .nominal_cycles(cfg_r_nominal_cycles),
    .delta_q8(cfg_r_delta_q8),

    .s_valid(M_AXI_RVALID),
    .s_ready(M_AXI_RREADY),
    .s_strobe(8'hFF),

    .m_valid(dma_rvalid),
    .m_ready(dma_rready),

    .copy_cycles(r_copy_cycles),
    .copy_valid(r_copy_valid),
    .idle_cycles(r_idle_cycles),
    .wait_active(r_wait_active)
);

// Write RBR: the DMA is the source and memory is the sink.
regulator u_wreg (
    .CLK(CLK),
    .RSTN(core_rstn),

    .enable(cfg_rbr_enable[1]),
    .threshold_bytes(cfg_w_threshold_bytes),
    .nominal_cycles(cfg_w_nominal_cycles),
    .delta_q8(cfg_w_delta_q8),

    .s_valid(dma_wvalid),
    .s_ready(dma_wready),
    .s_strobe(M_AXI_WSTRB),

    .m_valid(M_AXI_WVALID),
    .m_ready(M_AXI_WREADY),

    .copy_cycles(w_copy_cycles),
    .copy_valid(w_copy_valid),
    .idle_cycles(w_idle_cycles),
    .wait_active(w_wait_active)
);

// Counters cover one DMA command. They reset together with the command start
// and count only while the engine is busy.
counters u_counters (
    .CLK(CLK),
    .RSTN(core_rstn),
    .clear(dma_start),
    .active(engine_busy),

    .arvalid(M_AXI_ARVALID),
    .arready(M_AXI_ARREADY),
    .rvalid(M_AXI_RVALID),
    .rready(M_AXI_RREADY),
    .awvalid(M_AXI_AWVALID),
    .awready(M_AXI_AWREADY),
    .wvalid(M_AXI_WVALID),
    .wready(M_AXI_WREADY),
    .bvalid(M_AXI_BVALID),
    .bready(M_AXI_BREADY),

    .r_wait_active(r_wait_active),
    .w_wait_active(w_wait_active),
    .r_window_done(r_copy_valid),
    .w_window_done(w_copy_valid),

    .stall_ar(stall_ar),
    .stall_r(stall_r),
    .stall_aw(stall_aw),
    .stall_w(stall_w),
    .stall_b(stall_b),
    .read_txns(read_txns),
    .write_txns(write_txns),
    .r_wait_cycles(r_wait_cycles),
    .w_wait_cycles(w_wait_cycles),
    .r_windows(r_windows),
    .w_windows(w_windows)
);

// Processing slot
FIFO #(
    .DATA_WIDTH(64),
    .FIFO_DEPTH(64),
    .PTR_WIDTH(6)
) u_data_fifo (
    .CLK(CLK),
    .RSTN(fifo_rstn),

    .s_valid(dma_out_valid),
    .s_ready(dma_out_ready),
    .s_data(dma_out_data),

    .m_valid(dma_in_valid),
    .m_ready(dma_in_ready),
    .m_data(dma_in_data)
);

endmodule
