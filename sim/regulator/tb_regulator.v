`timescale 1ns/1ps

module tb_regulator;

reg         CLK;
reg         RSTN;
reg         enable;
reg  [31:0] threshold_bytes;
reg  [31:0] nominal_cycles;
reg  [15:0] delta_q8;
reg         s_valid;
wire        s_ready;
reg  [7:0]  s_strobe;
wire        m_valid;
reg         m_ready;
wire [31:0] copy_cycles;
wire        copy_valid;
wire [31:0] idle_cycles;
wire        wait_active;

wire s_hs;
wire m_hs;

integer error_count;
integer in_count;
integer out_count;
integer copy_count;
integer wait_count;
reg [31:0] last_copy;
reg [31:0] last_idle;

assign s_hs = s_valid && s_ready;
assign m_hs = m_valid && m_ready;

regulator dut (
    .CLK(CLK),
    .RSTN(RSTN),

    .enable(enable),
    .threshold_bytes(threshold_bytes),
    .nominal_cycles(nominal_cycles),
    .delta_q8(delta_q8),

    .s_valid(s_valid),
    .s_ready(s_ready),
    .s_strobe(s_strobe),

    .m_valid(m_valid),
    .m_ready(m_ready),

    .copy_cycles(copy_cycles),
    .copy_valid(copy_valid),
    .idle_cycles(idle_cycles),
    .wait_active(wait_active)
);

always #5 CLK = !CLK;

always @(posedge CLK) begin
    if (!RSTN) begin
        in_count   <= 0;
        out_count  <= 0;
        copy_count <= 0;
        wait_count <= 0;
        last_copy  <= 32'd0;
        last_idle  <= 32'd0;
    end else begin
        if (s_hs)
            in_count <= in_count + 1;

        if (m_hs)
            out_count <= out_count + 1;

        if (copy_valid) begin
            copy_count <= copy_count + 1;
            last_copy  <= copy_cycles;
            last_idle  <= idle_cycles;
        end

        if (wait_active)
            wait_count <= wait_count + 1;

        if (s_hs != m_hs) begin
            error_count = error_count + 1;
            $display("ERROR: input/output handshake mismatch");
        end

        if (wait_active && (s_hs || m_hs)) begin
            error_count = error_count + 1;
            $display("ERROR: handshake during WAIT");
        end
    end
end

task reset_dut;
    begin
        @(negedge CLK);
        RSTN = 1'b0;
        s_valid = 1'b0;
        m_ready = 1'b1;
        repeat (2) @(posedge CLK);
        @(negedge CLK);
        RSTN = 1'b1;
        repeat (2) @(posedge CLK);
    end
endtask

task send_beats;
    input integer count;
    input [7:0] strobe;
    integer k;
    begin
        @(negedge CLK);
        s_valid  = 1'b1;
        s_strobe = strobe;

        for (k = 0; k < count; k = k + 1) begin
            @(posedge CLK);
            while (!s_ready)
                @(posedge CLK);
        end

        @(negedge CLK);
        s_valid = 1'b0;
    end
endtask

// Natural AXI stalls must reduce the inserted WAIT from Eq. (2).
task test_stall_compensation;
    begin
        threshold_bytes = 32'd32;
        delta_q8 = 16'd256;
        reset_dut;

        @(negedge CLK);
        s_valid = 1'b1;
        m_ready = 1'b1;
        @(posedge CLK);

        @(negedge CLK);
        m_ready = 1'b0;
        repeat (3) @(posedge CLK);

        @(negedge CLK);
        m_ready = 1'b1;
        repeat (3) @(posedge CLK);
        @(negedge CLK);
        s_valid = 1'b0;

        wait (!wait_active);
        repeat (2) @(posedge CLK);

        if ((copy_count != 1) || (last_copy != 32'd7) ||
            (last_idle != 32'd1) || (wait_count != 1)) begin
            error_count = error_count + 1;
            $display("ERROR: three-cycle stall compensation");
        end else begin
            $display("STALL COMPENSATION PASS: copy=7 idle=1");
        end

        reset_dut;

        @(negedge CLK);
        s_valid = 1'b1;
        m_ready = 1'b1;
        @(posedge CLK);

        @(negedge CLK);
        m_ready = 1'b0;
        repeat (4) @(posedge CLK);

        @(negedge CLK);
        m_ready = 1'b1;
        repeat (3) @(posedge CLK);
        @(negedge CLK);
        s_valid = 1'b0;
        repeat (2) @(posedge CLK);

        if ((copy_count != 1) || (last_copy != 32'd8) ||
            (last_idle != 32'd0) || (wait_count != 0)) begin
            error_count = error_count + 1;
            $display("ERROR: fully compensated natural stall");
        end else begin
            $display("FULL STALL COMPENSATION PASS: copy=8 idle=0");
        end
    end
endtask

// A partial window and its idle time intentionally continue across jobs.
task test_continuous_window;
    begin
        threshold_bytes = 32'd32;
        delta_q8 = 16'd256;
        reset_dut;

        send_beats(2, 8'hFF);
        repeat (3) @(posedge CLK);
        send_beats(2, 8'hFF);
        wait (!wait_active);
        repeat (2) @(posedge CLK);

        if ((copy_count != 1) || (last_copy != 32'd7) ||
            (last_idle != 32'd1) || (wait_count != 1)) begin
            error_count = error_count + 1;
            $display("ERROR: continuous window across idle time");
        end else begin
            $display("CONTINUOUS WINDOW PASS: copy=7 idle=1");
        end
    end
endtask

initial begin
    CLK = 1'b0;
    RSTN = 1'b0;
    enable = 1'b0;
    threshold_bytes = 32'd32;
    nominal_cycles = 32'd4;
    delta_q8 = 16'd256;
    s_valid = 1'b0;
    s_strobe = 8'hFF;
    m_ready = 1'b1;
    error_count = 0;

    // Disabled regulator is a transparent handshake path.
    reset_dut;
    send_beats(8, 8'hFF);

    if ((in_count != 8) || (out_count != 8) ||
        (copy_count != 0) || (wait_count != 0)) begin
        error_count = error_count + 1;
        $display("ERROR: disabled pass-through");
    end else begin
        $display("PASS-THROUGH PASS");
    end

    // Runtime nominal values above 65535 are invalid and use safe bypass.
    enable = 1'b1;
    threshold_bytes = 32'd32;
    nominal_cycles = 32'd65536;
    delta_q8 = 16'd256;
    reset_dut;
    send_beats(4, 8'hFF);

    if ((in_count != 4) || (out_count != 4) ||
        (copy_count != 0) || (wait_count != 0)) begin
        error_count = error_count + 1;
        $display("ERROR: invalid nominal did not bypass");
    end else begin
        $display("INVALID NOMINAL BYPASS PASS");
    end

    // READY low before the first transfer must not start the monitor.
    enable = 1'b1;
    threshold_bytes = 32'd32;
    nominal_cycles = 32'd4;
    delta_q8 = 16'd0;
    reset_dut;

    @(negedge CLK);
    m_ready = 1'b0;
    s_valid = 1'b1;
    repeat (3) @(posedge CLK);

    if (copy_count != 0) begin
        error_count = error_count + 1;
        $display("ERROR: monitor counted a blocked transfer");
    end

    @(negedge CLK);
    m_ready = 1'b1;
    repeat (4) @(posedge CLK);
    @(negedge CLK);
    s_valid = 1'b0;
    repeat (2) @(posedge CLK);

    if ((copy_count != 1) || (last_copy != 32'd4)) begin
        error_count = error_count + 1;
        $display("ERROR: post-gate monitor copy=%0d count=%0d",
                 last_copy, copy_count);
    end else begin
        $display("POST-GATE MONITOR PASS: copy_cycles=%0d", last_copy);
    end

    test_stall_compensation;
    test_continuous_window;

    // Four 8-byte beats followed by four WAIT cycles, repeated twice.
    threshold_bytes = 32'd32;
    delta_q8 = 16'd256;
    reset_dut;
    send_beats(8, 8'hFF);
    wait (!wait_active);
    repeat (2) @(posedge CLK);

    if ((copy_count != 2) || (last_copy != 32'd4) ||
        (last_idle != 32'd4) || (wait_count != 8)) begin
        error_count = error_count + 1;
        $display("ERROR: fixed regulation copy=%0d idle=%0d waits=%0d windows=%0d",
                 last_copy, last_idle, wait_count, copy_count);
    end else begin
        $display("FIXED REGULATION PASS: windows=2 idle=4");
    end

    // Minimum paper-supported threshold: one 8-byte AXI beat.
    threshold_bytes = 32'd8;
    delta_q8 = 16'd256;
    reset_dut;
    send_beats(2, 8'hFF);
    wait (!wait_active);
    repeat (2) @(posedge CLK);

    if ((copy_count != 2) || (last_copy != 32'd1) ||
        (last_idle != 32'd7) || (wait_count != 14)) begin
        error_count = error_count + 1;
        $display("ERROR: one-beat threshold");
    end else begin
        $display("ONE-BEAT LOGIC PASS");
    end

    // A setting changed in the middle of a window applies next window.
    threshold_bytes = 32'd32;
    reset_dut;
    delta_q8 = 16'd256;

    @(negedge CLK);
    s_valid = 1'b1;
    repeat (2) @(posedge CLK);
    @(negedge CLK);
    delta_q8 = 16'd0;
    repeat (2) @(posedge CLK);
    @(negedge CLK);
    s_valid = 1'b0;

    wait (!wait_active);
    send_beats(4, 8'hFF);
    repeat (2) @(posedge CLK);

    if ((copy_count != 2) || (wait_count != 4) ||
        (last_idle != 32'd0)) begin
        error_count = error_count + 1;
        $display("ERROR: window configuration snapshot");
    end else begin
        $display("CONFIG WINDOW PASS");
    end

    // Runtime nominal is also captured at the window start.
    threshold_bytes = 32'd32;
    nominal_cycles = 32'd4;
    delta_q8 = 16'd256;
    reset_dut;

    @(negedge CLK);
    s_valid = 1'b1;
    repeat (2) @(posedge CLK);
    @(negedge CLK);
    nominal_cycles = 32'd8;
    repeat (2) @(posedge CLK);
    @(negedge CLK);
    s_valid = 1'b0;

    wait (!wait_active);
    send_beats(4, 8'hFF);
    wait (!wait_active);
    repeat (2) @(posedge CLK);

    if ((copy_count != 2) || (wait_count != 16) ||
        (last_idle != 32'd12)) begin
        error_count = error_count + 1;
        $display("ERROR: runtime nominal snapshot waits=%0d idle=%0d",
                 wait_count, last_idle);
    end else begin
        $display("RUNTIME NOMINAL PASS: first=4 next=8");
    end

    // Disabling during WAIT must release the channel without a stale window.
    threshold_bytes = 32'd32;
    nominal_cycles = 32'd4;
    delta_q8 = 16'd256;
    reset_dut;
    send_beats(4, 8'hFF);
    wait (wait_active);

    @(negedge CLK);
    enable = 1'b0;
    @(posedge CLK);

    if (wait_active || !s_ready) begin
        error_count = error_count + 1;
        $display("ERROR: runtime disable did not release WAIT");
    end

    send_beats(2, 8'hFF);

    if ((in_count != 6) || (out_count != 6)) begin
        error_count = error_count + 1;
        $display("ERROR: runtime disable lost a beat");
    end

    @(negedge CLK);
    enable = 1'b1;
    send_beats(4, 8'hFF);
    wait (!wait_active);
    repeat (2) @(posedge CLK);

    if ((copy_count != 2) || (last_copy != 32'd4) ||
        (last_idle != 32'd4)) begin
        error_count = error_count + 1;
        $display("ERROR: runtime re-enable window");
    end else begin
        $display("RUNTIME BYPASS PASS");
    end

    // WSTRB byte count: 4 + 2 + 4 = 10 bytes in three cycles.
    threshold_bytes = 32'd10;
    delta_q8 = 16'd0;
    reset_dut;

    @(negedge CLK);
    s_valid = 1'b1;
    s_strobe = 8'h0F;
    @(posedge CLK);
    @(negedge CLK);
    s_strobe = 8'h03;
    @(posedge CLK);
    @(negedge CLK);
    s_strobe = 8'h0F;
    @(posedge CLK);
    @(negedge CLK);
    s_valid = 1'b0;
    repeat (2) @(posedge CLK);

    if ((copy_count != 1) || (last_copy != 32'd3)) begin
        error_count = error_count + 1;
        $display("ERROR: WSTRB byte measurement");
    end else begin
        $display("WSTRB PASS: copy_cycles=3");
    end

    // Reset must remove an active wait immediately.
    threshold_bytes = 32'd32;
    delta_q8 = 16'd256;
    reset_dut;
    send_beats(4, 8'hFF);
    wait (wait_active);
    @(negedge CLK);
    RSTN = 1'b0;
    @(posedge CLK);
    @(negedge CLK);

    if (wait_active || !s_ready) begin
        error_count = error_count + 1;
        $display("ERROR: reset did not clear WAIT");
    end else begin
        $display("RESET WAIT PASS");
    end

    if (error_count == 0)
        $display("PASS: tb_regulator");
    else
        $display("FAIL: tb_regulator errors=%0d", error_count);

    $finish;
end

initial begin
    #20000;
    $display("FAIL: tb_regulator timeout");
    $finish;
end

endmodule
