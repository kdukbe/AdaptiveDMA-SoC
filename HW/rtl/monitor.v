`timescale 1ns/1ps

module monitor (
    input  wire        CLK,
    input  wire        RSTN,

    // from controller
    input  wire        enable,
    input  wire [31:0] threshold_bytes,

    input  wire        data_valid,
    input  wire        data_ready,
    input  wire [7:0]  data_strobe,

    // to throttler
    output wire        window_start,
    output reg  [31:0] copy_cycles,
    output reg         copy_valid
);

wire data_hs;
wire [31:0] beat_bytes_32;
wire clear;
wire finish;
wire first_beat_finishes;
wire active_beat_finishes;

reg  [3:0]  beat_bytes;
reg  [31:0] bytes_left;
reg  [31:0] timer_count;
reg         measuring;
reg  [31:0] finish_cycles;

integer i;

assign data_hs = data_valid && data_ready;
assign beat_bytes_32 = {28'd0, beat_bytes};
assign clear = !enable || (threshold_bytes == 32'd0);

assign first_beat_finishes = (threshold_bytes[31:4] == 28'd0) && (beat_bytes >= threshold_bytes[3:0]);
assign active_beat_finishes = (bytes_left[31:4] == 28'd0) && (beat_bytes >= bytes_left[3:0]);

assign window_start = !clear && !measuring && data_hs;

assign finish = !clear && data_hs && ((!measuring && first_beat_finishes) || (measuring && active_beat_finishes));

// Number of valid bytes in one beat
always @(*) begin
    beat_bytes = 4'd0;
    for (i = 0; i < 8; i = i + 1)
        beat_bytes = beat_bytes + data_strobe[i];
end

// Final cycles
always @(*) begin
    if (!measuring) begin
        finish_cycles = 32'd1;
    end else if (timer_count == 32'hFFFF_FFFF) begin
        finish_cycles = 32'hFFFF_FFFF;
    end else begin
        finish_cycles = timer_count + 1'b1;
    end
end

// Measurement state
always @(posedge CLK) begin
    if (!RSTN) begin
        measuring <= 1'b0;
    end else if (clear || finish) begin
        measuring <= 1'b0;
    end else if (window_start) begin
        measuring <= 1'b1;
    end
end

always @(posedge CLK) begin
    if (!RSTN) begin
        bytes_left <= 32'd0;
    end else if (clear || finish) begin
        bytes_left <= 32'd0;
    end else if (data_hs) begin // not finish at first cycle
        if (!measuring) begin
            bytes_left <= threshold_bytes - beat_bytes_32;
        end else begin
            bytes_left <= bytes_left - beat_bytes_32;
        end
    end
end

// Cycle timer
always @(posedge CLK) begin
    if (!RSTN) begin
        timer_count <= 32'd0;
    end else if (clear || finish) begin
        timer_count <= 32'd0;
    end else if (measuring) begin
        if (timer_count != 32'hFFFF_FFFF)
            timer_count <= timer_count + 1'b1;
    end else if (data_hs) begin
        timer_count <= 32'd1;
    end
end

// Result
always @(posedge CLK) begin
    if (!RSTN) begin
        copy_cycles <= 32'd0;
        copy_valid <= 1'b0;
    end else begin
        copy_valid <= 1'b0;

        if (finish) begin
            copy_cycles <= finish_cycles;
            copy_valid  <= 1'b1;
        end
    end
end

endmodule
