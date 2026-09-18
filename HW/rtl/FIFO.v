`timescale 1ns/1ps

module FIFO #(
    parameter DATA_WIDTH = 64,
    parameter FIFO_DEPTH = 64,
    parameter PTR_WIDTH  = 6
)(
    input  wire                  CLK,
    input  wire                  RSTN,

    input  wire                  s_valid,
    output wire                  s_ready,
    input  wire [DATA_WIDTH-1:0] s_data,

    output wire                  m_valid,
    input  wire                  m_ready,
    output wire [DATA_WIDTH-1:0] m_data
);

reg [DATA_WIDTH-1:0] memory [0:FIFO_DEPTH-1];
reg [PTR_WIDTH-1:0]  wr_ptr;
reg [PTR_WIDTH-1:0]  rd_ptr;
reg                  wr_round;
reg                  rd_round;

wire fifo_empty;
wire fifo_full;
wire push;
wire pop;

assign fifo_empty = (wr_ptr == rd_ptr) && (wr_round == rd_round);
assign fifo_full  = (wr_ptr == rd_ptr) && (wr_round != rd_round);

assign s_ready = !fifo_full;
assign m_valid = !fifo_empty;
assign m_data  = memory[rd_ptr];

assign push = s_valid && s_ready;
assign pop  = m_valid && m_ready;

// Write pointer
always @(posedge CLK) begin
    if (!RSTN) begin
        wr_ptr   <= {PTR_WIDTH{1'b0}};
        wr_round <= 1'b0;
    end else if (push) begin
        memory[wr_ptr] <= s_data;

        if (wr_ptr == FIFO_DEPTH-1) begin
            wr_ptr   <= {PTR_WIDTH{1'b0}};
            wr_round <= !wr_round;
        end else begin
            wr_ptr <= wr_ptr + 1'b1;
        end
    end
end

// Read pointer
always @(posedge CLK) begin
    if (!RSTN) begin
        rd_ptr   <= {PTR_WIDTH{1'b0}};
        rd_round <= 1'b0;
    end else if (pop) begin
        if (rd_ptr == FIFO_DEPTH-1) begin
            rd_ptr   <= {PTR_WIDTH{1'b0}};
            rd_round <= !rd_round;
        end else begin
            rd_ptr <= rd_ptr + 1'b1;
        end
    end
end

endmodule
