`timescale 1ns/1ps

module regulator (
    input  wire        CLK,
    input  wire        RSTN,

    input  wire        enable,
    input  wire [31:0] threshold_bytes,
    input  wire [31:0] nominal_cycles,
    input  wire [15:0] delta_q8,

    input  wire        s_valid,
    output wire        s_ready,
    input  wire [7:0]  s_strobe,

    output wire        m_valid,
    input  wire        m_ready,

    output wire [31:0] copy_cycles,
    output wire        copy_valid,
    output wire [31:0] idle_cycles,
    output wire        wait_active
);

wire config_valid;
wire allow;
wire window_start;

assign config_valid = enable && (threshold_bytes >= 32'd8) && (nominal_cycles != 32'd0) && (nominal_cycles[31:16] == 16'd0);

assign s_ready = m_ready && allow;
assign m_valid = s_valid && allow;

monitor u_monitor (
    .CLK(CLK),
    .RSTN(RSTN),

    .enable(config_valid),
    .threshold_bytes(threshold_bytes),

    .data_valid(m_valid),
    .data_ready(m_ready),
    .data_strobe(s_strobe),

    .window_start(window_start),
    .copy_cycles(copy_cycles),
    .copy_valid(copy_valid)
);

throttler u_throttler (
    .CLK(CLK),
    .RSTN(RSTN),

    .enable(config_valid),
    .config_load(window_start),
    .copy_cycles(copy_cycles),
    .copy_valid(copy_valid),
    .nominal_cycles(nominal_cycles),
    .delta_q8(delta_q8),

    .allow(allow),
    .wait_active(wait_active),
    .idle_cycles(idle_cycles)
);

endmodule
