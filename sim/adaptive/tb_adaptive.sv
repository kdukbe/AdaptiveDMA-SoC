`timescale 1ns/1ps

module tb_adaptive;

    logic CLK;
    logic RSTN;
    logic enable;
    logic restart;
    logic [31:0] latency_sample;
    logic sample_valid;
    logic [15:0] low_limit;
    logic [15:0] high_limit;
    logic [7:0] hold_samples;
    logic [7:0] low_confirm;
    logic [7:0] high_confirm;
    logic [1:0] initial_level;

    wire config_valid;
    wire [1:0] current_level;
    wire level_change;
    wire [7:0] cfg_burst_beats;
    wire [1:0] cfg_rd_out_limit;
    wire [1:0] cfg_wr_out_limit;
    wire [15:0] cfg_r_delta_q8;
    wire [15:0] cfg_w_delta_q8;
    wire [1:0] cfg_rbr_enable;

    int unsigned errors;
    int unsigned changes;
    bit [3:0] level_mask;
    bit saw_up;
    bit saw_down;
    logic [1:0] previous_level;

    adaptive dut (
        .CLK(CLK),
        .RSTN(RSTN),
        .enable(enable),
        .restart(restart),
        .latency_sample(latency_sample),
        .sample_valid(sample_valid),
        .low_limit(low_limit),
        .high_limit(high_limit),
        .hold_samples(hold_samples),
        .low_confirm(low_confirm),
        .high_confirm(high_confirm),
        .initial_level(initial_level),
        .config_valid(config_valid),
        .current_level(current_level),
        .level_change(level_change),
        .cfg_burst_beats(cfg_burst_beats),
        .cfg_rd_out_limit(cfg_rd_out_limit),
        .cfg_wr_out_limit(cfg_wr_out_limit),
        .cfg_r_delta_q8(cfg_r_delta_q8),
        .cfg_w_delta_q8(cfg_w_delta_q8),
        .cfg_rbr_enable(cfg_rbr_enable)
    );

    initial begin
        CLK = 1'b0;
        forever #5 CLK = ~CLK;
    end

    task automatic send_sample(input int unsigned value);
        @(negedge CLK);
        latency_sample = value;
        sample_valid = 1'b1;
        @(negedge CLK);
        sample_valid = 1'b0;
    endtask

    task automatic pulse_restart;
        @(negedge CLK);
        restart = 1'b1;
        @(negedge CLK);
        restart = 1'b0;
    endtask

    task automatic expect_level(input logic [1:0] expected,
                                input string where_text);
        if (current_level !== expected) begin
            errors++;
            $display("ERROR: %s level=%0d expected=%0d",
                     where_text, current_level, expected);
        end

        if ((cfg_burst_beats != 8'd16) ||
            (cfg_rd_out_limit != 2'd2) ||
            (cfg_wr_out_limit != 2'd2) ||
            (cfg_rbr_enable != 2'd3))
            errors++;

        case (expected)
            2'd0: begin
                if ((cfg_r_delta_q8 != 16'd256) ||
                    (cfg_w_delta_q8 != 16'd256)) errors++;
            end
            2'd1: begin
                if ((cfg_r_delta_q8 != 16'd128) ||
                    (cfg_w_delta_q8 != 16'd128)) errors++;
            end
            2'd2: begin
                if ((cfg_r_delta_q8 != 16'd64) ||
                    (cfg_w_delta_q8 != 16'd64)) errors++;
            end
            default: begin
                if ((cfg_r_delta_q8 != 16'd0) ||
                    (cfg_w_delta_q8 != 16'd0)) errors++;
            end
        endcase
    endtask

    task automatic drive_to_level(input logic [1:0] target,
                                  input int unsigned value);
        int unsigned count;
        count = 0;
        while ((current_level != target) && (count < 40)) begin
            send_sample(value);
            count++;
        end
        if (current_level != target) begin
            errors++;
            $display("ERROR: failed to reach level %0d", target);
        end
    endtask

    property p_change_uses_sample;
        @(posedge CLK) disable iff (!RSTN)
        level_change |-> $past(sample_valid);
    endproperty

    property p_hold_blocks_change;
        @(posedge CLK) disable iff (!RSTN)
        enable && config_valid && sample_valid && (dut.hold_count != 0)
        |=> !level_change;
    endproperty

    assert property (p_change_uses_sample) else begin
        errors++;
        $error("ASSERT: level changed without a latency sample");
    end

    assert property (p_hold_blocks_change) else begin
        errors++;
        $error("ASSERT: level changed during hold period");
    end

    always @(posedge CLK) begin
        if (!RSTN) begin
            previous_level <= 2'd0;
        end else begin
            if (enable && config_valid)
                level_mask[current_level] <= 1'b1;

            if (level_change) begin
                changes++;
                if (current_level > previous_level)
                    saw_up <= 1'b1;
                if (current_level < previous_level)
                    saw_down <= 1'b1;
            end
            previous_level <= current_level;
        end
    end

    initial begin
        errors = 0;
        changes = 0;
        level_mask = 4'b0000;
        saw_up = 1'b0;
        saw_down = 1'b0;
        previous_level = 2'd0;

        enable = 1'b0;
        restart = 1'b0;
        latency_sample = 32'd0;
        sample_valid = 1'b0;
        low_limit = 16'd14000;
        high_limit = 16'd16000;
        hold_samples = 8'd2;
        low_confirm = 8'd3;
        high_confirm = 8'd2;
        initial_level = 2'd1;

        RSTN = 1'b0;
        repeat (4) @(posedge CLK);
        @(negedge CLK);
        RSTN = 1'b1;
        repeat (2) @(posedge CLK);

        expect_level(2'd1, "disabled initial level");
        enable = 1'b1;

        // Values inside the hysteresis band do not move the level.
        for (int unsigned i = 0; i < 20; i++) begin
            send_sample($urandom_range(15900, 14100));
            expect_level(2'd1, "in-band random sample");
        end

        // Three consecutive low samples raise one level.
        send_sample(12000);
        send_sample(12000);
        expect_level(2'd1, "two low samples");
        send_sample(12000);
        expect_level(2'd2, "third low sample");

        // Hold consumes two complete valid samples. A single later outlier is
        // also insufficient, and an in-band sample clears its streak.
        send_sample(18000);
        send_sample(18000);
        expect_level(2'd2, "hold samples");
        send_sample(18000);
        send_sample(15000);
        expect_level(2'd2, "cleared high streak");

        // Exercise both saturation limits and every transition direction.
        drive_to_level(2'd0, 18000);
        expect_level(2'd0, "high-latency saturation");
        repeat (5) send_sample(18000);
        expect_level(2'd0, "remain at L0");

        drive_to_level(2'd3, 12000);
        expect_level(2'd3, "low-latency saturation");
        repeat (5) send_sample(12000);
        expect_level(2'd3, "remain at L3");

        // Invalid limits select the measured safe L0 preset.
        @(negedge CLK);
        low_limit = 16'd17000;
        high_limit = 16'd16000;
        @(posedge CLK);
        #1;
        if (config_valid || (current_level != 2'd0)) begin
            errors++;
            $display("ERROR: invalid policy did not select safe L0");
        end

        // Restore a valid policy and prove restart reloads initial_level.
        @(negedge CLK);
        low_limit = 16'd14000;
        high_limit = 16'd16000;
        initial_level = 2'd2;
        pulse_restart();
        expect_level(2'd2, "restart initial level");

        if ((level_mask != 4'b1111) || !saw_up || !saw_down) begin
            errors++;
            $display("COVERAGE_ERROR: levels=%04b up=%0b down=%0b",
                     level_mask, saw_up, saw_down);
        end

        $display("SUMMARY: changes=%0d levels=%04b errors=%0d",
                 changes, level_mask, errors);
        if (errors == 0)
            $display("PASS: Adaptive controller unit test complete");
        else
            $display("FAIL: Adaptive controller unit errors=%0d", errors);

        $finish;
    end

    initial begin
        #1_000_000;
        $fatal(1, "TB timeout");
    end

endmodule
