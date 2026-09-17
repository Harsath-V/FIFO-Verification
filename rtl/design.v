`timescale 1ns / 1ps

module fifo #(
        parameter width = 32,
        parameter depth = 128,
        parameter bits = $clog2(depth),
        parameter loc = (bits - 1)
)(
       input wire clk,
       input wire rst,
       input wire [width-1:0]din,
       input wire wr_en,
       input wire rd_en,
       input wire en,
       output reg full,
       output reg empty,
       
       output reg [width-1:0]dout       
);

reg [width-1:0]data[0:depth-1];
reg [loc-1:0]wrptr, rdptr;

always @(posedge clk or negedge rst) begin
    if(!rst) begin
        wrptr <= 0;
        rdptr <= 0;
    end
    
    else begin
        if(en == 1) begin
            if(wr_en == 1 && (!full)) begin
                wrptr <= wrptr + 1;
                data[wrptr] <= din;
            end
            else if(rd_en == 1 && (!empty)) begin
                rdptr <= rdptr + 1;
                dout <= data[rdptr];
            end
            else begin
                wrptr <= wrptr;
                rdptr <= rdptr;
            end
        end
    end
end

always @(posedge clk or negedge rst) begin
    if(!rst) begin
        full <= 0;
        empty <= 1;
    end  
    
    else begin
        if(en == 1) begin
            if(wr_en == 1 && (!full)) begin
                if(wrptr == rdptr) begin
                    full <= 1;
                    empty <= 0;
                end
            end
            if(rd_en == 1 && (!empty)) begin
                if(wrptr == rdptr) begin
                    full <= 0;
                    empty <= 1;
                end
            end
        end
    end
end

endmodule
