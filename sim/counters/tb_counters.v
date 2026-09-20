`timescale 1ns/1ps

module tb_counters;

reg CLK;
reg RSTN;
reg clear;
reg active;
reg arvalid;
reg arready;
reg rvalid;
reg rready;
reg awvalid;
reg awready;
reg wvalid;
reg wready;
reg bvalid;
reg bready;
reg r_wait_active;
reg w_wait_active;
reg r_window_done;
reg w_window_done;

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

integer error_count;

counters dut (
    .CLK(CLK),
    .RSTN(RSTN),
    .clear(clear),
    .active(active),
    .arvalid(arvalid),
    .arready(arready),
    .rvalid(rvalid),
    .rready(rready),
    .awvalid(awvalid),
    .awready(awready),
    .wvalid(wvalid),
    .wready(wready),
    .bvalid(bvalid),
    .bready(bready),
    .r_wait_active(r_wait_active),
    .w_wait_active(w_wait_active),
    .r_window_done(r_window_done),
    .w_window_done(w_window_done),
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

always #5 CLK = !CLK;

task clear_inputs;
    begin
        arvalid = 1'b0;
        arready = 1'b0;
        rvalid = 1'b0;
        rready = 1'b0;
        awvalid = 1'b0;
        awready = 1'b0;
        wvalid = 1'b0;
        wready = 1'b0;
        bvalid = 1'b0;
        bready = 1'b0;
        r_wait_active = 1'b0;
        w_wait_active = 1'b0;
        r_window_done = 1'b0;
        w_window_done = 1'b0;
    end
endtask

initial begin
    CLK = 1'b0;
    RSTN = 1'b0;
    clear = 1'b0;
    active = 1'b0;
    error_count = 0;
    clear_inputs;

    repeat (3) @(posedge CLK);
    @(negedge CLK);
    RSTN = 1'b1;
    clear = 1'b1;
    @(posedge CLK);
    @(negedge CLK);
    clear = 1'b0;
    active = 1'b1;

    // Three AR stalls followed by two accepted read transactions.
    arvalid = 1'b1;
    repeat (3) @(posedge CLK);
    @(negedge CLK);
    arready = 1'b1;
    repeat (2) @(posedge CLK);

    // Two R, one AW, three W, and four B stall cycles.
    @(negedge CLK);
    clear_inputs;
    rvalid = 1'b1;
    repeat (2) @(posedge CLK);

    @(negedge CLK);
    clear_inputs;
    awvalid = 1'b1;
    @(posedge CLK);

    @(negedge CLK);
    clear_inputs;
    wvalid = 1'b1;
    repeat (3) @(posedge CLK);

    @(negedge CLK);
    clear_inputs;
    bvalid = 1'b1;
    repeat (4) @(posedge CLK);

    // One accepted write transaction and independent RBR statistics.
    @(negedge CLK);
    clear_inputs;
    awvalid = 1'b1;
    awready = 1'b1;
    r_wait_active = 1'b1;
    w_wait_active = 1'b1;
    r_window_done = 1'b1;
    w_window_done = 1'b1;
    @(posedge CLK);

    @(negedge CLK);
    clear_inputs;
    r_wait_active = 1'b1;
    repeat (2) @(posedge CLK);

    @(negedge CLK);
    clear_inputs;
    #1;

    if ((stall_ar != 32'd3) || (stall_r != 32'd2) ||
        (stall_aw != 32'd1) || (stall_w != 32'd3) ||
        (stall_b != 32'd4) || (read_txns != 32'd2) ||
        (write_txns != 32'd1) || (r_wait_cycles != 32'd3) ||
        (w_wait_cycles != 32'd1) || (r_windows != 32'd1) ||
        (w_windows != 32'd1)) begin
        error_count = error_count + 1;
        $display("ERROR: counter values");
    end else begin
        $display("COUNT PASS: stalls=3/2/1/3/4 txns=2/1");
    end

    // Inactive cycles do not change a completed command's result.
    active = 1'b0;
    arvalid = 1'b1;
    r_wait_active = 1'b1;
    repeat (2) @(posedge CLK);

    if ((stall_ar != 32'd3) || (r_wait_cycles != 32'd3)) begin
        error_count = error_count + 1;
        $display("ERROR: inactive counter changed");
    end else begin
        $display("INACTIVE HOLD PASS");
    end

    // A new command clears every counter.
    @(negedge CLK);
    clear = 1'b1;
    @(posedge CLK);
    #1;

    if ((stall_ar != 0) || (stall_r != 0) || (stall_aw != 0) ||
        (stall_w != 0) || (stall_b != 0) || (read_txns != 0) ||
        (write_txns != 0) || (r_wait_cycles != 0) ||
        (w_wait_cycles != 0) || (r_windows != 0) || (w_windows != 0)) begin
        error_count = error_count + 1;
        $display("ERROR: clear did not reset counters");
    end else begin
        $display("CLEAR PASS");
    end

    if (error_count == 0)
        $display("PASS: tb_counters");
    else
        $display("FAIL: tb_counters errors=%0d", error_count);

    $finish;
end

initial begin
    #10000;
    $display("FAIL: tb_counters timeout");
    $finish;
end

endmodule
