`timescale 1ns/1ps

module throttler (
    input  wire        CLK,
    input  wire        RSTN,

    input  wire        enable,
    input  wire        config_load,
    input  wire [31:0] copy_cycles,
    input  wire        copy_valid,
    input  wire [31:0] nominal_cycles,
    input  wire [15:0] delta_q8,

    output wire        allow,
    output wire        wait_active,
    output reg  [31:0] idle_cycles
);

localparam S_PASS = 1'b0;
localparam S_WAIT = 1'b1;

reg         c_state;
reg         n_state;
reg  [31:0] wait_count;

wire [31:0] delta_product;
wire [32:0] rounded_product;

reg  [31:0] delta_cycles;
reg  [32:0] target_sum;
reg  [31:0] target_value;
reg  [31:0] target_cycles;
reg  [31:0] idle_calc;

// The supported runtime nominal range is 65535 cycles.
// multiplication uses one DSP instead of a long 32x16 combinational path.
assign delta_product = nominal_cycles[15:0] * delta_q8;
assign rounded_product = {1'b0, delta_product} + 33'd255; // rounding

// Unsigned Q8.8: delta_cycles = ceil(nominal_cycles * delta_q8 / 256).
always @(*) begin
    delta_cycles = {7'd0, rounded_product[32:8]};
end

// Total period required by the configured bandwidth ratio.
always @(*) begin
    target_sum = {1'b0, nominal_cycles} + {1'b0, delta_cycles};
    if (target_sum[32])
        target_value = 32'hFFFF_FFFF; // overflow
    else
        target_value = target_sum[31:0];
end

always @(posedge CLK) begin
    if (!RSTN)
        target_cycles <= 32'd0;
    else if (!enable)
        target_cycles <= 32'd0;
    else if (config_load)
        target_cycles <= target_value;
end

// idle = max(nominal + delta * nominal - copy, 0).
always @(*) begin
    if (target_cycles > copy_cycles)
        idle_calc = target_cycles - copy_cycles;
    else
        idle_calc = 32'd0;
end

// Block immediately during the copy_valid cycle, then use the WAIT state.
assign wait_active = enable && ((c_state == S_WAIT) || (copy_valid && (idle_calc != 32'd0)));

assign allow = !wait_active;

always @(*) begin
    if (enable)
        idle_cycles = idle_calc;
    else
        idle_cycles = 32'd0;
end

// PASS/WAIT state.
always @(posedge CLK) begin
    if (!RSTN)
        c_state <= S_PASS;
    else
        c_state <= n_state;
end

always @(*) begin
    n_state = c_state;

    case (c_state)
        S_PASS: begin
            if (enable && copy_valid && (idle_calc > 32'd1))
                n_state = S_WAIT;
        end

        S_WAIT: begin
            if (!enable || (wait_count <= 32'd1))
                n_state = S_PASS;
        end

        default: begin
            n_state = S_PASS;
        end
    endcase
end

// Remaining WAIT cycles.
always @(posedge CLK) begin
    if (!RSTN) begin
        wait_count <= 32'd0;
    end else if (!enable) begin
        wait_count <= 32'd0;
    end else if (c_state == S_PASS) begin
        if (copy_valid && (idle_calc > 32'd1))
            wait_count <= idle_calc - 1'b1;
        else
            wait_count <= 32'd0;
    end else if (wait_count != 32'd0) begin
        wait_count <= wait_count - 1'b1;
    end
end

endmodule