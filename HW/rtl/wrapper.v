`timescale 1ns/1ps

module wrapper #(
    parameter ID_WIDTH = 6
)(
    input  wire                    CLK,
    input  wire                    RSTN,

    // AXI4-Lite slave
    input  wire [31:0]             S_AXI_AWADDR,
    input  wire [2:0]              S_AXI_AWPROT,
    input  wire                    S_AXI_AWVALID,
    output wire                    S_AXI_AWREADY,

    input  wire [31:0]             S_AXI_WDATA,
    input  wire [3:0]              S_AXI_WSTRB,
    input  wire                    S_AXI_WVALID,
    output wire                    S_AXI_WREADY,

    output wire [1:0]              S_AXI_BRESP,
    output wire                    S_AXI_BVALID,
    input  wire                    S_AXI_BREADY,

    input  wire [31:0]             S_AXI_ARADDR,
    input  wire [2:0]              S_AXI_ARPROT,
    input  wire                    S_AXI_ARVALID,
    output wire                    S_AXI_ARREADY,

    output wire [31:0]             S_AXI_RDATA,
    output wire [1:0]              S_AXI_RRESP,
    output wire                    S_AXI_RVALID,
    input  wire                    S_AXI_RREADY,

    // AXI4 master write address channel
    output wire [ID_WIDTH-1:0]     M_AXI_AWID,
    output wire [31:0]             M_AXI_AWADDR,
    output wire [7:0]              M_AXI_AWLEN,
    output wire [2:0]              M_AXI_AWSIZE,
    output wire [1:0]              M_AXI_AWBURST,
    output wire                    M_AXI_AWLOCK,
    output wire [3:0]              M_AXI_AWCACHE,
    output wire [2:0]              M_AXI_AWPROT,
    output wire [3:0]              M_AXI_AWQOS,
    output wire                    M_AXI_AWVALID,
    input  wire                    M_AXI_AWREADY,

    // AXI4 master write data channel
    output wire [63:0]             M_AXI_WDATA,
    output wire [7:0]              M_AXI_WSTRB,
    output wire                    M_AXI_WLAST,
    output wire                    M_AXI_WVALID,
    input  wire                    M_AXI_WREADY,

    // AXI4 master write response channel
    input  wire [ID_WIDTH-1:0]     M_AXI_BID,
    input  wire [1:0]              M_AXI_BRESP,
    input  wire                    M_AXI_BVALID,
    output wire                    M_AXI_BREADY,

    // AXI4 master read address channel
    output wire [ID_WIDTH-1:0]     M_AXI_ARID,
    output wire [31:0]             M_AXI_ARADDR,
    output wire [7:0]              M_AXI_ARLEN,
    output wire [2:0]              M_AXI_ARSIZE,
    output wire [1:0]              M_AXI_ARBURST,
    output wire                    M_AXI_ARLOCK,
    output wire [3:0]              M_AXI_ARCACHE,
    output wire [2:0]              M_AXI_ARPROT,
    output wire [3:0]              M_AXI_ARQOS,
    output wire                    M_AXI_ARVALID,
    input  wire                    M_AXI_ARREADY,

    // AXI4 master read data channel
    input  wire [ID_WIDTH-1:0]     M_AXI_RID,
    input  wire [63:0]             M_AXI_RDATA,
    input  wire [1:0]              M_AXI_RRESP,
    input  wire                    M_AXI_RLAST,
    input  wire                    M_AXI_RVALID,
    output wire                    M_AXI_RREADY
);

// Fixed ID : 0
assign M_AXI_AWID = {ID_WIDTH{1'b0}};
assign M_AXI_ARID = {ID_WIDTH{1'b0}};

assign M_AXI_AWLOCK  = 1'b0;
assign M_AXI_ARLOCK  = 1'b0;
assign M_AXI_AWCACHE = 4'b0011;
assign M_AXI_ARCACHE = 4'b0011;
assign M_AXI_AWPROT  = 3'b000;
assign M_AXI_ARPROT  = 3'b000;
assign M_AXI_AWQOS   = 4'b0000;
assign M_AXI_ARQOS   = 4'b0000;

top u_top (
    .CLK(CLK),
    .RSTN(RSTN),

    .S_AXI_AWADDR(S_AXI_AWADDR[6:0]),
    .S_AXI_AWVALID(S_AXI_AWVALID),
    .S_AXI_AWREADY(S_AXI_AWREADY),

    .S_AXI_WDATA(S_AXI_WDATA),
    .S_AXI_WSTRB(S_AXI_WSTRB),
    .S_AXI_WVALID(S_AXI_WVALID),
    .S_AXI_WREADY(S_AXI_WREADY),

    .S_AXI_BRESP(S_AXI_BRESP),
    .S_AXI_BVALID(S_AXI_BVALID),
    .S_AXI_BREADY(S_AXI_BREADY),

    .S_AXI_ARADDR(S_AXI_ARADDR[6:0]),
    .S_AXI_ARVALID(S_AXI_ARVALID),
    .S_AXI_ARREADY(S_AXI_ARREADY),

    .S_AXI_RDATA(S_AXI_RDATA),
    .S_AXI_RRESP(S_AXI_RRESP),
    .S_AXI_RVALID(S_AXI_RVALID),
    .S_AXI_RREADY(S_AXI_RREADY),

    .M_AXI_ARADDR(M_AXI_ARADDR),
    .M_AXI_ARLEN(M_AXI_ARLEN),
    .M_AXI_ARSIZE(M_AXI_ARSIZE),
    .M_AXI_ARBURST(M_AXI_ARBURST),
    .M_AXI_ARVALID(M_AXI_ARVALID),
    .M_AXI_ARREADY(M_AXI_ARREADY),

    .M_AXI_RDATA(M_AXI_RDATA),
    .M_AXI_RRESP(M_AXI_RRESP),
    .M_AXI_RLAST(M_AXI_RLAST),
    .M_AXI_RVALID(M_AXI_RVALID),
    .M_AXI_RREADY(M_AXI_RREADY),

    .M_AXI_AWADDR(M_AXI_AWADDR),
    .M_AXI_AWLEN(M_AXI_AWLEN),
    .M_AXI_AWSIZE(M_AXI_AWSIZE),
    .M_AXI_AWBURST(M_AXI_AWBURST),
    .M_AXI_AWVALID(M_AXI_AWVALID),
    .M_AXI_AWREADY(M_AXI_AWREADY),

    .M_AXI_WDATA(M_AXI_WDATA),
    .M_AXI_WSTRB(M_AXI_WSTRB),
    .M_AXI_WLAST(M_AXI_WLAST),
    .M_AXI_WVALID(M_AXI_WVALID),
    .M_AXI_WREADY(M_AXI_WREADY),

    .M_AXI_BRESP(M_AXI_BRESP),
    .M_AXI_BVALID(M_AXI_BVALID),
    .M_AXI_BREADY(M_AXI_BREADY)
);

endmodule
