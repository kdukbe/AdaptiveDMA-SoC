`timescale 1ns/1ps

module tb_throttler;

reg         CLK;
reg         RSTN;
reg         enable;
reg         config_load;
reg  [31:0] copy_cycles;
reg         copy_valid;
reg  [31:0] nominal_cycles;
reg  [15:0] delta_q8;

wire        allow;
wire        wait_active;
wire [31:0] idle_cycles;
integer error_count;

throttler dut (
    .CLK(CLK),
    .RSTN(RSTN),

    .enable(enable),
    .config_load(config_load),
    .copy_cycles(copy_cycles),
    .copy_valid(copy_valid),
    .nominal_cycles(nominal_cycles),
    .delta_q8(delta_q8),

    .allow(allow),
    .wait_active(wait_active),
    .idle_cycles(idle_cycles)
);

always #5 CLK = !CLK;

task reset_dut;
    begin
        @(negedge CLK);
        RSTN = 1'b0;
        enable = 1'b0;
        config_load = 1'b0;
        copy_valid = 1'b0;
        copy_cycles = 32'd0;
        nominal_cycles = 32'd32;
        delta_q8 = 16'd0;

        repeat (3) @(posedge CLK);

        @(negedge CLK);
        RSTN = 1'b1;
        enable = 1'b1;
    end
endtask

task run_case;
    input [31:0] nominal_value;
    input [31:0] copy_value;
    input [15:0] delta_value;
    input [31:0] expected_idle;
    integer blocked_cycles;
    begin
        nominal_cycles = nominal_value;
        copy_cycles = copy_value;
        delta_q8 = delta_value;

        config_load = 1'b1;
        @(posedge CLK);
        #1;
        config_load = 1'b0;
        copy_valid = 1'b1;
        #1;

        blocked_cycles = 0;

        if ((expected_idle != 32'd0) && allow) begin
            error_count = error_count + 1;
            $display("ERROR: immediate block missing");
        end

        if ((expected_idle == 32'd0) && !allow) begin
            error_count = error_count + 1;
            $display("ERROR: zero-idle case blocked");
        end

        if (expected_idle == 32'd0) begin
            @(posedge CLK);
            #1;
            copy_valid = 1'b0;
        end else begin
            while (!allow && (blocked_cycles < 1000)) begin
                blocked_cycles = blocked_cycles + 1;
                @(posedge CLK);
                #1;
                copy_valid = 1'b0;
            end
        end

        if (idle_cycles != expected_idle) begin
            error_count = error_count + 1;
            $display("ERROR: idle calculation expected=%0d actual=%0d",
                     expected_idle, idle_cycles);
        end

        if (blocked_cycles != expected_idle) begin
            error_count = error_count + 1;
            $display("ERROR: blocked cycles expected=%0d actual=%0d",
                     expected_idle, blocked_cycles);
        end else begin
            $display("THROTTLE PASS: nominal=%0d copy=%0d delta_q8=%0d idle=%0d",
                     nominal_value, copy_value, delta_value, expected_idle);
        end

        @(posedge CLK);
        #1;
    end
endtask

task test_disable;
    begin
        enable = 1'b0;
        nominal_cycles = 32'd32;
        copy_cycles = 32'd32;
        delta_q8 = 16'd256;
        copy_valid = 1'b1;
        #1;

        if (!allow || wait_active) begin
            error_count = error_count + 1;
            $display("ERROR: disabled throttler blocked data");
        end else begin
            $display("DISABLE PASS: allow=1");
        end

        @(posedge CLK);
        #1;
        copy_valid = 1'b0;
        enable = 1'b1;
    end
endtask

task test_reset_wait;
    begin
        copy_cycles = 32'd32;
        nominal_cycles = 32'd32;
        delta_q8 = 16'd256;

        config_load = 1'b1;
        @(posedge CLK);
        #1;
        config_load = 1'b0;
        copy_valid = 1'b1;
        @(posedge CLK);
        #1;
        copy_valid = 1'b0;

        @(negedge CLK);
        RSTN = 1'b0;
        @(posedge CLK);
        #1;

        if (!allow || wait_active) begin
            error_count = error_count + 1;
            $display("ERROR: reset did not release WAIT");
        end else begin
            $display("RESET PASS: WAIT released");
        end

        @(negedge CLK);
        RSTN = 1'b1;
    end
endtask

initial begin
    CLK = 1'b0;
    RSTN = 1'b1;
    enable = 1'b0;
    config_load = 1'b0;
    copy_cycles = 32'd0;
    copy_valid = 1'b0;
    nominal_cycles = 32'd32;
    delta_q8 = 16'd0;
    error_count = 0;

    reset_dut;

    // delta=1.0, no natural delay: idle=32.
    run_case(32'd32, 32'd32, 16'd256, 32'd32);

    // Four delayed copy cycles reduce the idle from 32 to 28.
    run_case(32'd32, 32'd36, 16'd256, 32'd28);

    // Natural delay already satisfies the target period.
    run_case(32'd32, 32'd64, 16'd256, 32'd0);

    // A copy faster than nominal still uses target-copy without underflow.
    run_case(32'd32, 32'd30, 16'd256, 32'd34);

    // delta=0.5, nominal=32, two delayed cycles: idle=14.
    run_case(32'd32, 32'd34, 16'd128, 32'd14);

    // 32 x 10/256 = 1.25, rounded up to two idle cycles.
    run_case(32'd32, 32'd32, 16'd10, 32'd2);

    // Paper example: 30% read bandwidth, delta is 70/30 in Q8.8.
    run_case(32'd32, 32'd32, 16'd597, 32'd75);

    // Paper equation at 50% bandwidth.
    run_case(32'd32, 32'd32, 16'd256, 32'd32);

    // Runtime nominal update: paper write example uses 64 cycles.
    run_case(32'd64, 32'd64, 16'd256, 32'd64);

    test_disable;
    test_reset_wait;

    if (error_count == 0)
        $display("PASS: tb_throttler");
    else
        $display("FAIL: tb_throttler errors=%0d", error_count);

    $finish;
end

initial begin
    #100000;
    $display("FAIL: global timeout");
    $finish;
end

endmodule
