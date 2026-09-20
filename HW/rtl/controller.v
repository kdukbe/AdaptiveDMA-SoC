`timescale 1ns/1ps

module controller #(
    parameter AW = 7,
    parameter DW = 32,
    parameter RBR_R_BYTES_DEFAULT = 32'd256,
    parameter RBR_W_BYTES_DEFAULT = 32'd256,
    parameter RBR_R_NOM_DEFAULT   = 32'd32,
    parameter RBR_W_NOM_DEFAULT   = 32'd32
)(
    input  wire              CLK,
    input  wire              RSTN,

    // AW channel
    input  wire [AW-1:0]     AWADDR,
    input  wire              AWVALID,
    output wire              AWREADY,
    // W channel
    input  wire [DW-1:0]    WDATA,
    input  wire [DW/8-1:0]  WSTRB,
    input  wire             WVALID,
    output wire             WREADY,
    // B channel
    output wire [1:0]       BRESP,
    output wire             BVALID,
    input  wire             BREADY,
    // AR channel
    input  wire [AW-1:0]    ARADDR,
    input  wire             ARVALID,
    output wire             ARREADY,
    // R channel
    output wire [DW-1:0]    RDATA,
    output wire [1:0]       RRESP,
    output wire             RVALID,
    input  wire             RREADY,

    output reg              start_pulse,
    output reg              soft_reset_pulse,

    output wire [31:0]      cfg_src_addr,
    output wire [31:0]      cfg_dst_addr,
    output wire [31:0]      cfg_transfer_bytes,
    output wire [7:0]       cfg_burst_beats,
    output wire [1:0]       cfg_rd_out_limit,
    output wire [1:0]       cfg_wr_out_limit,
    output wire [15:0]      cfg_r_delta_q8,
    output wire [15:0]      cfg_w_delta_q8,
    output wire [1:0]       cfg_rbr_enable,
    output wire [31:0]      cfg_r_threshold_bytes,
    output wire [31:0]      cfg_w_threshold_bytes,
    output wire [31:0]      cfg_r_nominal_cycles,
    output wire [31:0]      cfg_w_nominal_cycles,

    output wire             adapt_enable,
    output reg              adapt_restart,
    output wire [31:0]      adapt_latency_sample,
    output reg              adapt_sample_valid,
    output wire [15:0]      adapt_low_limit,
    output wire [15:0]      adapt_high_limit,
    output wire [7:0]       adapt_hold_samples,
    output wire [7:0]       adapt_low_confirm,
    output wire [7:0]       adapt_high_confirm,
    output wire [1:0]       adapt_initial_level,
    input  wire [1:0]       adapt_level,
    input  wire             adapt_config_valid,

    input  wire             engine_busy,
    input  wire             engine_done,
    input  wire             engine_error,

    input  wire [31:0]      cyc_total,
    input  wire [31:0]      cyc_read,
    input  wire [31:0]      cyc_write,
    input  wire [31:0]      read_beats,
    input  wire [31:0]      write_beats,
    input  wire [31:0]      stall_ar,
    input  wire [31:0]      stall_r,
    input  wire [31:0]      stall_aw,
    input  wire [31:0]      stall_w,
    input  wire [31:0]      stall_b,
    input  wire [31:0]      read_txns,
    input  wire [31:0]      write_txns,
    input  wire [31:0]      r_wait_cycles,
    input  wire [31:0]      w_wait_cycles,
    input  wire [31:0]      r_windows,
    input  wire [31:0]      w_windows
);

// Register map
localparam [AW-1:0] ADDR_CTRL          = 7'h00;
localparam [AW-1:0] ADDR_STATUS        = 7'h04;
localparam [AW-1:0] ADDR_SRC_ADDR      = 7'h08;
localparam [AW-1:0] ADDR_DST_ADDR      = 7'h0c;
localparam [AW-1:0] ADDR_TRANSFER_BYTES = 7'h10;
localparam [AW-1:0] ADDR_CYC_TOTAL     = 7'h14;
localparam [AW-1:0] ADDR_CYC_READ      = 7'h18;
localparam [AW-1:0] ADDR_CYC_WRITE     = 7'h1c;
localparam [AW-1:0] ADDR_READ_BEATS    = 7'h20;
localparam [AW-1:0] ADDR_WRITE_BEATS   = 7'h24;
localparam [AW-1:0] ADDR_DMA_CFG       = 7'h28;
localparam [AW-1:0] ADDR_RBR_CFG       = 7'h2c;
localparam [AW-1:0] ADDR_RBR_CTRL      = 7'h30;
localparam [AW-1:0] ADDR_RBR_R_BYTES   = 7'h34;
localparam [AW-1:0] ADDR_RBR_W_BYTES   = 7'h38;
localparam [AW-1:0] ADDR_RBR_R_NOM     = 7'h3c;
localparam [AW-1:0] ADDR_RBR_W_NOM     = 7'h40;
localparam [AW-1:0] ADDR_STALL_AR      = 7'h44;
localparam [AW-1:0] ADDR_STALL_R       = 7'h48;
localparam [AW-1:0] ADDR_STALL_AW      = 7'h4c;
localparam [AW-1:0] ADDR_STALL_W       = 7'h50;
localparam [AW-1:0] ADDR_STALL_B       = 7'h54;
localparam [AW-1:0] ADDR_READ_TXNS     = 7'h58;
localparam [AW-1:0] ADDR_WRITE_TXNS    = 7'h5c;
localparam [AW-1:0] ADDR_R_WAIT        = 7'h60;
localparam [AW-1:0] ADDR_W_WAIT        = 7'h64;
localparam [AW-1:0] ADDR_R_WINDOWS     = 7'h68;
localparam [AW-1:0] ADDR_W_WINDOWS     = 7'h6c;
localparam [AW-1:0] ADDR_ADAPT_CTRL    = 7'h70;
localparam [AW-1:0] ADDR_LAT_SAMPLE    = 7'h74;
localparam [AW-1:0] ADDR_LAT_LIMITS    = 7'h78;
localparam [AW-1:0] ADDR_ADAPT_POLICY  = 7'h7c;

localparam WRIDLE  = 2'd0;
localparam WRDATA  = 2'd1;
localparam WRRESP  = 2'd2;
localparam WRRESET = 2'd3;

localparam RDIDLE  = 2'd0;
localparam RDDATA  = 2'd1;
localparam RDRESET = 2'd2;

// AXI write channel
reg  [1:0]    wstate;
reg  [1:0]    wnext;
reg  [AW-1:0] waddr;

wire          aw_hs;
wire          w_hs;
wire [DW-1:0] wmask;

assign AWREADY = (wstate == WRIDLE);
assign WREADY  = (wstate == WRDATA);
assign BRESP   = 2'b00;
assign BVALID  = (wstate == WRRESP);

assign aw_hs = AWVALID & AWREADY;
assign w_hs  = WVALID  & WREADY;
assign wmask = {{8{WSTRB[3]}}, {8{WSTRB[2]}}, {8{WSTRB[1]}}, {8{WSTRB[0]}}};

always @(posedge CLK) begin
    if (!RSTN)
        wstate <= WRRESET;
    else
        wstate <= wnext;
end

always @(*) begin
    case (wstate)
        WRIDLE:  wnext = AWVALID ? WRDATA : WRIDLE;
        WRDATA:  wnext = WVALID  ? WRRESP : WRDATA;
        WRRESP:  wnext = BREADY  ? WRIDLE : WRRESP;
        default: wnext = WRIDLE;
    endcase
end

always @(posedge CLK) begin
    if (!RSTN)
        waddr <= {AW{1'b0}};
    else if (aw_hs)
        waddr <= AWADDR[AW-1:0];
end

// AXI read channel
reg  [1:0]    rstate = RDRESET;
reg  [1:0]    rnext;
reg  [DW-1:0] rdata;
wire          ar_hs;
wire [AW-1:0] raddr;

assign ARREADY = (rstate == RDIDLE);
assign RDATA   = rdata;
assign RRESP   = 2'b00;
assign RVALID  = (rstate == RDDATA);

assign ar_hs = ARVALID & ARREADY;
assign raddr = ARADDR[AW-1:0];

always @(posedge CLK) begin
    if (!RSTN)
        rstate <= RDRESET;
    else
        rstate <= rnext;
end

always @(*) begin
    case (rstate)
        RDIDLE:  rnext = ARVALID ? RDDATA : RDIDLE;
        RDDATA:  rnext = (RREADY && RVALID) ? RDIDLE : RDDATA;
        default: rnext = RDIDLE;
    endcase
end

// configuration registers
reg [31:0] int_src_addr;
reg [31:0] int_dst_addr;
reg [31:0] int_transfer_bytes;
reg [11:0] int_dma_cfg;
reg [31:0] int_rbr_cfg;
reg [1:0]  int_rbr_ctrl;
reg [31:0] int_r_threshold_bytes;
reg [31:0] int_w_threshold_bytes;
reg [31:0] int_r_nominal_cycles;
reg [31:0] int_w_nominal_cycles;
reg        int_adapt_enable;
reg [31:0] int_latency_sample;
reg [31:0] int_latency_limits;
reg [31:0] int_adapt_policy;

assign cfg_src_addr = int_src_addr;
assign cfg_dst_addr = int_dst_addr;
assign cfg_transfer_bytes = int_transfer_bytes;
assign cfg_burst_beats = int_dma_cfg[7:0];
assign cfg_rd_out_limit = int_dma_cfg[9:8];
assign cfg_wr_out_limit = int_dma_cfg[11:10];
assign cfg_r_delta_q8 = int_rbr_cfg[15:0];
assign cfg_w_delta_q8 = int_rbr_cfg[31:16];
assign cfg_rbr_enable = int_rbr_ctrl;
assign cfg_r_threshold_bytes = int_r_threshold_bytes;
assign cfg_w_threshold_bytes = int_w_threshold_bytes;
assign cfg_r_nominal_cycles = int_r_nominal_cycles;
assign cfg_w_nominal_cycles = int_w_nominal_cycles;
assign adapt_enable = int_adapt_enable;
assign adapt_latency_sample = int_latency_sample;
assign adapt_low_limit = int_latency_limits[15:0];
assign adapt_high_limit = int_latency_limits[31:16];
assign adapt_hold_samples = int_adapt_policy[7:0];
assign adapt_low_confirm = int_adapt_policy[15:8];
assign adapt_high_confirm = int_adapt_policy[23:16];
assign adapt_initial_level = int_adapt_policy[25:24];

// Write register logic
always @(posedge CLK) begin
    if (!RSTN) begin
        int_src_addr      <= 32'd0;
        int_dst_addr      <= 32'd0;
        int_transfer_bytes <= 32'd0;
        int_dma_cfg       <= {2'b10, 2'b10, 8'd16};
        int_rbr_cfg       <= 32'd0;
        int_rbr_ctrl      <= 2'd0;
        int_r_threshold_bytes <= RBR_R_BYTES_DEFAULT;
        int_w_threshold_bytes <= RBR_W_BYTES_DEFAULT;
        int_r_nominal_cycles  <= RBR_R_NOM_DEFAULT;
        int_w_nominal_cycles  <= RBR_W_NOM_DEFAULT;
        int_adapt_enable   <= 1'b0;
        int_latency_sample <= 32'd0;
        int_latency_limits <= {16'd15954, 16'd13827};
        int_adapt_policy   <= {6'd0, 2'd3, 8'd2, 8'd3, 8'd4};
        start_pulse       <= 1'b0;
        soft_reset_pulse  <= 1'b0;
        adapt_restart     <= 1'b0;
        adapt_sample_valid <= 1'b0;
    end else begin
        start_pulse      <= 1'b0;
        soft_reset_pulse <= 1'b0;
        adapt_restart    <= 1'b0;
        adapt_sample_valid <= 1'b0;

        if (w_hs) begin
            case (waddr)
                ADDR_CTRL: begin
                    if (WSTRB[0]) begin
                        start_pulse      <= WDATA[0] & !engine_busy;
                        soft_reset_pulse <= WDATA[1] & !engine_busy;
                    end
                end

                ADDR_SRC_ADDR: begin
                    int_src_addr <= (WDATA & wmask) | (int_src_addr & ~wmask);
                end

                ADDR_DST_ADDR: begin
                    int_dst_addr <= (WDATA & wmask) | (int_dst_addr & ~wmask);
                end

                ADDR_TRANSFER_BYTES: begin
                    int_transfer_bytes <= (WDATA & wmask) | (int_transfer_bytes & ~wmask);
                end

                ADDR_DMA_CFG: begin
                    if (WSTRB[0])
                        int_dma_cfg[7:0] <= WDATA[7:0];
                    if (WSTRB[1])
                        int_dma_cfg[11:8] <= WDATA[11:8];
                end

                ADDR_RBR_CFG: begin
                    int_rbr_cfg <= (WDATA & wmask) | (int_rbr_cfg & ~wmask);
                end

                ADDR_RBR_CTRL: begin
                    if (WSTRB[0])
                        int_rbr_ctrl <= WDATA[1:0];
                end

                ADDR_RBR_R_BYTES: begin
                    int_r_threshold_bytes <= (WDATA & wmask) |
                                             (int_r_threshold_bytes & ~wmask);
                end

                ADDR_RBR_W_BYTES: begin
                    int_w_threshold_bytes <= (WDATA & wmask) |
                                             (int_w_threshold_bytes & ~wmask);
                end

                ADDR_RBR_R_NOM: begin
                    int_r_nominal_cycles <= (WDATA & wmask) |
                                            (int_r_nominal_cycles & ~wmask);
                end

                ADDR_RBR_W_NOM: begin
                    int_w_nominal_cycles <= (WDATA & wmask) |
                                            (int_w_nominal_cycles & ~wmask);
                end

                ADDR_ADAPT_CTRL: begin
                    if (WSTRB[0])
                        int_adapt_enable <= WDATA[0];
                    if (WSTRB[1])
                        adapt_restart <= WDATA[8];
                end

                ADDR_LAT_SAMPLE: begin
                    int_latency_sample <= (WDATA & wmask) |
                                          (int_latency_sample & ~wmask);
                    if (WSTRB != 4'b0000)
                        adapt_sample_valid <= 1'b1;
                end

                ADDR_LAT_LIMITS: begin
                    int_latency_limits <= (WDATA & wmask) |
                                          (int_latency_limits & ~wmask);
                end

                ADDR_ADAPT_POLICY: begin
                    int_adapt_policy <= (WDATA & wmask) |
                                        (int_adapt_policy & ~wmask);
                end

                default: begin
                    // read-only or unmapped address: ignore write
                end
            endcase
        end
    end
end

// Read register logic
always @(posedge CLK) begin
    if (!RSTN) begin
        rdata <= 32'd0;
    end else begin
        if (ar_hs) begin
            rdata <= 32'd0;
            case (raddr)
                ADDR_CTRL: begin
                    rdata <= 32'd0;
                end

                ADDR_STATUS: begin
                    rdata <= {29'd0, engine_error, engine_done, engine_busy};
                end

                ADDR_SRC_ADDR: begin
                    rdata <= int_src_addr;
                end

                ADDR_DST_ADDR: begin
                    rdata <= int_dst_addr;
                end

                ADDR_TRANSFER_BYTES: begin
                    rdata <= int_transfer_bytes;
                end

                ADDR_CYC_TOTAL: begin
                    rdata <= cyc_total;
                end

                ADDR_CYC_READ: begin
                    rdata <= cyc_read;
                end

                ADDR_CYC_WRITE: begin
                    rdata <= cyc_write;
                end

                ADDR_READ_BEATS: begin
                    rdata <= read_beats;
                end

                ADDR_WRITE_BEATS: begin
                    rdata <= write_beats;
                end

                ADDR_DMA_CFG: begin
                    rdata <= {20'd0, int_dma_cfg};
                end

                ADDR_RBR_CFG: begin
                    rdata <= int_rbr_cfg;
                end

                ADDR_RBR_CTRL: begin
                    rdata <= {30'd0, int_rbr_ctrl};
                end

                ADDR_RBR_R_BYTES: begin
                    rdata <= int_r_threshold_bytes;
                end

                ADDR_RBR_W_BYTES: begin
                    rdata <= int_w_threshold_bytes;
                end

                ADDR_RBR_R_NOM: begin
                    rdata <= int_r_nominal_cycles;
                end

                ADDR_RBR_W_NOM: begin
                    rdata <= int_w_nominal_cycles;
                end

                ADDR_STALL_AR: begin
                    rdata <= stall_ar;
                end

                ADDR_STALL_R: begin
                    rdata <= stall_r;
                end

                ADDR_STALL_AW: begin
                    rdata <= stall_aw;
                end

                ADDR_STALL_W: begin
                    rdata <= stall_w;
                end

                ADDR_STALL_B: begin
                    rdata <= stall_b;
                end

                ADDR_READ_TXNS: begin
                    rdata <= read_txns;
                end

                ADDR_WRITE_TXNS: begin
                    rdata <= write_txns;
                end

                ADDR_R_WAIT: begin
                    rdata <= r_wait_cycles;
                end

                ADDR_W_WAIT: begin
                    rdata <= w_wait_cycles;
                end

                ADDR_R_WINDOWS: begin
                    rdata <= r_windows;
                end

                ADDR_W_WINDOWS: begin
                    rdata <= w_windows;
                end

                ADDR_ADAPT_CTRL: begin
                    rdata <= {28'd0, adapt_config_valid,
                              adapt_level, int_adapt_enable};
                end

                ADDR_LAT_SAMPLE: begin
                    rdata <= int_latency_sample;
                end

                ADDR_LAT_LIMITS: begin
                    rdata <= int_latency_limits;
                end

                ADDR_ADAPT_POLICY: begin
                    rdata <= int_adapt_policy;
                end

                default: begin
                    rdata <= 32'd0;
                end
            endcase
        end
    end
end

endmodule
