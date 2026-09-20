`timescale 1ns/1ps

// TB용 DDR: 받은 AR/AW 주소와 길이에 맞춰 읽고 쓴다.
module axi_mem (
    input wire CLK, RSTN,
    input wire ar_enable, r_enable, aw_enable, w_enable, b_enable,
    input wire [31:0] ARADDR, AWADDR,
    input wire [7:0] ARLEN, AWLEN,
    input wire ARVALID, AWVALID,
    output wire ARREADY, AWREADY,
    output reg [63:0] RDATA,
    output reg RVALID, RLAST,
    input wire RREADY,
    input wire [63:0] WDATA,
    input wire [7:0] WSTRB,
    input wire WVALID, WLAST,
    output wire WREADY,
    output reg BVALID,
    input wire BREADY
);

reg [7:0] memory [0:1048575];
reg [31:0] r_addr [0:7], w_addr [0:7];
reg [7:0] r_len [0:7], w_len [0:7];
reg [2:0] r_wr, r_rd, w_wr, w_rd;
reg [3:0] r_count, w_count;
reg [8:0] r_next_beat;
reg [7:0] w_beat;
reg [7:0] b_pending;
integer j;
integer errors = 0;

wire ar_hs = ARVALID && ARREADY;
wire r_done = RVALID && RREADY && RLAST;
wire aw_hs = AWVALID && AWREADY;
wire w_hs = WVALID && WREADY;
wire w_done = w_hs && WLAST;
wire b_hs = BVALID && BREADY;
wire [31:0] read_addr = r_addr[r_rd] + (r_next_beat << 3);
wire [31:0] write_addr = w_addr[w_rd] + (w_beat << 3);

assign ARREADY = RSTN && ar_enable && (r_count < 8);
assign AWREADY = RSTN && aw_enable && (w_count < 8);
assign WREADY = RSTN && w_enable && (w_count != 0);

// AR 요청을 순서대로 보관한다. 마지막 R beat를 보낸 뒤에 요청을 꺼낸다.
always @(posedge CLK) begin
    if (!RSTN) begin
        r_wr <= 0;
        r_rd <= 0;
        r_count <= 0;
    end else begin
        if (ar_hs) begin
            r_addr[r_wr] <= ARADDR;
            r_len[r_wr] <= ARLEN;
            r_wr <= r_wr + 1'b1;
        end
        if (r_done)
            r_rd <= r_rd + 1'b1;
        case ({ar_hs, r_done})
            2'b10: r_count <= r_count + 1'b1;
            2'b01: r_count <= r_count - 1'b1;
            default: r_count <= r_count;
        endcase
    end
end

// RVALID를 올렸으면 RREADY가 올 때까지 DATA/LAST/VALID를 유지한다.
// r_next_beat는 다음에 RDATA에 넣을 beat 번호다.
always @(posedge CLK) begin
    if (!RSTN) begin
        RVALID <= 0;
        RLAST <= 0;
        RDATA <= 0;
        r_next_beat <= 0;
    end else if (r_done) begin
        RVALID <= 0;
        RLAST <= 0;
        r_next_beat <= 0;
    end else if (!RVALID || RREADY) begin
        if (r_enable && (r_count != 0)) begin
            for (j = 0; j < 8; j = j + 1)
                RDATA[j*8 +: 8] <= memory[read_addr + j];
            RLAST <= (r_next_beat == r_len[r_rd]);
            RVALID <= 1;
            r_next_beat <= r_next_beat + 1'b1;
        end else begin
            RVALID <= 0;
            RLAST <= 0;
        end
    end
end

// AW 요청은 WLAST까지 보관한다. AXI4의 동일 ID 순서를 모델링한다.
always @(posedge CLK) begin
    if (!RSTN) begin
        w_wr <= 0;
        w_rd <= 0;
        w_count <= 0;
    end else begin
        if (aw_hs) begin
            w_addr[w_wr] <= AWADDR;
            w_len[w_wr] <= AWLEN;
            w_wr <= w_wr + 1'b1;
        end
        if (w_done)
            w_rd <= w_rd + 1'b1;
        case ({aw_hs, w_done})
            2'b10: w_count <= w_count + 1'b1;
            2'b01: w_count <= w_count - 1'b1;
            default: w_count <= w_count;
        endcase
    end
end

// handshake된 W beat의 유효 byte만 메모리에 쓴다.
integer k;
always @(posedge CLK) begin
    if (!RSTN) begin
        w_beat <= 0;
    end else if (w_hs) begin
        if (WLAST !== (w_beat == w_len[w_rd])) begin
            errors = errors + 1;
            $display("ERROR: WLAST does not match accepted AWLEN");
        end
        for (k = 0; k < 8; k = k + 1)
            if (WSTRB[k])
                memory[write_addr + k] <= WDATA[k*8 +: 8];
        if (WLAST)
            w_beat <= 0;
        else
            w_beat <= w_beat + 1'b1;
    end
end

// 완료한 W burst마다 B response 하나를 반환한다.
always @(posedge CLK) begin
    if (!RSTN)
        b_pending <= 0;
    else begin
        case ({w_done, b_hs})
            2'b10: b_pending <= b_pending + 1'b1;
            2'b01: b_pending <= b_pending - 1'b1;
            default: b_pending <= b_pending;
        endcase
    end
end

always @(posedge CLK) begin
    if (!RSTN)
        BVALID <= 0;
    else if (b_hs)
        BVALID <= 0;
    else if (!BVALID && b_enable && (b_pending != 0))
        BVALID <= 1;
end

endmodule
