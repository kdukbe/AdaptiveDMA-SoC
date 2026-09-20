`timescale 1ns/1ps

module adaptive (
    input  wire        CLK,
    input  wire        RSTN,

    input  wire        enable,
    input  wire        restart,
    input  wire [31:0] latency_sample,
    input  wire        sample_valid,
    input  wire [15:0] low_limit,
    input  wire [15:0] high_limit,
    input  wire [7:0]  hold_samples,
    input  wire [7:0]  low_confirm,
    input  wire [7:0]  high_confirm,
    input  wire [1:0]  initial_level,

    output wire        config_valid,
    output wire [1:0]  current_level,
    output reg         level_change,

    output reg  [7:0]  cfg_burst_beats,
    output reg  [1:0]  cfg_rd_out_limit,
    output reg  [1:0]  cfg_wr_out_limit,
    output reg  [15:0] cfg_r_delta_q8,
    output reg  [15:0] cfg_w_delta_q8,
    output reg  [1:0]  cfg_rbr_enable
);

localparam [1:0] L0 = 2'd0;
localparam [1:0] L1 = 2'd1;
localparam [1:0] L2 = 2'd2;
localparam [1:0] L3 = 2'd3;

reg [1:0] c_level;
reg [7:0] hold_count;
reg [7:0] low_count;
reg [7:0] high_count;

wire sample_is_low;
wire sample_is_high;

assign config_valid = (low_limit < high_limit) && (low_confirm != 8'd0) && (high_confirm != 8'd0);

assign current_level = c_level;
assign sample_is_low = latency_sample < {16'd0, low_limit};
assign sample_is_high = latency_sample > {16'd0, high_limit};

always @(posedge CLK) begin
    if (!RSTN) begin
        c_level     <= L0;
        hold_count <= 8'd0;
        low_count  <= 8'd0;
        high_count <= 8'd0;
        level_change <= 1'b0;
    end else begin
        level_change <= 1'b0;

        if (!enable || restart) begin
            c_level     <= initial_level;
            hold_count <= 8'd0;
            low_count  <= 8'd0;
            high_count <= 8'd0;
        end else if (!config_valid) begin
            c_level     <= L0;
            hold_count <= 8'd0;
            low_count  <= 8'd0;
            high_count <= 8'd0;
        end else if (sample_valid) begin
            if (hold_count != 8'd0) begin
                hold_count <= hold_count - 1'b1;
                low_count  <= 8'd0;
                high_count <= 8'd0;
            end else if (sample_is_high) begin
                low_count <= 8'd0;

                if (c_level == L0) begin
                    high_count <= 8'd0;
                end else if ((high_confirm == 8'd1) || (high_count >= (high_confirm - 1'b1))) begin
                    c_level     <= c_level - 1'b1;
                    hold_count <= hold_samples;
                    high_count <= 8'd0;
                    level_change <= 1'b1;
                end else begin
                    high_count <= high_count + 1'b1;
                end
            end else if (sample_is_low) begin
                high_count <= 8'd0;

                if (c_level == L3) begin
                    low_count <= 8'd0;
                end else if ((low_confirm == 8'd1) ||
                             (low_count >= (low_confirm - 1'b1))) begin
                    c_level     <= c_level + 1'b1;
                    hold_count <= hold_samples;
                    low_count  <= 8'd0;
                    level_change <= 1'b1;
                end else begin
                    low_count <= low_count + 1'b1;
                end
            end else begin
                low_count  <= 8'd0;
                high_count <= 8'd0;
            end
        end
    end
end

always @(*) begin
    cfg_burst_beats = 8'd16;
    cfg_rd_out_limit = 2'b10;
    cfg_wr_out_limit = 2'b10;
    cfg_r_delta_q8 = 16'd256;
    cfg_w_delta_q8 = 16'd256;
    cfg_rbr_enable = 2'b11;

    case (current_level)
        L0: begin
            // RBR50_T256: 381.47 MiB/s, 20.65% CPU slowdown.
        end

        L1: begin
            // RBR67_T256: 508.61 MiB/s, 28.58% CPU slowdown.
            cfg_r_delta_q8 = 16'd128;
            cfg_w_delta_q8 = 16'd128;
        end

        L2: begin
            // RBR80_T256: 608.87 MiB/s, 42.12% CPU slowdown.
            cfg_r_delta_q8 = 16'd64;
            cfg_w_delta_q8 = 16'd64;
        end

        default: begin
            // RBR100_T256: 734.22 MiB/s, effectively unrestricted.
            cfg_r_delta_q8 = 16'd0;
            cfg_w_delta_q8 = 16'd0;
        end
    endcase
end

endmodule
