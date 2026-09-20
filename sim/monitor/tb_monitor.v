`timescale 1ns/1ps

module tb_monitor;

reg         CLK;
reg         RSTN;
reg         enable;
reg  [31:0] threshold_bytes;
reg         data_valid;
reg         data_ready;
reg  [7:0]  data_strobe;

wire [31:0] copy_cycles;
wire        copy_valid;
wire        window_start;

integer error_count;

monitor dut (
    .CLK(CLK),
    .RSTN(RSTN),

    .enable(enable),
    .threshold_bytes(threshold_bytes),

    .data_valid(data_valid),
    .data_ready(data_ready),
    .data_strobe(data_strobe),

    .window_start(window_start),
    .copy_cycles(copy_cycles),
    .copy_valid(copy_valid)
);

always #5 CLK = !CLK;

task reset_dut;
    begin
        @(negedge CLK);
        RSTN = 1'b0;
        enable = 1'b0;
        data_valid = 1'b0;
        data_ready = 1'b0;
        data_strobe = 8'd0;

        repeat (3) @(posedge CLK);

        @(negedge CLK);
        RSTN = 1'b1;
        enable = 1'b1;
    end
endtask

task send_beat;
    input [7:0] strobe_value;
    begin
        @(negedge CLK);
        data_valid = 1'b1;
        data_ready = 1'b1;
        data_strobe = strobe_value;
        @(posedge CLK);
    end
endtask

task stop_data;
    begin
        @(negedge CLK);
        data_valid = 1'b0;
        data_ready = 1'b0;
        data_strobe = 8'd0;
    end
endtask

// Four continuous 8-byte handshakes transfer 32 bytes in four cycles.
task test_continuous;
    begin
        reset_dut;
        threshold_bytes = 32'd32;

        send_beat(8'hFF);
        send_beat(8'hFF);
        send_beat(8'hFF);
        send_beat(8'hFF);
        stop_data;

        if (!copy_valid || (copy_cycles != 32'd4) ||
            (dut.bytes_left != 32'd0) || (dut.timer_count != 32'd0)) begin
            error_count = error_count + 1;
            $display("ERROR: continuous transfer");
        end else begin
            $display("CONTINUOUS PASS: bytes=32 copy_cycles=4");
        end

        @(posedge CLK);
        @(negedge CLK);

        if (copy_valid) begin
            error_count = error_count + 1;
            $display("ERROR: copy_valid longer than one cycle");
        end
    end
endtask

// The timer includes three idle cycles after the first transferred beat.
task test_gap;
    begin
        reset_dut;
        threshold_bytes = 32'd32;

        send_beat(8'hFF);

        @(negedge CLK);
        data_valid = 1'b0;
        data_ready = 1'b1;
        data_strobe = 8'd0;
        repeat (3) @(posedge CLK);

        send_beat(8'hFF);
        send_beat(8'hFF);
        send_beat(8'hFF);
        stop_data;

        if (!copy_valid || (copy_cycles != 32'd7)) begin
            error_count = error_count + 1;
            $display("ERROR: transfer gap");
        end else begin
            $display("GAP PASS: bytes=32 copy_cycles=7");
        end
    end
endtask

// WSTRB-like strobes transfer 4 + 2 + 4 bytes.
task test_partial_bytes;
    begin
        reset_dut;
        threshold_bytes = 32'd10;

        send_beat(8'h0F);
        send_beat(8'h03);
        send_beat(8'h0F);
        stop_data;

        if (!copy_valid || (copy_cycles != 32'd3)) begin
            error_count = error_count + 1;
            $display("ERROR: partial-byte count");
        end else begin
            $display("PARTIAL PASS: bytes=10 copy_cycles=3");
        end
    end
endtask

// A zero-strobe handshake starts timing but adds no bytes.
// The next full beat crosses the threshold and finish rises before its clock edge.
task test_zero_and_overshoot;
    begin
        reset_dut;
        threshold_bytes = 32'd10;

        send_beat(8'h00);
        send_beat(8'hFF);

        @(negedge CLK);
        data_valid = 1'b1;
        data_ready = 1'b1;
        data_strobe = 8'hFF;
        #1;

        if (!dut.finish) begin
            error_count = error_count + 1;
            $display("ERROR: finish did not rise in threshold-crossing cycle");
        end

        @(posedge CLK);
        stop_data;

        if (!copy_valid || (copy_cycles != 32'd3)) begin
            error_count = error_count + 1;
            $display("ERROR: zero-strobe or threshold overshoot");
        end else begin
            $display("OVERSHOOT PASS: bytes=16 threshold=10 copy_cycles=3");
        end
    end
endtask

// A threshold change does not alter a measurement already in progress.
task test_threshold_hold;
    begin
        reset_dut;
        threshold_bytes = 32'd24;

        send_beat(8'hFF);
        #1;
        threshold_bytes = 32'd8;

        send_beat(8'hFF);
        #1;

        if (copy_valid || (dut.bytes_left != 32'd8)) begin
            error_count = error_count + 1;
            $display("ERROR: active threshold changed during measurement");
        end

        send_beat(8'hFF);
        stop_data;

        if (!copy_valid || (copy_cycles != 32'd3)) begin
            error_count = error_count + 1;
            $display("ERROR: latched threshold result");
        end else begin
            $display("THRESHOLD HOLD PASS: active threshold=24 copy_cycles=3");
        end
    end
endtask

// READY=0 before the first handshake does not start the timer.
// READY=0 after the first handshake is included in copy_cycles.
task test_backpressure;
    begin
        reset_dut;
        threshold_bytes = 32'd16;

        @(negedge CLK);
        data_valid = 1'b1;
        data_ready = 1'b0;
        data_strobe = 8'hFF;
        repeat (3) @(posedge CLK);

        if (dut.measuring || (dut.timer_count != 32'd0)) begin
            error_count = error_count + 1;
            $display("ERROR: timer started without handshake");
        end

        @(negedge CLK);
        data_ready = 1'b1;
        @(posedge CLK);

        @(negedge CLK);
        data_ready = 1'b0;
        repeat (2) @(posedge CLK);

        @(negedge CLK);
        data_ready = 1'b1;
        @(posedge CLK);
        stop_data;

        if (!copy_valid || (copy_cycles != 32'd4)) begin
            error_count = error_count + 1;
            $display("ERROR: backpressure timing");
        end else begin
            $display("BACKPRESSURE PASS: bytes=16 copy_cycles=4");
        end
    end
endtask

// The monitor starts a new measurement after each threshold event.
task test_repeat;
    begin
        reset_dut;
        threshold_bytes = 32'd16;

        send_beat(8'hFF);
        send_beat(8'hFF);
        stop_data;

        if (!copy_valid || (copy_cycles != 32'd2)) begin
            error_count = error_count + 1;
            $display("ERROR: first repeated measurement");
        end

        @(posedge CLK);
        @(negedge CLK);

        send_beat(8'hFF);
        send_beat(8'hFF);
        stop_data;

        if (!copy_valid || (copy_cycles != 32'd2)) begin
            error_count = error_count + 1;
            $display("ERROR: second repeated measurement");
        end else begin
            $display("REPEAT PASS: two measurements completed");
        end
    end
endtask

initial begin
    CLK = 1'b0;
    RSTN = 1'b1;
    enable = 1'b0;
    threshold_bytes = 32'd0;
    data_valid = 1'b0;
    data_ready = 1'b0;
    data_strobe = 8'd0;
    error_count = 0;

    test_continuous;
    test_gap;
    test_partial_bytes;
    test_zero_and_overshoot;
    test_threshold_hold;
    test_backpressure;
    test_repeat;

    if (error_count == 0)
        $display("PASS: tb_monitor");
    else
        $display("FAIL: tb_monitor errors=%0d", error_count);

    $finish;
end

initial begin
    #100000;
    $display("FAIL: global timeout");
    $finish;
end

endmodule
