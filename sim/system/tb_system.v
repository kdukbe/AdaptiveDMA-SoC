`timescale 1ns/1ps

module tb_system;

reg CLK = 0;
reg RSTN = 0;
always #5 CLK = ~CLK;

// CPU 대신 레지스터를 읽고 쓰는 AXI4-Lite 신호
reg [6:0] S_AXI_AWADDR = 0, S_AXI_ARADDR = 0;
reg [31:0] S_AXI_WDATA = 0;
reg S_AXI_AWVALID = 0, S_AXI_WVALID = 0, S_AXI_BREADY = 0;
reg S_AXI_ARVALID = 0, S_AXI_RREADY = 0;
wire S_AXI_AWREADY, S_AXI_WREADY, S_AXI_BVALID;
wire S_AXI_ARREADY, S_AXI_RVALID;
wire [1:0] S_AXI_BRESP, S_AXI_RRESP;
wire [31:0] S_AXI_RDATA;

// DMA와 DDR 모델 사이의 AXI4 신호
wire [31:0] M_AXI_ARADDR, M_AXI_AWADDR;
wire [7:0] M_AXI_ARLEN, M_AXI_AWLEN, M_AXI_WSTRB;
wire [2:0] M_AXI_ARSIZE, M_AXI_AWSIZE;
wire [1:0] M_AXI_ARBURST, M_AXI_AWBURST;
wire M_AXI_ARVALID, M_AXI_ARREADY, M_AXI_RVALID, M_AXI_RREADY, M_AXI_RLAST;
wire M_AXI_AWVALID, M_AXI_AWREADY, M_AXI_WVALID, M_AXI_WREADY, M_AXI_WLAST;
wire M_AXI_BVALID, M_AXI_BREADY;
wire [63:0] M_AXI_RDATA, M_AXI_WDATA;
wire ar_hs = M_AXI_ARVALID && M_AXI_ARREADY;
wire r_hs = M_AXI_RVALID && M_AXI_RREADY;
wire aw_hs = M_AXI_AWVALID && M_AXI_AWREADY;
wire w_hs = M_AXI_WVALID && M_AXI_WREADY;
wire b_hs = M_AXI_BVALID && M_AXI_BREADY;

top dut (
    .CLK(CLK), .RSTN(RSTN),
    .S_AXI_AWADDR(S_AXI_AWADDR), .S_AXI_AWVALID(S_AXI_AWVALID), .S_AXI_AWREADY(S_AXI_AWREADY),
    .S_AXI_WDATA(S_AXI_WDATA), .S_AXI_WSTRB(4'hF), .S_AXI_WVALID(S_AXI_WVALID), .S_AXI_WREADY(S_AXI_WREADY),
    .S_AXI_BRESP(S_AXI_BRESP), .S_AXI_BVALID(S_AXI_BVALID), .S_AXI_BREADY(S_AXI_BREADY),
    .S_AXI_ARADDR(S_AXI_ARADDR), .S_AXI_ARVALID(S_AXI_ARVALID), .S_AXI_ARREADY(S_AXI_ARREADY),
    .S_AXI_RDATA(S_AXI_RDATA), .S_AXI_RRESP(S_AXI_RRESP), .S_AXI_RVALID(S_AXI_RVALID), .S_AXI_RREADY(S_AXI_RREADY),
    .M_AXI_ARADDR(M_AXI_ARADDR), .M_AXI_ARLEN(M_AXI_ARLEN), .M_AXI_ARSIZE(M_AXI_ARSIZE),
    .M_AXI_ARBURST(M_AXI_ARBURST), .M_AXI_ARVALID(M_AXI_ARVALID), .M_AXI_ARREADY(M_AXI_ARREADY),
    .M_AXI_RDATA(M_AXI_RDATA), .M_AXI_RRESP(2'b00), .M_AXI_RLAST(M_AXI_RLAST),
    .M_AXI_RVALID(M_AXI_RVALID), .M_AXI_RREADY(M_AXI_RREADY),
    .M_AXI_AWADDR(M_AXI_AWADDR), .M_AXI_AWLEN(M_AXI_AWLEN), .M_AXI_AWSIZE(M_AXI_AWSIZE),
    .M_AXI_AWBURST(M_AXI_AWBURST), .M_AXI_AWVALID(M_AXI_AWVALID), .M_AXI_AWREADY(M_AXI_AWREADY),
    .M_AXI_WDATA(M_AXI_WDATA), .M_AXI_WSTRB(M_AXI_WSTRB), .M_AXI_WLAST(M_AXI_WLAST),
    .M_AXI_WVALID(M_AXI_WVALID), .M_AXI_WREADY(M_AXI_WREADY),
    .M_AXI_BRESP(2'b00), .M_AXI_BVALID(M_AXI_BVALID), .M_AXI_BREADY(M_AXI_BREADY)
);

// pause는 특정 채널을 기다리게 한다. stall_mode는 반복 가능한 지연 패턴이다.
reg pause_r = 0, pause_w = 0, pause_b = 0, stall_mode = 0;
integer cycle = 0;
always @(posedge CLK) begin
    if (!RSTN) cycle <= 0;
    else cycle <= cycle + 1;
end
wire ar_enable = !stall_mode || ((cycle % 7) == 0);
wire aw_enable = !stall_mode || ((cycle % 9) == 0);
wire r_enable = !pause_r && (!stall_mode || ((cycle % 5) != 0));
wire w_enable = !pause_w && (!stall_mode || ((cycle % 11) < 4));
wire b_enable = !pause_b && (!stall_mode || ((cycle % 17) == 0));

axi_mem u_mem (
    .CLK(CLK), .RSTN(RSTN),
    .ar_enable(ar_enable), .r_enable(r_enable), .aw_enable(aw_enable), .w_enable(w_enable), .b_enable(b_enable),
    .ARADDR(M_AXI_ARADDR), .ARLEN(M_AXI_ARLEN), .ARVALID(M_AXI_ARVALID), .ARREADY(M_AXI_ARREADY),
    .RDATA(M_AXI_RDATA), .RVALID(M_AXI_RVALID), .RLAST(M_AXI_RLAST), .RREADY(M_AXI_RREADY),
    .AWADDR(M_AXI_AWADDR), .AWLEN(M_AXI_AWLEN), .AWVALID(M_AXI_AWVALID), .AWREADY(M_AXI_AWREADY),
    .WDATA(M_AXI_WDATA), .WSTRB(M_AXI_WSTRB), .WVALID(M_AXI_WVALID), .WLAST(M_AXI_WLAST), .WREADY(M_AXI_WREADY),
    .BVALID(M_AXI_BVALID), .BREADY(M_AXI_BREADY)
);

integer errors = 0, tests = 0;
integer src, dst, bytes, burst_limit, out_limit;
reg [255:0] test_name;
reg [31:0] value;
reg done_seen = 0;
reg command_clear = 0;
integer r_beats, w_beats, ar_count, aw_count, b_count;
integer r_pending, w_pending, max_r_pending, max_w_pending;
integer seen_r_wait, seen_w_wait, seen_r_windows, seen_w_windows;
reg [3:0] levels_seen = 0;

// 에러가 나온 위치와 현재 test 이름을 출력한다.
task fail;
    input [511:0] message;
    begin
        errors = errors + 1;
        $display("ERROR: %0s: %0s at %0t", test_name, message, $time);
    end
endtask

// AW와 W를 함께 시작하지만, 각 채널은 자기 handshake까지 VALID를 유지한다.
task axi_write;
    input [6:0] addr;
    input [31:0] data;
    reg aw_done, w_done;
    begin
        aw_done = 0; w_done = 0;
        @(negedge CLK);
        S_AXI_AWADDR = addr; S_AXI_AWVALID = 1;
        S_AXI_WDATA = data; S_AXI_WVALID = 1;
        while (!aw_done || !w_done) begin
            @(posedge CLK);
            if (S_AXI_AWVALID && S_AXI_AWREADY) aw_done = 1;
            if (S_AXI_WVALID && S_AXI_WREADY) w_done = 1;
            @(negedge CLK);
            if (aw_done) S_AXI_AWVALID = 0;
            if (w_done) S_AXI_WVALID = 0;
        end
        S_AXI_BREADY = 1;
        @(posedge CLK);
        while (!S_AXI_BVALID) @(posedge CLK);
        if (S_AXI_BRESP !== 2'b00) fail("AXI-Lite write response");
        @(negedge CLK);
        S_AXI_BREADY = 0;
    end
endtask

task axi_read;
    input [6:0] addr;
    output [31:0] data;
    begin
        @(negedge CLK);
        S_AXI_ARADDR = addr; S_AXI_ARVALID = 1;
        @(posedge CLK);
        while (!S_AXI_ARREADY) @(posedge CLK);
        @(negedge CLK);
        S_AXI_ARVALID = 0; S_AXI_RREADY = 1;
        @(posedge CLK);
        while (!S_AXI_RVALID) @(posedge CLK);
        data = S_AXI_RDATA;
        if (S_AXI_RRESP !== 2'b00) fail("AXI-Lite read response");
        @(negedge CLK);
        S_AXI_RREADY = 0;
    end
endtask

task reset_system;
    begin
        @(negedge CLK); RSTN = 0;
        repeat (4) @(posedge CLK);
        @(negedge CLK); RSTN = 1;
        repeat (4) @(posedge CLK);
    end
endtask

// 테스트마다 다른 source를 만들고 destination은 반대 값으로 채운다.
task prepare_copy;
    input [255:0] name;
    input integer source, destination, byte_count;
    integer k;
    begin
        @(negedge CLK); command_clear = 1;
        @(negedge CLK); command_clear = 0;
        test_name = name;
        tests = tests + 1;
        src = source; dst = destination; bytes = byte_count;
        $display("TEST %0d: %0s burst=%0d outstanding=%0d rbr=%0d delta=%0d",
                 tests, test_name, burst_limit, out_limit, dut.cfg_rbr_enable, dut.cfg_r_delta_q8);
        for (k = 0; k < bytes; k = k + 1) begin
            u_mem.memory[src+k] = (k*37 + tests*13 + 8'h5A);
            u_mem.memory[dst+k] = ~u_mem.memory[src+k];
        end
        u_mem.memory[dst-1] = 8'hA5;
        u_mem.memory[dst+bytes] = 8'h5A;
        axi_write(7'h08, src);
        axi_write(7'h0C, dst);
        axi_write(7'h10, bytes);
    end
endtask

// burst와 outstanding은 실제 개수로 입력한다. 레지스터에는 1/2/4를 0/1/2로 쓴다.
task fixed_config;
    input integer burst, outstanding, rbr_enable, delta;
    integer out_code;
    begin
        axi_write(7'h70, 0);
        axi_write(7'h30, 0);
        burst_limit = burst; out_limit = outstanding;
        case (outstanding)
            1: out_code = 0;
            2: out_code = 1;
            default: out_code = 2;
        endcase
        axi_write(7'h28, burst | (out_code << 8) | (out_code << 10));
        axi_write(7'h34, 256); axi_write(7'h38, 256);
        axi_write(7'h3C, 32); axi_write(7'h40, 32);
        axi_write(7'h2C, delta | (delta << 16));
        axi_write(7'h30, rbr_enable);
    end
endtask

// TB가 본 handshake와 RTL의 측정 counter를 비교한다.
task check_register;
    input [6:0] addr;
    input [31:0] expected;
    begin
        axi_read(addr, value);
        if (value !== expected) begin
            $display("  register 0x%02h: got=%0d expected=%0d", addr, value, expected);
            fail("register counter mismatch");
        end
    end
endtask

// 주소부터 남은 byte/최대 burst/4 KiB까지의 거리로 예상 transaction 수를 센다.
task expected_transactions;
    input integer addr, count;
    output integer result;
    integer length;
    begin
        result = 0;
        while (count > 0) begin
            length = burst_limit * 8;
            if (length > count) length = count;
            if (length > (4096 - (addr % 4096))) length = 4096 - (addr % 4096);
            addr = addr + length;
            count = count - length;
            result = result + 1;
        end
    end
endtask

task finish_copy;
    integer k, expected_r, expected_w, before_errors;
    begin
        // done은 한 cycle 펄스다. 아래 always 블록이 이를 done_seen에 보관한다.
        while (!done_seen) @(negedge CLK);
        before_errors = errors;
        if (dut.engine_busy || dut.engine_error) fail("DMA completion status");
        for (k = 0; k < bytes; k = k + 1) begin
            if (u_mem.memory[dst+k] !== u_mem.memory[src+k]) begin
                $display("  first mismatch: byte offset=%0d", k);
                fail("destination compare");
                k = bytes;
            end
        end
        if ((u_mem.memory[dst-1] !== 8'hA5) || (u_mem.memory[dst+bytes] !== 8'h5A))
            fail("write outside destination");
        expected_transactions(src, bytes, expected_r);
        expected_transactions(dst, bytes, expected_w);
        check_register(7'h20, bytes/8); check_register(7'h24, bytes/8);
        check_register(7'h58, expected_r); check_register(7'h5C, expected_w);
        check_register(7'h60, seen_r_wait); check_register(7'h64, seen_w_wait);
        check_register(7'h68, seen_r_windows); check_register(7'h6C, seen_w_windows);
        if ((r_beats != bytes/8) || (w_beats != bytes/8) ||
            (ar_count != expected_r) || (aw_count != expected_w) || (b_count != expected_w))
            fail("AXI handshake count");
        if ((r_pending != 0) || (w_pending != 0)) fail("response still pending");
        if (errors == before_errors)
            $display("DONE: %0s bytes=%0d AR/AW/B=%0d/%0d/%0d max_pending=%0d/%0d", test_name,
                     bytes, ar_count, aw_count, b_count, max_r_pending, max_w_pending);
    end
endtask

task run_copy;
    input [255:0] name;
    input integer source, destination, byte_count;
    begin
        prepare_copy(name, source, destination, byte_count);
        axi_write(7'h00, 1);
        finish_copy;
    end
endtask

// CPU 대신 latency sample을 입력한다. Adaptive RTL이 스스로 level을 고른다.
task reach_level;
    input [1:0] target;
    input integer latency;
    integer n;
    begin
        n = 0;
        while ((dut.adapt_level != target) && (n < 20)) begin
            axi_write(7'h74, latency);
            repeat (20) @(posedge CLK);
            n = n + 1;
        end
        if (dut.adapt_level != target) fail("adaptive level did not reach target");
        if (!dut.engine_busy) fail("adaptive transition missed active DMA");
    end
endtask

// 매 command의 handshake, pending, WAIT, window를 독립적으로 센다.
always @(posedge CLK) begin
    if (!RSTN || command_clear || dut.dma_start) begin
        done_seen <= 0;
        r_beats = 0; w_beats = 0; ar_count = 0; aw_count = 0; b_count = 0;
        r_pending = 0; w_pending = 0; max_r_pending = 0; max_w_pending = 0;
        seen_r_wait = 0; seen_w_wait = 0; seen_r_windows = 0; seen_w_windows = 0;
    end else begin
        if (dut.engine_done) done_seen <= 1;
        if (ar_hs) begin ar_count = ar_count + 1; r_pending = r_pending + 1; end
        if (r_hs) r_beats = r_beats + 1;
        if (r_hs && M_AXI_RLAST) r_pending = r_pending - 1;
        if (aw_hs) begin aw_count = aw_count + 1; w_pending = w_pending + 1; end
        if (w_hs) w_beats = w_beats + 1;
        if (b_hs) begin b_count = b_count + 1; w_pending = w_pending - 1; end
        if (r_pending > max_r_pending) max_r_pending = r_pending;
        if (w_pending > max_w_pending) max_w_pending = w_pending;
        if ((r_pending < 0) || (r_pending > out_limit) ||
            (w_pending < 0) || (w_pending > out_limit)) fail("outstanding limit");
        if (dut.engine_busy) begin
            if (dut.r_wait_active) seen_r_wait = seen_r_wait + 1;
            if (dut.w_wait_active) seen_w_wait = seen_w_wait + 1;
            if (dut.r_copy_valid) seen_r_windows = seen_r_windows + 1;
            if (dut.w_copy_valid) seen_w_windows = seen_w_windows + 1;
        end
        if (dut.adapt_enable) begin
            levels_seen[dut.adapt_level] = 1;
            if ((dut.cfg_burst_beats != 16) || (dut.cfg_rd_out_limit != 2) ||
                (dut.cfg_wr_out_limit != 2) || (dut.cfg_rbr_enable != 3)) fail("adaptive DMA preset");
            case (dut.adapt_level)
                0: if (dut.cfg_r_delta_q8 != 256) fail("L0 delta");
                1: if (dut.cfg_r_delta_q8 != 128) fail("L1 delta");
                2: if (dut.cfg_r_delta_q8 != 64) fail("L2 delta");
                3: if (dut.cfg_r_delta_q8 != 0) fail("L3 delta");
            endcase
            if (dut.cfg_r_delta_q8 != dut.cfg_w_delta_q8) fail("read/write adaptive delta");
        end
    end
end

// 직전 cycle에 VALID=1/READY=0이었다면 이번 cycle에도 VALID와 payload가 같아야 한다.
reg ar_stalled = 0, aw_stalled = 0, r_stalled = 0, w_stalled = 0, b_stalled = 0;
reg [44:0] ar_saved, aw_saved;
reg [64:0] r_saved;
reg [72:0] w_saved;
reg saw_ar_stall = 0, saw_aw_stall = 0, saw_r_stall = 0, saw_w_stall = 0;
always @(posedge CLK) begin
    if (!RSTN) begin
        ar_stalled <= 0; aw_stalled <= 0; r_stalled <= 0; w_stalled <= 0; b_stalled <= 0;
    end else begin
        if (ar_stalled && (!M_AXI_ARVALID || ({M_AXI_ARADDR,M_AXI_ARLEN,M_AXI_ARSIZE,M_AXI_ARBURST} !== ar_saved))) fail("AR changed while stalled");
        if (aw_stalled && (!M_AXI_AWVALID || ({M_AXI_AWADDR,M_AXI_AWLEN,M_AXI_AWSIZE,M_AXI_AWBURST} !== aw_saved))) fail("AW changed while stalled");
        if (r_stalled && (!M_AXI_RVALID || ({M_AXI_RLAST,M_AXI_RDATA} !== r_saved))) fail("R changed while stalled");
        if (w_stalled && (!M_AXI_WVALID || ({M_AXI_WLAST,M_AXI_WSTRB,M_AXI_WDATA} !== w_saved))) fail("W changed while stalled");
        if (b_stalled && !M_AXI_BVALID) fail("BVALID dropped while stalled");
        if (ar_hs && ((M_AXI_ARLEN >= burst_limit) || (M_AXI_ARSIZE != 3) || (M_AXI_ARBURST != 1) ||
            (M_AXI_ARADDR[2:0] != 0) || (M_AXI_ARADDR + (M_AXI_ARLEN+1)*8 > 1048576) ||
            ({1'b0,M_AXI_ARADDR[11:0]} + (({5'd0,M_AXI_ARLEN}+13'd1)<<3) > 4096))) fail("AR burst rule");
        if (aw_hs && ((M_AXI_AWLEN >= burst_limit) || (M_AXI_AWSIZE != 3) || (M_AXI_AWBURST != 1) ||
            (M_AXI_AWADDR[2:0] != 0) || (M_AXI_AWADDR + (M_AXI_AWLEN+1)*8 > 1048576) ||
            ({1'b0,M_AXI_AWADDR[11:0]} + (({5'd0,M_AXI_AWLEN}+13'd1)<<3) > 4096))) fail("AW burst rule");
        if (w_hs && (M_AXI_WSTRB !== 8'hFF)) fail("aligned copy WSTRB");
        if ((r_hs !== (dut.dma_rvalid && dut.dma_rready)) ||
            (w_hs !== (dut.dma_wvalid && dut.dma_wready))) fail("regulator handshake mismatch");
        if ((dut.r_wait_active && r_hs) || (dut.w_wait_active && w_hs)) fail("handshake during WAIT");
        ar_stalled <= M_AXI_ARVALID && !M_AXI_ARREADY;
        aw_stalled <= M_AXI_AWVALID && !M_AXI_AWREADY;
        r_stalled <= M_AXI_RVALID && !M_AXI_RREADY;
        w_stalled <= M_AXI_WVALID && !M_AXI_WREADY;
        b_stalled <= M_AXI_BVALID && !M_AXI_BREADY;
        ar_saved <= {M_AXI_ARADDR,M_AXI_ARLEN,M_AXI_ARSIZE,M_AXI_ARBURST};
        aw_saved <= {M_AXI_AWADDR,M_AXI_AWLEN,M_AXI_AWSIZE,M_AXI_AWBURST};
        r_saved <= {M_AXI_RLAST,M_AXI_RDATA};
        w_saved <= {M_AXI_WLAST,M_AXI_WSTRB,M_AXI_WDATA};
        if (ar_stalled) saw_ar_stall <= 1;
        if (aw_stalled) saw_aw_stall <= 1;
        if (r_stalled) saw_r_stall <= 1;
        if (w_stalled) saw_w_stall <= 1;
    end
end

// 여기부터 읽으면 전체 실행 순서를 볼 수 있다.
integer n;
initial begin
    test_name = "reset"; burst_limit = 16; out_limit = 4;
    reset_system;

    // 1. burst 1/2/4/8/16, outstanding 1/2/4와 가장 짧은 copy
    fixed_config(16, 4, 0, 0);
    run_copy("one beat", 'h1000, 'h81000, 8);
    for (n = 1; n <= 16; n = n * 2) begin
        fixed_config(n, 4, 0, 0);
        run_copy("burst setting", 'h1000, 'h81000, 512);
    end
    fixed_config(16, 1, 0, 0); run_copy("outstanding 1", 'h1000, 'h81000, 2048);
    fixed_config(16, 2, 0, 0); run_copy("outstanding 2", 'h1000, 'h81000, 2048);

    // 2. AR와 AW가 서로 다른 위치에서 4 KiB 경계를 만나는 copy
    fixed_config(16, 4, 0, 0);
    run_copy("4KiB split", 'h0FC0, 'h80FE8, 4096);

    // 3. 고정 RBR 100/80/66.7/50/25%. WAIT와 window 계수도 비교한다.
    for (n = 0; n < 5; n = n + 1) begin
        case (n)
            0: fixed_config(16, 4, 3, 0);
            1: fixed_config(16, 4, 3, 64);
            2: fixed_config(16, 4, 3, 128);
            3: fixed_config(16, 4, 3, 256);
            4: fixed_config(16, 4, 3, 768);
        endcase
        run_copy("fixed RBR", 'h0FC0, 'h81000, 4096);
        check_register(7'h68, 16); check_register(7'h6C, 16);
        if ((n == 0) && ((seen_r_wait != 0) || (seen_w_wait != 0))) fail("100 percent inserted WAIT");
        if ((n != 0) && ((seen_r_wait == 0) || (seen_w_wait == 0))) fail("RBR WAIT was not exercised");
    end

    // 4. 네 요청이 쌓인 상태, 지연된 B, 연속 backpressure
    fixed_config(16, 4, 0, 0);
    pause_r = 1; pause_w = 1; pause_b = 1;
    prepare_copy("pending and delayed B", 'h1000, 'h81000, 4096);
    axi_write(7'h00, 1);
    repeat (30) @(posedge CLK);
    @(negedge CLK);
    if ((r_pending != 4) || (w_pending != 4)) fail("four pending requests not reached");
    pause_r = 0; pause_w = 0;
    repeat (150) @(posedge CLK);
    @(negedge CLK);
    if ((u_mem.b_pending == 0) || done_seen) fail("delayed B was not exercised");
    pause_b = 0;
    finish_copy;
    stall_mode = 1;
    fixed_config(16, 4, 3, 256);
    run_copy("RBR with backpressure", 'h0FC0, 'h80FE8, 4096);
    stall_mode = 0;

    // 5. WAIT 중 RBR 해제 후에도 완료하는지 확인한다.
    fixed_config(16, 4, 3, 768);
    prepare_copy("disable during WAIT", 'h1000, 'h81000, 4096);
    axi_write(7'h00, 1);
    wait (dut.r_wait_active || dut.w_wait_active);
    axi_write(7'h30, 0);
    finish_copy;

    // 6. W가 막혀 전송 중인 상태에서 DMA와 DDR 모델을 함께 reset한다.
    fixed_config(16, 4, 0, 0);
    prepare_copy("reset and restart", 'h1000, 'h81000, 4096);
    pause_w = 1;
    axi_write(7'h00, 1);
    repeat (30) @(posedge CLK);
    if (!dut.engine_busy) fail("reset did not interrupt active DMA");
    reset_system;
    pause_w = 0;
    fixed_config(16, 4, 0, 0);
    axi_write(7'h08, src); axi_write(7'h0C, dst); axi_write(7'h10, bytes);
    axi_write(7'h00, 1);
    finish_copy;

    // 7. 한 command 안에서 L3 -> L0 -> L3. 이후 reset 없이 3회 더 복사한다.
    fixed_config(16, 4, 0, 0);
    axi_write(7'h78, {16'd16000,16'd14000});
    axi_write(7'h7C, {6'd0,2'd3,8'd2,8'd2,8'd1});
    axi_write(7'h70, 32'h101);
    stall_mode = 1;
    for (n = 0; n < 4; n = n + 1) begin
        prepare_copy("adaptive feedback", 'h0FC0, 'h80FC0, 65536);
        axi_write(7'h00, 1);
        reach_level(0, 18000);
        reach_level(3, 12000);
        finish_copy;
    end
    if (levels_seen != 4'b1111) fail("not all adaptive levels were exercised");
    if (!(saw_ar_stall && saw_aw_stall && saw_r_stall && saw_w_stall)) fail("missing backpressure exercise");
    errors = errors + u_mem.errors;
    $display("SUMMARY: copies=%0d levels=%04b AR/AW/R/W_stall=%b%b%b%b errors=%0d", tests,
             levels_seen, saw_ar_stall, saw_aw_stall, saw_r_stall, saw_w_stall, errors);
    if (errors == 0) $display("PASS: Verilog system test complete");
    else $display("FAIL: Verilog system test errors=%0d", errors);
    $finish;
end

initial begin
    #20000000;
    $display("FAIL: system timeout, test=%0s", test_name);
    $finish;
end

endmodule
