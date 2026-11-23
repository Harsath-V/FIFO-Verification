
`timescale 1ns / 1ps

module fifo #(
    parameter integer width = 32,
    parameter integer depth = 128
)(
    input  wire clk,
    input  wire rstn,       // Active-low reset
    input  wire [width-1:0] din,
    input  wire wr_en,
    input  wire rd_en,
    input  wire en,
    output wire full,
    output wire empty,
    output reg [width-1:0] dout
);

    localparam integer ADDR_WIDTH = (depth > 1) ? $clog2(depth) : 1;
    localparam integer COUNT_WIDTH = (depth > 1) ? $clog2(depth+1) : 1;

    reg [width-1:0] data [0:depth-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [COUNT_WIDTH-1:0] count;

    assign full  = (count == depth);
    assign empty = (count == 0);

    wire do_write;
    wire do_read;

    assign do_write = en && wr_en && !full;
    assign do_read  = en && rd_en && !empty;

    always @(posedge clk or negedge rstn) begin

        if (!rstn) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
            dout   <= 0;
        end

        else begin
            if (do_write) begin
                data[wr_ptr] <= din;
                if (wr_ptr == depth-1)
                    wr_ptr <= 0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end

            if (do_read) begin
                dout <= data[rd_ptr];
                if (rd_ptr == depth-1)
                    rd_ptr <= 0;
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end

            // OCCUPANCY COUNTER
            case ({do_write, do_read})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                2'b11: count <= count;
                2'b00: count <= count;
            endcase
        end
    end
endmodule
